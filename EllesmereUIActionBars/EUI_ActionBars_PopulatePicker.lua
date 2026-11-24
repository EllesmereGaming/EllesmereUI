if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ActionBars_PopulatePicker.lua
--
--  Choose Bars (ns.PopulatePicker): the view in which the player picks the
--  action bars that Populate (ns.Populate, EUI_ActionBars_Populate.lua) fills
--  with the active profile's action bar spells.
--
--  It shows the player's real bars with what is on them now, forced visible
--  through the module's runtime visibility override with a set of its own
--  (_gridState._popForced, and _popMoForced for mouseover bars), put back
--  exactly on close. Everything else is darkened by textures of ours drawn
--  AROUND the bars. Over each bar that has bar spells sits a click catcher of
--  ours that toggles its tick, and the full-screen frame under the catchers
--  eats every other click, so no action button can be clicked through the
--  view. Never a strata, level, alpha, parent, point or mouse change on an
--  action button, a bar frame or a Blizzard frame.
--
--  Out of combat only: it does not open in combat, in Unlock Mode, in Edit
--  Mode, in a vehicle or with something on the cursor, and combat closes it
--  with nothing changed. Built on
--  the first open and kept; nothing is registered, hooked or running while it
--  is closed. Loads after EUI_ActionBars_Populate.lua; reads ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...

local ipairs, pairs, next, type = ipairs, pairs, next, type
local max, min = math.max, math.min
local sort, concat = table.sort, table.concat
local wipe = wipe
local InCombatLockdown, GetCursorInfo = InCombatLockdown, GetCursorInfo
local issecretvalue = issecretvalue

local EAB, EAB_VTABLE = ns.EAB, ns.EAB_VTABLE
local I = ns._internals
local _gridState, barFrames, BAR_LOOKUP = I._gridState, I.barFrames, I.BAR_LOOKUP

local PANEL_W = 460   -- the panel's width
local SIDE = 20       -- panel edge to its text and listed bars
local BTN_W = 150     -- Populate and Cancel
local PAD = 4         -- clear space around a bar inside the darkening
local DIM_A = 0.6     -- the darkening's alpha
local HEAD_H = 18     -- a bar's tick and name, above or below the bar
local BOX = 14        -- the tick box
local ROW_H = 26      -- a bar listed in the panel (its frame gave no rect)
-- Where the panel's centre may stand, as a share of the screen height: the
-- centre first, then the upper and the lower part, the first that covers no
-- highlighted bar.
local SPOTS = { 0.5, 0.78, 0.22 }

local V = {}             -- ns.PopulatePicker
local view               -- the frames, built on the first open
local isOpen = false
local hidPanel = false   -- this open hid the options panel
local entries            -- this open's ns.Populate.Bars()
local ticks = {}         -- [barKey] = true while ticked
local byKey = {}         -- [barKey] = this open's entry
local holes = {}         -- the highlighted bars' rects { l, r, t, b }, view units
local nHoles = 0
local listed = {}        -- catchers shown as rows in the panel
local ys, order, parts = {}, {}, {}   -- scratch of the darkening and the notes
local Finish             -- closes the view (below)

-- A bar can be ticked when it is switched on in the profile and has a frame.
local function Tickable(e)
    return not e.off and barFrames[e.key] ~= nil
end

local function BarName(key)
    local info = BAR_LOOKUP[key]
    return EllesmereUI.L(info and info.label or key)
end

-- Blizzard's own test for the bars that replace the player's (the vehicle,
-- override, possess and temporary shapeshift bars), and a pet battle.
local function InVehicleLike()
    local AB = C_ActionBar
    if AB.HasVehicleActionBar() or AB.HasOverrideActionBar()
       or AB.IsPossessBarVisible() or AB.HasTempShapeshiftActionBar() then
        return true
    end
    local pb = C_PetBattles
    return (pb and pb.IsInBattle and pb.IsInBattle()) and true or false
end

local function Refuse(reason, msg)
    EllesmereUI.PrintError(msg)
    return false, reason
end

-------------------------------------------------------------------------------
--  The forced-visible set. Planted only on bars with no runtime override yet,
--  so a toggle key's, the spellbook's or a drag's entry is never taken over;
--  on close only the entries still reading "always" go. Mouseover bars are
--  faded in through the hover system and held by Hover.SpellbookHolds, which
--  reads _popMoForced: the set is emptied BEFORE the bars fade out.
-------------------------------------------------------------------------------
local function Plant()
    local forced, mo
    local ov = EAB._visOverride
    for _, e in ipairs(entries) do
        if Tickable(e) and not (ov and ov[e.key]) then
            if not ov then
                ov = {}
                EAB._visOverride = ov
            end
            ov[e.key] = "always"
            forced = forced or {}
            forced[e.key] = true
        end
    end
    _gridState._popForced = forced
    if forced then EAB:RefreshRuntimeVisibility() end
    local Hover = EAB_VTABLE.Hover
    for _, e in ipairs(entries) do
        if Tickable(e) then
            local key = e.key
            local s = Hover.GetSettings(key)
            if s and s.mouseoverEnabled then
                -- Listed before the fade-in, so a close always finds it.
                if not mo then
                    mo = {}
                    _gridState._popMoForced = mo
                end
                mo[key] = true
                Hover.FadeInOne(key, Hover.GetState(key, barFrames[key]))
            end
        end
    end
    _gridState._popMoForced = mo
end

-- Also in combat: RefreshRuntimeVisibility leaves its secure writes to the
-- combat-end apply there.
local function Restore()
    local Hover = EAB_VTABLE.Hover
    local mo = _gridState._popMoForced
    _gridState._popMoForced = nil
    if mo then
        for key in pairs(mo) do
            local s = Hover.GetSettings(key)
            local frame = barFrames[key]
            if s and s.mouseoverEnabled and frame then
                local state = Hover.GetState(key, frame)
                if not state.isHovered then Hover.FadeOut(key, state) end
            end
        end
    end
    local forced = _gridState._popForced
    if forced then
        _gridState._popForced = nil
        local ov = EAB._visOverride
        if ov then
            for key in pairs(forced) do
                if ov[key] == "always" then ov[key] = nil end
            end
        end
        EAB:RefreshRuntimeVisibility()
    end
end

-------------------------------------------------------------------------------
--  Ticks and their look
-------------------------------------------------------------------------------
local function Paint(c)
    local hover = c.hover
    if ticks[c.key] then
        local ac = EllesmereUI.ELLESMERE_GREEN
        local r, g, b = ac.r, ac.g, ac.b
        c.brd:SetColor(r, g, b, 1)
        c.wash:SetColorTexture(r, g, b, hover and 0.22 or 0.14)
        c.boxBrd:SetColor(r, g, b, 1)
        c.fill:SetColorTexture(r, g, b, 1)
        c.fill:Show()
    else
        c.brd:SetColor(1, 1, 1, hover and 0.7 or 0.35)
        c.wash:SetColorTexture(1, 1, 1, hover and 0.08 or 0)
        c.boxBrd:SetColor(1, 1, 1, hover and 0.9 or 0.5)
        c.fill:Hide()
    end
end

-- Populate is inert and dim while nothing is ticked.
local function RepaintAll()
    for _, c in ipairs(view.catchers) do
        if c.key then Paint(c) end
    end
    local any = next(ticks) ~= nil
    local b = view.populate
    b:SetAlpha(any and 1 or 0.35)
    b:EnableMouse(any)
end

-- A tied pair (a retail druid's Action Bar 1 and Action Bar 10 share the
-- Moonkin Form page) moves together.
local function SetTick(key, on)
    local e = byKey[key]
    if not e then return end
    ticks[key] = on or nil
    if e.tie then ticks[e.tie] = on or nil end
    RepaintAll()
end

local function CatcherOf(self) return self.catcher or self end

local function OnCatcherClick(self)
    local c = CatcherOf(self)
    if c.key then SetTick(c.key, not ticks[c.key]) end
end

local function OnCatcherEnter(self)
    local c = CatcherOf(self)
    c.hover = true
    if c.key then Paint(c) end
end

local function OnCatcherLeave(self)
    local c = CatcherOf(self)
    c.hover = false
    if c.key then Paint(c) end
end

-------------------------------------------------------------------------------
--  Text under a bar: the form and stance pages Action Bar 1's tick also
--  fills, and on a tied pair the page the two bars share.
-------------------------------------------------------------------------------
local function TiedFormName(e)
    local partner = byKey[e.tie]
    if partner and partner.pages then
        for _, p in ipairs(partner.pages) do
            if p.tie == e.key and p.label then return EllesmereUI.L(p.label) end
        end
    end
    return EllesmereUI.L("Moonkin Form")
end

local function NoteFor(e)
    if e.key == "MainBar" then
        local pages = e.pages
        if not pages then return nil end
        wipe(parts)
        local own = false
        for _, p in ipairs(pages) do
            if p.page == 1 then
                own = true
            else
                local name = p.label and EllesmereUI.L(p.label) or EllesmereUI.Lf("Page %d", p.page)
                if p.tie then
                    name = EllesmereUI.Lf("%1$s (also %2$s)", name, BarName(p.tie))
                end
                parts[#parts + 1] = name
            end
        end
        if #parts == 0 then return nil end
        local list = concat(parts, ", ")
        wipe(parts)
        if own then return EllesmereUI.Lf("Also fills: %s", list) end
        return EllesmereUI.Lf("Fills: %s", list)
    elseif e.tie then
        return EllesmereUI.Lf("Also %1$s in %2$s", EllesmereUI.L("Action Bar 1"), TiedFormName(e))
    end
    return nil
end

-------------------------------------------------------------------------------
--  Frames
-------------------------------------------------------------------------------
local function SetCatcherScripts(f)
    f:RegisterForClicks("LeftButtonUp")
    f:SetScript("OnClick", OnCatcherClick)
    f:SetScript("OnEnter", OnCatcherEnter)
    f:SetScript("OnLeave", OnCatcherLeave)
end

-- A text drawn over the game world. Its drop shadow comes from the shared
-- shadow font object: a shadow set on the string itself is not drawn.
local function OverlayFont(parent, size, alpha)
    local fs = EllesmereUI.MakeFont(parent, size, "", 1, 1, 1, alpha)
    local path, height, flags = fs:GetFont()
    EllesmereUI.PrimeFontShadow(fs, true)
    fs:SetFont(path, height, flags)
    return fs
end

-- One per tickable bar, pooled by index; chrome built once, the bar, texts,
-- anchors and level set again on every use.
local function NewCatcher(i)
    local v = view
    local c = CreateFrame("Button", nil, v.dimmer)
    SetCatcherScripts(c)
    c.wash = EllesmereUI.SolidTex(c, "BACKGROUND", 1, 1, 1, 0)
    c.wash:SetAllPoints()
    c.brd = EllesmereUI.MakeBorder(c, 1, 1, 1, 0.35)
    -- The tick and the bar's name: a second click target beside the bar.
    local head = CreateFrame("Button", nil, c)
    SetCatcherScripts(head)
    head:SetHeight(HEAD_H)
    head.catcher = c
    c.head = head
    local box = CreateFrame("Frame", nil, head)
    box:SetSize(BOX, BOX)
    box:SetPoint("LEFT", head, "LEFT", 0, 0)
    EllesmereUI.SolidTex(box, "BACKGROUND", 0, 0, 0, 0.8):SetAllPoints()
    c.boxBrd = EllesmereUI.MakeBorder(box, 1, 1, 1, 0.5)
    c.fill = EllesmereUI.SolidTex(box, "ARTWORK", 1, 1, 1, 1)
    c.fill:SetPoint("TOPLEFT", box, "TOPLEFT", 3, -3)
    c.fill:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -3, 3)
    c.label = OverlayFont(head, 13)
    c.label:SetPoint("LEFT", box, "RIGHT", 6, 0)
    c.note = OverlayFont(c, 12, 0.8)
    v.catchers[i] = c
    return c
end

local function Cancel() Finish(true) end

local function OnPopulate()
    if not isOpen or next(ticks) == nil then return end
    local P = ns.Populate
    if not P then return end
    local set = {}
    for key in pairs(ticks) do set[key] = true end
    local placed, reason = P.Run(set)
    if placed == nil and reason == "cursor" then
        EllesmereUI.PrintError(EllesmereUI.L("Put down what your cursor holds first."))
        return
    end
    Finish(true, true)
end

-- Events are registered only while the view is open; each closes it.
local function OnEvent(_, event)
    if not isOpen then return end
    Finish(false)
    if event == "PLAYER_REGEN_DISABLED" then
        EllesmereUI.PrintError(EllesmereUI.L("Choose Bars closed for combat. Nothing was changed."))
    end
end

local function Build()
    local v = { catchers = {}, darks = {}, offLines = {} }
    view = v
    -- The shell's dimmer covers the screen and eats the mouse (no action
    -- button can be clicked under it); it draws nothing itself, the
    -- darkening is the textures around the bars. Escape and controller Back
    -- cancel. Born shown: hidden until the first open shows it.
    v.dimmer, v.popup = EllesmereUI.BuildPopupShell("EUIPopulatePicker", {
        w = PANEL_W, h = 160, bump = 1, dimAlpha = 0, onEscape = Cancel,
    })
    v.dimmer:Hide()
    -- The panel's scale goes to the dimmer, the panel keeps its bump.
    EllesmereUI._popupFrames[#EllesmereUI._popupFrames + 1] = { popup = v.popup, dimmer = v.dimmer }
    local popup = v.popup

    v.title = EllesmereUI.MakeFont(popup, 16, "", 1, 1, 1)
    v.title:SetPoint("TOP", popup, "TOP", 0, -20)
    v.title:SetWidth(PANEL_W - SIDE * 2)
    v.title:SetJustifyH("CENTER")
    v.title:SetWordWrap(true)
    v.title:SetText(EllesmereUI.L("Select the action bars you want to overwrite"))

    local ar, ag, ab = EllesmereUI.GetAccentColor()
    local font = EllesmereUI.EXPRESSWAY
    v.populate = EllesmereUI.MakeActionButton(popup, font, EllesmereUI.L("Populate"), ar, ag, ab, { w = BTN_W })
    v.populate:SetPoint("BOTTOMLEFT", popup, "BOTTOM", 6, 18)
    v.populate:SetScript("OnClick", OnPopulate)
    v.cancel = EllesmereUI.MakeActionButton(popup, font, EllesmereUI.L("Cancel"), 1, 1, 1,
        { w = BTN_W, secondary = true, hoverA = 0.8 })
    v.cancel:SetPoint("BOTTOMRIGHT", popup, "BOTTOM", -6, 18)
    v.cancel:SetScript("OnClick", Cancel)

    v.shell = ns.TakeShell()
    v.shell:SetScript("OnEvent", OnEvent)
end

-------------------------------------------------------------------------------
--  Layout (once per open)
-------------------------------------------------------------------------------
-- A bar's rect in the view's units, padded and clipped to the screen; false
-- when the frame has none to give.
local function ReadRect(frame, dES, W, H, h)
    local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if type(l) ~= "number" or type(r) ~= "number" or type(t) ~= "number" or type(b) ~= "number" then
        return false
    end
    if issecretvalue(l) or issecretvalue(r) or issecretvalue(t) or issecretvalue(b) then
        return false
    end
    local k = frame:GetEffectiveScale() / dES
    l, r = max(0, l * k - PAD), min(W, r * k + PAD)
    t, b = min(H, t * k + PAD), max(0, b * k - PAD)
    if r - l < 8 or t - b < 8 then return false end
    h.l, h.r, h.t, h.b = l, r, t, b
    return true
end

local function ByLeft(a, b) return holes[a].l < holes[b].l end

local function Dark(i, x0, y0, x1, y1)
    local v = view
    local tex = v.darks[i]
    if not tex then
        tex = v.dimmer:CreateTexture(nil, "BACKGROUND")
        tex:SetColorTexture(0, 0, 0, DIM_A)
        v.darks[i] = tex
    end
    tex:ClearAllPoints()
    tex:SetPoint("BOTTOMLEFT", v.dimmer, "BOTTOMLEFT", x0, y0)
    tex:SetPoint("TOPRIGHT", v.dimmer, "BOTTOMLEFT", x1, y1)
    tex:Show()
end

-- The screen minus the bars' rects, in horizontal bands split at every rect
-- edge: in each band, the gaps between the rects that span it.
local function DrawDarks(W, H)
    wipe(ys)
    ys[1], ys[2] = 0, H
    for i = 1, nHoles do
        local h = holes[i]
        ys[#ys + 1] = h.b
        ys[#ys + 1] = h.t
    end
    sort(ys)
    local used = 0
    for i = 1, #ys - 1 do
        local y0, y1 = ys[i], ys[i + 1]
        if y1 > y0 then
            wipe(order)
            for j = 1, nHoles do
                local h = holes[j]
                if h.b <= y0 and h.t >= y1 then order[#order + 1] = j end
            end
            if #order > 1 then sort(order, ByLeft) end
            local x = 0
            for j = 1, #order do
                local h = holes[order[j]]
                if h.l > x then
                    used = used + 1
                    Dark(used, x, y0, h.l, y1)
                end
                if h.r > x then x = h.r end
            end
            if x < W then
                used = used + 1
                Dark(used, x, y0, W, y1)
            end
        end
    end
    for i = used + 1, #view.darks do view.darks[i]:Hide() end
end

-- The tick and name above the bar (below it when the screen's top edge is
-- too near), the note on the other side, both kept on the screen.
local function PlaceOverBar(c, h, W, H, note)
    local v = view
    local head, fs = c.head, c.note
    c:ClearAllPoints()
    c:SetFrameLevel(v.dimmer:GetFrameLevel() + 2)
    c:SetPoint("BOTTOMLEFT", v.dimmer, "BOTTOMLEFT", h.l, h.b)
    c:SetPoint("TOPRIGHT", v.dimmer, "BOTTOMLEFT", h.r, h.t)
    local above = h.t + HEAD_H + 4 <= H
    local right = h.l + head:GetWidth() > W
    head:ClearAllPoints()
    if above then
        head:SetPoint(right and "BOTTOMRIGHT" or "BOTTOMLEFT", c, right and "TOPRIGHT" or "TOPLEFT", 0, 4)
    else
        head:SetPoint(right and "TOPRIGHT" or "TOPLEFT", c, right and "BOTTOMRIGHT" or "BOTTOMLEFT", 0, -4)
    end
    fs:ClearAllPoints()
    if not note then
        fs:Hide()
        return
    end
    fs:SetText(note)
    local nRight = h.l + fs:GetStringWidth() > W
    local side = nRight and "RIGHT" or "LEFT"
    if above and h.b - 20 >= 0 then
        fs:SetPoint("TOP" .. side, c, "BOTTOM" .. side, 0, -4)
    elseif above then
        fs:SetPoint("BOTTOM" .. side, head, "TOP" .. side, 0, 2)
    else
        fs:SetPoint("TOP" .. side, head, "BOTTOM" .. side, 0, -2)
    end
    fs:Show()
end

-- A bar whose frame gave no rect is ticked from a row in the panel.
local function PlaceInPanel(c, y)
    local v = view
    local head = c.head
    c:ClearAllPoints()
    c:SetFrameLevel(v.popup:GetFrameLevel() + 3)
    c:SetPoint("TOPLEFT", v.popup, "TOPLEFT", SIDE, y)
    c:SetPoint("TOPRIGHT", v.popup, "TOPRIGHT", -SIDE, y)
    c:SetHeight(ROW_H)
    head:ClearAllPoints()
    head:SetPoint("LEFT", c, "LEFT", 6, 0)
    c.note:Hide()
end

-- Whether a switched-off bar loses nothing: every page it has spells on comes
-- in through its tied partner, which can be ticked. A switched-off Action
-- Bar 10 (its one page is Action Bar 1's Moonkin page) loses nothing; a
-- switched-off Action Bar 1 loses its own and its other form pages.
local function PartnerCovers(e)
    local partner = e.tie and byKey[e.tie]
    if not (partner and Tickable(partner)) then return false end
    for _, p in ipairs(e.pages) do
        local found = false
        for _, q in ipairs(partner.pages) do
            if q.page == p.page then
                found = true
                break
            end
        end
        if not found then return false end
    end
    return true
end

-- The sentence, a line per switched-off bar whose spells are skipped (none
-- for a bar whose pages all come in through its tied partner), the listed
-- bars and the buttons. Returns the panel's height.
local function LayoutPanel(nListed)
    local v = view
    local y = 20 + v.title:GetStringHeight() + 12
    local n = 0
    for _, e in ipairs(entries) do
        if e.off and not PartnerCovers(e) then
            n = n + 1
            local fs = v.offLines[n]
            if not fs then
                fs = EllesmereUI.MakeFont(v.popup, 12, "", 1, 1, 1, 0.6)
                fs:SetWidth(PANEL_W - SIDE * 2)
                fs:SetJustifyH("CENTER")
                fs:SetWordWrap(true)
                v.offLines[n] = fs
            end
            fs:ClearAllPoints()
            fs:SetPoint("TOP", v.popup, "TOP", 0, -y)
            fs:SetText(EllesmereUI.Lf("%s is switched off in this profile, so its spells are skipped.", EllesmereUI.L(e.label)))
            fs:Show()
            y = y + fs:GetStringHeight() + 6
        end
    end
    for i = n + 1, #v.offLines do v.offLines[i]:Hide() end
    for i = 1, nListed do
        PlaceInPanel(listed[i], -y)
        y = y + ROW_H + 4
    end
    y = y + 10 + 38 + 18
    EllesmereUI.PanelPP.Size(v.popup, PANEL_W, y)
    return y
end

-- At the screen's centre, or higher or lower when it would cover a bar.
local function PlacePanel(W, H, ph, dES)
    local v = view
    local s = v.popup:GetEffectiveScale() / dES
    local pw, phd = PANEL_W * s, ph * s
    local l, r = (W - pw) / 2, (W + pw) / 2
    local cy
    for i = 1, #SPOTS do
        local y = min(max(H * SPOTS[i], phd / 2 + 10), H - phd / 2 - 10)
        local b, t = y - phd / 2, y + phd / 2
        local hit = false
        for j = 1, nHoles do
            local h = holes[j]
            if h.l < r and h.r > l and h.b < t and h.t > b then
                hit = true
                break
            end
        end
        if not hit then
            cy = y
            break
        end
    end
    cy = cy or min(max(H * SPOTS[2], phd / 2 + 10), H - phd / 2 - 10)
    v.popup:ClearAllPoints()
    v.popup:SetPoint("CENTER", v.dimmer, "BOTTOMLEFT", (W / 2) / s, cy / s)
end

local function Layout()
    local v = view
    local dimmer = v.dimmer
    local W, H, dES = dimmer:GetWidth(), dimmer:GetHeight(), dimmer:GetEffectiveScale()
    nHoles = 0
    local nC, nListed = 0, 0
    for _, e in ipairs(entries) do
        if Tickable(e) then
            nC = nC + 1
            local c = v.catchers[nC] or NewCatcher(nC)
            c.key, c.hover = e.key, false
            c.label:SetText(EllesmereUI.L(e.label))
            c.head:SetWidth(BOX + 6 + c.label:GetStringWidth() + 2)
            local h = holes[nHoles + 1]
            if not h then
                h = {}
                holes[nHoles + 1] = h
            end
            if ReadRect(barFrames[e.key], dES, W, H, h) then
                nHoles = nHoles + 1
                PlaceOverBar(c, h, W, H, NoteFor(e))
            else
                nListed = nListed + 1
                listed[nListed] = c
            end
            c:Show()
        end
    end
    for i = nC + 1, #v.catchers do
        local c = v.catchers[i]
        c:Hide()
        c.key = nil
    end
    for i = nListed + 1, #listed do listed[i] = nil end
    DrawDarks(W, H)
    PlacePanel(W, H, LayoutPanel(nListed), dES)
    RepaintAll()
end

local function PlantAndLayout()
    Plant()
    Layout()
end

-------------------------------------------------------------------------------
--  Public: Open, Close, IsOpen
-------------------------------------------------------------------------------
-- Closes the view, puts the bars' visibility back and changes no slot.
-- reopen: the player's own Cancel, Escape or Populate brings back the
-- options panel this open hid. populated: a Populate ran, so the options
-- page re-reads (Auto Populate comes alive), at once when the panel is
-- shown again, else at the panel's next show.
Finish = function(reopen, populated)
    if not isOpen then return end
    isOpen = false
    local v = view
    v.shell:UnregisterAllEvents()
    v.dimmer:Hide()
    Restore()
    wipe(ticks)
    wipe(byKey)
    entries = nil
    local reshow = hidPanel and reopen and not InCombatLockdown()
    hidPanel = false
    if reshow then EllesmereUI:Show() end
    if reshow or populated then EllesmereUI:RefreshPage() end
end

function V.Close()
    Finish(false)
end

function V.IsOpen()
    return isOpen
end

-- Returns true, or false and the reason after a red chat line.
function V.Open()
    if isOpen then return true end
    if InCombatLockdown() then
        return Refuse("combat", EllesmereUI.L("Cannot choose bars during combat."))
    end
    if EllesmereUI._unlockModeActive then
        return Refuse("unlock", EllesmereUI.L("Close Unlock Mode first."))
    end
    if EllesmereUI.EditModeOpen() then
        return Refuse("editmode", EllesmereUI.L("Close Edit Mode first."))
    end
    if InVehicleLike() then
        return Refuse("vehicle", EllesmereUI.L("Leave your vehicle first."))
    end
    -- A full cursor makes the bars' drag pass raise every bar above the view's
    -- click catchers, so a click on a bar would drop it on an action button.
    if GetCursorInfo() then
        return Refuse("cursor", EllesmereUI.L("Put down what your cursor holds first."))
    end
    local P = ns.Populate
    if P then P.Sync() end
    if not (P and P.HasData()) then
        return Refuse("nodata", EllesmereUI.L("This profile has no action bar spells for this character."))
    end
    local list = P.Bars()
    wipe(byKey)
    local any = false
    for _, e in ipairs(list) do
        byKey[e.key] = e
        if Tickable(e) then any = true end
    end
    if not any then
        wipe(byKey)
        return Refuse("nobars", EllesmereUI.L("None of the bars with action bar spells is switched on."))
    end
    entries = list
    if not view then Build() end
    -- The bars ticked at the last Populate (none the first time).
    wipe(ticks)
    local last = P.LastBars()
    if last then
        for key in pairs(last) do
            local e = byKey[key]
            if e and Tickable(e) then
                ticks[key] = true
                if e.tie then ticks[e.tie] = true end
            end
        end
    end
    hidPanel = EllesmereUI:IsShown() and true or false
    if hidPanel then EllesmereUI:Hide() end
    isOpen = true
    -- An error while planting or laying out (a translated format string, say)
    -- closes the view again: the bars put back, the options panel shown.
    local ok, err = pcall(PlantAndLayout)
    if not ok then
        Finish(true)
        geterrorhandler()(err)
        return false, "error"
    end
    view.dimmer:Show()
    local sh = view.shell
    sh:RegisterEvent("PLAYER_REGEN_DISABLED")
    sh:RegisterEvent("PLAYER_ENTERING_WORLD")
    sh:RegisterEvent("UPDATE_OVERRIDE_ACTIONBAR")
    sh:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
    if not EllesmereUI.IS_FOREVER then
        sh:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
    end
    return true
end

ns.PopulatePicker = V
