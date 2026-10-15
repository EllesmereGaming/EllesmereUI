if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ActionBars_Chrome.lua
--
--  Bar chrome and end caps for the action bars and the extra bars. Loads
--  right after the main file and reads it through ns only.
-------------------------------------------------------------------------------
local _, ns = ...

local _G = _G
local pairs = pairs
local min, max = math.min, math.max
local hooksecurefunc = hooksecurefunc
local C_Timer_After = C_Timer.After

local EAB, BAR_LOOKUP = ns.EAB, ns.BAR_LOOKUP
local I = ns._internals
local _fadeAlpha, extraBarHolders = I._fadeAlpha, I.extraBarHolders

-------------------------------------------------------------------------------
--  The action bars' chrome. Every action bar can
--  carry end caps, left, right or both (the End Caps checklist), in the
--  current look's art (the EllesmereUI style: the art the player picks), with
--  its own size and offsets. WoW Forever: the metal frame round a bar and the
--  dividers between its buttons (Show Bar Background, on by default on Action
--  Bar 1 only) and the faction end caps (both sides on by default on Action
--  Bar 1 only), from Blizzard's own atlases (they draw the Forever art on
--  that client). Built per bar the first time a piece is on (LayoutBar's
--  tail, out of combat, stamp-gated); off, nothing is built and a built
--  piece hides. All on ns: the main chunk is at the 200-local cap.
-------------------------------------------------------------------------------
ns.AB_FV_ART = {
    frame = "UI-HUD-ActionBar-Frame",
    -- Divider slices { start edge, end edge, middle } and the edges' depth
    -- along the divider: between the columns of a horizontal bar, then
    -- between the rows of a vertical one.
    divH = { "ui-hud-actionbar-frame-divider-ThreeSlice-EdgeTop",
             "ui-hud-actionbar-frame-divider-ThreeSlice-EdgeBottom",
             "!ui-hud-actionbar-frame-divider-ThreeSlice-Center", 14, 15 },
    divV = { "ui-hud-actionbar-frame-divider-ThreeSlice-EdgeLeft",
             "ui-hud-actionbar-frame-divider-ThreeSlice-EdgeRight",
             "_ui-hud-actionbar-frame-divider-ThreeSlice-Center", 12, 12 },
}

-- End caps per look: the art by faction (`art`, none while neutral) or the
-- same for every faction (`any`), the size at the icon size `unit` the art is
-- drawn for (caps only ever scale down, as Blizzard's do), the frame levels
-- over the bar (`lvl`), and the anchors { left point, bar point, x, y, right
-- point, bar point, x, y } for one row (near) and several (far, else near).
-- mid: anchored on the bar's side middles, else its bottom corners.
ns.AB_CAPS = {
    -- WoW Forever: inner edge 30 inside the bar's ends, 5 above its middle;
    -- over the buttons.
    forever = {
        unit = 45, w = 154, h = 95, lvl = 4, mid = true,
        art = {
            Alliance = { "ui-hud-actionbar-gryphon-left", "ui-hud-actionbar-gryphon-right" },
            Horde    = { "ui-hud-actionbar-wyvern-left",  "ui-hud-actionbar-wyvern-right" },
        },
        near = { "RIGHT", "LEFT", 30, 5, "LEFT", "RIGHT", -30, 5 },
    },
    -- Blizzard Style: retail's MainActionBar end caps, over the buttons' proc
    -- glows and assisted highlight as retail's are. stock: drawn through
    -- EllesmereUI.StockAtlas (retail art where the Forever client swaps it).
    blizzard = {
        unit = 45, w = 104.5, h = 98, lvl = 17, stock = true,
        near = { "BOTTOMRIGHT", "BOTTOMLEFT", 9, -22, "BOTTOMLEFT", "BOTTOMRIGHT", -8, -22 },
    },
    -- Classic WoW UI: vanilla's compact end caps (a file, the right one
    -- mirrored), out at the bar's corners on a bar of several rows.
    classic = {
        unit = 36, w = 128, h = 128, lvl = 17, file = true,
        any = { "Interface\\MainMenuBar\\UI-MainMenuBar-EndCap-Dwarf",
                "Interface\\MainMenuBar\\UI-MainMenuBar-EndCap-Dwarf" },
        near = { "BOTTOMRIGHT", "BOTTOMLEFT", 28, -3, "BOTTOMLEFT", "BOTTOMRIGHT", -29, -3 },
        far  = { "BOTTOMRIGHT", "BOTTOMLEFT", 0, -3, "BOTTOMLEFT", "BOTTOMRIGHT", -1, -3 },
    },
}
ns.AB_CAPS.blizzard.art = ns.AB_CAPS.forever.art

-- Atlas presence, probed once per name (a piece the client lacks is skipped).
ns._abAtlas = {}
function ns.AB_AtlasOK(name)
    local v = ns._abAtlas[name]
    if v == nil then
        v = C_Texture.GetAtlasInfo(name) ~= nil
        ns._abAtlas[name] = v
    end
    return v
end

-- True when `art` (an EllesmereUI style End Caps art) draws on this client:
-- "blizzard", "classic", or "forever" -- the Forever client's own art, which
-- retail does not ship.
function ns.AB_CapsArtOK(art)
    return art == "blizzard" or art == "classic" or (art == "forever" and EllesmereUI.IS_FOREVER == true)
end

-- One of a bar's end cap settings (endCapArt, endCapScale, endCapOffsetX,
-- endCapOffsetY), nil = unset: the bar's own key, and on Action Bar 1 an
-- unset key reads the profile-wide key (euiEndCaps for the art, the same
-- name for the rest), which nothing writes. A bar that carries one of Action
-- Bar 1's caps (the first-install span below) reads bar 1's where unset, so
-- the pair matches.
function ns.AB_CapsVal(key, k)
    local p = EAB.db and EAB.db.profile
    if not p then return nil end
    local s = p.bars and p.bars[key]
    local v = s and s[k]
    if v == nil then
        if key == "MainBar" then
            v = p[(k == "endCapArt") and "euiEndCaps" or k]
        elseif p.endCapSpanLeft == key or p.endCapSpanRight == key then
            v = ns.AB_CapsVal("MainBar", k)
        end
    end
    return v
end

-- Whether Action Bar 1's unset sides show caps under the current look: WoW
-- Forever while foreverHideEndCaps is off; Blizzard Style and Classic WoW UI
-- while showEndCaps; the EllesmereUI style while euiEndCaps names art this
-- client draws.
function ns.AB_CapsMainDefault(p)
    if ns.AB_Forever() then return p.foreverHideEndCaps ~= true end
    if ns.AB_Style() == "eui" then return ns.AB_CapsArtOK(p.euiEndCaps) end
    return p.showEndCaps == true
end

-- Which ends of a bar show caps (the End Caps checklist): the bar's own
-- endCapLeft / endCapRight. An unset side reads the bar's default: Action Bar
-- 1 follows the look (ns.AB_CapsMainDefault), both sides alike; every other
-- bar shows none. The first-install span (endCapSpanLeft / endCapSpanRight,
-- written by the Action Bars capture: the outermost bar in a row directly
-- beside bar 1 on that side) moves bar 1's default for that side onto the
-- named bar's same side. Checklist choices always win.
function ns.AB_CapsSides(key)
    local p = EAB.db and EAB.db.profile
    local s = p and p.bars and p.bars[key]
    if not s then return false, false end
    local l, r = s.endCapLeft, s.endCapRight
    if l == nil or r == nil then
        local sl, sr = p.endCapSpanLeft, p.endCapSpanRight
        local dl, dr = false, false
        if key == "MainBar" then
            local d = ns.AB_CapsMainDefault(p)
            dl, dr = d and sl == nil, d and sr == nil
        elseif sl == key or sr == key then
            local d = ns.AB_CapsMainDefault(p)
            dl, dr = d and sl == key, d and sr == key
        end
        if l == nil then l = dl end
        if r == nil then r = dr end
    end
    return l and true or false, r and true or false
end

-- The art the EllesmereUI style draws on a bar's caps: its End Caps cog
-- pick; none, or art this client lacks, reads Modern.
function ns.AB_CapsArt(key)
    local art = ns.AB_CapsVal(key, "endCapArt")
    if ns.AB_CapsArtOK(art) then return art end
    return "blizzard"
end

-- The look whose end caps a bar draws, then its left and right sides, or nil
-- while the bar shows neither side: WoW Forever's under that variant,
-- Blizzard Style's and Classic WoW UI's own, and under the EllesmereUI style
-- the art the player picks.
function ns.AB_CapsLook(key)
    local l, r = ns.AB_CapsSides(key)
    if not (l or r) then return nil end
    local look
    if ns.AB_Forever() then
        look = "forever"
    else
        look = ns.AB_Style()
        if look == "eui" then look = ns.AB_CapsArt(key) end
    end
    return look, l, r
end

-- A bar's end cap tweaks (the End Caps cog): the size as a fraction of the
-- look's own, the X/Y offsets (X mirrored: a positive value moves both caps
-- away from the bar; Y defaults to 5, the caps a little higher than the
-- look's own spot), and last the size in percent as stored.
function ns.AB_CapsTweak(key)
    local sc = ns.AB_CapsVal(key, "endCapScale") or 100
    return sc / 100, ns.AB_CapsVal(key, "endCapOffsetX") or 0, ns.AB_CapsVal(key, "endCapOffsetY") or 5, sc
end

-- Every chrome input of a bar in one string, for LayoutBar's stamp (the
-- tweaks only while a cap shows; "-" for a bar with no chrome).
function ns.AB_ChromeStamp(key)
    local look, l, r = ns.AB_CapsLook(key)
    local fv = ns.AB_ForeverBg(key)
    if not look then return fv and "fv" or "-" end
    local _, dx, dy, sc = ns.AB_CapsTweak(key)
    return look .. (l and "L" or "") .. (r and "R" or "") .. (fv and ",fv," or ",")
        .. sc .. "," .. dx .. "," .. dy
end

-- How far a bar's chrome reaches past a button grid gridH tall (top,
-- bottom), for a preview that must make room: WoW Forever's frame (6/5 at
-- button size / 45) and `look`'s caps (nil = none; multi = several rows)
-- with bar `key`'s tweaks. pxK scales the cap offsets (the preview's scale;
-- nil = 1).
function ns.AB_ChromeReach(btnW, gridH, forever, look, multi, pxK, key)
    local top, bottom = 0, 0
    if forever then
        top, bottom = 6 * btnW / 45, 5 * btnW / 45
    end
    local c = look and ns.AB_CAPS[look]
    if c then
        local sc, _, dy = ns.AB_CapsTweak(key)
        dy = dy * (pxK or 1)
        local kc = min(btnW / c.unit, 1) * sc
        local y = ((multi and c.far) or c.near)[4]
        if c.mid then
            top = max(top, (c.h / 2 + y) * kc - gridH / 2 + dy)
            bottom = max(bottom, (c.h / 2 - y) * kc - gridH / 2 - dy)
        else
            top = max(top, (c.h + y) * kc - gridH + dy)
            bottom = max(bottom, -y * kc - dy)
        end
    end
    return top, bottom
end

-- One cap's art: a file (the right cap mirrored) or an atlas (a stock
-- look's through EllesmereUI.StockAtlas).
function ns.AB_SetCapArt(tex, c, name, right)
    if c.file then
        tex:SetTexture(name)
        if right then tex:SetTexCoord(1, 0, 0, 1) else tex:SetTexCoord(0, 1, 0, 1) end
    elseif c.stock then
        -- The art can switch live on the same textures (the EllesmereUI style's
        -- End Caps choice): clear a previous look's mirror or sheet coords first.
        tex:SetTexCoord(0, 1, 0, 1)
        EllesmereUI.StockAtlas(tex, name)
    else
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetAtlas(name)
    end
end

-- Paints the caps' art for the player's faction onto a chrome state (the
-- same art for every faction on a look with `any`), each side shown only
-- while the bar asks for it. True once the art no longer waits on the
-- faction (kept as st.capKnown).
function ns.AB_CapsFaction(st)
    local capL, capR = st.capL, st.capR
    if not capL then return true end
    local c = st.capsOn and ns.AB_CAPS[st.capLook]
    local fac = c and c.art and UnitFactionGroup("player")
    local set = c and (c.any or (fac and c.art[fac])) or nil
    if set and st.capSet ~= set then
        ns.AB_SetCapArt(capL, c, set[1], false)
        ns.AB_SetCapArt(capR, c, set[2], true)
        st.capSet = set
    end
    capL:SetShown(set ~= nil and st.capSideL == true)
    capR:SetShown(set ~= nil and st.capSideR == true)
    st.capKnown = not (c and c.art) or fac ~= nil
    return st.capKnown
end

-- Paints `look`'s end caps (nil = none) onto st (a state table the caller
-- keeps) round a button grid w x h whose TOPLEFT sits at (ox, oy) off
-- owner's TOPLEFT; btnW = the button size, multi = several rows, sideL /
-- sideR = the ends that show a cap. The caps sit the look's lvl over owner
-- (under Action Bar 1's paging arrows), scale with the icon size (down only)
-- times bar `key`'s size, and move by its offsets (times pxK, the preview's
-- scale; nil = 1).
function ns.AB_PaintCaps(st, owner, ox, oy, w, h, btnW, look, multi, pxK, key, sideL, sideR)
    local c = look and ns.AB_CAPS[look]
    st.capsOn = (c and (sideL or sideR) and (c.any or ns.AB_AtlasOK(c.art.Alliance[1]))) and true or false
    st.capSideL, st.capSideR = sideL and true or false, sideR and true or false
    local host = st.capHost
    if not st.capsOn then
        if host then host:Hide() end
        return
    end
    if not host then
        host = CreateFrame("Frame", nil, owner)
        st.capL = host:CreateTexture(nil, "OVERLAY", nil, 5)
        st.capR = host:CreateTexture(nil, "OVERLAY", nil, 5)
        st.capHost = host
    end
    local sc, dx, dy = ns.AB_CapsTweak(key)
    local kc = btnW / c.unit
    if kc > 1 then kc = 1 end
    kc = kc * sc
    -- The offsets in the host's (scaled) units.
    dx, dy = dx * (pxK or 1) / kc, dy * (pxK or 1) / kc
    local g = (multi and c.far) or c.near
    if st.capLook ~= look or st.capGeo ~= g or st.capDX ~= dx or st.capDY ~= dy then
        local capL, capR = st.capL, st.capR
        capL:SetSize(c.w, c.h)
        capR:SetSize(c.w, c.h)
        capL:ClearAllPoints()
        capR:ClearAllPoints()
        capL:SetPoint(g[1], host, g[2], g[3] - dx, g[4] + dy)
        capR:SetPoint(g[5], host, g[6], g[7] + dx, g[8] + dy)
        if st.capLook ~= look then st.capSet = nil end
        st.capLook, st.capGeo, st.capDX, st.capDY = look, g, dx, dy
    end
    host:SetFrameLevel(owner:GetFrameLevel() + c.lvl)
    host:SetScale(kc)
    host:ClearAllPoints()
    host:SetPoint("TOPLEFT", owner, "TOPLEFT", ox / kc, oy / kc)
    host:SetSize(w / kc, h / kc)
    host:Show()
end

function ns.AB_HideBarChrome(st)
    if st.under then st.under:Hide() end
    if st.capHost then st.capHost:Hide() end
    st.capsOn = false
end

-- Paints WoW Forever's frame and dividers onto st (a state table the caller
-- keeps) round a button grid w x h whose TOPLEFT sits at (ox, oy) off
-- owner's TOPLEFT. k = button size / 45 (Blizzard scales the art with the
-- icon size). n = the buttons along the bar when it runs as one line at
-- Blizzard's divider spacing, else 0; step = the distance between button
-- starts along it; the first `extra` buttons carry one onePx more. Both sit
-- on a frame one level under owner (under the buttons).
function ns.AB_PaintForeverChrome(st, owner, ox, oy, w, h, k, vertical, n, step, extra, onePx)
    local ART = ns.AB_FV_ART
    local lvl = owner:GetFrameLevel()

    -- Under the buttons, in 45px-button units.
    local under = st.under
    if not under then
        under = CreateFrame("Frame", nil, owner)
        st.under = under
        st.divs = {}
    end
    under:SetFrameLevel(lvl > 0 and lvl - 1 or 0)
    under:SetScale(k)
    under:ClearAllPoints()
    under:SetPoint("TOPLEFT", owner, "TOPLEFT", ox / k, oy / k)
    under:SetSize(w / k, h / k)
    under:Show()

    local border = st.border
    if not border and ns.AB_AtlasOK(ART.frame) then
        border = under:CreateTexture(nil, "BACKGROUND", nil, -3)
        border:SetAtlas(ART.frame)
        border:SetPoint("TOPLEFT", under, "TOPLEFT", -6, 6)
        border:SetPoint("BOTTOMRIGHT", under, "BOTTOMRIGHT", 4, -5)
        st.border = border
    end

    -- Dividers: one per pair of neighbours; a divider's end edge overlaps
    -- the later button by 5 (the flared ends fill the rings' corners).
    -- Unlike the frame they keep their native size whatever the icon size
    -- (12 across, 5 of overlap, the edges at the atlas depth), so in the
    -- under frame's units every one of those divides by k.
    local ik = 1 / k
    local set = vertical and ART.divV or ART.divH
    if n > 1 and not (ns.AB_AtlasOK(set[1]) and ns.AB_AtlasOK(set[2]) and ns.AB_AtlasOK(set[3])) then
        n = 0
    end
    local divs = st.divs
    for i = 1, n - 1 do
        local d = divs[i]
        if not d then
            d = { under:CreateTexture(nil, "BACKGROUND", nil, -2),
                  under:CreateTexture(nil, "BACKGROUND", nil, -2),
                  under:CreateTexture(nil, "BACKGROUND", nil, -2) }
            divs[i] = d
        end
        local a, b, c = d[1], d[2], d[3]
        if d.set ~= set then
            a:SetAtlas(set[1]); b:SetAtlas(set[2]); c:SetAtlas(set[3])
            d.set = set
        end
        local at = (i * step + (i < extra and i or extra) * onePx) / k
        a:ClearAllPoints(); b:ClearAllPoints(); c:ClearAllPoints()
        if vertical then
            a:SetSize(set[4] * ik, 12 * ik); b:SetSize(set[5] * ik, 12 * ik)
            a:SetPoint("TOPLEFT", under, "TOPLEFT", 0, 7 * ik - at)
            b:SetPoint("TOPRIGHT", under, "TOPRIGHT", 0, 7 * ik - at)
            c:SetPoint("TOPLEFT", a, "TOPRIGHT")
            c:SetPoint("BOTTOMRIGHT", b, "BOTTOMLEFT")
        else
            a:SetSize(12 * ik, set[4] * ik); b:SetSize(12 * ik, set[5] * ik)
            a:SetPoint("TOPLEFT", under, "TOPLEFT", at - 7 * ik, 0)
            b:SetPoint("BOTTOMLEFT", under, "BOTTOMLEFT", at - 7 * ik, 0)
            c:SetPoint("TOPLEFT", a, "BOTTOMLEFT")
            c:SetPoint("BOTTOMRIGHT", b, "TOPRIGHT")
        end
        a:Show(); b:Show(); c:Show()
    end
    for i = (n > 1 and n or 1), #divs do
        local d = divs[i]
        d[1]:Hide(); d[2]:Hide(); d[3]:Hide()
    end
end

-- A bar's chrome onto st, for the live bar and the options preview: WoW
-- Forever's frame and dividers when `forever`, then `look`'s end caps (nil =
-- none) on the sideL / sideR ends. Arguments as AB_PaintForeverChrome and
-- AB_PaintCaps. True once the caps' art no longer waits on the faction.
function ns.AB_PaintBarChrome(st, owner, ox, oy, w, h, btnW, forever, look, multi, vertical, n, step, extra, onePx, pxK, key, sideL, sideR)
    if forever then
        ns.AB_PaintForeverChrome(st, owner, ox, oy, w, h, btnW / 45, vertical, n, step, extra, onePx)
    elseif st.under then
        st.under:Hide()
    end
    ns.AB_PaintCaps(st, owner, ox, oy, w, h, btnW, look, multi, pxK, key, sideL, sideR)
    return ns.AB_CapsFaction(st)
end

-- The faction listener every bar's caps share: registered only while some
-- bar shows faction caps -- for the pick a neutral character makes, and for
-- one loading screen while a bar's faction art still waits. Runs after a
-- bar's chrome changes (LayoutBar's tail), never per event otherwise.
function ns.AB_CapsEvSync()
    local need, waiting = false, false
    local all = ns._abChrome
    if all then
        for _, st in pairs(all) do
            local c = st.capsOn and ns.AB_CAPS[st.capLook]
            if c and c.art then
                need = true
                if not st.capKnown then waiting = true end
            end
        end
    end
    local ev = ns._abCapsEv
    if not need then
        if ev then ev:UnregisterAllEvents() end
        return
    end
    if not ev then
        ev = ns.TakeShell()
        ev:SetScript("OnEvent", function(self, event)
            local known = true
            for _, cs in pairs(ns._abChrome) do
                if not ns.AB_CapsFaction(cs) then known = false end
            end
            if known and event == "PLAYER_ENTERING_WORLD" then
                self:UnregisterEvent(event)
            end
        end)
        ns._abCapsEv = ev
    end
    ev:RegisterEvent("NEUTRAL_FACTION_SELECT_RESULT")
    if waiting then
        ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    else
        ev:UnregisterEvent("PLAYER_ENTERING_WORLD")
    end
end

-- A bar's chrome, from LayoutBar's tail: WoW Forever's frame and dividers
-- (Show Bar Background), and the bar's end caps on a horizontal bar. Each
-- bar keeps its own state (ns._abChrome[key]), built the first time it shows
-- either piece.
function ns.AB_ApplyBarChrome(key, frame, w, h, btnW, vertical, multi, n, step, extra, onePx)
    local all = ns._abChrome
    local st = all and all[key]
    local fv = ns.AB_ForeverBg(key)
    local look, sideL, sideR
    if not vertical then look, sideL, sideR = ns.AB_CapsLook(key) end
    if not (fv or look) then
        if st then
            ns.AB_HideBarChrome(st)
            ns.AB_CapsEvSync()
        end
        return
    end
    if not all then all = {}; ns._abChrome = all end
    if not st then st = {}; all[key] = st end
    ns.AB_PaintBarChrome(st, frame, 0, 0, w, h, btnW, fv, look, multi, vertical, n, step, extra, onePx, nil, key, sideL, sideR)
    ns.AB_CapsEvSync()
end

-------------------------------------------------------------------------------
--  End caps on the micro menu and the bag bar. Both are Blizzard frames EAB
--  only follows, so their caps are painted (the painter above, the same keys
--  and checklist as an action bar) onto the bar's follower frame
--  (extraBarHolders, our own), never into Blizzard's tree. They take Action Bar
--  1's button size (neither bar has one), the strata and level of the frame
--  that holds the buttons (so they draw over them as bar 1's do), and the
--  Blizzard frame's alpha through the fader's twin. Shown state follows EAB's
--  own hides (the follower hides with them; SetManagedBlizzOwnedSuppressed
--  reports its own, Data Bars' micro menu hider too), the micro menu's docking
--  (a secure post-hook) and WoW Forever's interface-style switch (its event,
--  one frame later): never an OnShow hook, since Blizzard shows and hides
--  these frames inside functions that go on to call protected ones. The micro
--  menu's caps sit on the buttons' own rect (retail's container also keeps
--  the queue eye's slot), the bag bar's on its shown buttons (retail's bar
--  keeps its length while collapsed). Nothing runs until a side shows.
-------------------------------------------------------------------------------
ns.AB_CAP_EXTRAS = { MicroBar = true, BagBar = true }

-- The frame whose level the buttons ride on.
function ns.AB_ExtraCapsBase(key)
    if key == "MicroBar" then return _G.MicroMenu end
    return _G.BagsBar
end

-- Edit Mode laid the bar out vertically: no caps (as a vertical action bar).
function ns.AB_ExtraCapsVertical(key)
    local f = ns.AB_ExtraCapsBase(key)
    return f ~= nil and f.isHorizontal == false
end

function ns.AB_ExtraCapsShown(key)
    local st = ns._abChrome and ns._abChrome[key]
    local host = st and st.capHost
    if not host then return end
    local bf = _G[BAR_LOOKUP[key].frameName]
    local on = st.capsOn and bf ~= nil and bf:IsShown()
    if on and key == "MicroBar" then
        -- Docked into a vehicle or pet battle frame: the container is empty.
        local m = _G.MicroMenu
        on = m ~= nil and m:GetParent() == bf and m:IsShown()
    end
    host:SetShown(on and true or false)
end

-- After EAB itself hid or showed one of the two Blizzard frames.
function ns.AB_ExtraCapsFor(frame)
    if not ns._abCapHooked then return end
    if frame == _G.MicroMenuContainer then
        ns.AB_ExtraCapsShown("MicroBar")
    elseif frame == _G.BagsBar then
        ns.AB_ExtraCapsShown("BagBar")
    end
end

-- Once per bar, the first time its caps show (a secure post-hook cannot be
-- removed; with no caps it returns at the missing layer).
function ns.AB_ExtraCapsHooks(key)
    local done = ns._abCapHooked or {}
    ns._abCapHooked = done
    if done[key] then return end
    done[key] = true
    local m = _G.MicroMenu
    if key == "MicroBar" and m and m.OverrideMicroMenuPosition then
        hooksecurefunc(m, "OverrideMicroMenuPosition", function() ns.AB_ExtraCapsShown("MicroBar") end)
    end
end

-- WoW Forever's interface-style switch (keyboard and mouse vs controller)
-- hides and shows both Blizzard frames (INPUT_DEVICE_INTERFACE_TRANSITION):
-- the shown state is re-read one frame later, listened to only while either
-- bar shows caps. Retail's frames never follow that switch.
function ns.AB_ExtraCapsPadFlush()
    ns._abCapStyleArmed = nil
    ns.AB_ExtraCapsShown("MicroBar")
    ns.AB_ExtraCapsShown("BagBar")
end
function ns.AB_ExtraCapsPad()
    if not EllesmereUI.IS_FOREVER then return end
    local all = ns._abChrome
    local on = all and ((all.MicroBar and all.MicroBar.capsOn) or (all.BagBar and all.BagBar.capsOn))
    local ev = ns._abCapStyleEv
    if not on then
        if ev then ev:UnregisterAllEvents() end
        return
    end
    if not ev then
        if C_EventUtils and C_EventUtils.IsEventValid
            and not C_EventUtils.IsEventValid("INPUT_DEVICE_INTERFACE_TRANSITION") then
            return
        end
        ev = ns.TakeShell()
        ev:SetScript("OnEvent", function()
            if ns._abCapStyleArmed then return end
            ns._abCapStyleArmed = true
            C_Timer_After(0, ns.AB_ExtraCapsPadFlush)
        end)
        ns._abCapStyleEv = ev
    end
    ev:RegisterEvent("INPUT_DEVICE_INTERFACE_TRANSITION")
end

-- Retail's bag bar keeps its full length while collapsed (the expand arrow
-- only hides the bag slots), so its caps sit on the shown buttons: their
-- left edge and width in follower units, nil = the whole follower. WoW
-- Forever hides that arrow, so its bar never collapses.
function ns.AB_BagEdge(b, hs, hl, minL, maxR)
    if b and b:IsShown() then
        local l, r = b:GetLeft(), b:GetRight()
        if l and r then
            local k = b:GetEffectiveScale() / hs
            l, r = l * k - hl, r * k - hl
            if not minL or l < minL then minL = l end
            if not maxR or r > maxR then maxR = r end
        end
    end
    return minL, maxR
end
function ns.AB_BagCapsExtent(holder)
    local bb, mgr = _G.BagsBar, _G.MainMenuBarBagManager
    if not bb or bb.hideExpandToggle or not (mgr and mgr.EnumerateBagButtons) then return nil end
    local hs, hl = holder:GetEffectiveScale(), holder:GetLeft()
    if not hl then return nil end
    local minL, maxR = ns.AB_BagEdge(_G.BagBarExpandToggle, hs, hl, nil, nil)
    for _, b in mgr:EnumerateBagButtons() do
        minL, maxR = ns.AB_BagEdge(b, hs, hl, minL, maxR)
    end
    if not minL or maxR - minL < 1 then return nil end
    return minL, maxR - minL
end
-- Collapsing or expanding the bag bar repaints its caps (one frame later,
-- after Blizzard's own relayout), listened to only while it shows caps.
function ns.AB_BagCapsExpandFlush()
    ns._abBagArmed = nil
    ns.AB_ExtraCaps("BagBar")
end
function ns.AB_BagCapsExpandChanged()
    if ns._abBagArmed then return end
    ns._abBagArmed = true
    C_Timer_After(0, ns.AB_BagCapsExpandFlush)
end
function ns.AB_BagCapsWatch(on)
    local bb = _G.BagsBar
    if not (bb and not bb.hideExpandToggle and EventRegistry) then return end
    if on then
        if not ns._abBagWatch then
            ns._abBagWatch = true
            EventRegistry:RegisterCallback("MainMenuBarManager.OnExpandChanged", ns.AB_BagCapsExpandChanged, ns.AB_CAP_EXTRAS)
        end
    elseif ns._abBagWatch then
        ns._abBagWatch = nil
        EventRegistry:UnregisterCallback("MainMenuBarManager.OnExpandChanged", ns.AB_CAP_EXTRAS)
    end
end

-- Paints (or clears) a bar's caps. Stamp-gated on every input the paint
-- reads; the shown state is re-read every call.
function ns.AB_ExtraCaps(key)
    local holder = extraBarHolders[key]
    local bf = holder and _G[BAR_LOOKUP[key].frameName]
    if not bf then return end
    local all = ns._abChrome
    local st = all and all[key]
    local look, sL, sR
    if not ns.AB_ExtraCapsVertical(key) then look, sL, sR = ns.AB_CapsLook(key) end
    if not look then
        if st and st.capsOn then
            ns.AB_HideBarChrome(st)
            if ns._abFadeTwin then ns._abFadeTwin[bf] = nil end
            ns.AB_CapsEvSync()
            ns.AB_ExtraCapsPad()
            if key == "BagBar" then ns.AB_BagCapsWatch(false) end
        end
        return
    end
    if not all then all = {}; ns._abChrome = all end
    if not st then st = {}; all[key] = st end
    local base = ns.AB_ExtraCapsBase(key) or bf
    local lvl, strata = base:GetFrameLevel(), base:GetFrameStrata()
    local owner, ox = holder, 0
    local w, h, u = holder:GetWidth(), holder:GetHeight(), ns._abMainBtnW or 45
    local m = (key == "MicroBar") and _G.MicroMenu
    if m then
        -- The buttons' own rect, on a frame of ours anchored to it: it follows
        -- a corner flip of the menu in its container by itself.
        owner = st.xOwner
        if not owner then
            owner = CreateFrame("Frame", nil, holder)
            owner:SetPoint("TOPLEFT", m, "TOPLEFT")
            owner:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT")
            st.xOwner = owner
        end
        local k = m:GetEffectiveScale() / holder:GetEffectiveScale()
        w, h = m:GetWidth() * k, m:GetHeight() * k
    elseif key == "BagBar" then
        local l, bw = ns.AB_BagCapsExtent(holder)
        if l then ox, w = l, bw end
    end
    local sc, dx, dy = ns.AB_CapsTweak(key)
    if not st.capsOn or st.xLook ~= look or st.xL ~= sL or st.xR ~= sR or st.xW ~= w
        or st.xH ~= h or st.xU ~= u or st.xS ~= sc or st.xDX ~= dx or st.xDY ~= dy
        or st.xLvl ~= lvl or st.xStr ~= strata or st.xOX ~= ox then
        if holder:GetFrameStrata() ~= strata then holder:SetFrameStrata(strata) end
        holder:SetFrameLevel(lvl)
        if owner ~= holder then
            if owner:GetFrameStrata() ~= strata then owner:SetFrameStrata(strata) end
            owner:SetFrameLevel(lvl)
        end
        ns.AB_PaintCaps(st, owner, ox, 0, w, h, u, look, false, nil, key, sL, sR)
        ns.AB_CapsFaction(st)
        st.xLook, st.xL, st.xR, st.xW, st.xH, st.xU = look, sL, sR, w, h, u
        st.xS, st.xDX, st.xDY, st.xLvl, st.xStr, st.xOX = sc, dx, dy, lvl, strata, ox
        local tw = ns._abFadeTwin
        if not tw then
            tw = setmetatable({}, { __mode = "k" })
            ns._abFadeTwin = tw
        end
        tw[bf] = st.capsOn and st.capHost or nil
        if st.capHost then st.capHost:SetAlpha(_fadeAlpha[bf] or 1) end
        if st.capsOn then ns.AB_ExtraCapsHooks(key) end
        ns.AB_CapsEvSync()
        ns.AB_ExtraCapsPad()
        if key == "BagBar" then ns.AB_BagCapsWatch(st.capsOn) end
    end
    ns.AB_ExtraCapsShown(key)
end

function ns.AB_ExtraCapsAll()
    ns.AB_ExtraCaps("MicroBar")
    ns.AB_ExtraCaps("BagBar")
end

-- Repaints the bars that carry Action Bar 1's caps (its cap settings reach them).
function ns.AB_CapsSpanApply()
    local p = EAB.db and EAB.db.profile
    if not p then return end
    local l, r = p.endCapSpanLeft, p.endCapSpanRight
    for i = 1, 2 do
        local k = (i == 1) and l or r
        if k and not (i == 2 and k == l) then
            if ns.AB_CAP_EXTRAS[k] then ns.AB_ExtraCaps(k) else EAB:ApplyPaddingForBar(k) end
        end
    end
end

