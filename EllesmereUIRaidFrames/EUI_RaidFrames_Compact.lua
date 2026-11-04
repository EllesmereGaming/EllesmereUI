if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_RaidFrames_Compact.lua
--  Compact Mode (the raid and party Frame Spacing cogs) and Grid Mode (the
--  raid Group Spacing cog). With a visible Pixels or Pixels Textured border,
--  frames sit one physical pixel apart and each group draws one shared
--  outline with separators between its frames instead of a border per frame;
--  Grid Mode sets the raid groups one pixel apart too and fills each occupied
--  group to five with empty backgrounds, under one outline while the groups
--  make a rectangle. Grouped pets follow their tab's mode. Nothing is built,
--  hooked or registered until a mode is first on; a mode turned off hides its
--  pieces, and the hooks it left on the unit buttons return at once.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
if not I or I.broken then return end
I.broken = true

local EUI = ns.EllesmereUI
local CreateFrame, InCombatLockdown = CreateFrame, InCombatLockdown
local PixelSnap, FFD, GetFFD, defaults = I.PixelSnap, I.FFD, I.GetFFD, I.defaults
local allButtons, separatedHdrs = I.allButtons, I.separatedHdrs
local db, container, solidStyle
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end
I.containerFrameSetters[#I.containerFrameSetters + 1] = function(v) container = v end

-------------------------------------------------------------------------------
--  Gates and spacing
-------------------------------------------------------------------------------
-- The border either mode needs: a Pixels style above size 0, on the EllesmereUI look.
function ns.RF_CompactEligible(s)
    return s and EUI._pixelArtBorders[s.borderTexture] and not ns.RF_Stock() and (s.borderSize or 1) > 0
end

-- Compact Mode in effect for settings s (party: the Party tab's choice). The party
-- side also stands down under the Party Frames kit and while target frames sit along
-- the stack; a saved choice that cannot apply stays saved.
function ns.RF_CompactOn(s, party)
    if not s or not (party and s.partyCompactMode == true or not party and s.raidCompactMode == true) then return false end
    local style = s
    if party and s == db.profile then style = ns._partyProxy
    elseif party and s == ns._pvOverlayProxy then style = ns._scaledPartyProxy end
    if not ns.RF_CompactEligible(style) then return false end
    return not party or (not ns.RF_PartyKit()
        and not ns.PT_AlongStack(s, s.partyShowTargets == true))
end

-- The options pages' check for the tab they show (party: the Party tab).
function ns.RF_CompactOnTab(party)
    return ns.RF_CompactOn(party and ns._partyProxy or db.profile, party)
end

function ns.RF_GridOn(s)
    return s.raidGridMode == true and ns.RF_CompactOn(s, false)
end

-- One physical pixel at the container's scale.
function ns.RF_OnePixel(party)
    local frame = party and ns._partyContainerFrame or container
    return EUI.PP.perfect / (frame and frame:GetEffectiveScale() or UIParent:GetEffectiveScale())
end

-- The spacing the layout uses: one pixel under the mode, else the saved slider value.
function ns.RF_CellSpacing(s, party)
    if ns.RF_CompactOn(s, party) then return ns.RF_OnePixel(party) end
    return PixelSnap(party and (s.partyCellSpacing or s.cellSpacing or 2) or (s.cellSpacing or 2))
end

function ns.RF_GroupSpacing(s)
    return ns.RF_GridOn(s) and ns.RF_OnePixel(false) or PixelSnap(s.groupSpacing or 8)
end

-------------------------------------------------------------------------------
--  Per-frame borders under the mode: the frame's own border stands down for the
--  shared outline, and hover and target draw a solid border of their own size.
-------------------------------------------------------------------------------
function ns.RF_ButtonCompact(d, s)
    return not d._isExtra and ns.RF_CompactOn(s, d._isParty == true)
end

-- A grouped pet: a header pet while its tab's mode is on, or a grouped preview pet.
function ns.RF_PetCompactOn(button, s)
    local d = FFD[button]
    if not d then return false end
    if d._petGroupedPreview then return ns.RF_CompactOn(s, d._petPreviewParty) end
    local pf = ns._PF
    return d._petHeader and pf and pf.active and ns.RF_CompactOn(s, pf.styleCtx == "party") or false
end

function ns.RF_PetCompactHighlight(button, s)
    local d = GetFFD(button)
    d._hovered, d._isTarget = ns._FB.hov[button], ns._FB.tgt[button]
    ns.RF_CompactHighlight(button._borderFrame, d, s, button)
end

function ns.RF_CompactHighlight(frame, d, s, button)
    local c, a, size, px
    if d._hovered and s.hoverBorderEnabled ~= false then
        c, a, size = s.hoverBorderColor or defaults.profile.hoverBorderColor, s.hoverBorderAlpha or 1, s.hoverBorderSize or 1
        px = EUI.BorderPx(s.hoverBorderSizePx, size, "solid")
    elseif d._isTarget and s.targetBorderEnabled ~= false then
        c, a, size = s.targetBorderColor or defaults.profile.targetBorderColor, s.targetBorderAlpha or 1, s.targetBorderSize or 1
        px = EUI.BorderPx(s.targetBorderSizePx, size, "solid")
    end
    solidStyle = solidStyle or { borderTexture = "solid" }
    if c then
        local r, g, b = ns.RF_VisibleHighlight(s, c.r, c.g, c.b)
        local level = s.borderBehind and math.max(0, button:GetFrameLevel() - 1) or button:GetFrameLevel() + ns.LVL_RAISE
        if frame:GetFrameLevel() ~= level then frame:SetFrameLevel(level) end
        ns.ApplyHighlightBorder(frame, solidStyle, size, r, g, b, a, px)
        local strips = EUI.PP.GetBorders(frame)
        if strips and strips:GetFrameLevel() ~= level + 1 then strips:SetFrameLevel(level + 1) end
    else
        ns.ApplyHighlightBorder(frame, solidStyle, nil, 0, 0, 0, 0)
    end
end

-------------------------------------------------------------------------------
--  Shared outlines. A state is one set of frames (the live raid, party or pet
--  header, or an options preview): its cells (each frame's rect), the style its
--  pieces draw in, and its pooled pieces -- outline hosts, separators and Grid
--  Mode's empty backgrounds. Draw runs only when a cell or the style changed,
--  and a piece takes the style again only when the style changed since it last
--  did (styleGen), so a roster change only moves pieces.
-------------------------------------------------------------------------------
local raid, party, pets, raidPreview, partyPreview, petPreview

local function HideState(st)
    if not st or not st.shown then return end
    for _, host in ipairs(st.hosts) do
        if host:IsShown() then
            EUI.HideBorderStyle(host)
            host:Hide()
            host._sg = nil
        end
    end
    for _, f in ipairs(st.empty) do if f:IsShown() then f:Hide() end end
    for _, t in ipairs(st.seams) do if t:IsShown() then t:Hide() end end
    st.shown, st.dirty = false, true
end

local function NewState(owner, isParty)
    return { owner = owner, isParty = isParty,
        groups = {}, hosts = {}, empty = {}, seams = {}, style = {}, styleGen = 0, dirty = true }
end

local function PutStyle(st, key, value)
    if st.style[key] ~= value then st.style[key], st.dirty, st.styleDirty = value, true, true end
end

local function UpdateStyle(st, s)
    local c = s.borderColor or defaults.profile.borderColor
    local grid = not st.isParty and ns.RF_GridOn(s)
    local r, g, b, a
    if grid and not st.isPet then
        if s.healthColorMode == "dark" then r, g, b, a = EUI.GetDarkModeBg()
        else r, g, b, a = ns.GetBgColor(nil, s) end
    end
    PutStyle(st, "tex", s.borderTexture); PutStyle(st, "size", s.borderSize or 1)
    PutStyle(st, "px", EUI.BorderPx(s.borderSizePx, s.borderSize or 1, s.borderTexture))
    PutStyle(st, "offX", s.borderTextureOffset); PutStyle(st, "offY", s.borderTextureOffsetY)
    PutStyle(st, "shiftX", s.borderTextureShiftX); PutStyle(st, "shiftY", s.borderTextureShiftY)
    PutStyle(st, "behind", s.borderBehind); PutStyle(st, "r", c.r); PutStyle(st, "g", c.g); PutStyle(st, "b", c.b)
    PutStyle(st, "a", s.borderAlpha or 1); PutStyle(st, "bgR", r); PutStyle(st, "bgG", g); PutStyle(st, "bgB", b); PutStyle(st, "bgA", a)
    PutStyle(st, "one", EUI.PP.perfect / st.owner:GetEffectiveScale())
    PutStyle(st, "grid", grid)
    -- Textured Background on the empty backgrounds, as on the frames.
    PutStyle(st, "bgTex", grid and not st.isPet and ns.RF_TexBgPath(s) or false)
    PutStyle(st, "bgVert", grid and ns.RF_IsVerticalFill(s) or false)
end

-- Records frame f as the index-th cell of group gi (rect in the owner's scale, top-left).
local function Cell(st, gi, index, f)
    local group = st.groups[gi]
    if not group then group = { cells = {} }; st.groups[gi] = group end
    local cell = group.cells[index]
    if not cell then cell = {}; group.cells[index] = cell end
    local scale = f:GetEffectiveScale() / st.owner:GetEffectiveScale()
    local x, y, w, h = f:GetRect()
    if not x or not y then return false end
    x, y, w, h = x * scale, (y + h) * scale, w * scale, h * scale
    local level, strata = f:GetFrameLevel(), f:GetFrameStrata()
    if cell.frame ~= f or cell.x ~= x or cell.y ~= y or cell.w ~= w or cell.h ~= h
        or cell.level ~= level or cell.strata ~= strata then
        cell.frame, cell.x, cell.y, cell.w, cell.h = f, x, y, w, h
        cell.level, cell.strata = level, strata
        st.dirty = true
    end
    return true
end

-- Cells in screen order: left to right, then top to bottom.
local function Along(a, b)
    if a.x == b.x then return a.y > b.y end
    return a.x < b.x
end

local function FinishGroup(st, gi, count, growth)
    local group = st.groups[gi]
    if not group then group = { cells = {} }; st.groups[gi] = group end
    if group.count ~= count then group.count, st.dirty = count, true end
    if group.growth ~= growth then group.growth, st.dirty = growth, true end
end

-- An outline host round one box (x, y: its top-left in the owner's scale).
local function Host(st, index, first, x, y, w, h)
    local host = st.hosts[index]
    if not host then host = CreateFrame("Frame", nil, st.owner); st.hosts[index] = host end
    local v = st.style
    host:SetFrameStrata(first.strata)
    -- Normal dispel strips can reach button + 14; shared edges sit above them.
    host:SetFrameLevel(v.behind and math.max(0, first.level - 1) or first.level + ns.LVL_AURA + 2)
    host:ClearAllPoints()
    host:SetPoint("TOPLEFT", first.frame, "TOPLEFT", x - first.x, y - first.y)
    host:SetSize(w, h)
    if host._sg ~= st.styleGen or host._w ~= w or host._h ~= h then
        host._sg, host._w, host._h = st.styleGen, w, h
        EUI.ApplyBorderStyle(host, v.size, v.r, v.g, v.b, v.a, v.tex,
            v.offX, v.offY, v.shiftX, v.shiftY, "unitframes", v.size, nil, v.px)
    end
    host:Show()
end

-- A separator along one join (x, y: the join's top-left in the owner's scale).
local function Seam(st, index, first, x, y, length, vertical)
    local t = st.seams[index]
    if not t then
        if not st.seamHost then st.seamHost = CreateFrame("Frame", nil, st.owner) end
        t = st.seamHost:CreateTexture(nil, "OVERLAY")
        EUI.PP.DisablePixelSnap(t)
        st.seams[index] = t
    end
    local v = st.style
    local host = st.seamHost
    local level = v.behind and math.max(0, first.level - 1) or first.level + ns.LVL_AURA + 2
    if host._level ~= level or host._strata ~= first.strata then
        host._level, host._strata = level, first.strata
        host:SetFrameStrata(first.strata)
        host:SetFrameLevel(level)
    end
    if t._sg ~= st.styleGen or t._vertical ~= vertical then
        t._sg, t._vertical = st.styleGen, vertical
        t:SetDrawLayer("OVERLAY", vertical and 0 or 1)
        t:SetTexture(vertical and v.sepV or v.sepH)
        t:SetTexCoord(0, 1, 0, 1)
        t:SetVertexColor(v.r, v.g, v.b, v.a)
    end
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", first.frame, "TOPLEFT", x - first.x - (vertical and v.lead or 0), y - first.y + (vertical and 0 or v.lead))
    t:SetSize(vertical and v.thick or length, vertical and length or v.thick)
    t:Show()
end

local function Draw(st)
    if not st.dirty then return end
    local v = st.style
    if st.styleDirty then
        st.styleDirty = false
        st.styleGen = st.styleGen + 1
        local scale = st.owner:GetEffectiveScale()
        v.thick = EUI.BorderCompanionThickness(v.tex, v.size, v.px, scale)
        -- Both separator textures put their bright line at texel 5 of 32.
        v.lead = EUI.PP.SnapForES(v.thick * 5 / 32, scale)
        v.sepV, v.sepH = EUI.GetBorderCompanion(v.tex, "sepV"), EUI.GetBorderCompanion(v.tex, "sepH")
    end
    local gap = st.layoutPixel or v.one
    local hostCount, emptyCount, seamCount = 0, 0, 0
    local minX, maxY, maxX, minY, area, first = nil, nil, nil, nil, 0, nil
    for gi = 1, st.count do
        local group = st.groups[gi]
        local cells, n = group.cells, group.count
        if n > 0 then
            -- Keep the capture order stable so an unchanged UP/LEFT stack stays cached.
            group.sorted = group.sorted or {}
            for i = 1, n do group.sorted[i] = cells[i] end
            for i = #group.sorted, n + 1, -1 do group.sorted[i] = nil end
            table.sort(group.sorted, Along)
            cells = group.sorted
            local c = cells[1]
            local horizontal = group.growth == "LEFT" or group.growth == "RIGHT"
            local x, y = c.x, c.y
            local w = horizontal and (n * c.w + (n - 1) * gap) or c.w
            local h = horizontal and c.h or (n * c.h + (n - 1) * gap)
            -- Grid Mode: an occupied group fills to five with empty backgrounds past
            -- its last frame along its growth.
            if v.grid and not st.isPet and n < 5 then
                local missing = 5 - n
                if group.growth == "LEFT" then x = x - missing * (c.w + gap) end
                if group.growth == "UP" then y = y + missing * (c.h + gap) end
                w = horizontal and (5 * c.w + 4 * gap) or c.w
                h = horizontal and c.h or (5 * c.h + 4 * gap)
                for i = n + 1, 5 do
                    emptyCount = emptyCount + 1
                    local f = st.empty[emptyCount]
                    if not f then
                        f = CreateFrame("Frame", nil, st.owner)
                        f.bg = f:CreateTexture(nil, "BACKGROUND")
                        f.bg:SetAllPoints(); EUI.PP.DisablePixelSnap(f.bg)
                        st.empty[emptyCount] = f
                    end
                    local offset = i - n
                    local endCell = (group.growth == "UP" or group.growth == "LEFT") and cells[1] or cells[n]
                    local dx = horizontal and offset * (c.w + gap) * (group.growth == "LEFT" and -1 or 1) or 0
                    local dy = not horizontal and offset * (c.h + gap) * (group.growth == "UP" and 1 or -1) or 0
                    f:ClearAllPoints(); f:SetPoint("TOPLEFT", endCell.frame, "TOPLEFT", dx, dy)
                    f:SetSize(c.w, c.h); f:SetFrameStrata(c.strata); f:SetFrameLevel(c.level)
                    if f._sg ~= st.styleGen then
                        f._sg = st.styleGen
                        ns.RF_TexBgTint(f.bg, v.bgTex or nil, v.bgVert)
                        f.bg:SetColorTexture(v.bgR, v.bgG, v.bgB, v.bgA)
                    end
                    f:Show()
                end
                n = 5
            end
            group.x, group.y, group.w, group.h = x, y, w, h
            minX, maxY = math.min(minX or x, x), math.max(maxY or y, y)
            maxX, minY = math.max(maxX or (x + w), x + w), math.min(minY or (y - h), y - h)
            area = area + (w + gap) * (h + gap)
            first = first or c
            for i = 1, n - 1 do
                seamCount = seamCount + 1
                Seam(st, seamCount, c, horizontal and x + i * (c.w + gap) or x,
                    horizontal and y or y - i * (c.h + gap), horizontal and h or w, horizontal)
            end
        end
    end
    -- One outline round the groups only while they tile a rectangle (their padded
    -- areas fill the bounding box); any other shape keeps an outline per group.
    local rectangular = first and v.grid and math.abs(area - (maxX - minX + gap) * (maxY - minY + gap)) < gap * gap / 2
    if rectangular then
        hostCount = 1
        Host(st, 1, first, minX, maxY, maxX - minX, maxY - minY)
    end
    for gi = 1, st.count do
        local group = st.groups[gi]
        if group.count > 0 then
            if not rectangular then
                hostCount = hostCount + 1
                Host(st, hostCount, group.sorted[1], group.x, group.y, group.w, group.h)
            else
                -- Separators where two joined groups meet, along their shared length.
                for gj = gi + 1, st.count do
                    local other = st.groups[gj]
                    if other.count > 0 then
                        local x = math.max(group.x, other.x)
                        local y = math.min(group.y, other.y)
                        local width = math.min(group.x + group.w, other.x + other.w) - x
                        local height = y - math.max(group.y - group.h, other.y - other.h)
                        if height > 0 and (math.abs(group.x + group.w + gap - other.x) < gap / 2
                            or math.abs(other.x + other.w + gap - group.x) < gap / 2) then
                            seamCount = seamCount + 1
                            Seam(st, seamCount, first, x, y, height, true)
                        elseif width > 0 and (math.abs(group.y - group.h - gap - other.y) < gap / 2
                            or math.abs(other.y - other.h - gap - group.y) < gap / 2) then
                            seamCount = seamCount + 1
                            Seam(st, seamCount, first, x, y, width, false)
                        end
                    end
                end
            end
        end
    end
    for i = hostCount + 1, #st.hosts do
        local host = st.hosts[i]
        if host:IsShown() then EUI.HideBorderStyle(host); host:Hide(); host._sg = nil end
    end
    for i = emptyCount + 1, #st.empty do if st.empty[i]:IsShown() then st.empty[i]:Hide() end end
    for i = seamCount + 1, #st.seams do if st.seams[i]:IsShown() then st.seams[i]:Hide() end end
    st.shown, st.dirty = first ~= nil, false
end

-------------------------------------------------------------------------------
--  Live states. Hooks on the unit buttons queue a redraw, flushed once by a
--  hidden frame's one-shot OnUpdate in the same frame, after the header's own
--  pass and before the render.
-------------------------------------------------------------------------------
local RefreshLive, flusher
local function Flush(self)
    self:Hide()
    if raid and raid.pending then RefreshLive(raid) end
    if party and party.pending then RefreshLive(party) end
    if pets and pets.pending then RefreshLive(pets) end
end

local function Queue(st)
    if not st.on or st.pending then return end
    st.pending = true
    if not flusher then
        flusher = CreateFrame("Frame")
        flusher:Hide()
        flusher:SetScript("OnUpdate", Flush)
    end
    flusher:Show()
end

local function Hook(st, f)
    if st.hooked[f] then return end
    st.hooked[f] = true
    f:HookScript("OnShow", st.queue)
    f:HookScript("OnHide", st.queue)
    f:HookScript("OnSizeChanged", st.queue)
    f:HookScript("OnAttributeChanged", st.assigned)
end

-- A mode turning on or off restyles the frames' own borders, threat and dispel rings.
local function RefreshButtonBorders(st, on)
    local changed = false
    for _, f in ipairs(st.isParty and ns._partyAllButtons or allButtons) do
        local d = GetFFD(f)
        if not d._isExtra and d.UpdateBorder and (on or d._compactBorder) and d._compactBorder ~= on then
            d.UpdateBorder()
            changed = true
            local unit = f:GetAttribute("unit")
            if unit then ns.RF_PaintThreat(d, st.isParty and ns._scaledPartyProxy or ns._scaledProfile, unit) end
        end
    end
    if changed and ns.RFC_ReloadAll then ns.RFC_ReloadAll() end
end

local function CollectGroup(st, frames, start, limit, gi, growth)
    local n = 0
    for i = start, limit do
        local f = frames and frames[i]
        if f then
            Hook(st, f)
            if f:IsVisible() and f:GetAttribute("unit") and Cell(st, gi, n + 1, f) then
                n = n + 1
            end
        end
    end
    FinishGroup(st, gi, n, growth)
end

local function HeaderGrowth(header)
    local point = header and header:GetAttribute("point")
    return point == "BOTTOM" and "UP" or point == "LEFT" and "RIGHT" or point == "RIGHT" and "LEFT" or "DOWN"
end

local function CollectLive(st, s)
    local count = 0
    if st.isPet then
        local pf = ns._PF
        local growth = HeaderGrowth(pf.container)
        for gi = 1, math.ceil(#pf.buttons / 5) do
            CollectGroup(st, pf.buttons, (gi - 1) * 5 + 1, math.min(gi * 5, #pf.buttons), gi, growth)
            count = gi
        end
    elseif st.isParty then
        CollectGroup(st, ns._partyAllButtons, 1, #ns._partyAllButtons, 1, ns._PartyGrowth(s))
        count = 1
    elseif s.mergeGroups then
        st.flat = st.flat or {}
        local limit = 0
        for i = 1, 40 do
            local f = ns._flatHeader and ns._flatHeader[i]
            if f then
                Hook(st, f)
                if f:IsVisible() and f:GetAttribute("unit") then
                    limit = limit + 1
                    st.flat[limit] = f
                end
            end
        end
        local growth = HeaderGrowth(ns._flatHeader)
        for gi = 1, math.ceil(limit / 5) do
            local n = 0
            for i = (gi - 1) * 5 + 1, math.min(gi * 5, limit) do
                if Cell(st, gi, n + 1, st.flat[i]) then n = n + 1 end
            end
            FinishGroup(st, gi, n, growth); count = gi
        end
    else
        for gi = 1, 8 do
            local hdr = separatedHdrs[gi]
            CollectGroup(st, hdr, 1, 5, gi, HeaderGrowth(hdr))
        end
        count = 8
    end
    if st.count ~= count then st.count, st.dirty = count, true end
end

-- The settings a live state draws from.
local function StateSource(st)
    if st.isPet then return ns._PF.StyleSource() end
    return st.isParty and ns._partyProxy or db.profile
end

RefreshLive = function(st)
    st.pending = nil
    if not st.on then return end
    local s = StateSource(st)
    UpdateStyle(st, s)
    CollectLive(st, s)
    Draw(st)
end

local function NewLiveState(owner, isParty)
    local st = NewState(owner, isParty)
    st.hooked = setmetatable({}, { __mode = "k" })
    st.queue = function() Queue(st) end
    st.assigned = function(_, name) if name == "unit" then Queue(st) end end
    return st
end

-- Called at the end of every raid and party layout pass.
function ns.RF_SyncCompact(isParty)
    local s = isParty and ns._partyProxy or db.profile
    local on = ns.RF_CompactOn(s, isParty)
    local st
    if isParty then st = party else st = raid end
    if not on and not st then return end
    if on and not st then
        st = NewLiveState(isParty and ns._partyContainerFrame or container, isParty)
        if isParty then party = st else raid = st end
    end
    local wasOn = st.on
    st.on = on
    if wasOn ~= on then RefreshButtonBorders(st, on) end
    if on then st.layoutPixel = ns.RF_OnePixel(isParty); Queue(st) else HideState(st) end
end

-- Called at the end of every pet layout pass and when the pet header stands down.
function ns.RF_SyncPetCompact()
    local pf = ns._PF
    local isParty = pf and pf.styleCtx == "party"
    local on = pf and pf.active and ns.RF_CompactOn(pf.StyleSource(), isParty) or false
    local st = pets
    if not on and not st then return end
    if not st then
        st = NewLiveState(pf.container, isParty)
        st.isPet = true
        pets = st
    end
    if st.on ~= on then
        st.on = on
        for _, f in ipairs(pf.buttons) do
            local d = GetFFD(f)
            if f._borderFrame and (on or d._petCompactBorder) and d._petCompactBorder ~= on then
                ns._FB.StyleBorder(f)
            end
        end
    end
    st.isParty = isParty
    if on then st.layoutPixel = ns.RF_OnePixel(isParty); Queue(st) else HideState(st) end
end

-------------------------------------------------------------------------------
--  A new pixel grid (UI_SCALE_CHANGED, DISPLAY_SIZE_CHANGED and EUI's own UI
--  Scale, all through ns.RFC_PixelGridChanged): a live mode whose one pixel
--  moved re-lays its frames, at once out of combat and when combat ends in it,
--  and an attached boss group takes the new pitch (ns.FB_Repitch).
-------------------------------------------------------------------------------
local function Rescale(st)
    if not (st and st.on) or (st.isPet and not ns._PF.active) then return end
    if not ns.RF_CompactOn(StateSource(st), st.isParty) or st.layoutPixel == ns.RF_OnePixel(st.isParty) then return end
    if InCombatLockdown() then
        ns.CombatQueue.Defer(st.isPet and "compact-pet-scale" or st.isParty and "compact-party-scale"
            or "compact-raid-scale", function() Rescale(st) end)
        return
    end
    if st.isPet then ns._PF.Layout()
    elseif st.isParty then ns._LayoutPartyFrames()
    else I.LayoutGroups() end
end

function ns.RF_CompactScaleChanged()
    Rescale(raid); Rescale(party); Rescale(pets)
    ns.FB_Repitch()
end

-------------------------------------------------------------------------------
--  Options previews: the same pieces over the preview frames (party: the party
--  preview; growth: the preview's unit growth).
-------------------------------------------------------------------------------
local function PreviewCompact(st, frames, s, isParty, growth, isPet)
    if not frames or not ns.RF_CompactOn(s, isParty) then HideState(st); return st end
    local owner
    for _, f in ipairs(frames) do
        if f:IsShown() then owner = f:GetParent(); break end
    end
    if not owner then HideState(st); return st end
    if not st then
        st = NewState(owner, isParty)
    end
    st.isPet, st.isParty = isPet, isParty
    if st.owner ~= owner then
        st.owner, st.dirty = owner, true
        for _, f in ipairs(st.hosts) do f:SetParent(owner) end
        for _, f in ipairs(st.empty) do f:SetParent(owner) end
        if st.seamHost then st.seamHost:SetParent(owner) end
    end
    UpdateStyle(st, s)
    local count = isParty and 1 or math.ceil(#frames / 5)
    for gi = 1, count do
        local n = 0
        for i = (gi - 1) * 5 + 1, math.min(gi * 5, #frames) do
            local f = frames[i]
            if f:IsShown() and Cell(st, gi, n + 1, f) then n = n + 1 end
        end
        FinishGroup(st, gi, n, growth)
    end
    if st.count ~= count then st.count, st.dirty = count, true end
    Draw(st)
    return st
end

function ns.RF_PreviewCompact(frames, s, isParty, growth)
    if isParty then partyPreview = PreviewCompact(partyPreview, frames, s, true, growth)
    else raidPreview = PreviewCompact(raidPreview, frames, s, false, growth) end
end

function ns.RF_PreviewPetCompact(frames, s, isParty, growth)
    petPreview = PreviewCompact(petPreview, frames, s, isParty, growth, true)
end

I.broken = false
