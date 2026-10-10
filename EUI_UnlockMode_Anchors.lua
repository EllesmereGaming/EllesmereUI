if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_UnlockMode_Anchors.lua
--  Anchor / match engine: anchor and size-match DB helpers, match status
--  API, link pruning and re-keying, NotifyElementResized, OnSizeChanged
--  hooks, combat-parked positioning, fallback anchors.
--  Loaded after EUI_UnlockMode.lua; _unlockCoreInit runs it once with UM.
-------------------------------------------------------------------------------
local _, EUI_NS = ...
EUI_NS = EUI_NS.__euiCoreNS or EUI_NS  -- standalone builds: the core's own table (EllesmereUI.lua)
EUI_NS.unlockParts = EUI_NS.unlockParts or {}
EUI_NS.unlockParts.Anchors = function(UM)
local ns, floor, PP, registeredElements = EUI_NS, UM.floor, UM.PP, UM.registeredElements
local movers, pendingPositions, SELECT_ELEMENT_ALPHA, SELECT_ELEMENT_FADE = UM.movers, UM.pendingPositions, UM.SELECT_ELEMENT_ALPHA, UM.SELECT_ELEMENT_FADE

-------------------------------------------------------------------------------
--  Anchor / Match DB helpers  -- eui-style: allow comment-budget
--  EllesmereUIDB.unlockAnchors = { [childKey] = { target=key, side="LEFT"|"RIGHT"|"TOP"|"BOTTOM" } }
--  Width/height matches apply immediately into the element's own settings.
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
--  Actual grow direction -- never nil; used by position math that needs the
--  true anchor edge.
-------------------------------------------------------------------------------
local function GetBarGrowDirActual(barKey)
    if barKey == "EQT_Tracker" then return "DOWN" end
    -- Via the owning module's resolver so menu/layout never disagree (clamps to orientation on read, not save).
    if barKey == "ERB_TotemBar" then
        if EllesmereUI.GetTotemGrowDir then return (EllesmereUI.GetTotemGrowDir()) end
        return "RIGHT"
    end
    if barKey == "EABR_Reminders" then
        if EllesmereUI.GetAuraBuffGrowDir then
            return EllesmereUI.GetAuraBuffGrowDir()
        end
        return "CENTER"
    end
    if barKey:sub(1, 4) == "CDM_" then
        local rawKey = barKey:sub(5)
        local cdm = EllesmereUI.Lite.GetAddon("EllesmereUICooldownManager", true)
        local cdmBars = cdm and cdm.db and cdm.db.profile and cdm.db.profile.cdmBars
        if cdmBars and cdmBars.bars then
            for _, bar in ipairs(cdmBars.bars) do
                if bar.key == rawKey then
                    return bar.growDirection or "CENTER"
                end
            end
        end
        return "CENTER"
    else
        local eab = EllesmereUI.Lite.GetAddon("EllesmereUIActionBars", true)
        local s = eab and eab.db and eab.db.profile and eab.db.profile.bars
                  and eab.db.profile.bars[barKey]
        if s then
            return (s.growDirection or "up"):upper()
        end
        return "CENTER"
    end
end

-------------------------------------------------------------------------------
--  Grow direction from the bar's per-profile settings: uppercase string, or nil
--  if default/unset. Action bar default "UP", CDM default nil (centered).
-------------------------------------------------------------------------------
local function GetBarGrowDir(barKey)
    if barKey == "EQT_Tracker" then return "DOWN" end
    if barKey == "ERB_TotemBar" then
        if not EllesmereUI.GetTotemGrowDir then return "RIGHT" end
        local g = EllesmereUI.GetTotemGrowDir()
        if g == "CENTER" then return nil end   -- centered = no direction indicator
        return g
    end
    if barKey == "EABR_Reminders" then
        if not EllesmereUI.GetAuraBuffGrowDir then return nil end
        local g = EllesmereUI.GetAuraBuffGrowDir()
        if g and g ~= "CENTER" then return g end
        return nil
    end
    if barKey:sub(1, 4) == "CDM_" then
        local rawKey = barKey:sub(5)
        local cdm = EllesmereUI.Lite.GetAddon("EllesmereUICooldownManager", true)
        local cdmBars = cdm and cdm.db and cdm.db.profile and cdm.db.profile.cdmBars
        if cdmBars and cdmBars.bars then
            for _, bar in ipairs(cdmBars.bars) do
                if bar.key == rawKey then
                    local g = bar.growDirection
                    if g and g ~= "CENTER" then return g end
                    return nil
                end
            end
        end
        return nil
    else
        local eab = EllesmereUI.Lite.GetAddon("EllesmereUIActionBars", true)
        local s = eab and eab.db and eab.db.profile and eab.db.profile.bars
                  and eab.db.profile.bars[barKey]
        if s then
            local g = (s.growDirection or "up"):upper()
            if g == "CENTER" then return nil end
            -- UP is default for horizontal bars (no indicator) but meaningful for vertical (show indicator)
            if g == "UP" and (s.orientation or "horizontal") ~= "vertical" then return nil end
            return g
        end
        return nil
    end
end

local function GetAnchorDB()
    if not EllesmereUIDB then return nil end
    if not EllesmereUIDB.unlockAnchors then
        EllesmereUIDB.unlockAnchors = {}
    end
    return EllesmereUIDB.unlockAnchors
end

local function GetAnchorInfo(barKey)
    local db = GetAnchorDB()
    if not db then return nil end
    return db[barKey]
end

-- Re-applies the grow-direction-aware anchor after a resize so the fixed edge stays
-- put. Must be synchronous (no C_Timer.After) to avoid a visible flicker frame.
-- Defined here, after its dependencies, so the closure captures the right upvalues.
function EllesmereUI.RecenterBarAnchor(barKey)
    if not UM.isUnlocked then return end
    local elem = registeredElements[barKey]
    if elem and elem.isAnchored and elem.isAnchored() then return end
    local b = UM.GetBarFrame(barKey)
    if not b then return end

    local s = b:GetEffectiveScale()
    local uiS = UIParent:GetEffectiveScale()
    local elemScale = s / uiS

    local bL = b:GetLeft()
    local bT = b:GetTop()
    if not bL or not bT then return end

    local w = (b:GetWidth() or 0) * elemScale
    local h = (b:GetHeight() or 0) * elemScale
    if w < 1 or h < 1 then return end

    -- Center in UIParent-BOTTOMLEFT space
    local uiCX = bL * elemScale + w * 0.5
    local uiCY = bT * elemScale - h * 0.5

    local growDir = GetBarGrowDirActual(barKey)
    local anchor, aX, aY
    if growDir == "RIGHT" then
        anchor = "LEFT"
        aX = bL * elemScale
        aY = uiCY
    elseif growDir == "LEFT" then
        anchor = "RIGHT"
        aX = (bL * elemScale) + w
        aY = uiCY
    elseif growDir == "DOWN" then
        anchor = "TOP"
        aX = uiCX
        aY = bT * elemScale
    elseif growDir == "UP" then
        anchor = "BOTTOM"
        aX = uiCX
        aY = bT * elemScale - h
    else
        anchor = "CENTER"
        aX = uiCX
        aY = uiCY
    end

    -- Convert to CENTER-relative (the unlock mode system's standard format)
    local uiW, uiH = UIParent:GetSize()
    local cRelX = aX - uiW / 2
    local cRelY = aY - uiH / 2

    -- Snap to the physical pixel grid so subpixel coords never persist into pendingPositions -> CommitPositions -> SavedVariables.
    local PPr = PP or (EllesmereUI and EllesmereUI.PP)
    if PPr then
        if anchor == "CENTER" then
            cRelX = PPr.SnapCenterForDim(cRelX, w, uiS)
            cRelY = PPr.SnapCenterForDim(cRelY, h, uiS)
        else
            cRelX = PPr.SnapForES(cRelX, uiS)
            cRelY = PPr.SnapForES(cRelY, uiS)
        end
    end

    -- cRelX/cRelY are UIParent units; SetPoint offsets read in the frame's own space
    -- (identical unless the element self-scales, see ApplyCenterPosition) -- divide is a no-op for anything unscaled.
    local setX, setY = cRelX, cRelY
    if elemScale ~= 1 and elemScale > 0 then
        setX = cRelX / elemScale
        setY = cRelY / elemScale
    end

    pcall(function()
        EllesmereUI.ClearFramePoints(b)
        EllesmereUI.SetFramePoint(b, anchor, UIParent, "CENTER", setX, setY)
    end)

    -- Keep mover's stored center in sync so drag/snap logic stays consistent
    local m = movers[barKey]
    if m and m._setCenterXY then
        m._setCenterXY(uiCX, uiCY - uiH)
    end
end

local function SetAnchorInfo(childKey, targetKey, side, offsetX, offsetY)
    local db = GetAnchorDB()
    if not db then return end
    -- Keep an existing fallback only when re-anchoring to the SAME target; a new target invalidates it (fallback belongs to the link, not the child).
    local prev = db[childKey]
    local fb = prev and prev.target == targetKey and prev.fallback or nil
    -- The cross-axis screen edge belongs to the CHILD, not to this link, so it
    -- survives a re-anchor -- unless the new target claims its axis (edge target),
    -- in which case the two would fight over the same coordinate.
    local edge = prev and prev.edge or nil
    if edge and edge.key and EllesmereUI._ScreenEdgeAxis
       and EllesmereUI._ScreenEdgeAxis(edge.key) == EllesmereUI._ScreenEdgeAxis(targetKey) then
        edge = nil
    end
    db[childKey] = { target = targetKey, side = side, offsetX = offsetX, offsetY = offsetY,
                     fallback = fb, edge = edge }
    -- Link-change stamp: modules with memoized views over the anchor DB (e.g.
    -- the tracking bar growth-edge extent watch) re-derive lazily.
    EllesmereUI._anchorLinksStamp = (EllesmereUI._anchorLinksStamp or 0) + 1
end

local function ClearAnchorInfo(childKey)
    local db = GetAnchorDB()
    if not db then return end
    db[childKey] = nil
    EllesmereUI._anchorLinksStamp = (EllesmereUI._anchorLinksStamp or 0) + 1
end

local function IsAnchored(barKey)
    local info = GetAnchorInfo(barKey)
    if info ~= nil then return true end
    local elem = registeredElements[barKey]
    return elem and elem.isAnchored and elem.isAnchored() or false
end

-- Element anchored via a module option (e.g. ERB "Anchor To") with keepMoverWhenAnchored:
-- mover exists but is position-locked (module's anchor owns position) -- drag/nudge/
-- anchor-link disabled, resize and width/height match stay. On ns: deferred body is at the 200-local cap.
function ns.IsMoverPosLocked(barKey)
    local elem = registeredElements[barKey]
    if not (elem and elem.keepMoverWhenAnchored) then return false end
    return elem.isAnchored and elem.isAnchored() or false
end

-- Width/Height match persistent links
local MatchH = {}

function MatchH.GetWidthMatchDB()
    if not EllesmereUIDB then return nil end
    if not EllesmereUIDB.unlockWidthMatch then
        EllesmereUIDB.unlockWidthMatch = {}
    end
    return EllesmereUIDB.unlockWidthMatch
end


function MatchH.GetHeightMatchDB()
    if not EllesmereUIDB then return nil end
    if not EllesmereUIDB.unlockHeightMatch then
        EllesmereUIDB.unlockHeightMatch = {}
    end
    return EllesmereUIDB.unlockHeightMatch
end

-- Extra width / height on a match (the unlock cog's Extra Width / Extra Height
-- rows): whole physical pixels at the child's scale, added to the matched size
-- after the target's pad and before the child's own pad comes off. Keyed by the
-- child element like its link ("w" / "h" axis); stored only while non-zero and
-- read only while the child's link exists, so a leftover entry does nothing.
function EllesmereUI.GetMatchExtra(axis, key)
    if not EllesmereUIDB or not key then return nil end
    local t
    if axis == "h" then t = EllesmereUIDB.unlockHeightMatchExtra
    else t = EllesmereUIDB.unlockWidthMatchExtra end
    local v = t and t[key]
    if v and v ~= 0 then return v end
    return nil
end

function MatchH.SetMatchExtra(axis, key, px)
    if not EllesmereUIDB or not key then return end
    local field = "unlockWidthMatchExtra"
    if axis == "h" then field = "unlockHeightMatchExtra" end
    px = tonumber(px)
    if px then px = math.floor(px + 0.5) end
    local t = EllesmereUIDB[field]
    if not px or px == 0 then
        if t then t[key] = nil end
        return
    end
    if not t then t = {}; EllesmereUIDB[field] = t end
    t[key] = px
end

function MatchH.GetWidthMatchInfo(barKey)
    local db = MatchH.GetWidthMatchDB()
    return db and db[barKey] or nil
end

function MatchH.GetHeightMatchInfo(barKey)
    local db = MatchH.GetHeightMatchDB()
    return db and db[barKey] or nil
end

-- Cycle detect: walk the chain from targetKey; reaching childKey would loop forever.
function MatchH.WouldCreateCycle(db, childKey, targetKey)
    local visited = {}
    local current = targetKey
    while current do
        if current == childKey then return true end
        if visited[current] then return false end
        visited[current] = true
        current = db[current]
    end
    return false
end

-- True when barKey's width/height is driven, via an unbroken chain of match links,
-- by a content-sized bar: a CDM_ bar, or an action bar reached through at least one
-- link (0-hop start mirrors call-site direct-target tests, so a bar matched
-- DIRECTLY to a plain action bar never qualifies). Match DBs key on literal element
-- keys (no alias resolution), as the anchor cascade reads them; visited guards malformed cycles.
function MatchH.ChainDrivenToBar(barKey, axis)
    if not barKey then return false end
    local db
    if axis == "width" then
        db = MatchH.GetWidthMatchDB()
    elseif axis == "height" then
        db = MatchH.GetHeightMatchDB()
    else
        return false
    end
    local abKeys = EllesmereUI._abBarKeys
    local visited = {}
    local current = barKey
    while current do
        if current:sub(1, 4) == "CDM_" then
            return true
        end
        if abKeys and abKeys[current] and current ~= barKey then
            return true
        end
        if not db or visited[current] then return false end
        visited[current] = true
        current = db[current]
    end
    return false
end

function MatchH.SetWidthMatch(childKey, targetKey)
    local db = MatchH.GetWidthMatchDB()
    if not db then return end
    if MatchH.WouldCreateCycle(db, childKey, targetKey) then
        -- Break the cycle: clear the link that targetKey has, then set ours
        db[targetKey] = nil
        MatchH.SetMatchExtra("w", targetKey, nil)
    end
    -- A new match starts at +0.
    if db[childKey] ~= targetKey then MatchH.SetMatchExtra("w", childKey, nil) end
    db[childKey] = targetKey
end

function MatchH.SetHeightMatch(childKey, targetKey)
    local db = MatchH.GetHeightMatchDB()
    if not db then return end
    if MatchH.WouldCreateCycle(db, childKey, targetKey) then
        db[targetKey] = nil
        MatchH.SetMatchExtra("h", targetKey, nil)
    end
    if db[childKey] ~= targetKey then MatchH.SetMatchExtra("h", childKey, nil) end
    db[childKey] = targetKey
end

function MatchH.ClearWidthMatch(childKey)
    local db = MatchH.GetWidthMatchDB()
    if not db then return end
    -- Persist current width so "0 = match parent" defaults don't revert on reload
    -- (elem.setWidth saves to its own DB); pixel-snapped like every match apply, else an off-grid raw GetWidth propagates through setters/harvests.
    local elem = registeredElements[childKey]
    if elem and elem.setWidth then
        local frame = UM.GetBarFrame(childKey)
        if frame then
            local curW = frame:GetWidth()
            if curW and curW > 0 then
                local PPm = EllesmereUI and EllesmereUI.PP
                if PPm and PPm.SnapForES then
                    curW = PPm.SnapForES(curW, frame:GetEffectiveScale())
                end
                pcall(elem.setWidth, childKey, curW)
            end
        end
    end
    db[childKey] = nil
    MatchH.SetMatchExtra("w", childKey, nil)
end

function MatchH.ClearHeightMatch(childKey)
    local db = MatchH.GetHeightMatchDB()
    if not db then return end
    local elem = registeredElements[childKey]
    if elem and elem.setHeight then
        local frame = UM.GetBarFrame(childKey)
        if frame then
            local curH = frame:GetHeight()
            if curH and curH > 0 then
                local PPm = EllesmereUI and EllesmereUI.PP
                if PPm and PPm.SnapForES then
                    curH = PPm.SnapForES(curH, frame:GetEffectiveScale())
                end
                pcall(elem.setHeight, childKey, curH)
            end
        end
    end
    db[childKey] = nil
    MatchH.SetMatchExtra("h", childKey, nil)
end

-------------------------------------------------------------------------------
--  Public API: query width/height match state from any addon
-------------------------------------------------------------------------------
function EllesmereUI.GetWidthMatchTarget(barKey)
    local db = MatchH.GetWidthMatchDB()
    return db and db[barKey] or nil
end

function EllesmereUI.GetHeightMatchTarget(barKey)
    local db = MatchH.GetHeightMatchDB()
    return db and db[barKey] or nil
end

-- Returns (disabled_fn, tooltip_fn, rawTooltip) for width/height sliders, composing
-- with an optional existing disabled/tooltip so both conditions work.
-- rawTooltip=true tells the widget system to skip DisabledTooltip wrapping.
function EllesmereUI.MatchGuard(barKey, axis, existingDisabled, existingTooltip)
    local isWidth = (axis == "Width" or axis == "width")
    local getFn = isWidth and EllesmereUI.GetWidthMatchTarget or EllesmereUI.GetHeightMatchTarget
    local disabled = function()
        if getFn(barKey) then return true end
        if existingDisabled then return existingDisabled() end
        return false
    end
    local tooltip = function()
        local target = getFn(barKey)
        if target then
            local name = (EllesmereUI.GetBarLabel and EllesmereUI.GetBarLabel(target)) or target
            return isWidth
                and EllesmereUI.Lf("Width matched to %1$s. Unmatch in Unlock Mode to edit.", EllesmereUI.L(name))
                or EllesmereUI.Lf("Height matched to %1$s. Unmatch in Unlock Mode to edit.", EllesmereUI.L(name))
        end
        if existingTooltip then
            return type(existingTooltip) == "function" and existingTooltip() or existingTooltip
        end
        return ""
    end
    local rawTooltip = function()
        return getFn(barKey) ~= nil
    end
    return disabled, tooltip, rawTooltip
end

-------------------------------------------------------------------------------
--  PruneStaleLinks -- removes all anchor/match links for a key, as child AND
--  as target. Call on unregister so nothing points to a ghost key.
-------------------------------------------------------------------------------
local function PruneStaleLinks(key)
    if not EllesmereUIDB then return end

    -- Anchors: key as child
    local anchors = EllesmereUIDB.unlockAnchors
    if anchors then
        anchors[key] = nil
        -- key as target -- scan all children
        for childKey, info in pairs(anchors) do
            if info and info.target == key then
                anchors[childKey] = nil
            end
        end
    end

    -- Match extras go with the links dropped below: the key's own, and those of
    -- the children matched to it (read before those links are gone).
    local wx = EllesmereUIDB.unlockWidthMatchExtra
    if wx then
        local wmL = EllesmereUIDB.unlockWidthMatch
        wx[key] = nil
        for childKey in pairs(wx) do
            if wmL and wmL[childKey] == key then wx[childKey] = nil end
        end
    end
    local hx = EllesmereUIDB.unlockHeightMatchExtra
    if hx then
        local hmL = EllesmereUIDB.unlockHeightMatch
        hx[key] = nil
        for childKey in pairs(hx) do
            if hmL and hmL[childKey] == key then hx[childKey] = nil end
        end
    end

    -- Width matches: key as child or target
    local wm = EllesmereUIDB.unlockWidthMatch
    if wm then
        wm[key] = nil
        for childKey, targetKey in pairs(wm) do
            if targetKey == key then wm[childKey] = nil end
        end
    end

    -- Height matches: key as child or target
    local hm = EllesmereUIDB.unlockHeightMatch
    if hm then
        hm[key] = nil
        for childKey, targetKey in pairs(hm) do
            if targetKey == key then hm[childKey] = nil end
        end
    end
end
EllesmereUI.PruneStaleLinks = PruneStaleLinks

-- Override UnregisterUnlockElement so cleanup runs on removal (e.g. a deleted CDM bar).
function EllesmereUI:UnregisterUnlockElement(key)
    self._unlockRegisteredElements[key] = nil
    self._unlockRegistrationDirty = true
    PruneStaleLinks(key)
end

-------------------------------------------------------------------------------
--  ShiftIndexedAnchorKeys -- re-keys anchor/size-match links for an index-keyed
--  element family after a slot is removed (deleting Tracking Bar 2 of 4 shifts
--  TBB_3->TBB_2, TBB_4->TBB_3, mirroring the addon's own re-keyed position
--  store). Links pointing AT the removed key are severed (child keeps its
--  stored position); the removed key's own links go with it.
-------------------------------------------------------------------------------
function EllesmereUI.ShiftIndexedAnchorKeys(prefix, removedIdx, oldCount)
    if not EllesmereUIDB then return end
    local removedKey = prefix .. removedIdx
    local plen = #prefix

    -- Returns the shifted key for keys above the removed index, else nil.
    local function ShiftedKey(key)
        if type(key) ~= "string" or key:sub(1, plen) ~= prefix then return nil end
        local i = tonumber(key:sub(plen + 1))
        if not i or i <= removedIdx or i > oldCount then return nil end
        return prefix .. (i - 1)
    end

    local anchors = EllesmereUIDB.unlockAnchors
    if anchors then
        -- Sever children anchored to the removed key; retarget higher indexes.
        for childKey, info in pairs(anchors) do
            if info and info.target == removedKey then
                anchors[childKey] = nil
            elseif info then
                local nt = ShiftedKey(info.target)
                if nt then info.target = nt end
            end
        end
        -- Shift child-role keys down one slot.
        anchors[removedKey] = nil
        for i = removedIdx + 1, oldCount do
            local oldK, newK = prefix .. i, prefix .. (i - 1)
            anchors[newK] = anchors[oldK]
            anchors[oldK] = nil
        end
    end

    local function ShiftMatchStore(store)
        if not store then return end
        for childKey, targetKey in pairs(store) do
            if targetKey == removedKey then
                store[childKey] = nil
            else
                local nt = ShiftedKey(targetKey)
                if nt then store[childKey] = nt end
            end
        end
        store[removedKey] = nil
        for i = removedIdx + 1, oldCount do
            local oldK, newK = prefix .. i, prefix .. (i - 1)
            store[newK] = store[oldK]
            store[oldK] = nil
        end
    end
    -- Match extras (child key -> px) follow their links: a child whose link is
    -- severed (it pointed at the removed key) loses its extra, read before the
    -- link stores shift below; the rest re-key like the links (ShiftedKey never
    -- retargets a number, so only the child-role keys move).
    local function DropSeveredExtras(links, extras)
        if not (links and extras) then return end
        for childKey, targetKey in pairs(links) do
            if targetKey == removedKey then extras[childKey] = nil end
        end
    end
    DropSeveredExtras(EllesmereUIDB.unlockWidthMatch, EllesmereUIDB.unlockWidthMatchExtra)
    DropSeveredExtras(EllesmereUIDB.unlockHeightMatch, EllesmereUIDB.unlockHeightMatchExtra)
    ShiftMatchStore(EllesmereUIDB.unlockWidthMatchExtra)
    ShiftMatchStore(EllesmereUIDB.unlockHeightMatchExtra)
    ShiftMatchStore(EllesmereUIDB.unlockWidthMatch)
    ShiftMatchStore(EllesmereUIDB.unlockHeightMatch)
end

-- Validate stored relationships against registered elements. Runs on every
-- unlock-mode open: drops links whose endpoint is gone for good, and size
-- matches a noResize endpoint cannot use (see MatchUnusable).
local function ValidateStoredLinks()
    if not EllesmereUIDB then return end
    local elems = EllesmereUI._unlockRegisteredElements

    -- While a spec-override unlock LAYER is live, never prune a missing endpoint:
    -- elements may exist for only some specs, and the transition harvest would bank
    -- the prune into the layer, destroying data other specs expect.
    local activeFn = EllesmereUI.SpecOverrides_UnlockActive
    local function OverrideProtected()
        return (activeFn and activeFn() ~= nil) and true or false
    end

    -- Tracking Bar keys are spec-scoped (registry holds only the current spec's
    -- bars), so a missing TBB_ key may exist for another spec; never prune over one
    -- (bar deletion re-keys/severs via ShiftIndexedAnchorKeys). Global tracking bar
    -- groups (TBBG_) live in a per-profile registry too and may come back.
    local function MissingForGood(key)
        if key ~= nil and elems[key] then return false end
        if type(key) == "string" and key:find("^TBB_%d+$") then return false end
        if type(key) == "string" and key:find("^TBBG_") then return false end
        return true
    end

    -- A unit frame key missing from the registry is switched off by a unit
    -- setting (Frame Source, Enable) or the module being off, never deleted. A
    -- link whose CHILD is one stays for when it comes back (nothing places a
    -- missing child) as long as its other end is live or another such key (a
    -- cast bar and its frame). A live child anchored or matched to one is still
    -- freed, so it is never left following a frame that is not there.
    local resolveFolder = EllesmereUI.ResolveKeyToFolder
    local function ufKey(key)
        return resolveFolder ~= nil and resolveFolder(key) == "EllesmereUIUnitFrames"
    end
    -- WoW Forever never builds the House Favor bar or the Battle Res and
    -- Bloodlust icons: a link whose CHILD is one of them stays for the other
    -- client on the same terms (its other end live, a unit frame key, or
    -- another such key).
    local function clientAbsent(key)
        return EllesmereUI.IS_FOREVER == true
            and (key == "FavorBar" or key == "EUI_BattleRes" or key == "EUI_Bloodlust")
    end
    local function LinkGone(childKey, targetKey)
        local childGone, targetGone = MissingForGood(childKey), MissingForGood(targetKey)
        if not (childGone or targetGone) then return false end
        if childGone and (ufKey(childKey) or clientAbsent(childKey))
           and (not targetGone or ufKey(targetKey) or clientAbsent(targetKey)) then
            return false
        end
        return true
    end

    local anchors = EllesmereUIDB.unlockAnchors
    if anchors then
        for childKey, info in pairs(anchors) do
            if LinkGone(childKey, info and info.target)
               and not OverrideProtected(childKey) then
                anchors[childKey] = nil
            elseif info and info.edge and info.edge.key and LinkGone(childKey, info.edge.key)
                   and not OverrideProtected(childKey) then
                -- Unknown cross-axis edge (a string from a build without this
                -- feature): drop the extra, keep the link itself.
                info.edge = nil
            end
        end
    end

    -- A size match a noResize endpoint cannot use: a child that cannot be sized
    -- (unless it may match as a source) or a target with no size to follow.
    -- sizeFixedByLook endpoints are only size-locked by the current look
    -- (Blizzard Style unit frames), so their links stay for the other look.
    local function MatchUnusable(childKey, targetKey)
        local c, t = elems[childKey], elems[targetKey]
        if not (c and t) then return false end
        if c.noResize and not c.allowMatchSource and not c.sizeFixedByLook then return true end
        if t.noResize and not t.sizeFixedByLook then return true end
        return false
    end

    local wm = EllesmereUIDB.unlockWidthMatch
    if wm then
        for childKey, targetKey in pairs(wm) do
            if LinkGone(childKey, targetKey)
               and not OverrideProtected(childKey) then
                wm[childKey] = nil
            elseif MatchUnusable(childKey, targetKey) then
                wm[childKey] = nil
            end
        end
    end

    local hm = EllesmereUIDB.unlockHeightMatch
    if hm then
        for childKey, targetKey in pairs(hm) do
            if LinkGone(childKey, targetKey)
               and not OverrideProtected(childKey) then
                hm[childKey] = nil
            elseif MatchUnusable(childKey, targetKey) then
                hm[childKey] = nil
            end
        end
    end

    -- A match extra is read only while its link exists: drop every extra whose
    -- link is gone, so orphans never ride into snapshots and profiles.
    local wx = EllesmereUIDB.unlockWidthMatchExtra
    if wx then
        for childKey in pairs(wx) do
            if not (wm and wm[childKey]) then wx[childKey] = nil end
        end
    end
    local hx = EllesmereUIDB.unlockHeightMatchExtra
    if hx then
        for childKey in pairs(hx) do
            if not (hm and hm[childKey]) then hx[childKey] = nil end
        end
    end
end

-- Apply width/height match: sync source size from target. _propagatingMatch
-- prevents re-entrant loops (setWidth -> OnSizeChanged -> NotifyElementResized ->
-- PropagateWidthMatch); exposed so child addons' setWidth can detect it.
local _propagatingMatch = false
EllesmereUI._propagatingMatch = false

function MatchH.ApplyWidthMatch(sourceKey, targetKey)
    local targetElem = registeredElements[targetKey]
    local targetBar = UM.GetBarFrame(targetKey)
    local targetW
    if targetElem and targetElem.getSize then
        targetW = targetElem.getSize(targetKey)
    elseif targetBar then
        targetW = targetBar:GetWidth()
    end
    -- Chrome drawn outside the target's own rect (getMatchPad, e.g. a classic
    -- resource bar's frame): the match lines up with what is on screen.
    if targetW and targetElem and targetElem.getMatchPad then
        local pw = targetElem.getMatchPad(targetKey)
        if pw and pw > 0 then targetW = targetW + pw end
    end
    -- A width that is not a real number (a frame not laid out yet can read NaN)
    -- skips the match: WoW Forever errors on dividing one.
    if targetW and EllesmereUI.PP.IsNum(targetW) and targetW > 0 then
        local rawW, conv = targetW, 1
        -- Snap to the physical pixel grid with round-to-nearest: PP.Scale
        -- truncates and drops a pixel on float boundary values; SnapForES uses
        -- floor(x/px + 0.5), which is safe.
        local PPm = EllesmereUI and EllesmereUI.PP
        if PPm and PPm.SnapForES and targetBar then
            targetW = PPm.SnapForES(targetW, targetBar:GetEffectiveScale())
        else
            targetW = floor(targetW + 0.5)
        end
        -- Convert target width to source's coordinate space if scales differ
        local sourceBar = UM.GetBarFrame(sourceKey)
        if targetBar and sourceBar then
            local tES = targetBar:GetEffectiveScale()
            local sES = sourceBar:GetEffectiveScale()
            if math.abs(tES - sES) > 0.001 then
                targetW = targetW * tES / sES
                conv = tES / sES
            end
        end
        local sourceElem = registeredElements[sourceKey]
        if sourceElem and sourceElem.setWidth then
            -- The source's own outside chrome comes off the width it is set
            -- to, so what it draws is what matches. Taken off the unsnapped
            -- width and snapped once: snapping before the subtraction rounds a
            -- half-pixel pad twice, leaving two bars with the same pad a pixel
            -- apart.
            if sourceElem.getMatchPad then
                local pw = sourceElem.getMatchPad(sourceKey)
                if pw and pw > 0 then
                    targetW = rawW * conv - pw
                    if PPm and PPm.SnapForES and sourceBar then
                        targetW = PPm.SnapForES(targetW, sourceBar:GetEffectiveScale())
                    else
                        targetW = floor(targetW + 0.5)
                    end
                    targetW = math.max(1, targetW)
                end
            end
            -- The match's Extra Width (whole pixels at the source's scale). targetW
            -- sits on the source's pixel grid here, so whole pixels keep it there
            -- with no second rounding. nil = no extra: nothing changes.
            local ex = EllesmereUI.GetMatchExtra("w", sourceKey)
            if ex then
                local es = sourceBar and sourceBar:GetEffectiveScale()
                local one = (PPm and PPm.perfect and es and es > 0) and (PPm.perfect / es) or 1
                targetW = math.max(1, targetW + ex * one)
            end
            if UM.isUnlocked then
                local sb = UM.GetBarFrame(sourceKey)
                local savedAlpha = sb and EllesmereUI._GetFFD(sb).restoreAlpha
                if sb and not savedAlpha then EllesmereUI._UnlockSetBarAlpha(sb, 0) end
                _propagatingMatch = true; EllesmereUI._propagatingMatch = true
                pcall(sourceElem.setWidth, sourceKey, targetW)
                _propagatingMatch = false; EllesmereUI._propagatingMatch = false
                EllesmereUI.RecenterBarAnchor(sourceKey)
                if sb and not savedAlpha then
                    C_Timer.After(0, function() EllesmereUI._UnlockSetBarAlpha(sb, 1) end)
                end
                local m = movers[sourceKey]
                if m then m:SyncSize() end
            else
                _propagatingMatch = true; EllesmereUI._propagatingMatch = true
                pcall(sourceElem.setWidth, sourceKey, targetW)
                _propagatingMatch = false; EllesmereUI._propagatingMatch = false
                if sourceElem.loadPosition then
                    local pos = sourceElem.loadPosition(sourceKey)
                    if pos and pos.point == "CENTER" and pos.relPoint == "CENTER" then
                        UM.ApplyCenterPosition(sourceKey, pos)
                    end
                end
            end
        end
    end
end

function MatchH.ApplyHeightMatch(sourceKey, targetKey)
    local targetElem = registeredElements[targetKey]
    local targetBar = UM.GetBarFrame(targetKey)
    local _, targetH
    if targetElem and targetElem.getSize then
        _, targetH = targetElem.getSize(targetKey)
    elseif targetBar then
        targetH = targetBar:GetHeight()
    end
    -- Outside chrome on the target (getMatchPad), as in ApplyWidthMatch.
    if targetH and targetElem and targetElem.getMatchPad then
        local _, ph = targetElem.getMatchPad(targetKey)
        if ph and ph > 0 then targetH = targetH + ph end
    end
    if targetH and EllesmereUI.PP.IsNum(targetH) and targetH > 0 then
        local rawH, conv = targetH, 1
        local PPm = EllesmereUI and EllesmereUI.PP
        if PPm and PPm.SnapForES and targetBar then
            targetH = PPm.SnapForES(targetH, targetBar:GetEffectiveScale())
        else
            targetH = floor(targetH + 0.5)
        end
        -- Cross-scale conversion, mirroring ApplyWidthMatch: matched height is a
        -- coordinate in the TARGET's effective scale; a source at another scale
        -- would persist a physically wrong height into its module config.
        local sourceBar = UM.GetBarFrame(sourceKey)
        if targetBar and sourceBar then
            local tES = targetBar:GetEffectiveScale()
            local sES = sourceBar:GetEffectiveScale()
            if math.abs(tES - sES) > 0.001 then
                targetH = targetH * tES / sES
                conv = tES / sES
            end
        end
        local sourceElem = registeredElements[sourceKey]
        if sourceElem and sourceElem.setHeight then
            -- The source's own outside chrome comes off the unsnapped height,
            -- snapped once, as in ApplyWidthMatch.
            if sourceElem.getMatchPad then
                local _, ph = sourceElem.getMatchPad(sourceKey)
                if ph and ph > 0 then
                    targetH = rawH * conv - ph
                    if PPm and PPm.SnapForES and sourceBar then
                        targetH = PPm.SnapForES(targetH, sourceBar:GetEffectiveScale())
                    else
                        targetH = floor(targetH + 0.5)
                    end
                    targetH = math.max(1, targetH)
                end
            end
            -- The match's Extra Height, as the Extra Width in ApplyWidthMatch.
            local ex = EllesmereUI.GetMatchExtra("h", sourceKey)
            if ex then
                local es = sourceBar and sourceBar:GetEffectiveScale()
                local one = (PPm and PPm.perfect and es and es > 0) and (PPm.perfect / es) or 1
                targetH = math.max(1, targetH + ex * one)
            end
            if UM.isUnlocked then
                local sb = UM.GetBarFrame(sourceKey)
                local savedAlpha = sb and EllesmereUI._GetFFD(sb).restoreAlpha
                if sb and not savedAlpha then EllesmereUI._UnlockSetBarAlpha(sb, 0) end
                _propagatingMatch = true; EllesmereUI._propagatingMatch = true
                pcall(sourceElem.setHeight, sourceKey, targetH)
                _propagatingMatch = false; EllesmereUI._propagatingMatch = false
                EllesmereUI.RecenterBarAnchor(sourceKey)
                if sb and not savedAlpha then
                    C_Timer.After(0, function() EllesmereUI._UnlockSetBarAlpha(sb, 1) end)
                end
                local m = movers[sourceKey]
                if m then m:SyncSize() end
            else
                _propagatingMatch = true; EllesmereUI._propagatingMatch = true
                pcall(sourceElem.setHeight, sourceKey, targetH)
                _propagatingMatch = false; EllesmereUI._propagatingMatch = false
                if sourceElem.loadPosition then
                    local pos = sourceElem.loadPosition(sourceKey)
                    if pos and pos.point == "CENTER" and pos.relPoint == "CENTER" then
                        UM.ApplyCenterPosition(sourceKey, pos)
                    end
                end
            end
        end
    end
end

-- Pending anchor propagation keys -- batched into a single deferred frame
UM._pendingAnchorKeys = {}
local _anchorBatchScheduled = false

local function ScheduleAnchorBatch()
    if _anchorBatchScheduled then return end
    _anchorBatchScheduled = true
    C_Timer.After(0, function()
        _anchorBatchScheduled = false
        if UM.isUnlocked then return end  -- unlock mode handles its own saves
        local keys = UM._pendingAnchorKeys
        UM._pendingAnchorKeys = {}
        -- Profile swap: skip AB bars entirely (LayoutBar already positioned them from
        -- the new profile; stale resize events would move them wrong). CDM bars pass through (need post-settle).
        local abSkip = EllesmereUI._abAnchorSuppressed and EllesmereUI._abBarKeys
        for k, axis in pairs(keys) do
            if abSkip and abSkip[k] then
                -- skip: AB bar during profile swap
            else
            -- If this element is itself anchored, re-apply its own position
            -- first: it resized and must reposition relative to its target.
            local anchorDB = GetAnchorDB()
            if anchorDB then
                local ownInfo = anchorDB[k]
                if ownInfo and ownInfo.target then
                    -- Skip AB growth bars: LayoutBar/applyPos owns their position;
                    -- reapplying from a stale offset yields the wrong edge and visible drift.
                    local isAB = EllesmereUI._abBarKeys and EllesmereUI._abBarKeys[k]
                    if not isAB then
                        UM.ApplyAnchorPosition(k, ownInfo.target, ownInfo.side)
                    end
                end
                -- An alias key (global tracking bar group riding this bar's hooks) may itself be anchored: re-apply on a shared resize.
                local aliasK = EllesmereUI._unlockKeyAliases and EllesmereUI._unlockKeyAliases[k]
                local aliasInfo = aliasK and anchorDB[aliasK]
                if aliasInfo and aliasInfo.target then
                    UM.ApplyAnchorPosition(aliasK, aliasInfo.target, aliasInfo.side)
                end
            end
            -- Propagate with axis filter (nil = all axes)
            local propagateAxis = (axis == "all") and nil or axis
            UM.PropagateAnchorChain(k, nil, propagateAxis)
            end -- abSkip else
        end
        -- No persistence here: only Save & Exit (CommitPositions) writes the DB; the chain just repositioned in-place.
        wipe(pendingPositions)
    end)
end

-------------------------------------------------------------------------------
--  One-time follow-baseline migration ("bless the pin"): anchored grow-direction  -- eui-style: allow comment-budget
--  bars saved before follow-baseline capture have a savedEdge but no tgt*
--  baseline, so their follow delta stays 0 and they can't track a resizing
--  target. The baseline can't be reconstructed from ai.offsetX/Y (those drift
--  from layout maintenance and are non-authoritative for grow bars -- why
--  savedEdge is the authority). Instead, once per bar (tgt* presence = the
--  migrated flag) at a quiescent settle, pair the UNTOUCHED savedEdge with the
--  target's live settled geometry: delta is 0 at that instant by construction,
--  so the bar doesn't move, and every future resize/login follows from the
--  blessed pair. Skipped in combat/unlock mode (retries next settle).
-------------------------------------------------------------------------------
do
    local function MigrateOne(childKey, info)
        local savedEdge
        if childKey:sub(1, 4) == "CDM_" then
            local t = EllesmereUI._cdmBarPositions
            savedEdge = t and t[childKey:sub(5)]
        elseif EllesmereUI._abBarKeys and EllesmereUI._abBarKeys[childKey] then
            local t = EllesmereUI._abBarPositions
            savedEdge = t and t[childKey]
        end
        if not savedEdge then return end
        -- Presence of a baseline is the migrated flag -- never touch again.
        if savedEdge.tgtx ~= nil or savedEdge.tgty ~= nil then return end
        local growDir = GetBarGrowDirActual(childKey)
        if not growDir or growDir == "CENTER" then return end
        local targetBar = UM.GetBarFrame(info.target)
        if not targetBar or not targetBar:GetLeft() then return end
        -- A clamp-held target is not at its saved spot: pairing it would make the
        -- child jump once the target is released. Retries next settle.
        if EllesmereUI._RectHeldByClamp(info.target, targetBar) then return end
        -- UIParent-space target geometry, computed like ApplyAnchorPosition's tL/tR/tT/tB so the baseline is comparable.
        local uiS = UIParent:GetEffectiveScale()
        local tS = targetBar:GetEffectiveScale()
        local tL = (targetBar:GetLeft() or 0) * tS / uiS
        local tR = (targetBar:GetRight() or 0) * tS / uiS
        local tT = (targetBar:GetTop() or 0) * tS / uiS
        local tB = (targetBar:GetBottom() or 0) * tS / uiS
        savedEdge.tgtx = (tL + tR) / 2
        savedEdge.tgty = (tT + tB) / 2
        savedEdge.tgtL = tL
        savedEdge.tgtR = tR
        savedEdge.tgtT = tT
        savedEdge.tgtB = tB
        -- Blessed baselines need no override write-back: layer harvest banks the live stores wholesale at every spec/profile transition.
    end

    function EllesmereUI._MigrateAnchorFollowBaselines()
        if UM.isUnlocked or InCombatLockdown() then return end
        local adb = GetAnchorDB()
        if not adb then return end
        for childKey, info in pairs(adb) do
            if info.target and (childKey:sub(1, 4) == "CDM_"
               or (EllesmereUI._abBarKeys and EllesmereUI._abBarKeys[childKey])) then
                pcall(MigrateOne, childKey, info)
            end
        end
    end
end

-- Settle re-apply debounce: anchored CDM bars and their targets resize several times
-- on login (icon population, 1/3/6s refresh ladder, trinket retries) with no
-- reliable "done" signal. Rather than guess a delay, watch for QUIESCENCE: every
-- real resize (NotifyElementResized) restarts this cancelable timer, and only a
-- full quiet window forces ONE full anchor re-apply against the final chain. The
-- 0.25s window must exceed the 0.2s resize throttle so a burst of throttled reanchors keeps the timer alive instead of mis-firing between them.
function EllesmereUI.ScheduleSettleReapply()
    if UM.isUnlocked then return end                            -- unlock owns positioning
    if EllesmereUI._settleReapplyInProgress then return end  -- never re-arm from our own pass
    -- The in-progress flag only covers the SYNCHRONOUS pass; everything it spawns
    -- (anchor batches, SetPoint move checks) is After(0) deferred and lands after the
    -- flag clears. If the forced re-apply isn't pixel-stable (1 physical px snap
    -- deltas exceed the 0.5 UI-unit epsilon at low UI scale), that tail re-arms the
    -- timer forever -- a permanent ~5Hz re-apply burning the client in combat.
    -- Suppress re-arms long enough to swallow the deferred tail; a real disturbance
    -- inside the window only loses this belt-and-braces pass, already handled by notify/batch.
    local su = EllesmereUI._settleSuppressUntil
    if su and GetTime() < su then return end
    if EllesmereUI._settleTimer then EllesmereUI._settleTimer:Cancel() end
    EllesmereUI._settleTimer = C_Timer.NewTimer(0.25, function()
        EllesmereUI._settleTimer = nil
        if UM.isUnlocked then return end
        -- Chain settled: absolute pin may now pick up the target-follow delta.
        -- Flipping only after true quiescence guarantees the target is at its
        -- settled position, so the first follow-aware pass computes a ~0 delta on a
        -- same-spec login and the pin->follow handoff shows no jump.
        EllesmereUI._anchorFollowReady = true
        -- One-shot follow-baseline migration for anchored grow bars; no-op once every candidate has its tgt* baseline.
        if EllesmereUI._MigrateAnchorFollowBaselines then
            pcall(EllesmereUI._MigrateAnchorFollowBaselines)
        end
        -- Re-pull every width/height MATCH before the anchor pass. A match child  -- eui-style: allow comment-budget
        -- is corrected only by a full pass or by its target's own resize notify,
        -- and a spec swap ends with resizes that reach neither: the authoritative
        -- passes (OnSpecSwitchComplete, CDM's reanchor pass) run before the CDM
        -- retry ladder re-lays out the bar, and a size change landing inside the
        -- 50ms notify throttle is dropped outright with nothing to re-run it. The
        -- child then stays pinned to the size its target held mid-rebuild until a
        -- reload -- the power bar <- Essential Cooldowns mismatch. Quiescence
        -- means every target is at its final size, so this is the same correction
        -- a reload performs. Gated on a non-empty store: no matches, no work.
        local wdb = EllesmereUIDB and EllesmereUIDB.unlockWidthMatch
        local hdb = EllesmereUIDB and EllesmereUIDB.unlockHeightMatch
        if ((wdb and next(wdb)) or (hdb and next(hdb)))
           and EllesmereUI.ApplyAllWidthHeightMatches then
            EllesmereUI._settleReapplyInProgress = true
            EllesmereUI._settleSuppressUntil = GetTime() + 0.75
            pcall(EllesmereUI.ApplyAllWidthHeightMatches)
            EllesmereUI._settleReapplyInProgress = false
        end
        if EllesmereUI.ReapplyAllUnlockAnchorsForced then
            EllesmereUI._settleReapplyInProgress = true
            EllesmereUI._settleSuppressUntil = GetTime() + 0.75
            pcall(EllesmereUI.ReapplyAllUnlockAnchorsForced)
            EllesmereUI._settleReapplyInProgress = false
        end
    end)
end

function EllesmereUI.PropagateWidthMatch(key)
    local db = MatchH.GetWidthMatchDB()
    if not db then return end
    -- Push width to elements matching this key, then recurse so chained
    -- matches (A -> B -> C) propagate fully.
    local visited = { [key] = true }
    local function pushChildren(parentKey)
        for childKey, tKey in pairs(db) do
            if tKey == parentKey and not visited[childKey] then
                visited[childKey] = true
                MatchH.ApplyWidthMatch(childKey, parentKey)
                UM._pendingAnchorKeys[childKey] = "width"
                pushChildren(childKey)
            end
        end
    end
    pushChildren(key)
    ScheduleAnchorBatch()
end

function EllesmereUI.PropagateHeightMatch(key)
    local db = MatchH.GetHeightMatchDB()
    if not db then return end
    local visited = { [key] = true }
    local function pushChildren(parentKey)
        for childKey, tKey in pairs(db) do
            if tKey == parentKey and not visited[childKey] then
                visited[childKey] = true
                MatchH.ApplyHeightMatch(childKey, parentKey)
                UM._pendingAnchorKeys[childKey] = "height"
                pushChildren(childKey)
            end
        end
    end
    pushChildren(key)
    ScheduleAnchorBatch()
end

-------------------------------------------------------------------------------
--  Centralized resize notification: EllesmereUI.NotifyElementResized(key), called
--  after changing a frame's size, propagates width/height matches and anchor
--  chains. OnSizeChanged hooks on registered elements call it automatically.
-------------------------------------------------------------------------------
local _resizeNotifyThrottle = {}  -- [key] = GetTime() of last notify
local _resizeLastSize = {}  -- [key] = { w = ..., h = ... }
local RESIZE_THROTTLE_SEC = 0.05 -- ignore rapid-fire size changes within 50ms
-- Trailing re-run bookkeeping (this file is at the 200-local cap, so it lives on
-- EllesmereUI rather than in locals). pending[key] = a re-run is queued;
-- at[key] = when the last one ran, floored to one per 0.5s. That floor is the
-- hard spin guard: an element whose re-apply is not pixel-stable (1 physical px
-- exceeds the 0.5 UI-unit epsilon at low UI scale) would otherwise re-arm a
-- trailing run every 50ms forever. It costs no real correction, since the tail of
-- a same-frame burst always lands within the first throttle window.
EllesmereUI._resizeTrail = { pending = {}, at = {} }

-- Set by LayoutBar (action bars) to suppress position re-application during
-- SetSize; LayoutBar handles its own edge re-anchoring.
EllesmereUI._layoutBarResizing = nil

function EllesmereUI.NotifyElementResized(key)
    if UM.isUnlocked then return end  -- unlock mode owns positioning
    -- Skip if we're inside a width/height match propagation to avoid loops:
    -- setWidth/setHeight -> rebuild -> OnSizeChanged -> NotifyElementResized
    if _propagatingMatch then return end
    -- When LayoutBar handles positioning (custom grow directions), skip only the
    -- position re-apply below; match propagation and anchor chains still run.
    local layoutBarHandled = (EllesmereUI._layoutBarResizing == key)
    -- Suppression scope (spec swap / zone transition): CDM bar icon counts
    -- fluctuate in these windows as Blizzard recycles viewer frames, and a
    -- transient empty width propagated to a width-MATCHED sibling corrupts it until
    -- re-matched. Anchor propagation has no such risk (worst case a child
    -- re-anchors twice), so suppress ONLY the width/height match block below,
    -- never the anchor cascade -- else a spec-swap resize (Class Resource shrinking
    -- 1px on the new pip count) strands anchored children with no event to re-cascade them.
    local suppressMatchProp = EllesmereUI._specProfileSwitching
                           or EllesmereUI._zoneTransitionActive
    -- Throttle: skip if we just processed this key, but re-run once when the
    -- window closes. Dropping outright loses the LAST size of a burst, and that
    -- is exactly where a rebuild's final SetSize lands (BuildAllCDMBars then the
    -- synchronous CollectAndReanchor, both inside one frame): the first pass
    -- propagated a transient width to every matched child and the settled one
    -- never propagated at all, so the child stayed wrong until a reload. The
    -- deferred call takes the normal path below and converges, since a size that
    -- no longer changes fires no further OnSizeChanged. One pending re-run per key.
    local now = GetTime()
    local lastNotify = _resizeNotifyThrottle[key]
    if lastNotify and (now - lastNotify) < RESIZE_THROTTLE_SEC then
        local trail = EllesmereUI._resizeTrail
        local lastTrail = trail.at[key]
        if not trail.pending[key]
           and (not lastTrail or (now - lastTrail) >= 0.5) then
            trail.pending[key] = true
            C_Timer.After(RESIZE_THROTTLE_SEC - (now - lastNotify), function()
                trail.pending[key] = nil
                trail.at[key] = GetTime()
                EllesmereUI.NotifyElementResized(key)
            end)
        end
        return
    end
    _resizeNotifyThrottle[key] = now

    -- Detect which axis changed by comparing to last known size
    local bar = UM.GetBarFrame(key)
    local curW = bar and bar:GetWidth()
    local curH = bar and bar:GetHeight()
    -- A secret size (a frame riding an engine aura container under aura
    -- restriction) can't be compared; the next plain resize converges.
    if issecretvalue and (issecretvalue(curW) or issecretvalue(curH)) then return end
    curW = curW or 0
    curH = curH or 0
    local prev = _resizeLastSize[key]
    local widthChanged = not prev or math.abs(curW - prev.w) > 0.5
    local heightChanged = not prev or math.abs(curH - prev.h) > 0.5

    _resizeLastSize[key] = { w = curW, h = curH }

    -- Reapply own anchor first: an anchored element may need repositioning after
    -- its own resize. Unanchored elements get the stored CENTER re-applied so the
    -- WoW anchor stays CENTER after rebuilds that may use TOPLEFT. Skip when
    -- LayoutBar already positioned from its captured edge (avoids CENTER->edge->
    -- CENTER round-trip drift), and skip AB bars during profile swap (stale offsets cause a 1-frame blink); CDM bars are not suppressed.
    local abSwapSkip = EllesmereUI._abAnchorSuppressed
        and EllesmereUI._abBarKeys and EllesmereUI._abBarKeys[key]
    if not layoutBarHandled and not abSwapSkip then
        local anchorDB = GetAnchorDB()
        local ownAnchor = anchorDB and anchorDB[key]
        if ownAnchor and ownAnchor.target then
            if EllesmereUI.ReapplyOwnAnchor then
                EllesmereUI.ReapplyOwnAnchor(key)
            end
        else
            -- Unanchored: re-apply stored CENTER position
            local elem = registeredElements[key]
            if elem and elem.noInitHook then
                -- Self-positioning element (noInitHook): stored CENTER was captured
                -- under whatever footprint was live at save time, and re-applying it
                -- clobbers the element's own scheme (e.g. raid container's per-tier
                -- growth-corner anchor). Delegate to its own position authority instead.
                if elem.applyPosition then pcall(elem.applyPosition, key) end
            else
                local pos
                if elem and elem.loadPosition then
                    pos = elem.loadPosition(key)
                else
                    local db = UM.GetPositionDB()
                    pos = db and db[key]
                end
                if pos and pos.point == "CENTER" and pos.relPoint == "CENTER" then
                    UM.ApplyCenterPosition(key, pos)
                end
            end
        end
    end

    -- Propagate width/height matches to dependents (suppressed during spec-swap
    -- / zone-transition -- see suppressMatchProp above).
    if not suppressMatchProp then
        local wdb = MatchH.GetWidthMatchDB()
        if wdb then
            local hasChildren = false
            for childKey, tKey in pairs(wdb) do
                if tKey == key then hasChildren = true; break end
            end
            if hasChildren then
                EllesmereUI.PropagateWidthMatch(key)
            end
            -- Re-pull from own target if this element is a width-match child
            local ownTarget = wdb[key]
            if ownTarget and widthChanged then
                MatchH.ApplyWidthMatch(key, ownTarget)
            end
        end
        local hdb = MatchH.GetHeightMatchDB()
        if hdb then
            local hasChildren = false
            for childKey, tKey in pairs(hdb) do
                if tKey == key then hasChildren = true; break end
            end
            if hasChildren then
                EllesmereUI.PropagateHeightMatch(key)
            end
            -- Re-pull from own target if this element is a height-match child
            local ownHTarget = hdb[key]
            if ownHTarget and heightChanged then
                MatchH.ApplyHeightMatch(key, ownHTarget)
            end
        end
    end

    -- Propagate the anchor chain to children anchored to this element, using the
    -- detected axis so children on the unaffected axis don't move.
    local axis
    if widthChanged and heightChanged then
        axis = "all"
    elseif widthChanged then
        axis = "width"
    elseif heightChanged then
        axis = "height"
    end
    if axis then
        local existing = UM._pendingAnchorKeys[key]
        if existing and existing ~= axis then
            UM._pendingAnchorKeys[key] = "all"
        else
            UM._pendingAnchorKeys[key] = axis
        end
        ScheduleAnchorBatch()
        -- Arm the settle debounce so a forced full re-apply lands once the chain
        -- stops resizing -- catches late login/spec-swap resizes the one-shot
        -- reanchor misses. See ScheduleSettleReapply.
        if EllesmereUI.ScheduleSettleReapply then EllesmereUI.ScheduleSettleReapply() end
    end
end

-- Pad-change notifier. A module calls EllesmereUI.MatchPadChanged(key) after it  -- eui-style: allow comment-budget
-- applies an element's border / chrome settings; the element's own getMatchPad
-- output is compared with the last one seen, so no setter anywhere has to know
-- which settings move the pad. A key's first sighting only records (the login
-- match pass already reads pads); a real change queues the key and ONE deferred
-- flush re-applies each queued key through ReapplyMatchPads, on the axes whose
-- pad moved (pending value: 1 = width, 2 = height, 3 = both; an element with
-- linked dimensions re-pulls both). Pads never depend on size, so the re-push's
-- own setWidth -> rebuild sees an equal pad and stops. During a profile apply
-- the pad is only recorded: that apply ends in the full match pass
-- (ApplySavedPositions), which reads every live pad.
-- State on the addon table: this file sits at the 200-local cap.
EllesmereUI._matchPad = { w = {}, h = {}, pending = {}, spare = {}, armed = false }
EllesmereUI._matchPad.flush = function()
    local mp = EllesmereUI._matchPad
    mp.armed = false
    local batch = mp.pending
    mp.pending, mp.spare = mp.spare, batch
    for k, m in pairs(batch) do
        batch[k] = nil
        EllesmereUI.ReapplyMatchPads(k, m)
    end
end
function EllesmereUI.MatchPadChanged(key)
    if UM.isUnlocked or not key then return end
    local elem = registeredElements[key]
    if not (elem and elem.getMatchPad) then return end
    local pw, ph = elem.getMatchPad(key)
    pw, ph = pw or 0, ph or 0
    local mp = EllesmereUI._matchPad
    local ow, oh = mp.w[key], mp.h[key]
    mp.w[key], mp.h[key] = pw, ph
    if ow == nil or (ow == pw and oh == ph) then return end
    if EllesmereUI._abAnchorSuppressed then return end
    local m = ((ow ~= pw) and 1 or 0) + ((oh ~= ph) and 2 or 0)
    if elem.linkedDimensions then m = 3 end
    local cur = mp.pending[key]
    if cur and cur ~= m then m = 3 end
    mp.pending[key] = m
    if not mp.armed then
        mp.armed = true
        C_Timer.After(0, mp.flush)
    end
end

-- An element's match pad or scale changed while its own size did not (a
-- Classic WoW UI frame-size slider, a Blizzard Style Frame Scale change):
-- re-pull its own width/height match and re-push its children.
-- NotifyElementResized cannot do this, since its self re-pull keys on a size
-- change. Never in unlock mode; a no-op for elements in no match. mask (the
-- notifier's): 1 = width only, 2 = height only, nil = both.
function EllesmereUI.ReapplyMatchPads(key, mask)
    if UM.isUnlocked or not key then return end
    -- An explicit call covers a queued one, and the pad it applies is the one
    -- on record, so the rebuild it triggers does not queue the same pass again.
    local mp = EllesmereUI._matchPad
    mp.pending[key] = nil
    local pe = registeredElements[key]
    if pe and pe.getMatchPad then
        local pw, ph = pe.getMatchPad(key)
        mp.w[key], mp.h[key] = pw or 0, ph or 0
    end
    local wdb = MatchH.GetWidthMatchDB()
    if wdb and mask ~= 2 then
        if wdb[key] then MatchH.ApplyWidthMatch(key, wdb[key]) end
        EllesmereUI.PropagateWidthMatch(key)
    end
    local hdb = MatchH.GetHeightMatchDB()
    if hdb and mask ~= 1 then
        if hdb[key] then MatchH.ApplyHeightMatch(key, hdb[key]) end
        EllesmereUI.PropagateHeightMatch(key)
    end
end

-- Commit a typed Extra Width / Height from the unlock cog (axis "w" / "h",
-- whole pixels clamped to -100..100): store it, re-pull the element's own match,
-- then re-push its match children and anchor chain exactly as a fresh match pick
-- does. ReapplyMatchPads cannot serve here, it stands down in unlock mode. File
-- scope because CreateMover sits at Lua 5.1's 60-upvalue cap.
function MatchH.CommitMatchExtra(axis, key, px)
    if not key then return end
    local isH = (axis == "h")
    local target
    if isH then target = MatchH.GetHeightMatchInfo(key)
    else target = MatchH.GetWidthMatchInfo(key) end
    if not target then return end
    local ax = isH and "h" or "w"
    px = math.floor(math.max(-100, math.min(100, tonumber(px) or 0)) + 0.5)
    if px == (EllesmereUI.GetMatchExtra(ax, key) or 0) then return end
    MatchH.SetMatchExtra(ax, key, px)
    if isH then MatchH.ApplyHeightMatch(key, target)
    else MatchH.ApplyWidthMatch(key, target) end
    UM.hasChanges = true
    local m = movers[key]
    if m then
        m:SyncSize()
        if m.RefreshAnchoredText then m:RefreshAnchoredText() end
        -- The matched label grew or shrank ("W Matched +5"): re-lay the row.
        if m._layoutActionRow then m._layoutActionRow() end
    end
    local ai = GetAnchorInfo(key)
    if ai then UM.ApplyAnchorPosition(key, ai.target, ai.side, true) end
    if isH then EllesmereUI.PropagateHeightMatch(key)
    else EllesmereUI.PropagateWidthMatch(key) end
    -- A linked-dimensions element (square icons) resizes both sides from one
    -- axis: re-push the other axis's match children too.
    local el = registeredElements[key]
    if el and el.linkedDimensions then
        if isH then EllesmereUI.PropagateWidthMatch(key)
        else EllesmereUI.PropagateHeightMatch(key) end
    end
    UM.PropagateAnchorChain(key)
end

-- Each match's Extra Width / Height as it stood when unlock mode opened
-- (SnapshotPositions), restored with the links on discard (RevertPositions).
MatchH.snapExtra = { w = {}, h = {} }

-------------------------------------------------------------------------------
--  Apply ALL width/height matches globally (used on login/reload)
-------------------------------------------------------------------------------
-- Break circular chains in a match DB before applying: walk each chain and
-- remove the link that closes a loop.
function MatchH.BreakMatchCycles(db)
    if not db then return end
    local safe = {}  -- keys confirmed cycle-free
    for childKey in pairs(db) do
        if not safe[childKey] then
            local visited = {}
            local current = childKey
            while current and db[current] do
                if visited[current] then
                    -- current closes the cycle; break it
                    db[current] = nil
                    break
                end
                visited[current] = true
                current = db[current]
            end
            -- Mark all visited keys as safe
            for k in pairs(visited) do safe[k] = true end
        end
    end
end

-- Apply every entry in a match DB in dependency order (roots, then children,
-- then grandchildren). Required for chains A -> B -> C: C processed before B
-- reads B's stale width and stays wrong. BreakMatchCycles runs first so the
-- graph is acyclic; the visited guard is defensive.
local function ApplyMatchesInDependencyOrder(db, applyFn)
    if not db then return end
    local depth = {}
    local function GetDepth(k, visiting)
        if depth[k] ~= nil then return depth[k] end
        if visiting[k] then return 0 end
        visiting[k] = true
        local target = db[k]
        if target and db[target] then
            depth[k] = 1 + GetDepth(target, visiting)
        else
            depth[k] = 0
        end
        visiting[k] = nil
        return depth[k]
    end
    local order = {}
    for childKey in pairs(db) do
        GetDepth(childKey, {})
        order[#order + 1] = childKey
    end
    table.sort(order, function(a, b) return depth[a] < depth[b] end)
    for _, childKey in ipairs(order) do
        applyFn(childKey, db[childKey])
    end
end

local function ApplyAllWidthHeightMatches()
    -- No mid-rebuild CDM guard here: CDM fires its own ApplyAllWidthHeightMatches at
    -- the end of CollectAndReanchor, which corrects any transient widths read while its
    -- icon counts were stale. A guard blocked unrelated UF height matches during spec
    -- swap. Break circular chains from old data before applying.
    MatchH.BreakMatchCycles(MatchH.GetWidthMatchDB())
    MatchH.BreakMatchCycles(MatchH.GetHeightMatchDB())
    ApplyMatchesInDependencyOrder(MatchH.GetWidthMatchDB(), MatchH.ApplyWidthMatch)
    ApplyMatchesInDependencyOrder(MatchH.GetHeightMatchDB(), MatchH.ApplyHeightMatch)
end

-- Re-sync every active width/height match when the global UI Scale changes.  -- eui-style: allow comment-budget
-- ApplyWidth/HeightMatch convert the target's size into the source's space via
-- GetEffectiveScale() ratio, but nothing else re-runs that conversion after a UI
-- Scale change, so a pair whose frames don't scale identically (a UIParent-parented
-- element matched to an Edit Mode frame with its own scale) keeps the OLD ratio
-- until something unrelated forces a re-match, showing as extra spacing. The short
-- delay lets every frame's GetEffectiveScale() finish propagating. Debounced to a
-- quiet period, not a fixed delay: a live-preview UI Scale slider fires many times
-- per second while dragged, and re-running per firing fed a non-converging loop
-- (re-applied width -> SetSize -> resize propagation -> re-apply). Timer lives on
-- EllesmereUI.PP, shared with EllesmereUI.lua's PP.SetUIScale trigger, so one
-- listener cancels/replaces the other's pending timer instead of both running a full pass.
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("UI_SCALE_CHANGED")
    f:SetScript("OnEvent", function()
        local PPu = EllesmereUI and EllesmereUI.PP
        if not PPu then return end
        if PPu._scaleMatchDebounce then PPu._scaleMatchDebounce:Cancel() end
        PPu._scaleMatchDebounce = C_Timer.NewTimer(0.3, function()
            PPu._scaleMatchDebounce = nil
            ApplyAllWidthHeightMatches()
        end)
    end)
end

-------------------------------------------------------------------------------
--  OnSizeChanged hook for registered element frames: fires NotifyElementResized so
--  dependent elements (width-matched, anchored) update without the source addon calling anything.
-------------------------------------------------------------------------------
local _sizeHookedFrames = {}  -- [frame] = true
local _pointHookedFrames = {} -- [frame] = true

-- Last-seen screen position per key. NotifyElementMoved compares GetLeft/GetTop to
-- these to detect real moves (SetPoint fires many times per frame via ClearAllPoints+SetPoint pairs).
local _lastScreenPos = {}  -- [key] = { l = ..., t = ... }
local _moveCheckScheduled = {}  -- [key] = true (dedupes same-frame checks)

-- Fires the anchor cascade for `key` if its frame actually moved on screen since the
-- last check. Deferred to end-of-frame so a ClearAllPoints+SetPoint pair coalesces
-- into one check. Needed because NotifyElementResized only fires from
-- OnSizeChanged and the cascade only from ApplyAnchorPosition, so pure position
-- changes from an addon's own SetPoint (e.g. ERB re-applying sp.unlockPos on every
-- Class Resource rebuild) hit neither emitter and anchored children never learn the target moved.
local function NotifyElementMoved(key)
    if UM.isUnlocked then return end  -- unlock mode owns positioning
    if _moveCheckScheduled[key] then return end
    _moveCheckScheduled[key] = true
    C_Timer.After(0, function()
        _moveCheckScheduled[key] = nil
        if UM.isUnlocked then return end
        local bar = UM.GetBarFrame(key)
        if not bar then return end
        local l, t = bar:GetLeft(), bar:GetTop()
        -- A frame riding an engine aura container (a Blizzard Style cast bar
        -- under its frame's aura stack) reports a secret position: nothing to
        -- compare, and its children cannot follow it anyway (they re-anchor on
        -- the next plain apply).
        if issecretvalue and (issecretvalue(l) or issecretvalue(t)) then return end
        if not l or not t then return end
        local prev = _lastScreenPos[key]
        if prev and math.abs(l - prev.l) < 0.5 and math.abs(t - prev.t) < 0.5 then
            return  -- position unchanged (within half a physical pixel)
        end
        if prev then prev.l, prev.t = l, t else _lastScreenPos[key] = { l = l, t = t } end
        -- Convergence: ApplyAnchorPosition's idempotent guard skips SetPoint when the
        -- child is already within 0.5px of target, so the cascade drains in bounded
        -- passes -- each call re-enters this hook, but the check above returns early once settled.
        if EllesmereUI.PropagateAnchorChain then
            EllesmereUI.PropagateAnchorChain(key, "all")
        end
    end)
end

local function HookFrameSizeChanged(key)
    -- No hooks on chat frames: ChatFrame1 is docked inside Blizzard's secure
    -- FCF_OpenTemporaryWindow chain and any addon code in OnSizeChanged/SetPoint
    -- hooks taints the execution context. Chat persists its own position/size.
    if key and key:find("^ECHAT_") then return end
    local bar = UM.GetBarFrame(key)
    if not bar then return end
    if not _sizeHookedFrames[bar] then
        _sizeHookedFrames[bar] = true
        bar:HookScript("OnSizeChanged", function()
            if UM.isUnlocked then return end
            EllesmereUI.NotifyElementResized(key)
        end)
    end
    if not _pointHookedFrames[bar] then
        _pointHookedFrames[bar] = true
        hooksecurefunc(bar, "SetPoint", function()
            NotifyElementMoved(key)
        end)
    end
end

-- Wrap RegisterUnlockElements so new elements get OnSizeChanged hooks
-- installed automatically (handles late registrations like CDM bars).
do
    local origRegister = EllesmereUI.RegisterUnlockElements
    function EllesmereUI:RegisterUnlockElements(elements, folder)
        origRegister(self, elements, folder)
        -- Defer hook installation so the frame has time to be created/sized
        C_Timer.After(0.1, function()
            for _, elem in ipairs(elements) do
                if elem.key then
                    HookFrameSizeChanged(elem.key)
                end
            end
        end)
    end
end

local _overlayFadeFrame         -- tiny OnUpdate driver for select-element dimmer fade

-- Smoothly fade the background overlay between normal and select-element alpha
local function FadeOverlayForSelectElement(entering)
    if not UM.unlockFrame or not UM.unlockFrame._overlay then return end
    local startA = entering and (UM.unlockFrame._overlayMaxAlpha or 0.20) or SELECT_ELEMENT_ALPHA
    local endA   = entering and SELECT_ELEMENT_ALPHA or (UM.unlockFrame._overlayMaxAlpha or 0.20)
    if not _overlayFadeFrame then
        _overlayFadeFrame = CreateFrame("Frame")
    end
    local elapsed = 0
    _overlayFadeFrame:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        local t = math.min(elapsed / SELECT_ELEMENT_FADE, 1)
        local a = startA + (endA - startA) * t
        UM.unlockFrame._overlay:SetColorTexture(0.030, 0.023, 0.018, a)
        if t >= 1 then self:SetScript("OnUpdate", nil) end
    end)
end

-- Cancel any active pick mode (width/height match, anchor to, snap select) and
-- restore overlay text and screen brightness.
local function CancelPickMode()
    if UM.pickModeMover then
        local m = UM.pickModeMover
        -- Restore overlay text visibility only if still hovered
        if m._hidePickText then m._hidePickText() end
        if m:IsMouseOver() then
            if m._showOverlayText then m._showOverlayText() end
        else
            if m._hideOverlayText then m._hideOverlayText() end
        end
        UM.pickMode = nil
        UM.pickModeMover = nil
        FadeOverlayForSelectElement(false)
    end
    -- Also cancel snap select-element picker if active
    if UM.selectElementPicker then
        local picker = UM.selectElementPicker
        picker._snapTarget = picker._preSelectTarget
        picker._preSelectTarget = nil
        if picker._updateSnapLabel then picker._updateSnapLabel() end
        UM.selectElementPicker = nil
        FadeOverlayForSelectElement(false)
    end
    -- Hide anchor dropdown if open
    if UM.anchorDropdownFrame then UM.anchorDropdownFrame:Hide() end
    if UM.anchorDropdownCatcher then UM.anchorDropdownCatcher:Hide() end
    if UM.growDropdownFrame then UM.growDropdownFrame:Hide() end
    if UM.growDropdownCatcher then UM.growDropdownCatcher:Hide() end
end

-- Enter element pick mode for a FALLBACK anchor target: same flow as anchoring,
-- but the dispatcher stores the result on the child's existing anchor link.
-- Namespace-attached so the cog menu can start it without another upvalue.
function EllesmereUI._BeginFallbackAnchorPick(mover)
    if not mover then return end
    CancelPickMode()
    UM.pickMode = "fallbackAnchor"
    UM.pickModeMover = mover
    if mover._showPickText then
        mover._showPickText("Click any element\nto set as the Fallback Anchor")
    end
    FadeOverlayForSelectElement(true)
end

-- Red border flash animation for error feedback (e.g. trying to drag an anchored element)
local function FlashRedBorder(m)
    if not m or not m._brd then return end
    if not m._redFlashBrd then
        m._redFlashBrd = EllesmereUI.MakeBorder(m, 1, 0.2, 0.2, 0)
        m._redFlashBrd._frame:SetFrameLevel(m:GetFrameLevel() + 4)
        local PP = EllesmereUI and EllesmereUI.PP
        if PP then PP.SetBorderSize(m._redFlashBrd._frame, 2) end
    end
    local brd = m._redFlashBrd
    local elapsed = 0
    if not m._redFlashFrame then
        m._redFlashFrame = CreateFrame("Frame")
    end
    m._redFlashFrame:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed < 0.8 then
            local a = 0.5 + 0.5 * math.sin(elapsed * 10)
            brd:SetColor(1, 0.2, 0.2, a)
        elseif elapsed < 1.5 then
            brd:SetColor(1, 0.2, 0.2, math.max(0, 1 - (elapsed - 0.8) / 0.7))
        else
            brd:SetColor(1, 0.2, 0.2, 0)
            self:SetScript("OnUpdate", nil)
        end
    end)
end

local RejectH = {}
function RejectH.ShowTooltip(text)
    if not RejectH._anchor then
        RejectH._anchor = CreateFrame("Frame", nil, UIParent)
        RejectH._anchor:SetSize(1, 1)
        RejectH._timer = CreateFrame("Frame")
    end
    local sc = UIParent:GetEffectiveScale()
    local mx, my = GetCursorPosition()
    RejectH._anchor:ClearAllPoints()
    RejectH._anchor:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", mx / sc, my / sc)
    EllesmereUI.ShowWidgetTooltip(RejectH._anchor, text, {})
    local elapsed = 0
    RejectH._timer:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed >= 3 then
            EllesmereUI.HideWidgetTooltip()
            self:SetScript("OnUpdate", nil)
            return
        end
        local s = UIParent:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        RejectH._anchor:ClearAllPoints()
        RejectH._anchor:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx / s, cy / s)
    end)
end
function RejectH.IsActionBar(barKey)
    if barKey == "MainBar" then return true end
    if barKey:sub(1, 3) == "Bar" then
        local n = tonumber(barKey:sub(4))
        return n and n >= 2 and n <= 8
    end
    return false
end

-------------------------------------------------------------------------------
--  Combat-parked positioning: any anchor application (or guarded bar reposition)
--  skipped for combat lockdown is recorded here and reapplied once on
--  PLAYER_REGEN_ENABLED. Without it, skips in the cascade paths
--  (PropagateAnchorChain, ScheduleAnchorBatch, retry loops) are silent and the
--  element stays misplaced until an unrelated full reapply happens.
--  Namespace-scoped, not file-local: file is at the Lua 5.1 200-local cap.
-------------------------------------------------------------------------------
do
    local AnchorPark = {}
    EllesmereUI._AnchorPark = AnchorPark

    -- One combat queue for every lockdown-skipped apply in this file
    local queue = EllesmereUI.NewCombatQueue(CreateFrame("Frame"))
    EllesmereUI._UnlockCombatQueue = queue

    local function AnchorPark_Drain()
        local anchorKeys = AnchorPark.keys
        local posKeys = AnchorPark.posKeys
        AnchorPark.keys = nil
        AnchorPark.posKeys = nil
        -- Bar positions first: anchored children read target bounds,
        -- so targets must be placed before the anchor pass.
        if posKeys then
            local db = UM.GetPositionDB()
            for key in pairs(posKeys) do
                local pos = db and db[key]
                if pos and pos.point then
                    if not UM.ApplyCenterPosition(key, pos) then
                        local bar = UM.GetBarFrame(key)
                        if bar then
                            pcall(function()
                                EllesmereUI.ClearFramePoints(bar)
                                EllesmereUI.SetFramePoint(bar, pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
                            end)
                        end
                    end
                end
            end
        end
        if anchorKeys then
            -- Full dependency-sorted pass instead of per-key applies: parked
            -- chains must apply parents first; idempotent for never-parked anchors.
            if EllesmereUI.ReapplyAllUnlockAnchors then
                EllesmereUI.ReapplyAllUnlockAnchors()
            end
        end
    end

    -- Park an anchored child whose apply was blocked by combat lockdown.
    function AnchorPark.Park(childKey)
        local keys = AnchorPark.keys
        if not keys then keys = {}; AnchorPark.keys = keys end
        keys[childKey] = true
        queue.Defer("AnchorPark", AnchorPark_Drain)
    end

    -- Park a bar whose saved-position reapply was blocked by combat lockdown.
    function AnchorPark.ParkBarPos(barKey)
        local keys = AnchorPark.posKeys
        if not keys then keys = {}; AnchorPark.posKeys = keys end
        keys[barKey] = true
        queue.Defer("AnchorPark", AnchorPark_Drain)
    end
end

-- Apply an anchor: place the child on `side` ("LEFT"/"RIGHT"/"TOP"/"BOTTOM") of  -- eui-style: allow comment-budget
-- the target; offsetX/offsetY, if present, position it from the anchor edge.
-------------------------------------------------------------------------------
--  Fallback anchors (opt-in, per anchored element): a target that doesn't exist
--  leaves the child unpositioned -- its saved position is skipped (anchor-linked)
--  and the anchor can't apply, so it lands wherever the default build put it. A
--  stored fallback gives it a concrete position. Scoped to targets absent by
--  config/gameplay: tracking bars/groups (per-spec) and the pet frame (no pet).
--  Free until stored: one table lookup per apply; pet watcher created on first use.
-------------------------------------------------------------------------------
do
    local function EligibleTarget(targetKey)
        if type(targetKey) ~= "string" then return false end
        return targetKey == "pet"
            or targetKey:find("^TBB_%d+$") ~= nil
            or targetKey:find("^TBBG_") ~= nil
    end

    -- Targets where a HIDDEN frame means "logically inactive" (pet frame with no
    -- pet). Tracking bars hide by design when their buff is down, so they are NOT
    -- in this set -- their absent signal is a nil frame.
    local hiddenIsInactive = { pet = true }

    function EllesmereUI.EligibleFallbackTarget(targetKey)
        return EligibleTarget(targetKey)
    end

    -- Growth-fixed-edge pin for fallback placement: the flush side-snap centers
    -- the child on the target's CROSS axis, which shifts a custom-growth bar's
    -- fixed edge when it's a different size elsewhere. A standard anchor pins the
    -- GROWTH edge, not the center; this returns what to add to the flush-snap
    -- center on the cross axis to match (the snap axis already holds its own edge,
    -- e.g. cx = tL - cW/2 keeps the right edge at tL). Zero for center-growth bars
    -- and non-CDM/AB elements (GetBarGrowDirActual returns "CENTER"). cW/cH are UIParent-space dims. Fallback/override anchor code only.
    EllesmereUI._FallbackGrowShift = function(childKey, side, cW, cH)
        local gd = GetBarGrowDirActual(childKey)
        if not gd or gd == "CENTER" then return 0, 0 end
        local horiz = (gd == "LEFT" or gd == "RIGHT")
        local crossX = (side == "TOP" or side == "BOTTOM" or side == "CENTER" or side == nil)
        local crossY = (side == "LEFT" or side == "RIGHT" or side == "CENTER" or side == nil)
        -- RIGHT/UP fix the near edge (left/bottom) -> center sits +half past it;
        -- LEFT/DOWN fix the far edge (right/top) -> center sits -half before it.
        if horiz and crossX then
            return (gd == "RIGHT") and (cW / 2) or (-cW / 2), 0
        elseif (not horiz) and crossY then
            return 0, (gd == "UP") and (cH / 2) or (-cH / 2)
        end
        return 0, 0
    end

    -- True when this owned positioning for the apply (fallback applied, already in
    -- place, held, or parked for regen); false = normal path. A fallback is a
    -- secondary anchor link {target, side}: with the primary target absent, the
    -- child snaps flush to that side of the fallback target, using the same
    -- absolute UIParent-space math as a fresh side-snap anchor.
    function EllesmereUI._TryFallbackAnchor(childKey, targetKey, childBar, targetBar)
        if UM.isUnlocked then return false end
        local db = GetAnchorDB()
        local info = db and db[childKey]
        local fb = info and info.fallback
        if not fb or not fb.target then return false end
        local side = fb.side
        local inactive
        if not targetBar then
            inactive = true
        elseif hiddenIsInactive[targetKey] then
            inactive = not targetBar:IsShown()
        end
        if not inactive then return false end
        if InCombatLockdown() and childBar:IsProtected() then
            EllesmereUI._AnchorPark.Park(childKey)
            return true
        end
        local tgt = UM.GetBarFrame(fb.target)
        if not tgt or not tgt:GetLeft() then
            -- Fallback target unavailable as well: hold position.
            return true
        end
        local uiS = UIParent:GetEffectiveScale()
        local tS = tgt:GetEffectiveScale()
        local cS = childBar:GetEffectiveScale()
        local tL = (tgt:GetLeft() or 0) * tS / uiS
        local tR = (tgt:GetRight() or 0) * tS / uiS
        local tT = (tgt:GetTop() or 0) * tS / uiS
        local tB = (tgt:GetBottom() or 0) * tS / uiS
        local tCX = (tL + tR) / 2
        local tCY = (tT + tB) / 2
        -- Growth-edge extent applies to the fallback target too.
        if EllesmereUI._GetAnchorTargetExtent then
            local ext = EllesmereUI._GetAnchorTargetExtent(fb.target, side)
            if ext then
                if side == "TOP" then tT = ext
                elseif side == "BOTTOM" then tB = ext
                elseif side == "LEFT" then tL = ext
                elseif side == "RIGHT" then tR = ext
                end
            end
        end
        local cW = (childBar:GetWidth() or 50) * cS / uiS
        local cH = (childBar:GetHeight() or 50) * cS / uiS
        local cx, cy
        if side == "LEFT" then
            cx, cy = tL - cW / 2, tCY
        elseif side == "RIGHT" then
            cx, cy = tR + cW / 2, tCY
        elseif side == "TOP" then
            cx, cy = tCX, tT + cH / 2
        elseif side == "BOTTOM" then
            cx, cy = tCX, tB - cH / 2
        else
            cx, cy = tCX, tCY
        end
        -- User-set offsets relative to the fallback anchor point (UIParent
        -- units; edited in physical pixels via the cog menu rows).
        cx = cx + (fb.offsetX or 0)
        cy = cy + (fb.offsetY or 0)
        -- Keep the growth-fixed edge (not the center) pinned on the cross axis so
        -- a differently-sized bar on another character still lines up, like a
        -- standard anchor. Inert (0,0) for center-growth / non-bar children.
        local gsx, gsy = EllesmereUI._FallbackGrowShift(childKey, side, cW, cH)
        cx = cx + gsx
        cy = cy + gsy
        -- Temporary per-target visual shift (e.g. "Shift Elements if No
        -- Resource/Power"), mirroring the main path. fb.target is the live target
        -- actually in use here, not targetKey (the inactive primary).
        if not UM.isUnlocked and EllesmereUI._GetAnchorTargetShiftDir then
            local dir, extraY = EllesmereUI._GetAnchorTargetShiftDir(fb.target, childKey)
            if dir ~= 0 then cy = cy + dir * ((tT - tB) + (extraY or 0)) end
        end
        -- Child-local scale space + pixel snap + idempotent guard, mirroring
        -- the standard CENTER path in ApplyAnchorPosition.
        local acRatio = uiS / cS
        local bCenterX = (cx - UIParent:GetWidth() / 2) * acRatio
        local bCenterY = (cy - UIParent:GetHeight() / 2) * acRatio
        local PPa = PP or (EllesmereUI and EllesmereUI.PP)
        if PPa and PPa.SnapCenterForDim then
            bCenterX = PPa.SnapCenterForDim(bCenterX, childBar:GetWidth() or 0, cS)
            bCenterY = PPa.SnapCenterForDim(bCenterY, childBar:GetHeight() or 0, cS)
        end
        local okPt, point, relTo, relPoint, curX, curY = pcall(childBar.GetPoint, childBar, 1)
        -- A child still on a followed edge reads its anchor back secret: never compared.
        if okPt and issecretvalue and (issecretvalue(point) or issecretvalue(relPoint)
           or issecretvalue(curX) or issecretvalue(curY)) then okPt = false end
        if okPt and point == "CENTER" and relPoint == "CENTER" and relTo == UIParent then
            local onePx = ((PPa and PPa.perfect) or 1) / cS
            local tol = onePx * 0.5
            if curX and curY
               and math.abs(curX - bCenterX) < tol
               and math.abs(curY - bCenterY) < tol then
                return true
            end
        end
        pcall(function()
            EllesmereUI.ClearFramePoints(childBar)
            EllesmereUI.SetFramePoint(childBar, "CENTER", UIParent, "CENTER", bCenterX, bCenterY)
        end)
        -- Children anchored to THIS child must follow it to the fallback spot.
        UM._pendingAnchorKeys[childKey] = "all"
        ScheduleAnchorBatch()
        return true
    end

    -- Store the fallback link (target + side), chosen through the same element
    -- pick mode as regular anchoring.
    function EllesmereUI.SetAnchorFallback(childKey, targetKey, side)
        local db = GetAnchorDB()
        local info = db and db[childKey]
        if not info or not info.target then return false end
        if not targetKey or targetKey == childKey or targetKey == info.target then return false end
        info.fallback = { target = targetKey, side = side or "BOTTOM" }
        EllesmereUI._anchorLinksStamp = (EllesmereUI._anchorLinksStamp or 0) + 1
        EllesmereUI._EnsureFallbackWatchers()
        if EllesmereUI._RefreshFallbackGhosts then EllesmereUI._RefreshFallbackGhosts() end
        return true
    end

    function EllesmereUI.ClearAnchorFallback(childKey)
        local db = GetAnchorDB()
        local info = db and db[childKey]
        if info then info.fallback = nil end
        EllesmereUI._anchorLinksStamp = (EllesmereUI._anchorLinksStamp or 0) + 1
        if EllesmereUI._RefreshFallbackGhosts then EllesmereUI._RefreshFallbackGhosts() end
    end

    -- Pet watcher: created only once a pet-target fallback exists (free until
    -- opted in). UNIT_PET fires on summon AND dismiss/death, so one debounced reapply covers both.
    local petWatcher
    local petPassPending
    function EllesmereUI._EnsureFallbackWatchers()
        local db = GetAnchorDB()
        if not db then return end
        local needPet = false
        for _, info in pairs(db) do
            if info.fallback and hiddenIsInactive[info.target] then
                needPet = true
                break
            end
        end
        if needPet and not petWatcher then
            petWatcher = CreateFrame("Frame")
            petWatcher:RegisterUnitEvent("UNIT_PET", "player")
            petWatcher:SetScript("OnEvent", function()
                if petPassPending then return end
                petPassPending = true
                C_Timer.After(0.1, function()
                    petPassPending = nil
                    if UM.isUnlocked then return end
                    if EllesmereUI.ReapplyAllUnlockAnchors then
                        EllesmereUI.ReapplyAllUnlockAnchors()
                    end
                end)
            end)
        elseif not needPet and petWatcher then
            petWatcher:UnregisterAllEvents()
            petWatcher:SetScript("OnEvent", nil)
            petWatcher = nil
        end
    end

    -- Debounced re-eval when a fallback-eligible target may have appeared or
    -- vanished (TBB registration runs on every bar edit / spec swap). No-op
    -- unless at least one fallback is stored.
    local tbbPassPending
    function EllesmereUI.NotifyFallbackTargetsChanged()
        local db = GetAnchorDB()
        if not db then return end
        local any = false
        for _, info in pairs(db) do
            if info.fallback then any = true break end
        end
        if not any or tbbPassPending or UM.isUnlocked then return end
        tbbPassPending = true
        C_Timer.After(0.2, function()
            tbbPassPending = nil
            if UM.isUnlocked then return end
            if EllesmereUI.ReapplyAllUnlockAnchors then
                EllesmereUI.ReapplyAllUnlockAnchors()
            end
        end)
    end
end

UM.GetBarGrowDirActual, UM.GetBarGrowDir, UM.GetAnchorDB, UM.GetAnchorInfo = GetBarGrowDirActual, GetBarGrowDir, GetAnchorDB, GetAnchorInfo
UM.SetAnchorInfo, UM.ClearAnchorInfo, UM.IsAnchored, UM.MatchH = SetAnchorInfo, ClearAnchorInfo, IsAnchored, MatchH
UM.ValidateStoredLinks, UM.ScheduleAnchorBatch, UM.ApplyAllWidthHeightMatches, UM.HookFrameSizeChanged = ValidateStoredLinks, ScheduleAnchorBatch, ApplyAllWidthHeightMatches, HookFrameSizeChanged
UM.FadeOverlayForSelectElement, UM.CancelPickMode, UM.FlashRedBorder, UM.RejectH = FadeOverlayForSelectElement, CancelPickMode, FlashRedBorder, RejectH
end
