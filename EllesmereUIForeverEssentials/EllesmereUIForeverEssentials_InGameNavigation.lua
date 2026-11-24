if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_InGameNavigation.lua  (WoW Forever only)
--  Show Waypoints in the World: a click-through marker with a beam over what
--  you track, its name, the distance and the time to get there, and an arrow
--  at the screen edge while it is out of sight; it steps aside where the game
--  says you got there. Drawn on the game's navigation frame, which Forever
--  places but shows no marker on (Invalid state); that frame is only read.
--  No timer: Build says how its moves and new distances are heard.
-------------------------------------------------------------------------------
local _, module = ...

-- Settings live in EllesmereUIDB.inGameNavigation; unset keys read these.
local F = module.Feature("inGameNavigation", {
    enabled = false,
})
local Enabled = F.Enabled
local IsSecret = EllesmereUI.IsSecret

local ST = Enum.SuperTrackingType
local NS = Enum.NavigationState
-- The game's own icon for each kind of target (Blizzard_QuestNavigation,
-- Forever 1.60.1.71037); any other kind takes the quest one.
local ICONS = {
    [ST.Quest]        = "Navigation-Tracked-Icon",
    [ST.UserWaypoint] = "Waypoint-MapPin-Tracked",
    [ST.Content]      = "Waypoint-MapPin-Tracked",
    [ST.Corpse]       = "Navigation-Tombstone-Icon",
}

local EDGE = 0.38       -- edge path: an ellipse at this share of the screen from its center
local ARROW_GAP = 26    -- arrow center from the icon center
local ARRIVE_MARGIN = 5 -- yards past the arrival point before the marker comes back
local BEAM_HEIGHT = 220 -- the whole beam, its fade-in included
local BEAM_BASE = 16    -- the beam fades in over this much above the icon

-- Only while something is tracked (Attach).
local TRACKED_EVENTS = {
    "NAVIGATION_DESTINATION_REACHED",
    "PLAYER_STARTED_MOVING",
    "PLAYER_STOPPED_MOVING",
}

-- Inert until the feature turns on.
local eventFrame = CreateFrame("Frame")
local marker, icon, arrow, nameText, watch
local beam, beamBase, glow, glowBase
local info, infoHead, infoTail  -- distance line: its frame, the text before the number, the rest
local infoDigits = {}     -- one text per digit of the distance
local MAX_DIGITS = 6
local cellW               -- the widest digit in the module font
local rangeFormat         -- the distance with a short unit (Build)
local tint, clear         -- gradient colors, reused
local navFrame            -- the game's navigation frame while one exists
local shown, atEdge       -- last visibility and edge state applied
local lastYards, lastEta  -- last distance and time written
local lastHead, lastTail, lastCount  -- the line's texts and digit count when it was laid out
local cellText = {}       -- the digit each cell shows
local lastDX, lastDY      -- last edge placement
local arrivedAt           -- the distance when the game said you got there

-- Accent color: on each new navigation frame and on an accent change.
local function Paint()
    local r, g, b = EllesmereUI.GetAccentColor()
    icon:SetVertexColor(r, g, b)
    arrow:SetVertexColor(r, g, b)
    tint.r, tint.g, tint.b = r, g, b
    clear.r, clear.g, clear.b = r, g, b
    tint.a = 0.8
    beamBase:SetGradient("VERTICAL", clear, tint)
    beam:SetGradient("VERTICAL", tint, clear)
    tint.a = 0.25
    glowBase:SetGradient("VERTICAL", clear, tint)
    glow:SetGradient("VERTICAL", tint, clear)
    nameText:SetTextColor(r, g, b)
end

-- The module font, and the cell width it gives a digit: on each new
-- navigation frame.
local function ApplyFonts()
    local font = EllesmereUI.GetFontPath("essentials")
    EllesmereUI.ApplyModuleFont(nameText, font, 13, "essentials")
    EllesmereUI.ApplyModuleFont(infoHead, font, 12, "essentials")
    EllesmereUI.ApplyModuleFont(infoTail, font, 12, "essentials")
    for i = 1, MAX_DIGITS do
        EllesmereUI.ApplyModuleFont(infoDigits[i], font, 12, "essentials")
    end
    cellW = 0
    for n = 0, 9 do
        cellW = math.max(cellW, infoTail:GetUnboundedStringWidthForText(tostring(n)))
    end
    for i = 1, MAX_DIGITS do infoDigits[i]:SetWidth(cellW) end
    info:SetHeight(infoTail:GetLineHeight())
end

-- Icon and name for what is tracked now. Only a quest has a name; the
-- distance line then sits under it.
local function UpdateTarget()
    local kind = C_SuperTrack.GetHighestPrioritySuperTrackingType()
    icon:SetAtlas(ICONS[kind] or ICONS[ST.Quest], true)
    icon:SetDesaturated(true)
    local title
    if kind == ST.Quest then
        local questID = C_SuperTrack.GetSuperTrackedQuestID()
        title = questID and C_QuestLog.GetTitleForQuestID(questID)
    end
    nameText:SetText(title or "")
    info:ClearAllPoints()
    if title then
        info:SetPoint("TOP", nameText, "BOTTOM", 0, -2)
    else
        info:SetPoint("TOP", icon, "BOTTOM", 0, -4)
    end
    lastYards, lastEta, lastHead, arrivedAt = nil, nil, nil, nil
end

-- Distance, and the time to get there at the current speed (none while
-- standing still, or while the game keeps the speed secret). Rewritten only
-- when one of them changes: the time counts down in seconds up to 89, in
-- whole minutes above (SecondsToTime with one unit turns to minutes at 90 s).
local function UpdateTexts()
    local yards = math.floor(C_Navigation.GetDistance() + 0.5)
    local eta
    local speed = GetUnitSpeed("player")
    if not IsSecret(speed) and speed > 0 then
        eta = yards / speed
        eta = eta <= 89 and math.ceil(eta) or math.max(2, math.floor(eta / 60 + 0.5)) * 60
    end
    if yards == lastYards and eta == lastEta then return end
    lastYards, lastEta = yards, eta
    -- The number up to 999, abbreviated above, as Blizzard_QuestNavigation writes it.
    local text = rangeFormat:format(yards < 1000 and tostring(yards) or AbbreviateNumbers(yards))
    if eta and eta > 0 then text = text .. "  -  " .. SecondsToTime(eta, false, false, 1) end
    -- Each digit of the distance in a cell as wide as the widest one, so a new
    -- distance only changes the digits that differ, in place; the line is laid
    -- out and centered again only when the text around them or the digit
    -- count changes.
    local s, e = text:find("%d+")
    if not s or e - s >= MAX_DIGITS then s, e = #text + 1, #text end
    local head, tail = text:sub(1, s - 1), text:sub(e + 1)
    local count = e - s + 1
    for i = 1, MAX_DIGITS do
        local digit = i <= count and text:sub(s + i - 1, s + i - 1) or ""
        if cellText[i] ~= digit then
            cellText[i] = digit
            infoDigits[i]:SetText(digit)
        end
    end
    if head == lastHead and tail == lastTail and count == lastCount then return end
    lastHead, lastTail, lastCount = head, tail, count
    infoHead:SetText(head)
    infoTail:SetText(tail)
    local x = infoHead:GetStringWidth()
    for i = 1, count do
        infoDigits[i]:SetPoint("LEFT", info, "LEFT", x, 0)
        x = x + cellW
    end
    infoTail:SetPoint("LEFT", info, "LEFT", x, 0)
    info:SetWidth(x + infoTail:GetStringWidth())
end

-- Near the screen edge on the destination's side, the arrow turned toward
-- it. dx, dy: from the screen center to the game's (clamped) frame.
local function PlaceAtEdge(dx, dy)
    if lastDX and math.abs(dx - lastDX) < 0.5 and math.abs(dy - lastDY) < 0.5 then return end
    local len = math.sqrt(dx * dx + dy * dy)
    if len == 0 then return end
    lastDX, lastDY = dx, dy
    local a, b = UIParent:GetWidth() * EDGE, UIParent:GetHeight() * EDGE
    local k = 1 / math.sqrt(dx * dx / (a * a) + dy * dy / (b * b))
    marker:ClearAllPoints()
    marker:SetPoint("CENTER", UIParent, "CENTER", dx * k, dy * k)
    arrow:SetRotation(math.atan2(dy, dx) - math.pi / 2)
    arrow:ClearAllPoints()
    arrow:SetPoint("CENTER", icon, "CENTER", dx / len * ARROW_GAP, dy / len * ARROW_GAP)
end

-- On each move of the game's frame, each distance the game writes, and the
-- events below.
local function Refresh()
    if not navFrame then return end
    -- Hidden once the game says you got there, until you walk back out a few
    -- yards past that distance (coming back in, it says so again).
    if arrivedAt and C_Navigation.GetDistance() > arrivedAt + ARRIVE_MARGIN then arrivedAt = nil end
    -- Only in the state Forever reports, where the game shows no marker.
    local show = not arrivedAt and C_Navigation.HasValidScreenPosition()
        and C_Navigation.GetTargetState() == NS.Invalid
    local edge, nx, ny, scale
    if show then
        edge = C_Navigation.WasClampedToScreen()
        if edge then
            -- The edge spot comes from the game's frame's geometry, which its
            -- anchoring can make secret: no math on it, the marker waits hidden
            -- until a pass can read it.
            nx, ny = navFrame:GetCenter()
            scale = navFrame:GetEffectiveScale()
            if IsSecret(nx) or IsSecret(ny) or IsSecret(scale) then show = false end
        end
    end
    if show ~= shown then
        shown = show
        marker:SetShown(show)
    end
    if not show then return end
    if edge ~= atEdge then
        atEdge = edge
        beam:SetShown(not edge)
        beamBase:SetShown(not edge)
        glow:SetShown(not edge)
        glowBase:SetShown(not edge)
        nameText:SetShown(not edge)
        info:SetShown(not edge)
        arrow:SetShown(edge)
        lastDX, lastDY = nil, nil
        if not edge then
            marker:ClearAllPoints()
            marker:SetPoint("CENTER", navFrame, "CENTER")
        end
    end
    if edge then
        -- The game's frame lives at WorldFrame's scale, the marker at UIParent's.
        local cx, cy = UIParent:GetCenter()
        if nx then
            local s = scale / UIParent:GetEffectiveScale()
            PlaceAtEdge(nx * s - cx, ny * s - cy)
        end
    else
        UpdateTexts()
    end
end

local function BeamPart(layer, width, height, anchor)
    -- Off the pixel grid like every texture (the parent's image-setter hook),
    -- so the marker glides with the game's frame.
    local t = marker:CreateTexture(nil, layer)
    t:SetColorTexture(1, 1, 1, 1)
    t:SetBlendMode("ADD")
    t:SetSize(width, height)
    t:SetPoint("BOTTOM", anchor, "TOP")
    return t
end

-- Built the first time the feature has something to show.
local function Build()
    if marker then return end
    marker = CreateFrame("Frame", nil, UIParent)
    marker:SetFrameStrata("BACKGROUND")
    marker:SetSize(1, 1)
    marker:Hide()

    icon = marker:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("CENTER")

    -- The beam: a thin core in a wider glow, both fading in just above the
    -- icon and out toward the top.
    glowBase = BeamPart("BACKGROUND", 14, BEAM_BASE, icon)
    glow = BeamPart("BACKGROUND", 14, BEAM_HEIGHT - BEAM_BASE, glowBase)
    beamBase = BeamPart("BORDER", 3, BEAM_BASE, icon)
    beam = BeamPart("BORDER", 3, BEAM_HEIGHT - BEAM_BASE, beamBase)

    arrow = marker:CreateTexture(nil, "ARTWORK")
    arrow:SetAtlas("Navigation-Tracked-Arrow", true)   -- points up unrotated
    arrow:SetDesaturated(true)
    arrow:Hide()

    nameText = marker:CreateFontString(nil, "OVERLAY")
    nameText:SetPoint("TOP", icon, "BOTTOM", 0, -4)
    info = CreateFrame("Frame", nil, marker)
    info:SetSize(1, 1)
    infoHead = info:CreateFontString(nil, "OVERLAY")
    infoHead:SetPoint("LEFT")
    for i = 1, MAX_DIGITS do
        infoDigits[i] = info:CreateFontString(nil, "OVERLAY")
    end
    infoTail = info:CreateFontString(nil, "OVERLAY")

    -- No event reports the game's frame moving. This one is stretched from it
    -- to a point past WorldFrame's corner, the frame it hangs on (Attach), so
    -- each move resizes it. The game refuses an anchor set joining its frame
    -- to UIParent's. Nothing drawn, no mouse.
    watch = CreateFrame("Frame", nil, UIParent)
    watch:Hide()
    watch:SetScript("OnSizeChanged", function() Refresh() end)

    -- Walking straight at a far destination moves that frame too little for
    -- OnSizeChanged. Blizzard_QuestNavigation's marker, transparent on
    -- Forever, still rewrites its distance text each time the rounded
    -- distance changes: a post-hook on it hears every new yard.
    local gameDistance = SuperTrackedFrame and SuperTrackedFrame.DistanceText
    if gameDistance then
        hooksecurefunc(gameDistance, "SetText", function() Refresh() end)
    end

    tint, clear = CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 0)
    -- A short unit has no plural to get wrong. The game's own string
    -- (IN_GAME_NAVIGATION_RANGE) spells the unit out, with a plural the
    -- client picks from the number before it, which the digit cells split off.
    rangeFormat = EllesmereUI.L("%s yd")
    EllesmereUI.RegAccent({ type = "callback", fn = function()
        if navFrame then Paint() end
    end })
end

-- Hangs the marker on the game's navigation frame, or takes it down (nil).
local function Attach(nav)
    navFrame = nav
    shown, atEdge, lastYards, lastEta, lastDX, lastDY, arrivedAt = nil, nil, nil, nil, nil, nil, nil
    if not nav then
        for _, event in ipairs(TRACKED_EVENTS) do eventFrame:UnregisterEvent(event) end
        if marker then
            marker:Hide()
            marker:ClearAllPoints()
            watch:Hide()
            watch:ClearAllPoints()
        end
        return
    end
    Build()
    Paint()
    ApplyFonts()
    UpdateTarget()
    marker:ClearAllPoints()
    marker:SetPoint("CENTER", nav, "CENTER")
    watch:ClearAllPoints()
    watch:SetPoint("TOPLEFT", nav, "CENTER")
    watch:SetPoint("BOTTOMRIGHT", WorldFrame, "BOTTOMRIGHT", 2000, -2000)
    watch:Show()
    for _, event in ipairs(TRACKED_EVENTS) do eventFrame:RegisterEvent(event) end
    Refresh()
end

-- Moving or stopping shows or drops the time; arriving hides the marker.
eventFrame:SetScript("OnEvent", function(_, event, region)
    if event == "NAVIGATION_FRAME_CREATED" then
        Attach(region)
    elseif event == "NAVIGATION_FRAME_DESTROYED" then
        Attach(nil)
    elseif navFrame then
        if event == "SUPER_TRACKING_CHANGED" then
            UpdateTarget()
        elseif event == "NAVIGATION_DESTINATION_REACHED" then
            arrivedAt = C_Navigation.GetDistance()
        end
        Refresh()
    elseif event == "SUPER_TRACKING_CHANGED" then
        Attach(C_Navigation.GetFrame())
    end
end)

-- Login and the options; takes effect at once. Off: no event, nothing built.
local function Apply()
    if Enabled() then
        eventFrame:RegisterEvent("NAVIGATION_FRAME_CREATED")
        eventFrame:RegisterEvent("NAVIGATION_FRAME_DESTROYED")
        eventFrame:RegisterEvent("SUPER_TRACKING_CHANGED")
        Attach(C_Navigation.GetFrame())
    else
        eventFrame:UnregisterAllEvents()
        Attach(nil)
    end
end

-- The options switch.
local function Set(on)
    F.Cfg().enabled = on
    Apply()
end

-- Options-page entry points.
EllesmereUI._InGameNavigation = {
    Get = F.Get,
    Cfg = F.Cfg,
    Apply = Apply,
    Set = Set,
}

F.Start(Apply)
