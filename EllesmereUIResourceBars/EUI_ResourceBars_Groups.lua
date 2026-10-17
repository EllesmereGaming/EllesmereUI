if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ResourceBars_Groups.lua
--
--  Border Around All groups, the Blizzard Style bar backing, shadow and
--  mask, and the chrome of the stock cast bar.
--  Reads the earlier Resource Bars files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIResourceBars.lua or an earlier Resource Bars file failed to load.
if not I or I.broken then return end
I.broken = true

local PP = EllesmereUI.PP

local ERB, GetPrimaryPowerType = I.ERB, I.GetPrimaryPowerType
local GetSecondaryResource, DEFAULTS = I.GetSecondaryResource, I.DEFAULTS
local IsVerticalOrientation, NormalizeAnchorKey = I.IsVerticalOrientation, I.NormalizeAnchorKey
local ShouldShowBar, ShouldShowSecondary = I.ShouldShowBar, I.ShouldShowSecondary

local mainFrame
I.mainFrameSetters[#I.mainFrameSetters + 1] = function(v) mainFrame = v end
local healthBar
I.healthBarSetters[#I.healthBarSetters + 1] = function(v) healthBar = v end
local primaryBar
I.primaryBarSetters[#I.primaryBarSetters + 1] = function(v) primaryBar = v end
local secondaryFrame
I.secondaryFrameSetters[#I.secondaryFrameSetters + 1] = function(v) secondaryFrame = v end
local castBarFrame
I.castBarFrameSetters[#I.castBarFrameSetters + 1] = function(v) castBarFrame = v end

-------------------------------------------------------------------------------
--  "Border Around All" (general.classicBorderAll, off by default; one key
--  for both stock styles, each style keeping its own value through the Style
--  page's per-style slots): one frame round the shown health, power and
--  class resource bars as a group instead of one per bar -- the vanilla
--  frame under Classic WoW UI, the personal resource display's panel under
--  Blizzard Style (ERB_ApplyBlizzGroupPanel). It holds only while at
--  least two bars show, share one orientation and one length (width-matched
--  to each other in unlock mode, or simply equal), their long-axis edges line
--  up within a physical pixel and no gap between them is wider than a bar
--  plus the frame's reach; otherwise every bar keeps its own frame (the
--  setting stays on and takes over again once they line up). The group frame
--  is our own host anchored from the first bar's TOPLEFT to the last bar's
--  BOTTOMRIGHT, so the layout engine keeps it on the bars through every move
--  with no Lua running; membership and eligibility are decided on the
--  visibility pass (which follows every rebuild and every visibility edge)
--  and on unlock moves, coalesced to one pass per frame. All three bars wear
--  the lead bar's Border Size while the setting is on, so a fallback's
--  per-bar frames and the size-match pads agree with the group frame. On ns.
-------------------------------------------------------------------------------
ns._erbGrpMatchKeys = { "ERB_Health", "ERB_Power", "ERB_ClassResource" }
ns._erbGrpMembers, ns._erbGrpLo, ns._erbGrpHi = {}, {}, {}
function ns.ERB_GroupSettingOn(p)
    p = p or (ERB.db and ERB.db.profile)
    return (p and p.general and p.general.classicBorderAll and ns.ERB_BarsBlizz()) and true or false
end
-- The bar whose Border Size the group wears: health, else power, else the
-- class resource (settings only, so the pads never flip at runtime).
function ns.ERB_GroupLeadCfg(p)
    if p.health and p.health.enabled then return p.health end
    if p.primary and p.primary.enabled ~= false then return p.primary end
    return p.secondary
end
-- A health, power or class resource bar's frame scale: the group's while
-- the setting is on under Classic WoW UI, the bar's own otherwise.
function ns.ERB_BarFrameK(cfg)
    local p = ERB.db and ERB.db.profile
    if p and ns.ERB_GroupSettingOn(p) then return ns.ERB_ClassicFrameK(ns.ERB_GroupLeadCfg(p)) end
    return ns.ERB_ClassicFrameK(cfg)
end
-- The unlock-mode match root of a bar on its long axis (width links for a
-- horizontal bar, height links for a vertical one), following chained
-- links; the key itself when unmatched.
function ns.ERB_GroupMatchRoot(key, vertical)
    local get = vertical and EllesmereUI.GetHeightMatchTarget or EllesmereUI.GetWidthMatchTarget
    if not get then return key end
    for _ = 1, 16 do
        local nxt = get(key)
        if not nxt then break end
        -- A match with Extra Width/Height is not its target's length: root here.
        if EllesmereUI.GetMatchExtra and EllesmereUI.GetMatchExtra(vertical and "h" or "w", key) then break end
        key = nxt
    end
    return key
end
-- Whether the setting can apply to this profile on this character (the
-- options toggle's requirement): ok, or false and why ("count" = fewer than
-- two bars have something to show, "orient" = mixed orientations, "width" =
-- neither width-matched to each other nor the same length). A bar the group
-- could never hold does not count: one riding the cursor, shown only on
-- mouseover (revealed on its own) or set never to show.
function ns.ERB_GroupCheck(p)
    if not p then return false, "count" end
    local g = p.general or DEFAULTS.profile.general
    local hp, pp, sp = p.health, p.primary, p.secondary
    local hasRes = GetSecondaryResource() ~= nil
    local es = mainFrame and mainFrame:GetEffectiveScale() or 1
    local tol = ((PP and PP.perfect) or 1) / es + 0.01
    local n, vert, len, root, sameRoot, sameLen = 0, nil, nil, nil, true, true
    for i = 1, 3 do
        local inBar, v, l
        if i == 1 then
            inBar = hp and hp.enabled and not (healthBar and healthBar._erbMouseTrack
                    or (not healthBar and NormalizeAnchorKey(hp.anchorTo) == "mouse"))
                and hp.visibility ~= "never" and ShouldShowBar(hp) ~= "mouseover"
            v = hp and IsVerticalOrientation(hp.orientation or g.orientation)
            l = (hp and hp.width) or 214
        elseif i == 2 then
            inBar = pp and pp.enabled ~= false and GetPrimaryPowerType() ~= nil
                and not (sp and sp.hidePowerIfResource and sp.enabled ~= false and hasRes)
                and not (primaryBar and primaryBar._erbMouseTrack
                    or (not primaryBar and NormalizeAnchorKey(pp.anchorTo) == "mouse"))
                and pp.visibility ~= "never" and ShouldShowBar(pp) ~= "mouseover"
            v = pp and IsVerticalOrientation(pp.orientation or g.orientation)
            l = (pp and pp.width) or 214
        else
            -- Blizzard Class Resource Art stands outside the group frame.
            inBar = sp and sp.enabled ~= false and hasRes and not ns._erbArtOn
                and not (secondaryFrame and secondaryFrame._erbMouseTrack
                    or (not secondaryFrame and NormalizeAnchorKey(sp.anchorTo) == "mouse"))
                and sp.visibility ~= "never" and ShouldShowSecondary() ~= "mouseover"
            v = sp and (sp.pipOrientation or "HORIZONTAL") ~= "HORIZONTAL"
            l = (sp and sp.pipWidth) or 214
        end
        -- Membership for ERB_BarsAnchoredTight (reused table).
        ns._erbGrpChk[i] = inBar and true or false
        if inBar then
            n = n + 1
            v = v and true or false
            ns._erbGrpChkVert = v
            if vert == nil then vert = v elseif vert ~= v then return false, "orient" end
            local r = ns.ERB_GroupMatchRoot(ns._erbGrpMatchKeys[i], v)
            if root == nil then root = r elseif root ~= r then sameRoot = false end
            if len == nil then len = l elseif math.abs(len - l) > tol then sameLen = false end
        end
    end
    if n < 2 then return false, "count" end
    if not (sameRoot or sameLen) then return false, "width" end
    return true
end
ns._erbGrpChk = {}
-- Whether the bars the group would hold already sit as one stack: every
-- shown member but one anchored (unlock mode) to another member along the
-- stacking axis, within a physical pixel either way. Turns Border Around All
-- on by default under Classic WoW UI (ERB_SeedStockBars); the runtime check
-- still decides each session whether the group frame holds.
function ns.ERB_BarsAnchoredTight(p)
    if not (p and ns.ERB_GroupCheck(p)) then return false end
    local anchors = EllesmereUIDB and EllesmereUIDB.unlockAnchors
    if not anchors then return false end
    local P = EllesmereUI.PP
    local ui = UIParent and UIParent:GetEffectiveScale() or 1
    if not ui or ui <= 0 then ui = 1 end
    local tol = ((P and P.perfect) or 1) / ui + 0.01
    local keys, members, vert = ns._erbGrpMatchKeys, ns._erbGrpChk, ns._erbGrpChkVert
    local count, linked = 0, 0
    for i = 1, 3 do
        if members[i] then
            count = count + 1
            local info = anchors[keys[i]]
            local target = info and info.target
            local inGroup = false
            for j = 1, 3 do
                if j ~= i and members[j] and keys[j] == target then inGroup = true end
            end
            if inGroup then
                local side = info.side
                local onAxis
                if vert then onAxis = (side == "LEFT" or side == "RIGHT")
                else onAxis = (side == "TOP" or side == "BOTTOM") end
                if onAxis and math.abs(info.offsetX or 0) <= tol and math.abs(info.offsetY or 0) <= tol then
                    linked = linked + 1
                end
            end
        end
    end
    return count >= 2 and linked == count - 1
end
-- A bar's own frame (the classic art, or the Blizzard Style panel) steps
-- aside while the group frame wears it (the per-bar pieces stay seated, so a
-- fallback is instant).
function ns.ERB_GroupSuppress(bar, grouped)
    if not bar then return end
    grouped = grouped and true or nil
    if bar._classicGrouped == grouped then return end
    bar._classicGrouped = grouped
    if bar._classicArt then bar._classicArt:SetShown(not grouped) end
    -- Blizzard Style: the atlas panel, or a vertical bar's nine pieces.
    local pcs = bar._blizzBar9On and bar._blizzBar9
    if pcs then
        for i = 1, 9 do pcs[i]:SetShown(not grouped) end
    elseif bar._blizzBarBg then
        bar._blizzBarBg:SetShown(not grouped)
    end
end
-- Back to per-bar frames. `keepSig` (the evaluator's own fallbacks) keeps
-- the membership stamp, so the same members with no geometry change are not
-- re-judged on every visibility pass; nil (the setting turned off) clears it.
function ns.ERB_GroupRelease(keepSig)
    local host = ns._erbGroupHost
    if host then host:Hide(); host._gFirst = nil end
    ns.ERB_GroupSuppress(healthBar, false)
    ns.ERB_GroupSuppress(primaryBar, false)
    ns.ERB_GroupSuppress(secondaryFrame, false)
    ns._erbGroupActive = false
    ns._erbGrpLastSig = keepSig
end
-- Decide and seat the group. Membership (ns._erbGrpH/P/S) comes from the
-- visibility pass; a pass with the same members and no geometry change is
-- a no-op. A secret rect keeps the last decision standing and an unresolved
-- one falls back, both retried on the next pass.
function ns.ERB_GroupEval()
    if not ns._erbGroupOn then
        if ns._erbGroupActive then ns.ERB_GroupRelease() end
        return
    end
    -- Members must share one opacity (bar opacity, out-of-combat fade): the
    -- frame rides the first member's alpha. Part of the stamp, so a fade edge
    -- re-judges the group.
    local aEq, a0 = true, nil
    if ns._erbGrpH then a0 = ns.ResolveBarAlpha(_G._ERB_ResolveHealthCfg()) end
    if ns._erbGrpP then
        local a = ns.ResolveBarAlpha(_G._ERB_ResolvePowerCfg())
        if a0 and math.abs(a - a0) > 0.01 then aEq = false end
        a0 = a0 or a
    end
    if ns._erbGrpS then
        local a = ns.ResolveBarAlpha(_G._ERB_ResolveSecondaryCfg())
        if a0 and math.abs(a - a0) > 0.01 then aEq = false end
    end
    local sig = (ns._erbGrpH and 1 or 0) + (ns._erbGrpP and 2 or 0) + (ns._erbGrpS and 4 or 0)
        + (aEq and 8 or 0)
    if sig == ns._erbGrpLastSig and not ns._erbGrpGeomDirty then return end
    ns._erbGrpLastSig = sig
    ns._erbGrpGeomDirty = nil
    local p = ERB.db and ERB.db.profile
    if not (p and mainFrame) then ns.ERB_GroupRelease(sig); return end
    local g = p.general or DEFAULTS.profile.general
    local m, lo, hi, n = ns._erbGrpMembers, ns._erbGrpLo, ns._erbGrpHi, 0
    local vertical
    for i = 1, 3 do
        local f, v
        if i == 1 and ns._erbGrpH then
            f = healthBar; v = IsVerticalOrientation(p.health.orientation or g.orientation)
        elseif i == 2 and ns._erbGrpP then
            f = primaryBar; v = IsVerticalOrientation(p.primary.orientation or g.orientation)
        elseif i == 3 and ns._erbGrpS then
            f = secondaryFrame; v = (p.secondary.pipOrientation or "HORIZONTAL") ~= "HORIZONTAL"
        end
        if f then
            v = v and true or false
            if vertical == nil then vertical = v elseif vertical ~= v then ns.ERB_GroupRelease(sig); return end
            n = n + 1
            m[n] = f
        end
    end
    for i = n + 1, 3 do m[i] = nil end
    if n < 2 or not aEq then ns.ERB_GroupRelease(sig); return end
    -- Long-axis edges must line up (this also holds the lengths equal live);
    -- the cross-axis spans order the members and bound the gaps.
    local sec = issecretvalue
    local es = mainFrame:GetEffectiveScale()
    local tol = ((PP and PP.perfect) or 1) / es + 0.01
    local a1, a2, thick = nil, nil, 0
    for i = 1, n do
        local f = m[i]
        local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
        if not (l and r and t and b) then
            ns.ERB_GroupRelease(sig)
            ns._erbGrpGeomDirty = true
            return
        end
        if sec and (sec(l) or sec(r) or sec(t) or sec(b)) then
            ns._erbGrpGeomDirty = true
            return
        end
        local s1, s2, c1, c2 = l, r, b, t
        if vertical then s1, s2, c1, c2 = b, t, l, r end
        if i == 1 then a1, a2 = s1, s2
        elseif math.abs(s1 - a1) > tol or math.abs(s2 - a2) > tol then ns.ERB_GroupRelease(sig); return end
        lo[i], hi[i] = c1, c2
        if c2 - c1 > thick then thick = c2 - c1 end
    end
    -- Order along the cross axis (insertion sort on the member slots):
    -- horizontal bars stack top to bottom, vertical ones sit left to right.
    for i = 2, n do
        local f, l1, h1 = m[i], lo[i], hi[i]
        local j = i - 1
        while j >= 1 and ((vertical and lo[j] > l1) or (not vertical and hi[j] < h1)) do
            m[j + 1], lo[j + 1], hi[j + 1] = m[j], lo[j], hi[j]
            j = j - 1
        end
        m[j + 1], lo[j + 1], hi[j + 1] = f, l1, h1
    end
    local CF = EllesmereUI.ClassicFrame
    local k = ns.ERB_BarFrameK(nil)
    local classic = ns.ERB_BarsClassic()
    -- The frame's reach across the stacking axis: the vanilla frame's
    -- overhangs, or the Blizzard panel's 3 + 7.
    local reach = classic and (CF and ((CF.OVER_T + CF.OVER_B) * k) or 0) or 10
    for i = 2, n do
        local gap = vertical and (lo[i] - hi[i - 1]) or (lo[i - 1] - hi[i])
        if gap > thick + reach + tol then ns.ERB_GroupRelease(sig); return end
    end
    local first, last = m[1], m[n]
    local host = ns._erbGroupHost
    if not host then
        host = CreateFrame("Frame", nil, mainFrame)
        host:EnableMouse(false)
        -- The union's extent moved without a pass of ours (an anchor cascade
        -- sliding one member): look again next frame.
        host:SetScript("OnSizeChanged", ns.ERB_GroupDirty)
        ns._erbGroupHost = host
    end
    if host._gFirst ~= first or host._gLast ~= last then
        host._gFirst, host._gLast = first, last
        -- A child of the first bar: its alpha, fade and hide carry the frame.
        if host:GetParent() ~= first then host:SetParent(first) end
        host:ClearAllPoints()
        host:SetPoint("TOPLEFT", first, "TOPLEFT", 0, 0)
        host:SetPoint("BOTTOMRIGHT", last, "BOTTOMRIGHT", 0, 0)
    end
    local lvl, minLvl = 0, nil
    for i = 1, n do
        local fl = m[i]:GetFrameLevel()
        if fl > lvl then lvl = fl end
        if not minLvl or fl < minLvl then minLvl = fl end
    end
    host._blizzVertical = vertical or nil
    if classic then
        -- The vanilla frame rides above every member (its art at +9).
        if host:GetFrameLevel() ~= lvl then host:SetFrameLevel(lvl) end
        local uw = vertical and (hi[n] - lo[1]) or (a2 - a1)
        local uh = vertical and (a2 - a1) or (hi[1] - lo[n])
        ns.ERB_ApplyClassicBarChrome(host, nil, uw, uh, vertical, k)
    else
        -- The Blizzard panel sits under every member's own textures (as a
        -- bar's panel does under its fill); the separators ride above.
        local below = math.max(0, minLvl - 1)
        if host:GetFrameLevel() ~= below then host:SetFrameLevel(below) end
        ns.ERB_ApplyBlizzGroupPanel(host, vertical, lvl + 9)
    end
    ns.ERB_GroupSeatSeparators(host, g, n, vertical)
    host:Show()
    ns.ERB_GroupSuppress(healthBar, ns._erbGrpH)
    ns.ERB_GroupSuppress(primaryBar, ns._erbGrpP)
    ns.ERB_GroupSuppress(secondaryFrame, ns._erbGrpS)
    ns._erbGroupActive = true
end
-- Blizzard Style "Border Around All": the personal resource display's panel
-- round the whole group as a nine-slice, so its rims and drop shadow keep
-- their single-bar size however long and tall the group is (a bar's own
-- panel gets this from SetAtlas; a texcoord cut of the sheet does not, and a
-- panel stretched end to end slides its side rims in under the fills). The
-- atlas is 132x19: 2 columns left of the fill (soft edge, rim), 6 right of it
-- (rim, drop shadow), 3 rows above (soft edge, rim, inner shadow row) and 7
-- below (rim, drop shadow); the fill area stretches across the bars and the
-- gaps between them. A vertical group takes the art a quarter turn
-- counter-clockwise, as a vertical bar's panel does (3 left, 6 above, 7
-- right, 2 below). Under every member, as a bar's panel sits under its fill;
-- `sepLevel` seats the separators' art frame above every member.
ns._erbGrpU = { 0, 2 / 132, 126 / 132, 1 }        -- art columns: left cap, fill, right cap
ns._erbGrpV = { 0, 3 / 19, 12 / 19, 1 }           -- art rows: top cap, fill, bottom cap
-- Screen edges per orientation: { anchor side, offset } for the 4 x edges
-- (left to right) and the 4 y edges (top to bottom).
ns._erbGrpEdges = {
    [false] = { x = { { "LEFT", -2 }, { "LEFT", 0 }, { "RIGHT", 0 }, { "RIGHT", 6 } },
                y = { { "TOP", 3 }, { "TOP", 0 }, { "BOTTOM", 0 }, { "BOTTOM", -7 } } },
    [true]  = { x = { { "LEFT", -3 }, { "LEFT", 0 }, { "RIGHT", 0 }, { "RIGHT", 7 } },
                y = { { "TOP", 6 }, { "TOP", 0 }, { "BOTTOM", 0 }, { "BOTTOM", -2 } } },
}
-- The nine pieces `pcs` seated round `anchor` (the group host, or a
-- vertical bar's fill rect), art from `info` (the panel atlas).
function ns.ERB_SeatBlizzPanel9(pcs, anchor, vertical, info)
    local file = info.file or info.filename
    local l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
    local E = ns._erbGrpEdges[vertical and true or false]
    local GRP_U, GRP_V = ns._erbGrpU, ns._erbGrpV
    for i = 1, 3 do          -- screen column (left to right)
        for j = 1, 3 do      -- screen row (top to bottom)
            local tex = pcs[(j - 1) * 3 + i]
            tex:SetTexture(file)
            if vertical then
                -- Screen x runs down the art's rows, screen y up its
                -- columns (right to left): column i = art row band i,
                -- row j = art column band 4 - j.
                local ua = l + (r - l) * GRP_U[4 - j]
                local ub = l + (r - l) * GRP_U[5 - j]
                local va = t + (b - t) * GRP_V[i]
                local vb = t + (b - t) * GRP_V[i + 1]
                tex:SetTexCoord(ub, va, ua, va, ub, vb, ua, vb)
            else
                tex:SetTexCoord(l + (r - l) * GRP_U[i], l + (r - l) * GRP_U[i + 1],
                    t + (b - t) * GRP_V[j], t + (b - t) * GRP_V[j + 1])
            end
            local x1, x2, y1, y2 = E.x[i], E.x[i + 1], E.y[j], E.y[j + 1]
            tex:ClearAllPoints()
            tex:SetPoint("TOPLEFT", anchor, y1[1] .. x1[1], x1[2], y1[2])
            tex:SetPoint("BOTTOMRIGHT", anchor, y2[1] .. x2[1], x2[2], y2[2])
        end
    end
end
function ns.ERB_ApplyBlizzGroupPanel(host, vertical, sepLevel)
    local info = C_Texture.GetAtlasInfo(ns.ERB_BLIZZ_BAR_BG)
    local pcs = host._blizzGrpPanel9
    if not pcs then
        pcs = {}
        for i = 1, 9 do
            local t = host:CreateTexture(nil, "BACKGROUND", nil, -2)
            if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
            pcs[i] = t
        end
        host._blizzGrpPanel9 = pcs
    end
    local sa = host._sepArt
    if not sa then
        sa = CreateFrame("Frame", nil, host)
        sa:EnableMouse(false)
        sa:SetAllPoints(host)
        host._sepArt = sa
    end
    if sa:GetFrameLevel() ~= sepLevel then sa:SetFrameLevel(sepLevel) end
    if not info then
        for i = 1, 9 do pcs[i]:Hide() end
        return
    end
    vertical = vertical and true or false
    if host._blizzGrpRot ~= vertical then
        host._blizzGrpRot = vertical
        ns.ERB_SeatBlizzPanel9(pcs, host, vertical, info)
    end
    for i = 1, 9 do pcs[i]:Show() end
end
-- Separator lines between the grouped bars (the Border Around All cog):
-- general.classicBorderAllSepSize physical pixels (nil = 1, 0 = none) in
-- classicBorderAllSepR/G/B (nil = black), centred in each gap and snapped to
-- whole physical pixels, on the group frame's art frame (above the fills,
-- like the frame). Runs on the evaluator's sorted members; textures made
-- once, re-seated per evaluation, spares hidden.
function ns.ERB_GroupSeatSeparators(host, g, n, vertical)
    local seps = host._seps
    if not seps then seps = {}; host._seps = seps end
    local size = g.classicBorderAllSepSize
    if size == nil then size = 1 end
    local af = host._classicArt or host._sepArt
    local used = 0
    if af and size > 0 then
        local m, lo, hi = ns._erbGrpMembers, ns._erbGrpLo, ns._erbGrpHi
        local px = ((PP and PP.perfect) or 1) / host:GetEffectiveScale()
        local t = size * px
        local r, gr, b = g.classicBorderAllSepR or 0, g.classicBorderAllSepG or 0, g.classicBorderAllSepB or 0
        for i = 1, n - 1 do
            used = i
            local s = seps[i]
            if not s then
                s = af:CreateTexture(nil, "OVERLAY", nil, 3)
                seps[i] = s
            end
            s:SetColorTexture(r, gr, b, 1)
            -- Members are sorted top to bottom (horizontal bars) or left to
            -- right (vertical bars); the line hangs off the earlier one.
            local a = m[i]
            local gap = vertical and (lo[i + 1] - hi[i]) or (lo[i] - hi[i + 1])
            local off = math.floor(((gap - t) / 2) / px + 0.5) * px
            s:ClearAllPoints()
            if vertical then
                s:SetPoint("TOPLEFT", a, "TOPRIGHT", off, 0)
                s:SetPoint("BOTTOMLEFT", a, "BOTTOMRIGHT", off, 0)
                s:SetWidth(t)
            else
                s:SetPoint("TOPLEFT", a, "BOTTOMLEFT", 0, -off)
                s:SetPoint("TOPRIGHT", a, "BOTTOMRIGHT", 0, -off)
                s:SetHeight(t)
            end
            s:Show()
        end
    end
    for i = used + 1, #seps do seps[i]:Hide() end
end
-- Coalesced re-evaluation (unlock moves, saved positions, the host's own
-- resize): one pass next frame. Idle while the setting is off.
function ns.ERB_GroupFlush()
    ns._erbGrpFlushPending = nil
    ns._erbGrpGeomDirty = true
    ns.ERB_GroupEval()
end
function ns.ERB_GroupDirty()
    if not (ns._erbGroupOn or ns._erbGroupActive) then return end
    ns._erbGrpGeomDirty = true
    if ns._erbGrpFlushPending then return end
    ns._erbGrpFlushPending = true
    C_Timer.After(0, ns.ERB_GroupFlush)
end

-- The panel art on `bg`: the atlas as is, or (vertical) the sheet file with
-- the atlas rect's corners rotated a quarter turn counter-clockwise (an
-- atlas cannot take texcoords). Memo on the orientation. (A live vertical
-- bar takes the nine-slice in ERB_ApplyBlizzBarChrome instead.)
function ns.ERB_SeatBlizzBarBg(bg, vertical)
    vertical = vertical and true or false
    if bg._blizzRot == vertical then return end
    local info = C_Texture.GetAtlasInfo(ns.ERB_BLIZZ_BAR_BG)
    if not info then return end
    bg._blizzRot = vertical
    if vertical then
        bg:SetTexture(info.file or info.filename)
        local l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
        bg:SetTexCoord(r, t, l, t, r, b, l, b)
    else
        bg:SetAtlas(ns.ERB_BLIZZ_BAR_BG)
    end
end
-- Inner bevel under the style: the stock fill art bakes a dark edge into
-- its long sides (and a darker left end), which is what makes the stock
-- bar read as recessed inside the frame; the user's own texture has none,
-- so without this the bar reads as pasted over the frame. Four gradient
-- strips on the fill's StatusBar at OVERLAY -3 (above fill and backing,
-- under hash lines and text), the long edges carrying the bevel and the
-- short ends the end darkening whichever way the bar runs, masked to the
-- bar shape. Created once, re-sized on every chrome pass.
ns._erbShadeClear  = CreateColor(0, 0, 0, 0)
ns._erbShadeTop    = CreateColor(0, 0, 0, 0.55)
ns._erbShadeBottom = CreateColor(0, 0, 0, 0.30)
ns._erbShadeEnd    = CreateColor(0, 0, 0, 0.35)
function ns.ERB_BlizzBarShadow(sb, mask, fw, fh)
    if not sb then return end
    local sh = sb._blizzShadow
    if not sh then
        sh = {}
        sb._blizzShadow = sh
        for i = 1, 4 do
            local tex = sb:CreateTexture(nil, "OVERLAY", nil, -3)
            tex:SetTexture("Interface\\Buttons\\WHITE8X8")
            if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false); tex:SetTexelSnappingBias(0) end
            sh[i] = tex
        end
    end
    -- An explicit flag (the chrome pass's target orientation) wins over the
    -- bar's own, which lags on the pass that flips it.
    local vertical = sb._blizzVertical
    if vertical == nil then vertical = sb.GetOrientation and sb:GetOrientation() == "VERTICAL" end
    local w, h = fw or sb:GetWidth(), fh or sb:GetHeight()
    -- A bar carrying secret values reports secret sizes: leave the strips
    -- as they are (a later plain-sized pass lays them) rather than compare.
    if issecretvalue and (issecretvalue(w) or issecretvalue(h)) then return end
    if not w or w <= 0 then w = 100 end
    if not h or h <= 0 then h = 10 end
    local long, short = h, w
    if vertical then long, short = w, h end
    local a = math.max(2, math.floor(long * 0.2))
    local b = math.max(1, math.floor(long * 0.1))
    local e = math.max(2, math.floor(short * 0.15))
    for i = 1, 4 do sh[i]:ClearAllPoints() end
    -- VERTICAL gradients run bottom -> top, HORIZONTAL left -> right.
    if vertical then
        sh[1]:SetGradient("HORIZONTAL", ns._erbShadeTop, ns._erbShadeClear)
        sh[1]:SetPoint("TOPLEFT", sb, "TOPLEFT", 0, 0); sh[1]:SetPoint("BOTTOMLEFT", sb, "BOTTOMLEFT", 0, 0); sh[1]:SetWidth(a)
        sh[2]:SetGradient("HORIZONTAL", ns._erbShadeClear, ns._erbShadeBottom)
        sh[2]:SetPoint("TOPRIGHT", sb, "TOPRIGHT", 0, 0); sh[2]:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 0, 0); sh[2]:SetWidth(b)
        sh[3]:SetGradient("VERTICAL", ns._erbShadeClear, ns._erbShadeEnd)
        sh[3]:SetPoint("TOPLEFT", sb, "TOPLEFT", 0, 0); sh[3]:SetPoint("TOPRIGHT", sb, "TOPRIGHT", 0, 0); sh[3]:SetHeight(e)
        sh[4]:SetGradient("VERTICAL", ns._erbShadeEnd, ns._erbShadeClear)
        sh[4]:SetPoint("BOTTOMLEFT", sb, "BOTTOMLEFT", 0, 0); sh[4]:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 0, 0); sh[4]:SetHeight(e)
    else
        sh[1]:SetGradient("VERTICAL", ns._erbShadeClear, ns._erbShadeTop)
        sh[1]:SetPoint("TOPLEFT", sb, "TOPLEFT", 0, 0); sh[1]:SetPoint("TOPRIGHT", sb, "TOPRIGHT", 0, 0); sh[1]:SetHeight(a)
        sh[2]:SetGradient("VERTICAL", ns._erbShadeBottom, ns._erbShadeClear)
        sh[2]:SetPoint("BOTTOMLEFT", sb, "BOTTOMLEFT", 0, 0); sh[2]:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 0, 0); sh[2]:SetHeight(b)
        sh[3]:SetGradient("HORIZONTAL", ns._erbShadeEnd, ns._erbShadeClear)
        sh[3]:SetPoint("TOPLEFT", sb, "TOPLEFT", 0, 0); sh[3]:SetPoint("BOTTOMLEFT", sb, "BOTTOMLEFT", 0, 0); sh[3]:SetWidth(e)
        sh[4]:SetGradient("HORIZONTAL", ns._erbShadeClear, ns._erbShadeEnd)
        sh[4]:SetPoint("TOPRIGHT", sb, "TOPRIGHT", 0, 0); sh[4]:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 0, 0); sh[4]:SetWidth(e)
    end
    for i = 1, 4 do sh[i]:Show() end
    if mask and sh._mask ~= mask then
        for i = 1, 4 do
            if sh._mask then pcall(sh[i].RemoveMaskTexture, sh[i], sh._mask) end
            sh[i]:AddMaskTexture(mask)
        end
        sh._mask = mask
    end
end
-- Seat the row's bar-shape mask on one texture, once per texture object
-- (AddMaskTexture is additive).
function ns.ERB_MaskTex(tex, mask)
    if tex and mask and tex._blizzMasked ~= mask then
        tex:AddMaskTexture(mask)
        tex._blizzMasked = mask
    end
end
-- Pips and runes under the style: every texture a pip draws (backing, fill,
-- pixel-border strips, the inner bars the secret renderer and recharge
-- create) takes the row's bar-shape mask so the end pips round off with
-- the frame; middle pips sit inside the footprint's straight edges and are
-- unaffected. Stamps the mask on the pip so the lazy creation and
-- re-texture sites can re-seat (a path swap mints a new fill object); the
-- per-object memo makes every other call free.
function ns.ERB_MaskPip(pip, mask)
    if not (pip and mask) then return end
    pip._blizzMask = mask
    local M = ns.ERB_MaskTex
    M(pip._bg, mask)
    M(pip._fill, mask)
    local bf = pip._border and pip._border._frame
    local c = bf and PP.GetBorders(bf)
    if c then M(c._top, mask); M(c._bottom, mask); M(c._left, mask); M(c._right, mask) end
    local sb = pip._secretBar
    if sb then M(sb:GetStatusBarTexture(), mask) end
    sb = pip._bandResetBar
    if sb then M(sb:GetStatusBarTexture(), mask) end
    sb = pip._secretThreshBar
    if sb then M(sb:GetStatusBarTexture(), mask) end
    sb = pip._rechargeBar
    if sb then M(sb:GetStatusBarTexture(), mask) end
    local bands = pip._bandBars
    if bands then
        for k = 1, #bands do M(bands[k]:GetStatusBarTexture(), mask) end
    end
end
-- Seat the host's bar-shape mask on `target`'s fill and backing (`target`
-- defaults to the host; the class resource frame passes its bar-type bar).
-- Memoized per texture object: a status bar texture path swap mints a new
-- fill object, and AddMaskTexture is additive.
function ns.ERB_SeatBlizzMask(host, target)
    local mask = host and host._blizzBarMask
    if not mask then return end
    target = target or host
    local fill = target.GetStatusBarTexture and target:GetStatusBarTexture()
    if fill and target._blizzMaskedFill ~= fill then
        fill:AddMaskTexture(mask)
        target._blizzMaskedFill = fill
    end
    local bgTex = target._bg
    if bgTex and target._blizzMaskedBg ~= bgTex then
        bgTex:AddMaskTexture(mask)
        target._blizzMaskedBg = bgTex
    end
end
-- First existing atlas for a piece, memoized (false = none available).
function ns.ERB_BlizzAtlas(key)
    local memo = ns._erbBlizzAtlasMemo
    local hit = memo[key]
    if hit ~= nil then return hit or nil end
    local list = ns.ERB_CAST_BLIZZ[key]
    local found = false
    if list and C_Texture and C_Texture.GetAtlasInfo then
        for i = 1, #list do
            if C_Texture.GetAtlasInfo(list[i]) then found = list[i]; break end
        end
    end
    memo[key] = found
    return found or nil
end
-- Cast icon side (0 while the icon is off): the bar height, or under
-- Blizzard Style the bar plus the stock text box's 13px drop while the spell
-- text shows, so the icon spans bar and box (Classic WoW UI has no text box:
-- the icon stays a square of the bar height). The frame width, the fill
-- inset and the unlock sizing all take it from here.
function ns.ERB_CastIconW(cb)
    if cb.showIcon == false or ns.ERB_CastIconFree(cb) then return 0 end
    local h = cb.height
    if ns.ERB_CastStyle() == "blizzard" and cb.showSpellText and ns.ERB_BlizzAtlas("textbox") then
        return h + 13
    end
    return h
end
-- Icon Size / Offset: a custom size or any offset takes the icon out of the
-- frame (ERB_CastIconW is 0) and it floats beside the bar with its own border.
-- The stock styles keep it inside their frame art.
function ns.ERB_CastIconFree(cb)
    if cb.showIcon == false or ns.ERB_CastStyle() ~= "eui" then return false end
    return (cb.iconSize or 0) > 0 or (cb.iconOffsetX or 0) ~= 0 or (cb.iconOffsetY or 0) ~= 0
end
-- Lays out a floating icon (live bar and options preview), or hides its border.
function ns.ERB_LayoutFreeCastIcon(iconFrame, host, cb, free)
    local P = EllesmereUI.PP
    if not free then
        if P.GetBorders(iconFrame) then P.HideBorder(iconFrame) end
        return
    end
    local size = (cb.iconSize or 0) > 0 and cb.iconSize or cb.height
    iconFrame:SetSize(size, size)
    iconFrame:ClearAllPoints()
    if cb.iconOnRight then
        iconFrame:SetPoint("LEFT", host, "RIGHT", cb.iconOffsetX or 0, cb.iconOffsetY or 0)
    else
        iconFrame:SetPoint("RIGHT", host, "LEFT", cb.iconOffsetX or 0, cb.iconOffsetY or 0)
    end
    if (cb.borderSize or 0) > 0 then
        if not P.GetBorders(iconFrame) then P.CreateBorder(iconFrame, 0, 0, 0, 1, 1) end
        P.SetBorderColor(iconFrame, cb.borderR or 0, cb.borderG or 0, cb.borderB or 0, cb.borderA or 1)
        P.ShowBorder(iconFrame)
    elseif P.GetBorders(iconFrame) then
        P.HideBorder(iconFrame)
    end
end
-- Fill art for the current cast kind ("cast" | "channel" | "interrupted").
-- One field test when the style is off; a memo skips repeat atlas swaps.
function ns.ERB_SetBlizzCastFill(kind)
    local f = castBarFrame
    if not f or not f._blizzFill then return end
    if f._blizzFillKind == kind then return end
    local atlas = ns.ERB_BlizzAtlas(kind)
    if not atlas then return end
    f._blizzFillKind = kind
    f._bar:GetStatusBarTexture():SetAtlas(atlas)
end
-- Frame art around the bar plus, under Blizzard Style, the text box under it
-- (the spell name moves into the box, honouring the Spell Text side and
-- offsets); Classic WoW UI draws the vanilla frame alone. Rebuilt on every
-- BuildCastBar pass; regions are created once.
function ns.ERB_ApplyBlizzCastChrome(cb, barW)
    local f = castBarFrame
    if not f then return end
    local clip = f._barClip
    if not f._blizzFrame then
        -- Own host above the bar and icon (the EUI border child is hidden by
        -- its size-0 pass under this style, so the art cannot ride on it).
        local af = CreateFrame("Frame", nil, f)
        af:SetAllPoints(f)
        af:EnableMouse(false)
        f._blizzArtFrame = af
        local fr = af:CreateTexture(nil, "OVERLAY", nil, 2)
        if fr.SetSnapToPixelGrid then fr:SetSnapToPixelGrid(false); fr:SetTexelSnappingBias(0) end
        f._blizzFrame = fr
        local tb = f:CreateTexture(nil, "BACKGROUND", nil, -1)
        if tb.SetSnapToPixelGrid then tb:SetSnapToPixelGrid(false); tb:SetTexelSnappingBias(0) end
        f._blizzTextBox = tb
    end
    -- Same level the EUI border host uses (re-asserted: the bar's level follows its strata setting).
    f._blizzArtFrame:SetFrameLevel(f:GetFrameLevel() + 5)
    local fr, tb = f._blizzFrame, f._blizzTextBox
    if ns.ERB_CastClassic() then
        -- Classic WoW UI: the vanilla frame round the whole bar, icon
        -- included (the icon is part of the bar, so it sits inside the
        -- frame's window beside the fill and the frame wraps the bar's rect,
        -- not the fill's clip); no text box, the spell name stays on the bar
        -- where the text pass put it.
        ns.ERB_SeatClassicChrome(fr, f, cb.height, false, ns.ERB_ClassicFrameK(cb))
        tb:Hide()
        return
    end
    local frameAtlas = ns.ERB_BlizzAtlas("frame")
    if frameAtlas then
        ns.ERB_StockAtlas(fr, frameAtlas)
        fr:ClearAllPoints()
        fr:SetPoint("TOPLEFT", clip, "TOPLEFT", -2, 2)
        fr:SetPoint("BOTTOMRIGHT", clip, "BOTTOMRIGHT", 2, -2)
        fr:Show()
    else
        fr:Hide()
    end
    local boxAtlas = cb.showSpellText and ns.ERB_BlizzAtlas("textbox")
    if boxAtlas then
        ns.ERB_StockAtlas(tb, boxAtlas)
        tb:ClearAllPoints()
        tb:SetPoint("TOPLEFT", clip, "BOTTOMLEFT", 0, 3)
        tb:SetPoint("BOTTOMRIGHT", clip, "BOTTOMRIGHT", 0, -13)
        tb:Show()
        local nameText = f._nameText
        local side = cb.spellTextSide or "left"
        local x, y = cb.spellTextX or 0, cb.spellTextY or 0
        nameText:ClearAllPoints()
        if side == "right" then
            nameText:SetJustifyH("RIGHT")
            nameText:SetPoint("RIGHT", tb, "RIGHT", -8 + x, y)
        elseif side == "center" then
            nameText:SetJustifyH("CENTER")
            nameText:SetPoint("CENTER", tb, "CENTER", x, y)
        else
            nameText:SetJustifyH("LEFT")
            nameText:SetPoint("LEFT", tb, "LEFT", 8 + x, y)
        end
        nameText:SetWidth(math.max(10, (barW or cb.width or 220) - 16))
        ns.ReflowFontString(nameText)
    else
        tb:Hide()
    end
end

I.broken = false
