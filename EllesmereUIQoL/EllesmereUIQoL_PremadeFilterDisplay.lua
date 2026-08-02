-------------------------------------------------------------------------------
--  EllesmereUIQoL_PremadeFilterDisplay.lua
--  Row-display enhancements for Blizzard's Premade Groups search results:
--  the leader's M+ score on each dungeon row, spec-icon / class-bar member
--  displays over the group-composition icons, and the shade drawn over rows the
--  filter rejects. Purely visual -- this file never filters, sorts or reorders
--  anything, and neither does the filter module any more: NOTHING in this addon
--  writes panel.results. EllesmereUIQoL_PremadeFilter.lua owns the criteria, the
--  verdict pass and the shared settings table; read its header for why.
--
--  Taint / secret-value safety (read before editing):
--   - Post-hooks only (hooksecurefunc) on LFGListSearchEntry_Update and
--     LFGListGroupDataDisplayEnumerate_Update. Both bodies exit before touching
--     anything while their setting is off (PGF's "exit early" pattern).
--   - Zero custom keys are ever written onto a Blizzard frame. Per-row state
--     lives in EXTERNAL weak-keyed tables (scoreFrames keyed by the row button,
--     overlays keyed by the Blizzard icon frame).
--   - NOTHING on a Blizzard frame, region or fontstring is ever written -- not
--     text, not shown state, not colour, not a property. Both features are
--     pools of OUR OWN frames parented to a Blizzard frame and drawn over it,
--     so turning them off is just hiding our frames. Where our overlay would
--     occlude something of Blizzard's that still matters (the leaver badge) we
--     READ its atlas/size/anchor and re-draw our own copy on top.
--   - Blizzard state we depend on is read only: button.resultID, the icon's
--     LeaverIcon, ActivityName's font family, DataDisplay's shown state.
--   - Every C_LFGList read goes through a pcall'd accessor with its arguments
--     in upvalues (no closure allocation) and every consumed field is
--     issecretvalue()-checked. A failed or secret read leaves that row exactly
--     as Blizzard rendered it.
--   - Nothing is hooked or created until one of the two settings is first
--     active; only a lone boot frame listening for PLAYER_LOGIN exists
--     unconditionally. Both settings off/DEFAULT costs nothing.
--   - No OnUpdate, no tickers. SetScript appears only on the two frames this
--     file creates itself (the boot frame and the ADDON_LOADED waiter).
-------------------------------------------------------------------------------

local issecretvalue = issecretvalue or function() return false end
local format, floor = string.format, math.floor

-- Blizzard_GroupFinder is load-on-demand, so the global may not exist yet when
-- this file loads; resolve it at use time (its value is 2 either way).
local function DungeonCategory()
    return GROUP_FINDER_CATEGORY_ID_DUNGEONS or 2
end

-- Blizzard's own fill order for the enumerate icons; mirrored so our overlays
-- land on the same icon Blizzard put that role on.
local ROLE_ORDER_FALLBACK = { "TANK", "HEALER", "DAMAGER" }

-------------------------------------------------------------------------------
--  Settings. The defaults table lives in EllesmereUIQoL_PremadeFilter.lua; we
--  read the shared db through the accessor it publishes (nil until its
--  PLAYER_LOGIN handler has run) and fall back inline for our two keys.
-------------------------------------------------------------------------------
local _dbFn

local function P()
    _dbFn = _dbFn or _G._EUI_PremadeFilter_DB
    local db = _dbFn and _dbFn()
    return db and db.profile and db.profile.premadeFilter
end

-- Both features stand alone: they are NOT gated on premadeFilter.enabled (the
-- filter panel's master switch), only on their own key plus the category and
-- panel-shown conditions at the call sites.
local function ShowScore()
    local p = P()
    if not p then return false end
    return p.showLeaderScore and true or false
end

local function MemberDisplay()
    local p = P()
    if not p then return "DEFAULT" end
    local mode = p.memberDisplay
    if mode == "SPEC" or mode == "SPEC_BAR" then return mode end
    return "DEFAULT"
end

-- The dimming pass IS gated on the filter panel's master switch, unlike the two
-- display features above: it is the visible half of the filter itself.
local function FilterEnabled()
    local p = P()
    return (p and p.enabled) and true or false
end

local function Active()
    return ShowScore() or MemberDisplay() ~= "DEFAULT" or FilterEnabled()
end

-- Rows only carry a leader score / role enumeration while the dungeon category
-- is being browsed; everything else is left to Blizzard.
local function DungeonBrowseActive()
    local panel = LFGListFrame and LFGListFrame.SearchPanel
    if not panel or not panel:IsShown() then return false end
    return panel.categoryID == DungeonCategory()
end

-------------------------------------------------------------------------------
--  Guarded reads
-------------------------------------------------------------------------------
-- issecretvalue() is tested first: comparing a secret value against nil throws
-- just as readily as consuming it, and some of these run outside a pcall.
local function Num(v)
    if issecretvalue(v) or v == nil or type(v) ~= "number" then return nil end
    return v
end
local function Str(v)
    if issecretvalue(v) or v == nil or type(v) ~= "string" then return nil end
    return v
end

local _rID
local _scoreOut, _membersOut

local function ReadScore()
    local info = C_LFGList.GetSearchResultInfo(_rID)
    if not info or issecretvalue(info) then return end
    _scoreOut = Num(info.leaderOverallDungeonScore)
end

local function ReadNumMembers()
    local info = C_LFGList.GetSearchResultInfo(_rID)
    if not info or issecretvalue(info) then return end
    _membersOut = Num(info.numMembers)
end

-------------------------------------------------------------------------------
--  Feature 1 -- leader M+ score on its own line above the role-icon strip
--
--  The score is OUR fontstring on OUR frame; Blizzard's ActivityName is never
--  written to. Geometry (LFGList.xml, LFGListSearchEntryTemplate): the entry is
--  312x54, DataDisplay is 125x24 anchored RIGHT/RIGHT at y=-1 -- so it spans
--  roughly y-15..-40 and leaves ~13px clear between its top edge and the row's
--  background inset at y=-2. Below the strip is not usable: the SPEC_BAR class
--  bars sit there. So the score goes ABOVE the strip, right-aligned to the same
--  -12 inset Icon1 uses, which keeps the row's 54px height untouched.
-------------------------------------------------------------------------------
local scoreText = {}          -- score -> pre-coloured string (built once each)
local _colorIn, _colorOut

local function ReadScoreColor()
    local c = C_ChallengeMode.GetDungeonScoreRarityColor(_colorIn)
    if not c or issecretvalue(c) then return end
    _colorOut = c
end

local function ScoreText(score)
    local t = scoreText[score]
    if t then return t end
    local r, g, b = 1, 1, 1
    if C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor then
        _colorIn, _colorOut = score, nil
        pcall(ReadScoreColor)
        local c = _colorOut
        if c then
            local cr, cg, cb = Num(c.r), Num(c.g), Num(c.b)
            if cr and cg and cb then r, g, b = cr, cg, cb end
        end
    end
    t = format("|cff%02x%02x%02x%d|r", floor(r * 255 + 0.5), floor(g * 255 + 0.5),
        floor(b * 255 + 0.5), score)
    scoreText[score] = t
    return t
end

-- Keyed by the row button; weak keys, no Blizzard table write. The frame is
-- parented to the row's DataDisplay, so Blizzard hiding that block (it does for
-- pending applications) hides our score with it, for free.
local scoreFrames = setmetatable({}, { __mode = "k" })
local anyScoreFrames = false

local function GetScoreFrame(button)
    local f = scoreFrames[button]
    if f then return f end

    local anchor = button.DataDisplay
    if not anchor then return nil end

    f = CreateFrame("Frame", nil, anchor)
    f:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 0)
    f:SetSize(125, 12)

    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    -- Match the row's own font family so we do not look pasted on; the size is
    -- ours because the gap above the strip is only ~13px.
    local path, _, flags
    if button.ActivityName then path, _, flags = button.ActivityName:GetFont() end
    if type(path) == "string" then fs:SetFont(path, 10, flags) end
    fs:SetJustifyH("RIGHT")
    -- -12 lines the score up with Icon1's right inset (LFGList.xml).
    fs:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 0)
    f.Text = fs

    f:Hide()
    scoreFrames[button] = f
    anyScoreFrames = true
    return f
end

local function HideScore(button)
    local f = scoreFrames[button]
    if f then f:Hide() end
end

local function ApplyScore(button)
    local id = Num(button.resultID)
    if not id then return HideScore(button) end

    _rID, _scoreOut = id, nil
    pcall(ReadScore)
    local score = _scoreOut
    if not score or score <= 0 then return HideScore(button) end

    local f = GetScoreFrame(button)
    if not f then return end
    f.Text:SetText(ScoreText(score))
    f:Show()
end

-------------------------------------------------------------------------------
--  Feature 2 -- member spec icon / class bar overlays
--
--  One overlay frame per Blizzard icon frame, created once and reused. The
--  overlay is parented to the icon, so Blizzard hiding the icon hides ours too.
-------------------------------------------------------------------------------
local overlays = setmetatable({}, { __mode = "k" })
local anyOverlays = false

local function GetOverlay(icon)
    local f = overlays[icon]
    if f then return f end

    f = CreateFrame("Frame", nil, icon)
    f:SetAllPoints(icon)
    f:SetFrameLevel(icon:GetFrameLevel() + 3)

    -- 18x18 so it fully covers RoleIconWithBackground (setAllPoints on the
    -- 18x18 icon frame); the texcoord trims the spec art's own border.
    f.Spec = f:CreateTexture(nil, "ARTWORK", nil, 5)
    f.Spec:SetSize(18, 18)
    f.Spec:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.Spec:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    f.Bar = f:CreateTexture(nil, "OVERLAY")
    f.Bar:SetSize(18, 2)
    f.Bar:SetPoint("TOP", f, "BOTTOM", 0, 0)
    f.Bar:Hide()

    f:Hide()
    overlays[icon] = f
    anyOverlays = true
    return f
end

local function HideOverlay(icon)
    local f = icon and overlays[icon]
    if f then f:Hide() end
end

-- A child frame always draws above its parent's textures, so our overlay hides
-- Blizzard's leaver badge no matter what frame level we pick. Mirror it instead:
-- read the badge's atlas, size and anchor once (all static, set in LFGList.xml
-- and only ever SetShown from Lua) and re-create it on our own frame. If any of
-- that is unreadable we simply have no mirror, which is the behaviour we had
-- before. Nothing is written to the Blizzard texture.
local function LeaverMirror(f, icon)
    if f.leaverDone then return f.Leaver end
    f.leaverDone = true

    local li = icon.LeaverIcon
    if not li then return nil end

    local atlas = li.GetAtlas and li:GetAtlas()
    local tex = (type(atlas) ~= "string") and li.GetTexture and li:GetTexture() or nil
    if type(atlas) ~= "string" and not tex then return nil end

    local t = f:CreateTexture(nil, "OVERLAY", nil, 7)
    if type(atlas) == "string" then t:SetAtlas(atlas, false) else t:SetTexture(tex) end

    local w, h = li:GetSize()
    if type(w) == "number" and w > 0 then t:SetSize(w, h) end

    local point, relativeTo, relativePoint, x, y = li:GetPoint(1)
    if type(point) == "string" and type(relativePoint) == "string" and relativeTo == icon then
        t:SetPoint(point, f, relativePoint, x or 0, y or 0)
    else
        t:SetPoint("TOPRIGHT", f, "TOPRIGHT", 4, 2)
    end

    t:Hide()
    f.Leaver = t
    return t
end

local function HideAllOverlays(enumerate)
    local icons = enumerate and enumerate.Icons
    if not icons then return end
    for i = 1, #icons do HideOverlay(icons[i]) end
end

--  Spec icon lookup ------------------------------------------------------
--  localized spec name -> icon, built once per class on first sight and kept
--  for the session (the mapping cannot change while logged in).
local specIcons = {}
local classIDs

local function ClassID(class)
    if not classIDs then
        classIDs = {}
        local getClass = C_CreatureInfo and C_CreatureInfo.GetClassInfo
        if getClass then
            for i = 1, 20 do
                local info = getClass(i)
                if info and info.classFile then
                    classIDs[info.classFile] = info.classID or i
                end
            end
        end
    end
    return classIDs[class]
end

local function SpecIcon(class, spec)
    if not class or not spec then return nil end
    local map = specIcons[class]
    if not map then
        map = {}
        specIcons[class] = map
        local id = ClassID(class)
        if id and type(GetSpecializationInfoForClassID) == "function" then
            local getNum = C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializationsForClassID
            local num = (getNum and getNum(id)) or 4
            for i = 1, num do
                local _, name, _, icon = GetSpecializationInfoForClassID(id, i)
                if name and icon then map[name] = icon end
            end
        end
    end
    return map[spec]
end

--  Member reads. The parallel arrays are module-level and reused every pass,
--  so a populated row allocates nothing.
local _mRole, _mClass, _mSpec, _mIcon = {}, {}, {}, {}
local _mCount = 0
local _mWanted = 0

local function ReadMembers()
    local n = 0
    for i = 1, _mWanted do
        local mi = C_LFGList.GetSearchResultPlayerInfo(_rID, i)
        if mi and not issecretvalue(mi) then
            local role = Str(mi.assignedRole)
            local class = Str(mi.classFilename)
            if role and class then
                n = n + 1
                _mRole[n], _mClass[n], _mSpec[n] = role, class, Str(mi.specName)
            end
        end
    end
    _mCount = n
end

local function PaintIcon(icon, member, wantBar)
    local f = GetOverlay(icon)
    f.Spec:SetTexture(_mIcon[member])

    if wantBar then
        local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[_mClass[member]]
        if c then
            f.Bar:SetColorTexture(c.r, c.g, c.b, 1)
            f.Bar:Show()
        else
            f.Bar:Hide()
        end
    else
        f.Bar:Hide()
    end

    -- Blizzard has already set its own badge's state by the time this post-hook
    -- runs, so IsShown() is current.
    local mirror = LeaverMirror(f, icon)
    if mirror then
        local li = icon.LeaverIcon
        mirror:SetShown((li and li:IsShown()) and true or false)
    end

    f:Show()
end

-- Blizzard fills the icons right-to-left starting at Icons[numPlayers] (Icon1
-- is the rightmost frame), walking iconOrder role by role -- see
-- LFGListGroupDataDisplayEnumerate_Update. We assign in exactly that order so
-- each overlay lands on the icon drawn for that member's role.
--
-- The painting is all-or-nothing per row. In the dungeon category Blizzard
-- fills each role's icons from displayData.classesByRole via pairs(), i.e. in
-- hash order, so which CLASS sits on which icon within a role is not knowable
-- from the member list. That is invisible while every icon is covered, but a
-- single un-overlaid icon could then contradict one of ours -- so if any member
-- is unreadable we hand the whole row back to Blizzard.
local function UpdateEnumerate(enumerate, mode, numPlayers, iconOrder)
    local icons = enumerate.Icons
    if not icons then return end
    local numIcons = #icons
    if numIcons == 0 then return end

    if not numPlayers or numPlayers < 1 then
        -- Refresh path: Blizzard shows exactly icons 1..numPlayers.
        numPlayers = 0
        for i = 1, numIcons do
            if icons[i]:IsShown() then numPlayers = i end
        end
    end
    if numPlayers > numIcons then numPlayers = numIcons end
    if numPlayers < 1 then return HideAllOverlays(enumerate) end

    local button = enumerate:GetParent()
    button = button and button:GetParent()
    local id = button and Num(button.resultID)
    if not id then return HideAllOverlays(enumerate) end

    _rID, _membersOut = id, nil
    pcall(ReadNumMembers)
    local numMembers = _membersOut
    if not numMembers or numMembers < 1 or numMembers > numIcons then
        return HideAllOverlays(enumerate)
    end

    _mCount, _mWanted = 0, numMembers
    pcall(ReadMembers)
    -- A partial roster would shift every later member onto the wrong icon.
    if _mCount ~= numMembers then return HideAllOverlays(enumerate) end

    for m = 1, _mCount do
        local tex = SpecIcon(_mClass[m], _mSpec[m])
        if not tex then return HideAllOverlays(enumerate) end
        _mIcon[m] = tex
    end

    local wantBar = (mode == "SPEC_BAR")
    local order = iconOrder
    if issecretvalue(order) or type(order) ~= "table" then
        order = LFG_LIST_GROUP_DATA_ROLE_ORDER
    end
    if type(order) ~= "table" then order = ROLE_ORDER_FALLBACK end

    -- A role Blizzard's order does not cover would never claim a slot and so
    -- would shift every later member onto the wrong icon.
    for m = 1, _mCount do
        local known = false
        for o = 1, #order do
            if order[o] == _mRole[m] then known = true break end
        end
        if not known then return HideAllOverlays(enumerate) end
    end

    local slot = numPlayers
    for o = 1, #order do
        local role = order[o]
        for m = 1, _mCount do
            if _mRole[m] == role then
                PaintIcon(icons[slot], m, wantBar)
                slot = slot - 1
                if slot < 1 then break end
            end
        end
        if slot < 1 then break end
    end

    -- Empty slots (and anything we could not account for) keep Blizzard's art.
    for i = 1, slot do HideOverlay(icons[i]) end
end

-------------------------------------------------------------------------------
--  Dimming
--
--  This is where the half of the filter that CANNOT be expressed natively
--  becomes visible. EllesmereUIQoL_PremadeFilter.lua runs a read-only pass over
--  the results and publishes a verdict per resultID; a false verdict means the
--  row failed a criterion Blizzard's advanced filter has no field for (delisted,
--  declined, party fit, the expression box, anything on the raid tab) or one it
--  will only act on at the next search. We shade the row instead of removing it,
--  because removing it means writing panel.results -- the taint documented at
--  the top of EllesmereUIQoL_PremadeFilter.lua.
--
--  Same discipline as the rest of this file: the shade is OUR frame drawn over
--  Blizzard's row, weak-keyed by the button. Nothing on the row is written --
--  not its alpha, not a flag. Turning the feature off just hides our frames.
--  The frame takes no mouse input (a plain CreateFrame does not), so the row
--  underneath still clicks, hovers and signs up exactly as Blizzard drew it.
-------------------------------------------------------------------------------
local dimFrames = setmetatable({}, { __mode = "k" })
local anyDimFrames = false

local function GetDim(button)
    local f = dimFrames[button]
    if f then return f end
    f = CreateFrame("Frame", nil, button)
    f:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    f:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints(f)
    t:SetColorTexture(0, 0, 0, 0.55)
    f:Hide()
    dimFrames[button] = f
    anyDimFrames = true
    return f
end

local function HideDim(button)
    local f = dimFrames[button]
    if f then f:Hide() end
end

local function ApplyDim(button)
    if not FilterEnabled() then
        if anyDimFrames then HideDim(button) end
        return
    end
    local verdict = _G._EUI_PremadeFilter_Verdict
    local id = verdict and Num(button.resultID)
    -- No verdict function, a row with no readable resultID, or a result the pass
    -- never saw: no opinion, so leave the row exactly as Blizzard rendered it.
    if not id or verdict(id) ~= false then
        if anyDimFrames then HideDim(button) end
        return
    end
    local f = GetDim(button)
    -- Re-levelled on every update: ScrollBox recycles rows between listings and
    -- the button's own level can move under us.
    f:SetFrameLevel(button:GetFrameLevel() + 6)
    f:Show()
end

-------------------------------------------------------------------------------
--  Hook bodies
-------------------------------------------------------------------------------
local function OnSearchEntryUpdate(button)
    if not button then return end
    -- Dimming is independent of the two display settings and of the category, so
    -- it runs before the score bail below.
    ApplyDim(button)
    -- A row recycled onto a non-dungeon listing, or updated after the feature
    -- was switched off, must not keep showing a stale score. The anyScoreFrames
    -- flag keeps this a true bail until a score frame has actually been built.
    if not ShowScore() or not DungeonBrowseActive() then
        if anyScoreFrames then HideScore(button) end
        return
    end
    ApplyScore(button)
end

local function OnEnumerateUpdate(enumerate, numPlayers, displayData, disabled, iconOrder)
    local mode = MemberDisplay()
    if mode == "DEFAULT" then
        -- Nothing to do, and nothing exists to clean up until an overlay has
        -- been created at least once this session.
        if anyOverlays then HideAllOverlays(enumerate) end
        return
    end
    if not enumerate or not DungeonBrowseActive() then
        if anyOverlays then HideAllOverlays(enumerate) end
        return
    end
    UpdateEnumerate(enumerate, mode, Num(numPlayers), iconOrder)
end

-------------------------------------------------------------------------------
--  Refresh. Re-applies (or clears) both features on the rows currently on
--  screen; the options page calls this after writing either setting. The
--  iteration is read-only -- we only ever show, hide or retext our own frames.
-------------------------------------------------------------------------------
local function TouchRow(button)
    ApplyDim(button)

    if ShowScore() and DungeonBrowseActive() then
        ApplyScore(button)
    else
        HideScore(button)
    end

    local display = button.DataDisplay
    local enumerate = display and display.Enumerate
    if enumerate then OnEnumerateUpdate(enumerate, nil) end
end

local function RefreshRows()
    local panel = LFGListFrame and LFGListFrame.SearchPanel
    if not panel or not panel:IsShown() then return end
    local box = panel.ScrollBox
    if not box or not box.ForEachFrame then return end
    box:ForEachFrame(TouchRow)
end

-------------------------------------------------------------------------------
--  Install. hooksecurefunc is permanent, so once installed the hook bodies
--  gate themselves; nothing is installed until a setting is first active.
-------------------------------------------------------------------------------
local _installed = false

local function InstallHooks()
    if _installed then return end
    if type(LFGListSearchEntry_Update) ~= "function" then return end
    if type(LFGListGroupDataDisplayEnumerate_Update) ~= "function" then return end
    _installed = true

    hooksecurefunc("LFGListSearchEntry_Update", OnSearchEntryUpdate)
    hooksecurefunc("LFGListGroupDataDisplayEnumerate_Update", OnEnumerateUpdate)
end

local _waiting = false
local waiter

-- Blizzard_GroupFinder is DefaultState:enabled so it is normally already there
-- at PLAYER_LOGIN; InstallHooks self-guards on the globals and the
-- ADDON_LOADED wait is only the fallback for a delayed load.
local function EnsureInstalled()
    if _installed or not Active() then return end
    InstallHooks()
    if _installed or _waiting then return end
    _waiting = true
    waiter = waiter or CreateFrame("Frame")
    waiter:RegisterEvent("ADDON_LOADED")
    waiter:SetScript("OnEvent", function(self, _, name)
        if name ~= "Blizzard_GroupFinder" then return end
        self:UnregisterAllEvents()
        _waiting = false
        InstallHooks()
        RefreshRows()
    end)
end

-------------------------------------------------------------------------------
--  Public entry point (options page coupling, house _G pattern)
-------------------------------------------------------------------------------
local function Refresh()
    if not P() then return end
    EnsureInstalled()
    RefreshRows()
end

_G._EUI_RefreshPremadeFilterDisplay = Refresh

-------------------------------------------------------------------------------
--  Init
-------------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    -- The shared db is created by EllesmereUIQoL_PremadeFilter.lua's own
    -- PLAYER_LOGIN handler; if the .toc loads us first, ours runs first too --
    -- so keep listening for the PLAYER_ENTERING_WORLD that follows it until
    -- the settings table is actually reachable.
    if not P() then
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        return
    end
    self:UnregisterAllEvents()
    EnsureInstalled()
end)
