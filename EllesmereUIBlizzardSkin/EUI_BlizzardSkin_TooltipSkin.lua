if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_BlizzardSkin_TooltipSkin.lua
--
--  The game tooltip in the EllesmereUI style, with static popups, context
--  menus, the resurrect glow and the LFG queue popup.
--  Reads EllesmereUIBlizzardSkin.lua through ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIBlizzardSkin.lua or an earlier EUI_BlizzardSkin_*.lua file
-- failed to load.
if not I or I.last ~= "main" then return end

local FFD, GetFFD = I.FFD, I.GetFFD

-------------------------------------------------------------------------------
--  Tooltip / Context Menu / Static Popup Skinning
--  Restyles GameTooltip et al in EUI dark style; visual-only (alpha, backdrop color,
--  font). NEVER Hide/Show/SetParent Blizzard frames; hooks are hooksecurefunc post-hooks only.
-------------------------------------------------------------------------------
;(function()
    local _ttSkinned = {}
    local _isSecret = issecretvalue
    local _PP  -- resolved lazily
    local _select = select
    local _GameTooltip = GameTooltip
    local _RAID_CC = RAID_CLASS_COLORS
    local _nameL1 = nil  -- cached ref to GameTooltipTextLeft1

    local function _enabled()
        return not EllesmereUIDB or EllesmereUIDB.customTooltips ~= false
    end
    -- Popups + context menus reskin. customTooltips governs ONLY the game tooltip; reskinPopupsMenus
    -- is seeded from it once at login then independent. BLIZZARD WINDOW RESKINS (queue popup, game menu, group finder, great vault) are independent of BOTH masters.
    local function _pmEnabled()
        return not EllesmereUIDB or EllesmereUIDB.reskinPopupsMenus ~= false
    end

    -- IsForbidden() reports only EXPLICIT marking. A forbidden LAYOUT aspect inherited from
    -- the frame a tooltip or menu is anchored to (Blizzard UI widget owners hand one to the
    -- tooltip they own, on hover) restricts every call on it and on everything anchored
    -- below it without ever setting that flag, so the only legal probe is a pcall'd read.
    -- Skip the pass instead of raising inside a Blizzard OnShow; the last-good skin stands and the next apply, off that anchor, runs normally.
    local function _ttUsable(tt)
        local ok, w = pcall(tt.GetWidth, tt)
        if not ok then return false end
        if _isSecret and _isSecret(w) then return false end
        return true
    end

    local function _applyConfiguredBorder(owner, prefix, legacySize)
        if not owner or not EllesmereUI.ApplyBorderStyle then return end
        -- Read the level up front: it is the first widget call this makes, so it doubles as the restriction probe (see _ttUsable).
        local okLvl, ownerLevel = pcall(owner.GetFrameLevel, owner)
        if not okLvl then return end
        local db = EllesmereUIDB or {}
        local key = db[prefix .. "BorderThickness"]
        local sizes = { none=0, thin=1, normal=2, heavy=3, strong=4 }
        local size = key and (sizes[key] or 1) or (legacySize or 1)
        key = key or ({ [0]="none", [1]="thin", [2]="normal", [3]="heavy", [4]="strong" })[size] or "thin"
        local mode = db[prefix .. "BorderColorMode"] or "custom"
        local color
        if mode == "accent" then
            color = EllesmereUI.ELLESMERE_GREEN or { r=.27, g=.86, b=.49 }
        elseif mode == "class" then
            local _, class = UnitClass("player")
            color = class and RAID_CLASS_COLORS[class] or { r=1, g=1, b=1 }
        else
            color = db[prefix .. "BorderColor"] or { r=1, g=1, b=1 }
        end
        local alpha = db[prefix .. "BorderOpacity"]
        if alpha == nil then alpha = (mode == "custom") and EllesmereUI.RESKIN.BRD_ALPHA or .5 end
        local data = GetFFD(owner)
        if not data.configBorder then
            data.configBorder = CreateFrame("Frame", nil, owner, "BackdropTemplate")
            data.configBorder:SetAllPoints(owner)
            data.configBorder:EnableMouse(false)
            if not _PP then _PP = EllesmereUI.PP end
            if _PP and _PP.HideBorder then _PP.HideBorder(owner) end
        end
        -- Recomputed every apply so Show Behind works live. +4 not +5: the resurrect-accept
        -- glow overlay sits at +5 on the same buttons and a tie goes to the later-created sibling, so the border must never bury it.
        data.configBorder:SetFrameLevel(db[prefix .. "BorderBehind"]
            and math.max(0, ownerLevel - 1) or (ownerLevel + 4))
        local tex = db[prefix .. "BorderTexture"] or "solid"
        -- Exact Border Size (the <prefix>BorderThicknessPx companion); nil = the legacy step above, unchanged.
        local px = EllesmereUI.BorderPx(db[prefix .. "BorderThicknessPx"], size, tex)
        EllesmereUI.ApplyBorderStyle(data.configBorder, size, color.r, color.g, color.b, alpha,
            tex, db[prefix .. "BorderOffsetX"],
            db[prefix .. "BorderOffsetY"], db[prefix .. "BorderShiftX"], db[prefix .. "BorderShiftY"],
            "blizzardSkin", key, nil, px)
    end
    EllesmereUI._applyBlizzardConfiguredBorder = _applyConfiguredBorder

    -- Element & Text Color mode. "native" = surfaces keep original coloring (Game Menu header
    -- stays branded green). UNSET resolves to native unless the user had the legacy Accent Colored Elements toggle on, so old choices carry forward with no migration write and a fresh install sees no change.
    local function _elementColorMode()
        local db = EllesmereUIDB or {}
        local mode = db.popupMenuButtonTextColorMode
        if mode == nil then
            mode = db.accentReskinElements and "accent" or "native"
        end
        return mode
    end
    EllesmereUI._getPopupMenuElementMode = _elementColorMode

    local function _getElementColor()
        local db = EllesmereUIDB or {}
        local mode = _elementColorMode()
        if mode == "custom" then
            local c = db.popupMenuButtonTextColor or { r=1, g=1, b=1 }
            return c.r, c.g, c.b
        elseif mode == "class" then
            local _, class = UnitClass("player")
            local c = class and RAID_CLASS_COLORS[class]
            if c then return c.r, c.g, c.b end
        end
        -- accent AND native both land here; only the Game Menu header calls this unconditionally under native (branded green) -- others gate first.
        local c = EllesmereUI.ELLESMERE_GREEN or { r=.27, g=.86, b=.49 }
        return c.r, c.g, c.b
    end
    EllesmereUI._getPopupMenuButtonTextColor = _getElementColor

    local function _ttSkin(tt, _, isEmbedded)
        if not tt or tt:IsForbidden() or not _enabled() then return end
        -- Embedded tooltips (EmbeddedItemTooltip, reward block inside a world-quest tooltip) render INSIDE a parent; skip bg/border to avoid a nested-tooltip look.
        if isEmbedded or tt.IsEmbedded then return end
        if not _ttUsable(tt) then return end
        if not _PP then _PP = EllesmereUI and EllesmereUI.PP end
        if tt.NineSlice then tt.NineSlice:SetAlpha(0) end
        if not GetFFD(tt).bg then
            GetFFD(tt).bg = tt:CreateTexture(nil, "BACKGROUND", nil, -8)
            GetFFD(tt).bg:SetAllPoints()
        end
        -- Unified user-customizable background (shared with EUI custom tooltips via GetTooltipBg); re-applied each call so a settings change shows immediately.
        GetFFD(tt).bg:SetColorTexture(EllesmereUI.GetTooltipBg())
        GetFFD(tt).bg:Show()
        -- Border size/color (Blizz UI Enhanced > Blizzard Tooltip > Border), same reapply-every-call pattern; size 0 hides the border.
        local _, _, _, _, legacySize = EllesmereUI.GetTooltipBorder()
        _applyConfiguredBorder(tt, "tooltip", legacySize)
    end
    -- The same look for Blizzard's tooltip-like frames that are not GameTooltips
    -- (their window packs call it on show).
    EllesmereUI._skinBlizzardTooltipFrame = _ttSkin

    local function _ttFonts(tt, startFrom)
        if not tt or tt:IsForbidden() or not _enabled() then return end
        local fp = EllesmereUI.GetFontPath("blizzardSkin") or STANDARD_TEXT_FONT
        local ol = EllesmereUI.GetFontOutlineFlag("blizzardSkin") or ""
        local scale = EllesmereUIDB and EllesmereUIDB.tooltipFontScale or 1.0
        local titleSize = math.floor(13 * scale + 0.5)
        local bodySize  = math.floor(11 * scale + 0.5)
        -- pcall'd for the same reason as _ttUsable, and this is the first widget call here.
        local okName, name = pcall(tt.GetName, tt)
        if not okName or not name then return end
        local nLines = tt.NumLines and tt:NumLines() or 30
        for i = (startFrom or 1), nLines do
            local left = _G[name .. "TextLeft" .. i]
            if not left then break end
            left:SetFont(fp, (i == 1) and titleSize or bodySize, ol)
            local right = _G[name .. "TextRight" .. i]
            if right then right:SetFont(fp, bodySize, ol) end
        end
    end

    local _ttRelaying = setmetatable({}, { __mode = "k" })
    local function _ttOnShow(self)
        _ttSkin(self)
        _ttFonts(self)
        -- Re-show to recalc size with the new fonts. Gated on the skin toggle (hook is
        -- uninstallable, must stay zero-cost when off). pcall'd: a tooltip rendering
        -- secret-capable content (e.g. SetSpellByID) denies a tainted re-Show as
        -- forbidden-object access (field-hit via Blizzard_PTRFeedback's tooltip hook,
        -- which Shows the tooltip from secure code with our OnShow hook behind it);
        -- the recalc is optional polish, the font writes above are region-level and legal regardless.
        if _enabled() and not _ttRelaying[self] then
            _ttRelaying[self] = true
            pcall(self.Show, self)
            _ttRelaying[self] = nil
        end
    end

    local function _ttHook(tt)
        if not tt or tt:IsForbidden() or _ttSkinned[tt] then return end
        if EllesmereUI.BlizzSkinPadStandDown() then return end
        _ttSkinned[tt] = true
        tt:HookScript("OnShow", _ttOnShow)
    end

    local function _accentEnabled()
        -- False in native mode so gated surfaces keep their else-branch look (unrecolored/plain white).
        return _elementColorMode() ~= "native"
    end

    -- Unified inspect system: while Show Item Level is active, one INSPECT_READY handler fills the tooltip ilvl cache from every inspect, whoever requested it; the tooltip's own requests are paced below.
    local _ilvlCache = {}       -- guid -> { ilvl = number, time = GetTime() }
    local _ilvlCacheTTL = 120
    -- Mount-name cache: short TTL, just enough to survive one hover's refresh ticks so an unmounted player is scanned once, not per tick. name=false means "scanned, none".
    local _mountCache = {}      -- guid -> { name = string|false, collected = bool|nil, time = GetTime() }
    local _mountCacheTTL = 3
    local _inspectPendingGUID = nil
    -- Inspect request pacing, one table so this chunk gains a single local. The server
    -- silently drops requests that arrive in a burst, and a dropped one yields no
    -- INSPECT_READY, so Blizzard's inspect window (which only opens on a matching one)
    -- stays shut. Hovering across raid frames used to fire one request per frame.
    -- Timings are tuned from one in-game log; the server's real limits are undocumented.
    local _insp = {
        active = false,         -- Show Item Level live: event registered, hooks doing work
        pruneAt = 0,            -- next time expired _ilvlCache entries are swept
        lastAny = 0,            -- last NotifyInspect from ANY source (ours, Blizzard, other addons)
        lastForeign = 0,        -- last NotifyInspect that was not ours
        prevForeign = 0,        -- lastForeign before the latest foreign call
        ourAt = -1,             -- GetTime() of our own last call; same frame in the hook = ours
        pendingAt = 0,          -- when our outstanding tooltip request went out
        dwellGUID = nil,        -- latest guid the tooltip wants inspected
        dwellAt = 0,            -- when that guid was first requested
        dwellArmed = false,     -- one dwell timer at a time
        MIN_GAP = 2,            -- seconds a tooltip request keeps clear of the previous one, whoever sent it
        DWELL = 0.9,            -- cursor must rest on the same unit this long before we ask; long enough that a
                                -- quick hover-then-Inspect never puts our request right before Blizzard's
        FOREIGN_WINDOW = 10,    -- another addon polling this recently: stay passive, use its data
        PENDING_TTL = 5,        -- our own request counts as lost after this, so a retry is allowed
    }
    -- GUID the visible GameTooltip was last populated for (set by the Unit post-call, cleared on hide); lets the async inspect handler confirm identity before touching it.
    local _tipShownGUID = nil
    -- True when any left line already shows label, so an appended score/ilvl line never duplicates one another Unit post-call produced. Matches label as a plain (non-pattern) substring, so "+" is literal.
    local function _tipHasLine(tt, label)
        local nm = tt.GetName and tt:GetName()
        if not nm then return false end
        local n = tt.NumLines and tt:NumLines() or 0
        for i = 1, n do
            local fs = _G[nm .. "TextLeft" .. i]
            local txt = fs and fs:GetText()
            if txt and not (_isSecret and _isSecret(txt)) and txt:find(label, 1, true) then
                return true
            end
        end
        return false
    end

    -- Returns the mount name shown on a unit and whether the LOCAL player has it collected
    -- (true/false, nil if unknown -- e.g. name came from the aura, not MountJournal). Collection state is the 11th return of GetMountInfoByID, per-character.
    local function _getMountedAuraName(unit)
        if not unit or (_isSecret and _isSecret(unit)) then return nil end
        if not UnitExists(unit) or not UnitIsPlayer(unit) then return nil end
        if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
        if not (C_MountJournal and C_MountJournal.GetMountFromSpell) then return nil end
        -- GetAuraDataByIndex hard-errors for tainted callers while auras are
        -- restricted instead of returning nil, so an issecretvalue() check
        -- comes too late -- skip outright (cosmetic addition, not worth the
        -- risk). Gate on the LIVE restriction probe: combat lockdown alone
        -- misses between-pull windows in protected instances AND forced
        -- restriction states, which is exactly where this scan detonated.
        local AK = EllesmereUI.AuraKit
        if InCombatLockdown()
            or (AK and AK.AurasRestricted and AK.AurasRestricted()) then
            return nil
        end

        for i = 1, 255 do
            local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
            if not aura then break end
            local spellID = aura.spellId
            if spellID and not (_isSecret and _isSecret(spellID)) then
                local mountID = C_MountJournal.GetMountFromSpell(spellID)
                if mountID and not (_isSecret and _isSecret(mountID)) and mountID > 0 then
                    local name, collected
                    if C_MountJournal.GetMountInfoByID then
                        local mountName, _, _, _, _, _, _, _, _, _, isCollected =
                            C_MountJournal.GetMountInfoByID(mountID)
                        if mountName and not (_isSecret and _isSecret(mountName)) then
                            name = mountName
                            if type(isCollected) == "boolean" then collected = isCollected end
                        end
                    end
                    if not name then
                        local auraName = aura.name
                        if auraName and not (_isSecret and _isSecret(auraName)) then
                            name = auraName
                        end
                    end
                    if name and name ~= "" then return name, collected end
                end
            end
        end
        return nil
    end
    -- InspectFrame_Show's NotifyInspect ran just before this post-hook, in the same frame,
    -- and was counted as foreign. It is the user's own inspect, not another addon
    -- polling, so it must not switch the tooltip to passive mode.
    local function _onInspectUnit()
        if _insp.active and _insp.lastForeign == GetTime() then
            _insp.lastForeign = _insp.prevForeign
        end
    end
    -- Caches every INSPECT_READY, including the ones other addons asked for, which is
    -- what lets the tooltip stay passive while such an addon polls the group.
    local _inspectFrame
    local function _onInspectReady(self, _, guid)
        -- Option turned off this session: stop listening; the next unit tooltip with it
        -- on re-activates. Same test as the tooltip pass, so the two never flip-flop
        -- (the reskin master only takes effect on /reload, when nothing is activated).
        if EllesmereUIDB and EllesmereUIDB.tooltipItemLevel == false then
            self:UnregisterEvent("INSPECT_READY")
            _insp.active = false
            return
        end
        if not guid or (_isSecret and _isSecret(guid)) then return end
        if guid == _inspectPendingGUID then _inspectPendingGUID = nil end
        -- Read item level through a token derived from THAT GUID, so it is captured even after the cursor left the unit and cached under the right GUID.
        if C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel and _G.UnitTokenFromGUID then
            local u = _G.UnitTokenFromGUID(guid)
            if u and not (_isSecret and _isSecret(u)) and UnitExists(u) then
                local val = C_PaperDollInfo.GetInspectItemLevel(u)
                if val and not (_isSecret and _isSecret(val)) and val > 0 then
                    -- One request fires a burst of 10+ events; update in place instead of allocating per event.
                    local entry = _ilvlCache[guid]
                    local now = GetTime()
                    if entry then
                        entry.ilvl = math.floor(val)
                        entry.time = now
                    else
                        -- Every inspect source feeds the cache now, so sweep expired
                        -- entries at most once per TTL, only when a new one is added.
                        if now >= _insp.pruneAt then
                            _insp.pruneAt = now + _ilvlCacheTTL
                            for g, e in pairs(_ilvlCache) do
                                if (now - e.time) >= _ilvlCacheTTL then _ilvlCache[g] = nil end
                            end
                        end
                        _ilvlCache[guid] = { ilvl = math.floor(val), time = now }
                    end
                end
            end
        end
        -- Append only while the tooltip still shows this GUID and the line is not already present.
        local cached = _ilvlCache[guid]
        local ttd = GetFFD(_GameTooltip)
        if cached and _GameTooltip:IsShown() and _tipShownGUID == guid
            and not ttd.ilvlShown
            and not _tipHasLine(_GameTooltip, EllesmereUI.L("Item Level")) then
            local nBefore = _GameTooltip:NumLines() or 0
            _GameTooltip:AddDoubleLine(EllesmereUI.L("Item Level:"), cached.ilvl, 1, 1, 1, 1, 1, 1)
            _ttFonts(_GameTooltip, nBefore + 1)
            -- Runs for every source's result, also in combat; pcall'd like the re-Show in
            -- _ttOnShow, since a tainted re-Show can be denied as forbidden access.
            pcall(_GameTooltip.Show, _GameTooltip)
            ttd.ilvlShown = true
        end
    end
    -- Built and registered only while Show Item Level is on (from _ttInitData at login,
    -- or from the first unit tooltip after it is turned back on), so with it or the
    -- tooltip reskin off after a /reload nothing is registered, hooked or created.
    -- hooksecurefunc cannot be undone: after a mid-session toggle-off the hook returns
    -- at once. Passive mode starts only once another addon's request is actually seen;
    -- the first request just waits MIN_GAP, so it cannot land inside that polling.
    _insp.Activate = function()
        if _insp.active then return end
        _insp.active = true
        _insp.lastAny = GetTime()
        if not _inspectFrame then
            _inspectFrame = CreateFrame("Frame")
            _inspectFrame:SetScript("OnEvent", _onInspectReady)
            -- Every inspect request passes here, whoever sent it. A call is ours when it
            -- happens in the frame we stamped (GetTime() is fixed per frame), so a call
            -- that raised can never leave a stuck "ours" flag behind.
            hooksecurefunc("NotifyInspect", function()
                if not _insp.active then return end
                local t = GetTime()
                _insp.lastAny = t
                if _insp.ourAt ~= t then
                    _insp.prevForeign = _insp.lastForeign
                    _insp.lastForeign = t
                end
            end)
            if InspectUnit then hooksecurefunc("InspectUnit", _onInspectUnit) end
        end
        _inspectFrame:RegisterEvent("INSPECT_READY")
    end
    -- Exposed on EllesmereUI; nothing outside this file reads it today.
    EllesmereUI._inspectCache = _ilvlCache

    -- Re-derive a CLEAN literal group unit token for a GUID by matching it against
    -- tokens we build ourselves (player/raidN/partyN). On secure raid-frame unit
    -- tooltips, GetUnit()/UnitTokenFromGUID can return a secret/unusable token even
    -- though the GUID is clean, starving token-based APIs (M+ summary, inspect item level); a literal token built here is never secret.
    local function _CleanTokenForGUID(guid)
        if not guid or (_isSecret and _isSecret(guid)) then return nil end
        if UnitGUID("player") == guid then return "player" end
        if IsInRaid() then
            for i = 1, GetNumGroupMembers() do
                local tk = "raid" .. i
                local tg = UnitGUID(tk)
                if tg and not (_isSecret and _isSecret(tg)) and tg == guid then return tk end
            end
        else
            for i = 1, GetNumSubgroupMembers() do
                local tk = "party" .. i
                local tg = UnitGUID(tk)
                if tg and not (_isSecret and _isSecret(tg)) and tg == guid then return tk end
            end
        end
        return nil
    end

    -- Hard blocks for a tooltip request, checked before the dwell and again in it: the
    -- inspect window is open or waiting on this player, or the talent frame is inspecting
    -- someone (ClearInspectPlayer would retarget it). Timed hold-offs, passive mode
    -- included, are not blocks; _dwellTick waits them out.
    local function _inspBlocked(guid, now)
        local psf = PlayerSpellsFrame
        if psf and psf.IsInspecting and psf:IsInspecting() then return true end
        local f = InspectFrame
        if f then
            if f:IsShown() then return true end
            -- Blizzard keeps .unit on a window that never opened and shows it on any
            -- later matching INSPECT_READY, so never ask for that person ourselves.
            local u = f.unit
            if u and not (_isSecret and _isSecret(u)) then
                local g = UnitGUID(u)
                if g and not (_isSecret and _isSecret(g)) and g == guid then return true end
            end
        end
        return false
    end
    -- Tooltip-side inspect request, paced. It never fires straight out of the tooltip
    -- pass: a dwell timer runs first, so sweeping the cursor across raid frames costs
    -- one request instead of one per frame. It then yields to the shared request
    -- budget, and asks for no group member while another addon is polling the group --
    -- the INSPECT_READY handler caches whatever that addon asked for, so in a raid
    -- with such an addon running the tooltip adds requests only for non-members.
    -- The price is that an uncached player's item level appears a moment later.
    -- One named timer function, rescheduled while needed, so no closure per hover.
    local function _dwellTick()
        _insp.dwellArmed = false
        local guid = _insp.dwellGUID
        if not guid then return end
        local db = EllesmereUIDB
        -- Cursor moved on, option turned off, or combat started: drop it; the next tooltip pass re-arms.
        if _tipShownGUID ~= guid or not _GameTooltip:IsShown()
            or not (db and db.tooltipItemLevel ~= false) or InCombatLockdown() then
            _insp.dwellGUID = nil
            return
        end
        local now = GetTime()
        local cached = _ilvlCache[guid]
        if cached and (now - cached.time) < _ilvlCacheTTL then
            _insp.dwellGUID = nil
            return
        end
        if _inspBlocked(guid, now) then
            _insp.dwellGUID = nil
            return
        end
        -- Timing gates only postpone: wait for the dwell, the gap after anyone's last
        -- request (the user's own Inspect included), and our outstanding request's expiry.
        -- Raid frames never refresh their tooltip, so a dropped hover would stay blank.
        local readyAt = math.max(_insp.dwellAt + _insp.DWELL, _insp.lastAny + _insp.MIN_GAP)
        if guid == _inspectPendingGUID then
            readyAt = math.max(readyAt, _insp.pendingAt + _insp.PENDING_TTL)
        end
        -- Passive mode: a group member waits out another addon's polling, which will
        -- inspect them and feed the open tooltip through the handler. Anyone outside the
        -- group is never polled by it, so they keep the plain MIN_GAP pacing.
        local unit = _CleanTokenForGUID(guid)
        if unit then
            readyAt = math.max(readyAt, _insp.lastForeign + _insp.FOREIGN_WINDOW)
        end
        if readyAt > now then
            _insp.dwellArmed = true
            C_Timer.After(readyAt - now, _dwellTick)
            return
        end
        _insp.dwellGUID = nil
        if not unit and _G.UnitTokenFromGUID then
            local tu = _G.UnitTokenFromGUID(guid)
            if tu and not (_isSecret and _isSecret(tu)) then unit = tu end
        end
        -- Same last resort as _resolveTipIdentity: "mouseover" only when it provably maps to this guid.
        if not unit and UnitExists("mouseover") then
            local mg = UnitGUID("mouseover")
            if mg and not (_isSecret and _isSecret(mg)) and mg == guid then unit = "mouseover" end
        end
        if not unit or not UnitExists(unit) or not CanInspect(unit) then return end
        _inspectPendingGUID = guid
        _insp.pendingAt = now
        _insp.ourAt = now
        ClearInspectPlayer()
        NotifyInspect(unit)
    end
    -- Caller has already found no cached item level for guid.
    local function _requestTooltipInspect(guid)
        -- The pending dwell re-checks every gate itself; skip them on each refresh meanwhile.
        if _insp.dwellArmed and _insp.dwellGUID == guid then return end
        local now = GetTime()
        -- Hard-blocked now: arm nothing; a later tooltip refresh or re-hover asks again.
        if _inspBlocked(guid, now) then return end
        -- Always track the latest unit; a running timer picks up the retarget.
        if _insp.dwellGUID ~= guid then
            _insp.dwellGUID = guid
            _insp.dwellAt = now
        end
        if not _insp.dwellArmed then
            _insp.dwellArmed = true
            C_Timer.After(_insp.DWELL, _dwellTick)
        end
    end

    -- Resolve who this unit tooltip was populated for. SetUnit(u) stamps u's GUID into
    -- data.guid before this post-call runs, so data.guid is the authoritative identity,
    -- correct on the very first hover. The cursor-focus "mouseover" token is NOT trusted
    -- for identity: the secure focus system updates it on its own schedule and can still
    -- point at the previous frame's unit on fast movement/first hover. Returns (guid,
    -- token); token always maps to guid, used only by token-based APIs (class fallback, M+ summary, inspect). Either may be nil; callers then skip our extras.
    local function _resolveTipIdentity(tt, data)
        local guid = data and data.guid
        if guid and _isSecret and _isSecret(guid) then guid = nil end
        local token
        local ok, _, u = pcall(tt.GetUnit, tt)
        if ok and u and not (_isSecret and _isSecret(u)) and UnitExists(u) then
            local g = UnitGUID(u)
            if g and not (_isSecret and _isSecret(g)) then
                if not guid then guid = g end
                if g == guid then token = u end
            end
        end
        -- Covers our raid/party frames, where GetUnit()/UnitTokenFromGUID return secret tokens but the GUID is clean.
        if guid and not token then
            token = _CleanTokenForGUID(guid)
        end
        if guid and not token and _G.UnitTokenFromGUID then
            local tu = _G.UnitTokenFromGUID(guid)
            if tu and not (_isSecret and _isSecret(tu)) and UnitExists(tu) then token = tu end
        end
        -- Last resort: accept "mouseover" ONLY when it provably maps to the same authoritative
        -- guid -- recovers a usable token (M+/ilvl/title) where UnitTokenFromGUID returns secret, with no cursor-lag misattribution risk.
        if guid and not token and UnitExists("mouseover") then
            local mg = UnitGUID("mouseover")
            if mg and not (_isSecret and _isSecret(mg)) and mg == guid then
                token = "mouseover"
            end
        end
        return guid, token
    end

    do
        local installed = false
        EllesmereUI._applyTooltipUnitDetails = function()
            local db = EllesmereUIDB
            if installed or not _enabled() or not db
                or not db.tooltipShowRarity then return end
            if EllesmereUI.BlizzSkinPadStandDown() then return end
            installed = true
            local levelLine, levelText, levelColor

            local function plainText(text)
                if _isSecret and _isSecret(text) then return nil end
                if type(text) ~= "string" then return nil end
                return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
            end
            local function formatPattern(format)
                return "^" .. format:gsub("%%(%d*)%$?[sd]", "\001")
                    :gsub("(%W)", "%%%1"):gsub("%%\001", ".+") .. "$"
            end
            local levelPatterns = {
                formatPattern(TOOLTIP_UNIT_LEVEL), formatPattern(TOOLTIP_UNIT_LEVEL_TYPE),
                formatPattern(TOOLTIP_UNIT_LEVEL_RACE), formatPattern(TOOLTIP_UNIT_LEVEL_RACE_TYPE),
            }
            local function isLevelLine(line)
                if not canaccesstable(line) or (_isSecret and _isSecret(line.type)) then return false end
                if line.type == Enum.TooltipDataLineType.UnitLevel then return true end
                if line.type ~= Enum.TooltipDataLineType.None then return false end
                local text = plainText(line.leftText)
                if not text then return false end
                -- Some unit tooltips mark their level lines as generic text.
                for _, pattern in ipairs(levelPatterns) do
                    if text:match(pattern) then return true end
                end
                return false
            end
            local function replaceLabel(text, label, replacement)
                local first, last = text:find("(" .. label .. ")", 1, true)
                if not first then first, last = text:lower():find("(" .. label:lower() .. ")", 1, true) end
                if first then
                    return text:sub(1, first) .. replacement .. text:sub(last)
                end
            end
            local function publicUnit(unit)
                if not canaccessallvalues(unit) or type(unit) ~= "string" or unit == "" then return end
                local exists = UnitExists(unit)
                if canaccessallvalues(exists) and exists == true then return unit end
            end
            local function tooltipUnit(tt, data)
                -- The name line carries the unit for world-cursor tooltips, even with a secret GUID.
                for _, line in ipairs(data.lines) do
                    if canaccesstable(line) and canaccessallvalues(line.type)
                        and line.type == Enum.TooltipDataLineType.UnitName then
                        local unit = publicUnit(line.unitToken)
                        if unit then return unit end
                    end
                end
                local worldCursor
                local info = tt.GetProcessingTooltipInfo and tt:GetProcessingTooltipInfo()
                if canaccesstable(info) and canaccessallvalues(info.tooltipData, info.getterName, info.getterFunction)
                    and info.tooltipData == data and not info.getterFunction then
                    if info.getterName == "GetUnit" and canaccesstable(info.getterArgs) then
                        local unit = publicUnit(info.getterArgs[1])
                        if unit then return unit end
                    elseif info.getterName == "GetWorldCursor" and canaccessallvalues(info.append) and not info.append then
                        worldCursor = true
                    end
                end
                local ok, _, unit = pcall(_resolveTipIdentity, tt, data)
                if ok then
                    unit = publicUnit(unit)
                    if unit then return unit end
                end
                -- World-cursor tooltips have no explicit unit argument.
                if worldCursor then return publicUnit("mouseover") end
            end
            local function genericLevelLine(lines)
                local count, first, second, named = 0
                for _, line in ipairs(lines) do
                    if not canaccesstable(line) or not canaccessallvalues(line.type)
                        or type(line.type) ~= "number" then return end
                    local kind = line.type
                    -- A typed category/corpse row invalidates the generic-layout assumption.
                    if kind == Enum.TooltipDataLineType.UnitType or kind == Enum.TooltipDataLineType.UnitDead then return end
                    if kind == Enum.TooltipDataLineType.UnitName then
                        if named or count > 0 then return end
                        named = true
                    elseif kind == Enum.TooltipDataLineType.None then
                        if not named then return end
                        count = count + 1
                        if count > 3 then return end
                        if count == 1 then first = line elseif count == 2 then second = line end
                    end
                end
                -- Generic rows: level alone, level + type/corpse, or subtitle + level + type/corpse.
                local line = (count == 1 or count == 2) and first or count == 3 and second
                if line and _isSecret and _isSecret(line.leftText) then return line end
            end
            local function prepare(tt, data)
                if not canaccesstable(data) or not canaccesstable(data.lines) then return end
                local unit = tooltipUnit(tt, data)
                if not unit then return end
                local classification = UnitClassification(unit)
                if _isSecret and _isSecret(classification) then return end
                local label
                if classification == "rareelite" then
                    label = EllesmereUI.L("Rare Elite")
                elseif classification == "rare" then
                    label = EllesmereUI.L("Rare")
                else
                    return
                end
                for _, line in ipairs(data.lines) do
                    if isLevelLine(line) then
                        levelLine = line
                        break
                    end
                end
                if not levelLine then levelLine = genericLevelLine(data.lines) end
                if not levelLine then return end
                if not canaccessallvalues(levelLine.wrapText, levelLine.leftOffset, levelLine.rightText) then return end
                if levelLine.rightText and levelLine.rightText ~= "" then return end
                local publicColor = canaccessallvalues(levelLine.leftColor)
                if not publicColor and not (_isSecret and _isSecret(levelLine.leftText)) then return end
                levelColor = publicColor and (levelLine.leftColor or NORMAL_FONT_COLOR) or HIGHLIGHT_FONT_COLOR
                local text = levelLine.leftText
                if _isSecret and _isSecret(text) then
                    -- Rebuild from public unit data without inspecting the restricted text.
                    local level = UnitEffectiveLevel(unit)
                    if not canaccessallvalues(level) or type(level) ~= "number" or level <= 0 then return end
                    levelText = format(TOOLTIP_UNIT_LEVEL_TYPE, level, label)
                    return
                end
                if not plainText(text) then return end
                if text:find("(" .. label .. ")", 1, true) then return end
                levelText = replaceLabel(text, ELITE, label)
                    or replaceLabel(text, EllesmereUI.L("Rare"), label)
                    or (text .. " (" .. label .. ")")
            end
            TooltipDataProcessor.AddTooltipPreCall(Enum.TooltipDataType.Unit, function(tt, data)
                if tt ~= _GameTooltip then return end
                levelLine, levelText, levelColor = nil, nil, nil
                local settings = EllesmereUIDB
                if not _enabled() or not settings
                    or not settings.tooltipShowRarity
                    or tt:IsForbidden() or not _ttUsable(tt) then return end
                -- Unidentifiable or restricted data leaves Blizzard's original lines intact.
                if not pcall(prepare, tt, data) then
                    levelLine, levelText, levelColor = nil, nil, nil
                end
            end)
            local function renderLevelLine(tt, line)
                local settings = EllesmereUIDB
                if not settings or not _enabled()
                    or not settings.tooltipShowRarity
                    or tt ~= _GameTooltip or tt:IsForbidden() then return end
                if _isSecret and _isSecret(line) then return end
                if line == levelLine and levelText then
                    -- Render our text without changing Blizzard's shared line data.
                    return pcall(GameTooltip_AddColoredLine, tt, levelText,
                        levelColor or NORMAL_FONT_COLOR, line.wrapText or false, line.leftOffset)
                end
            end
            TooltipDataProcessor.AddLinePreCall(Enum.TooltipDataLineType.None, renderLevelLine)
            TooltipDataProcessor.AddLinePreCall(Enum.TooltipDataLineType.UnitLevel, renderLevelLine)
        end
    end

    -- "Targeting" line: who the hovered unit targets. Opt-in (default off). Needs a
    -- live unit token to build the relational target token, so hovers resolving only
    -- a GUID (our raid/party frames) skip it; identity-secret targets are skipped
    -- entirely. Refresh passes re-run the postprocessor while the tip is up, so an existing line is updated IN PLACE (never appended twice).
    local function _ttTargetLine(tt, unit)
        local db = EllesmereUIDB
        if not (unit and db and db.tooltipShowTarget) then return end
        local tu = unit .. "target"
        if C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret then
            local s = C_Secrets.ShouldUnitIdentityBeSecret(tu)
            if (_isSecret and _isSecret(s)) or s == true then return end
        end
        local label = EllesmereUI.L("Targeting:")
        local tName, r, g, b
        if UnitExists(tu) then
            if UnitIsUnit(tu, "player") then
                tName = EllesmereUI.L("You")
                r, g, b = 0.1, 1, 0.1
            else
                local n = UnitName(tu)
                if n and not (_isSecret and _isSecret(n)) then
                    tName = n
                    r, g, b = 0.9, 0.9, 0.9
                    if UnitIsPlayer(tu) then
                        local _, cf = UnitClass(tu)
                        local cc = cf and not (_isSecret and _isSecret(cf)) and _RAID_CC and _RAID_CC[cf]
                        if cc then r, g, b = cc.r, cc.g, cc.b end
                    else
                        local reaction = UnitReaction and UnitReaction(tu, "player")
                        local fc = reaction and not (_isSecret and _isSecret(reaction))
                            and FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
                        if fc then r, g, b = fc.r, fc.g, fc.b end
                    end
                end
            end
        end
        for i = 2, (tt.NumLines and tt:NumLines() or 0) do
            local lineL = _G["GameTooltipTextLeft" .. i]
            local txt = lineL and lineL:GetText()
            if txt and not (_isSecret and _isSecret(txt)) and txt == label then
                local lineR = _G["GameTooltipTextRight" .. i]
                if lineR then
                    if tName then
                        lineR:SetText(tName)
                        lineR:SetTextColor(r, g, b)
                    else
                        -- Target dropped mid-hover: blank the value, keep the row.
                        lineR:SetText("-")
                        lineR:SetTextColor(0.6, 0.6, 0.6)
                    end
                end
                return
            end
        end
        if tName then
            tt:AddDoubleLine(label, tName, 1, 1, 1, r, g, b)
        end
    end

    -- Hovered player's buffs as icons on the tooltip (opt-in, tooltipShowBuffs).
    -- One engine aura container on GameTooltip, built on first use; the unit is
    -- re-bound only when the hovered GUID changes.
    local _ttBuffs, _ttBuffsGUID, _ttBuffsUnit
    -- position = { container point, tooltip point, growthH, growthV, x, y }
    local _TT_BUFF_POS = {
        bottom = { "TOPLEFT", "BOTTOMLEFT", "Right", "Down", 0, -2 },
        top    = { "BOTTOMLEFT", "TOPLEFT", "Right", "Up", 0, 2 },
        left   = { "TOPRIGHT", "TOPLEFT", "Left", "Down", -2, 0 },
        right  = { "TOPLEFT", "TOPRIGHT", "Right", "Down", 2, 0 },
    }
    local function _ttBuffsLayout()
        local c = _ttBuffs
        if not c then return end
        local AK = EllesmereUI.AuraKit
        local db = EllesmereUIDB or {}
        if not db.tooltipShowBuffs then
            c:Hide()
            return
        end
        local size = db.tooltipBuffSize or 20
        local perRow = db.tooltipBuffsPerRow or 8
        local p = _TT_BUFF_POS[db.tooltipBuffPosition or "bottom"] or _TT_BUFF_POS.bottom
        local style = AK.styles.ttBuffs
        -- Only a size change restyles, and through the deferred restyle: the
        -- tooltip can be built from tainted code (a unit frame hover) while
        -- auras are secret, when the engine's aura buttons refuse tainted calls,
        -- and the deferred pass holds the restyle until that lifts.
        if style.width ~= size or style.height ~= size then
            style.width, style.height = size, size
            AK.RestyleSoon("ttBuffs")
        end
        c:SetAuraGroupLayout("buffs", { elementWidth = size, elementHeight = size, elementSpacing = 2, lineSpacing = 2 })
        AK.SetContainerRowWidth(c, perRow * size + (perRow - 1) * 2 + 0.4)
        c:ClearAllPoints()
        c:SetPoint(p[1], _GameTooltip, p[2], p[5] + (db.tooltipBuffOffsetX or 0), p[6] + (db.tooltipBuffOffsetY or 0))
        AK.SetContainerAnchor(c, p[1])
        local FD = AnchorUtil.FlowDirection
        AK.SetContainerGrowth(c, FD[p[3]], FD[p[4]])
    end
    EllesmereUI._applyTooltipBuffs = _ttBuffsLayout

    local function _ttShowBuffs(guid, unit)
        local db = EllesmereUIDB
        if not (unit and db and db.tooltipShowBuffs) then return end
        -- Its GameTooltip hooks stand down with the others under the gamepad
        -- interface style.
        if EllesmereUI.BlizzSkinPadStandDown() then return end
        local AK = EllesmereUI.AuraKit
        if not _ttBuffs then
            -- noTooltips: no hover tooltips (they would take over GameTooltip);
            -- AuraKit keeps the buttons mouse-free through every restyle. Built
            -- at the saved size, so the buttons are decorated in the engine's
            -- creation window and the first show needs no restyle.
            local size = db.tooltipBuffSize or 20
            AK.styles.ttBuffs = { width = size, height = size, iconCrop = true, hideDurationText = true,
                noTooltips = true, border = { 0, 0, 0, 1, size = 1 } }
            local c = AK.CreateContainerShell(_GameTooltip, { point = { "TOPLEFT", _GameTooltip, "BOTTOMLEFT" } })
            -- Capped at 16 icons.
            AK.AddGroupToContainer(c, { key = "buffs", filter = { "HELPFUL" }, maxFrameCount = 16,
                style = "ttBuffs",
                layout = { elementWidth = size, elementHeight = size, elementSpacing = 2, lineSpacing = 2 } })
            _ttBuffs = c
            _ttBuffsLayout()
            -- Cleared on every tooltip rebuild; the unit post-call re-shows it for players.
            _GameTooltip:HookScript("OnTooltipCleared", function() c:Hide() end)
            _GameTooltip:HookScript("OnHide", function() _ttBuffsGUID = nil end)
        end
        if guid ~= _ttBuffsGUID or unit ~= _ttBuffsUnit then
            _ttBuffsGUID, _ttBuffsUnit = guid, unit
            _ttBuffs:SetUnit(unit)
            _ttBuffs:UpdateAllAuras()
        end
        _ttBuffs:Show()
    end

    local function _ttUnitColor(tt, data)
        if tt ~= _GameTooltip or tt:IsForbidden() then return end
        local nLinesBefore = tt.NumLines and tt:NumLines() or 0
        -- Identity comes from the tooltip's own SetUnit data pass (data.guid), never the cursor-focus token, so it never lags to the previous frame.
        local guid, unit = _resolveTipIdentity(tt, data)
        -- Record who this render is for (so a late INSPECT_READY can confirm the tooltip still shows this person) and reset the ilvl marker, before any early return.
        _tipShownGUID = guid
        local ttd = GetFFD(tt)
        ttd.ilvlShown = false
        if not guid then return end
        -- Class and plain name from the authoritative GUID, with a live-token fallback. Non-players get no additions (GetPlayerInfoByGUID returns no class for non-player GUIDs, matching stock hover).
        local classFile, pname, prealm
        if GetPlayerInfoByGUID then
            local _, eClass, _, _, _, n, r = GetPlayerInfoByGUID(guid)
            if eClass and not (_isSecret and _isSecret(eClass)) then
                classFile, pname, prealm = eClass, n, r
            end
        end
        if not classFile and unit then
            if not UnitIsPlayer(unit) then
                -- No class additions on non-players, but Targeting still applies (checking a boss's target is the core case).
                _ttTargetLine(tt, unit)
                _ttFonts(tt, nLinesBefore)
                return
            end
            local _, cf = UnitClass(unit)
            if cf and not (_isSecret and _isSecret(cf)) then
                classFile = cf
                pname, prealm = UnitName(unit)
            end
        end
        if not classFile then return end
        if not _nameL1 then _nameL1 = _G.GameTooltipTextLeft1 end
        if not _nameL1 then return end
        local db = EllesmereUIDB
        -- Title hiding is default (tooltipPlayerTitles is opt-in). Rewrite line 1 ONLY when a title is genuinely present, so the no-title case never clobbers foreign line-1 formatting.
        if not (db and db.tooltipPlayerTitles) and pname
            and not (_isSecret and _isSecret(pname)) then
            local display = (prealm and prealm ~= "") and (pname .. "-" .. prealm) or pname
            local cur = _nameL1:GetText()
            -- Line 1 carries a title (or other decoration) when it differs from the plain name.
            -- With a clean token, confirm via UnitPVPName so an equivalent plain-name form is never rewritten; without one (our raid/party frames, secret token, GUID-only) fall back to the name-difference check.
            if cur and not (_isSecret and _isSecret(cur)) and cur ~= display then
                local strip
                if unit and UnitPVPName then
                    local titled = UnitPVPName(unit)
                    strip = titled and not (_isSecret and _isSecret(titled)) and titled ~= pname
                else
                    strip = true
                end
                if strip then _nameL1:SetText(display) end
            end
        end
        -- Recolor only (never replaces text): name line + health bar.
        local cc = _RAID_CC and _RAID_CC[classFile]
        if cc then
            _nameL1:SetTextColor(cc.r, cc.g, cc.b)
            if GameTooltipStatusBar then
                GameTooltipStatusBar:SetStatusBarColor(cc.r, cc.g, cc.b)
            end
        end
        -- Guild rank next to guild name: Name-Realm [Rank]. Re-found every call (index varies
        -- per unit; titles shift it, so a cached index would decorate the wrong row). Deduped like the M+ line against refresh re-runs.
        if unit and db and db.tooltipShowGuildRank then
            local guildName, guildRankName = GetGuildInfo(unit)
            if guildName and guildRankName
                and not (_isSecret and (_isSecret(guildName) or _isSecret(guildRankName))) then
                local suffix = " [" .. guildRankName .. "]"
                for i = 2, nLinesBefore do
                    local line = _G["GameTooltipTextLeft" .. i]
                    local text = line and line:GetText()
                    if text and not (_isSecret and _isSecret(text))
                        and string.find(text, guildName, 1, true) then
                        if text:sub(-#suffix) ~= suffix then
                            line:SetText(text .. suffix)
                        end
                        break
                    end
                end
            end
        end
        -- M+ Score (append-only, deduped against an equivalent foreign line).
        if unit and db and db.tooltipMythicScore ~= false
            and C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary then
            local info = C_PlayerInfo.GetPlayerMythicPlusRatingSummary(unit)
            local score = info and info.currentSeasonScore
            if score and not (_isSecret and _isSecret(score)) and score > 0
                and not _tipHasLine(tt, EllesmereUI.L("M+ Score:")) then
                local sColor = C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor
                    and C_ChallengeMode.GetDungeonScoreRarityColor(score)
                local r, g, b = 1, 1, 1
                if sColor then r, g, b = sColor.r, sColor.g, sColor.b end
                tt:AddDoubleLine(EllesmereUI.L("M+ Score:"), score, 1, 1, 1, r, g, b)
            end
        end
        -- Mount name from the live helpful aura MountJournal recognizes. Opt-in (default off); per-GUID cached so refresh ticks on an unmounted player never re-walk the aura list.
        if unit and guid and db and db.tooltipShowMount and not _tipHasLine(tt, EllesmereUI.L("Mount:")) then
            local mountName, mountCollected
            local cached = _mountCache[guid]
            local now = GetTime()
            if cached and (now - cached.time) < _mountCacheTTL then
                mountName = cached.name
                mountCollected = cached.collected
            else
                local nm, col = _getMountedAuraName(unit)
                mountName = nm or false
                mountCollected = col
                -- Expired entries are dropped, so only the last few seconds of hovers stay
                -- cached and this loop stays tiny; this player's stale entry is refreshed
                -- in place rather than replaced.
                for g, e in pairs(_mountCache) do
                    if e ~= cached and (now - e.time) >= _mountCacheTTL then _mountCache[g] = nil end
                end
                if cached then
                    cached.name, cached.collected, cached.time = mountName, mountCollected, now
                else
                    _mountCache[guid] = { name = mountName, collected = mountCollected, time = now }
                end
            end
            if mountName then
                -- Green check / red X for whether YOU own this mount (nil = unknown, no marker).
                local valText = mountName
                if mountCollected == true then
                    valText = mountName .. " |TInterface\\RaidFrame\\ReadyCheck-Ready:0|t"
                elseif mountCollected == false then
                    valText = mountName .. " |TInterface\\RaidFrame\\ReadyCheck-NotReady:0|t"
                end
                tt:AddDoubleLine(EllesmereUI.L("Mount:"), valText, 1, 1, 1, 1, 1, 1)
            end
        end
        _ttShowBuffs(guid, unit)
        -- Who the hovered player currently targets (opt-in, default off).
        _ttTargetLine(tt, unit)
        -- Item Level. Cache keyed strictly by the authoritative GUID so reads/writes can never land under a different person.
        if db and db.tooltipItemLevel ~= false then
            -- Re-activates after a mid-session toggle back on (login activation is in _ttInitData).
            if not _insp.active then _insp.Activate() end
            local ilvl
            if unit and UnitIsUnit(unit, "player") then
                local _, equipped = GetAverageItemLevel()
                if equipped and equipped > 0 then ilvl = math.floor(equipped) end
            else
                local cached = _ilvlCache[guid]
                if cached and (GetTime() - cached.time) < _ilvlCacheTTL then
                    ilvl = cached.ilvl
                elseif unit then
                    if C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel then
                        local val = C_PaperDollInfo.GetInspectItemLevel(unit)
                        if val and not (_isSecret and _isSecret(val)) and val > 0 then
                            ilvl = math.floor(val)
                            _ilvlCache[guid] = { ilvl = ilvl, time = GetTime() }
                        end
                    end
                    local inspOpen = InspectFrame and InspectFrame:IsShown()
                    if not ilvl and not inspOpen
                        and CanInspect(unit) and not InCombatLockdown() then
                        -- Paced and re-checked there; timed gaps are waited out, not dropped.
                        _requestTooltipInspect(guid)
                    end
                end
            end
            if ilvl and not _tipHasLine(tt, EllesmereUI.L("Item Level")) then
                tt:AddDoubleLine(EllesmereUI.L("Item Level:"), ilvl, 1, 1, 1, 1, 1, 1)
                ttd.ilvlShown = true
            end
        end
        -- Re-apply our font to lines added after OnShow.
        _ttFonts(tt, nLinesBefore)
    end

    -- Visual reskin: dark bg/border (via _ttHook -> _ttSkin), EUI fonts, and restyled status bar. Gated on "Reskin Tooltip" (customTooltips).
    local function _ttInitVisual()
        if EllesmereUI.BlizzSkinPadStandDown() then return end
        for _, tt in ipairs({
            _GameTooltip, ShoppingTooltip1, ShoppingTooltip2,
            ItemRefTooltip, ItemRefShoppingTooltip1, ItemRefShoppingTooltip2,
            FriendsTooltip, EmbeddedItemTooltip, GameSmallHeaderTooltip, QuickKeybindTooltip,
            _G.WarCampaignTooltip, _G.ReputationParagonTooltip,
            _G.LibDBIconTooltip, _G.SettingsTooltip,
            QuestScrollFrame and QuestScrollFrame.StoryTooltip,
            QuestScrollFrame and QuestScrollFrame.CampaignTooltip,
        }) do
            _ttHook(tt)
        end
        if SharedTooltip_SetBackdropStyle then
            -- Deferred: SharedTooltip_SetBackdropStyle can fire from secure Blizzard code
            -- (casting bar, combat UI); a synchronous _ttSkin in the hook would taint the call stack (BackdropTemplate OnLoad propagates to CastingBarFrame).
            hooksecurefunc("SharedTooltip_SetBackdropStyle", function(tt)
                C_Timer.After(0, function() _ttSkin(tt) end)
            end)
        end
        if GameTooltipStatusBar then
            local sbBg = GameTooltipStatusBar:CreateTexture(nil, "BACKGROUND")
            sbBg:SetAllPoints(); sbBg:SetColorTexture(0, 0, 0, 0.5)
            GameTooltipStatusBar:ClearAllPoints()
            GameTooltipStatusBar:SetPoint("BOTTOMLEFT", _GameTooltip, "BOTTOMLEFT", 1, 1)
            GameTooltipStatusBar:SetPoint("BOTTOMRIGHT", _GameTooltip, "BOTTOMRIGHT", -1, 1)
            -- Texture + height (the Show Health Strip cog); unset keeps UI-StatusBar at 3px.
            EllesmereUI._applyTooltipHealthStripStyle(true)
        end
    end

    -- Tooltip DATA additions: class-colored names, player-title control, M+ score,
    -- item level (via _ttUnitColor) and accent spell/macro titles. Each has its own
    -- toggle (tooltipPlayerTitles/tooltipMythicScore/tooltipItemLevel/accentReskinElements),
    -- gated by the customTooltips master (PLAYER_LOGIN calls this only when _enabled()),
    -- so disabling the reskin stops every tooltip option too. Idempotent: safe for the live re-apply path to call again.
    local _ttDataInited = false
    local function _ttInitData()
        EllesmereUI._applyTooltipUnitDetails()
        if _ttDataInited then return end
        _ttDataInited = true
        -- Clear the recorded identity on hide so a late inspect result can never append to a closed/switched tooltip. HookScript (never SetScript) keeps the secure OnHide handler intact.
        if not EllesmereUI.BlizzSkinPadStandDown() then
            _GameTooltip:HookScript("OnHide", function() _tipShownGUID = nil end)
        end
        -- Item level inspect pacing starts at login, so the request history from other
        -- addons is already being tracked before the first hover.
        if not EllesmereUIDB or EllesmereUIDB.tooltipItemLevel ~= false then _insp.Activate() end
        -- Accent-color the title line for spells/macros (not items or units)
        local function _ttAccentTitle(tt)
            if tt ~= _GameTooltip or tt:IsForbidden() or not _accentEnabled() then return end
            if not _nameL1 then _nameL1 = _G.GameTooltipTextLeft1 end
            if _nameL1 then
                local r,g,b=_getElementColor(); _nameL1:SetTextColor(r,g,b)
            end
        end
        if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, _ttUnitColor)
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, _ttAccentTitle)
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Macro, _ttAccentTitle)
        else
            _GameTooltip:HookScript("OnTooltipSetUnit", _ttUnitColor)
            _GameTooltip:HookScript("OnTooltipSetSpell", _ttAccentTitle)
        end
    end

    -- Back-compat full init (data + visual), used by the live re-apply path.
    local function _ttInit() _ttInitData(); _ttInitVisual() end

    -- Context menu skinning. Deliberately NOT memoised per frame: menu frames are
    -- pooled, so Blizzard hands the same frame back for the next menu and rebuilds
    -- its textures from the new description, silently undoing our background --
    -- an "already skinned" flag would skip reuse and leave Blizzard's background
    -- under our border. _menuSkinFrame is idempotent (skips owned regions,
    -- re-anchors relative to the frame, nothing accumulates), so running every pass self-heals reuse.

    local function _menuSkinFrame(frame)
        if not frame or frame:IsForbidden() or not _pmEnabled() then return end
        for i = 1, _select("#", frame:GetRegions()) do
            local region = _select(i, frame:GetRegions())
            if region and region:IsObjectType("Texture") and not GetFFD(region).owned then
                local RS = EllesmereUI.RESKIN
                region:SetColorTexture(RS.BG_R, RS.BG_G, RS.BG_B, 1)
                region:SetAlpha(RS.CTX_ALPHA)
                region:ClearAllPoints()
                region:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
                region:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
            end
        end
        _applyConfiguredBorder(frame, "popupMenu", 1)
    end

    local function _menuOnOpen(manager, _, menuDescription)
        if not _pmEnabled() then return end
        -- Defer out of the secure context: this post-hook runs inside Blizzard's
        -- protected menu pipeline, so touching Blizzard objects here taints action bar buttons.
        --
        -- NEVER use menuDescription:AddMenuAcquiredCallback(): deferring the REGISTRATION
        -- doesn't help -- it plants an insecure Lua function that Blizzard itself CALLS
        -- from its pipeline, tainting the pipeline that builds the menu AND owns entry
        -- click handlers. Observed failure: right-click Whisper opened the chat edit box
        -- with a SECRET target name; the tainted ChatFrameUtil.OpenChat write made
        -- Blizzard's own ChatFrameEditBoxMixin:OnUpdate refuse SetText every frame (the terminating setText=0 never ran).
        --
        -- Self-owned staggered passes instead: fetch the menu frame from the manager and
        -- skin it ourselves, handing Blizzard nothing. Extra passes cover submenus and pooled frames acquired shortly after open.
        local function skinOpenMenu()
            local menu = manager.GetOpenMenu and manager:GetOpenMenu()
            if menu then
                _menuSkinFrame(menu)
            end
        end
        C_Timer.After(0, skinOpenMenu)
        C_Timer.After(0.05, skinOpenMenu)
        C_Timer.After(0.15, skinOpenMenu)
    end

    -- Submenu coverage via the style mixin. The manager hooks above only ever
    -- see the ROOT menu: GetOpenMenu returns the root even during a flyout, a
    -- submenu frame is a parentless SIBLING of the root, and hovering a submenu
    -- parent fires neither OpenMenu nor OpenContextMenu. Blizzard instead styles
    -- every menu level through one code path (Menu.lua, MenuManagerMixin:AcquireMenu ->
    -- SecureGenerate: Mixin(proxy, menuDescription:GetMenuMixin()); proxy:Generate()).
    -- GetMenuMixin() resolves to the GLOBAL MenuStyle1Mixin (MenuStyle2Mixin for
    -- WowStyle2), and the Mixin() copy happens at every open, so a hooksecurefunc
    -- on the mixin's Generate is copied onto each menu frame and hands us that
    -- exact frame as self -- root and every flyout, no frame ID needed.
    --
    -- NOT the AddMenuAcquiredCallback mistake: that callback is an insecure closure
    -- invoked BARE (Menu.lua 2354, no securecallfunction) in the same execution that
    -- builds entry click handlers. Here containment is double: hooksecurefunc's contract keeps
    -- hook taint from propagating into the calling execution (so the Mixin() copy
    -- stays secure), and Blizzard wraps this call site in securecallfunction because
    -- addon-supplied menu mixins are an anticipated input (see MenuUtil.lua's
    -- GetDefaultContextMenuMixin override). NEVER ASSIGN into the mixin table
    -- (plants a tainted function) -- hooksecurefunc only.
    --
    -- The hook only collects and schedules; skinning runs from our own timer after
    -- the secure execution finishes. While a menu is open the compositor replaces
    -- the frame's metatable and disallows CreateTexture/CreateFontString/CreateLine,
    -- so only the EXISTING background region may be recoloured -- already how _menuSkinFrame operates.
    local _stylePending, _styleArmed = {}, false
    local function _styleFlush()
        _styleArmed = false
        for i = #_stylePending, 1, -1 do
            local f = _stylePending[i]
            _stylePending[i] = nil
            -- _menuSkinFrame re-checks IsForbidden and the enable toggle.
            _menuSkinFrame(f)
        end
    end
    local function _onStyleGenerate(menuFrame)
        _stylePending[#_stylePending + 1] = menuFrame
        if not _styleArmed then
            _styleArmed = true
            C_Timer.After(0, _styleFlush)
        end
    end

    local function _menuInit()
        if not _G.Menu or not _G.Menu.GetManager then return end
        local mgr = _G.Menu.GetManager()
        if not mgr then return end
        hooksecurefunc(mgr, "OpenMenu", function(self, ownerRegion, menuDescription)
            _menuOnOpen(self, ownerRegion, menuDescription)
        end)
        hooksecurefunc(mgr, "OpenContextMenu", function(self, ownerRegion, menuDescription)
            _menuOnOpen(self, ownerRegion, menuDescription)
        end)
        if _G.MenuStyle1Mixin and type(_G.MenuStyle1Mixin.Generate) == "function" then
            hooksecurefunc(_G.MenuStyle1Mixin, "Generate", _onStyleGenerate)
        end
        if _G.MenuStyle2Mixin and type(_G.MenuStyle2Mixin.Generate) == "function" then
            hooksecurefunc(_G.MenuStyle2Mixin, "Generate", _onStyleGenerate)
        end
    end

    local function _popupSkin(popup)
        if not popup or popup:IsForbidden() then return end
        if not _pmEnabled() then return end
        for i = 1, _select("#", popup:GetRegions()) do
            local r = _select(i, popup:GetRegions())
            if r and r:IsObjectType("Texture") and not GetFFD(r).owned then
                r:SetTexture(nil)
                if r.SetAtlas then r:SetAtlas("") end
            end
        end
        if popup.BG then popup.BG:SetAlpha(0) end
        if popup.NineSlice then popup.NineSlice:SetAlpha(0) end
        if not GetFFD(popup).bg then
            local RS = EllesmereUI.RESKIN
            GetFFD(popup).bg = popup:CreateTexture(nil, "BACKGROUND", nil, -8)
            GetFFD(popup).bg:SetAllPoints()
            GetFFD(popup).bg:SetColorTexture(RS.BG_R, RS.BG_G, RS.BG_B, RS.QT_ALPHA)
            GetFFD(GetFFD(popup).bg).owned = true
            if not _PP then _PP = EllesmereUI and EllesmereUI.PP end
            if _PP and _PP.CreateBorder then
                _PP.CreateBorder(popup, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
            end
        end
        GetFFD(popup).bg:Show()
        _applyConfiguredBorder(popup, "popupMenu", 1)
        local popupBtns = {}
        for i = 1, 4 do
            popupBtns[#popupBtns + 1] = popup["button" .. i]
                or _G[popup:GetName() and (popup:GetName() .. "Button" .. i)]
        end
        local popupName = popup.GetName and popup:GetName()
        popupBtns[#popupBtns + 1] = popup.extraButton
            or (popupName and _G[popupName .. "ExtraButton"])
        for _, btn in ipairs(popupBtns) do
            if btn and not GetFFD(btn).skinned then
                GetFFD(btn).skinned = true
                local regions = { btn:GetRegions() }
                for j = 1, #regions do
                    local r = regions[j]
                    if r and r:IsObjectType("Texture") and r ~= btn:GetFontString() then
                        r:SetTexture(nil)
                        if r.SetAtlas then r:SetAtlas("") end
                    end
                end
                local btnBg = btn:CreateTexture(nil, "BACKGROUND", nil, -6)
                btnBg:SetAllPoints()
                GetFFD(btnBg).owned = true
                GetFFD(btn).bg = btnBg
                -- 10% white wash; the HIGHLIGHT layer only renders while the button is enabled and hovered.
                local hov = btn:CreateTexture(nil, "HIGHLIGHT")
                hov:SetColorTexture(1, 1, 1, 0.1)
                hov:SetAllPoints()
                GetFFD(hov).owned = true

                -- Mirror Blizzard's enabled/disabled state so buttons visibly dim when locked out (e.g. Release in boss combat).
                local function _euiRefreshEnabled(self)
                    local fs = self:GetFontString()
                    local enabled = (self.IsEnabled and self:IsEnabled()) and true or false
                    if fs then
                        if enabled then
                            -- Native mode enabled color is white.
                            if _elementColorMode() == "native" then
                                fs:SetTextColor(1, 1, 1, 1)
                            else
                                local r, g, b = _getElementColor()
                                fs:SetTextColor(r, g, b, 1)
                            end
                        else
                            fs:SetTextColor(0.4, 0.4, 0.4, 1)
                        end
                    end
                    if GetFFD(self).bg then
                        GetFFD(self).bg:SetAlpha(enabled and 1 or 0.5)
                    end
                end
                GetFFD(btn).refreshEnabled = _euiRefreshEnabled
                btn:HookScript("OnEnable",  _euiRefreshEnabled)
                btn:HookScript("OnDisable", _euiRefreshEnabled)
                _euiRefreshEnabled(btn)
            end
            if btn then
                local c = EllesmereUIDB and EllesmereUIDB.popupMenuButtonBackgroundColor or { r=.1,g=.1,b=.1,a=.8 }
                if GetFFD(btn).bg then GetFFD(btn).bg:SetColorTexture(c.r, c.g, c.b, c.a == nil and .8 or c.a) end
                _applyConfiguredBorder(btn, "popupMenuButton", 1)
            end
        end

        -- Hook UpdateRecapButton once per popup to keep our per-button enabled visual in sync with Blizzard's enable/disable swaps.
        if popup.UpdateRecapButton and not GetFFD(popup).recapHooked then
            GetFFD(popup).recapHooked = true
            hooksecurefunc(popup, "UpdateRecapButton", function(self)
                for i = 1, 4 do
                    local b = self["button" .. i]
                    local fn = b and GetFFD(b).refreshEnabled
                    if fn then fn(b) end
                end
            end)
        end

        -- Re-sync state for popups shown already-disabled
        for i = 1, 4 do
            local b = popup["button" .. i]
            local fn = b and GetFFD(b).refreshEnabled
            if fn then fn(b) end
        end
        local eb = popup.editBox or (popup.GetName and _G[popup:GetName() .. "EditBox"])
        if eb and not GetFFD(eb).skinned then
            GetFFD(eb).skinned = true
            local regions = { eb:GetRegions() }
            for j = 1, #regions do
                local r = regions[j]
                if r and r:IsObjectType("Texture") then
                    r:SetTexture(nil)
                    if r.SetAtlas then r:SetAtlas("") end
                end
            end
            -- Midnight edit boxes carry their art on a NineSlice child.
            if eb.NineSlice and eb.NineSlice.SetAlpha then
                eb.NineSlice:SetAlpha(0)
            end
            -- 6px left padding: box edge extends, text stays put.
            if EllesmereUI._WSkinPadInput then EllesmereUI._WSkinPadInput(eb) end
            local ebBg = eb:CreateTexture(nil, "BACKGROUND", nil, -6)
            ebBg:SetAllPoints()
            ebBg:SetColorTexture(0.05, 0.05, 0.05, 0.9)
            GetFFD(ebBg).owned = true
            -- Border matching the popup buttons: accent, or white in native.
            local borderR, borderG, borderB = 1, 1, 1
            if _elementColorMode() ~= "native" then
                borderR, borderG, borderB = _getElementColor()
            end
            if not _PP then _PP = EllesmereUI and EllesmereUI.PP end
            if _PP and _PP.CreateBorder then
                _PP.CreateBorder(eb, borderR, borderG, borderB, 0.5, 1, "OVERLAY", 7)
            end
        end
    end

    local function _popupInit()
        if EllesmereUI.BlizzSkinPadStandDown() then return end
        for i = 1, STATICPOPUP_NUMDIALOGS or 4 do
            local popup = _G["StaticPopup" .. i]
            if popup then
                popup:HookScript("OnShow", function(self) _popupSkin(self) end)
            end
        end
    end

    ---------------------------------------------------------------------------
    --  Resurrect Accept Glow (resurrectAcceptGlow, default OFF)
    --  Pulsating border around button1 of the RESURRECT StaticPopups. Runs only
    --  while reskinPopupsMenus is on too (its options row greys out under it).
    --  Zero cost until first enable: no hooks or frames exist before then. The
    --  overlay is our own frame (state in FFD); the pulse is a C-side Alpha AnimationGroup, so no per-frame Lua.
    ---------------------------------------------------------------------------
    local RES_WHICH = {
        RESURRECT             = true,
        RESURRECT_NO_SICKNESS = true,
        RESURRECT_NO_TIMER    = true,
    }
    local _resGlowHooked = false

    local function _resGlowEnabled()
        local db = EllesmereUIDB
        return db and db.resurrectAcceptGlow and db.reskinPopupsMenus ~= false or false
    end

    local function _resGlowButton(popup)
        return popup.button1
            or (popup.GetName and popup:GetName() and _G[popup:GetName() .. "Button1"])
    end

    -- Addon-owned overlay 3px outside the button, built once per button on first glow; state lives in FFD, never on the Blizzard frame.
    local function _resGlowGet(btn)
        local d = GetFFD(btn)
        if not d.resGlow then
            local ov = CreateFrame("Frame", nil, btn)
            ov:SetPoint("TOPLEFT", btn, "TOPLEFT", -3, 3)
            ov:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 3, -3)
            ov:SetFrameLevel(btn:GetFrameLevel() + 5)
            ov:Hide()
            if not _PP then _PP = EllesmereUI and EllesmereUI.PP end
            if _PP and _PP.CreateBorder then
                _PP.CreateBorder(ov, 1, 1, 1, 1, 2, "OVERLAY", 7)
            end
            local ag = ov:CreateAnimationGroup()
            ag:SetLooping("BOUNCE")
            local pulse = ag:CreateAnimation("Alpha")
            pulse:SetFromAlpha(1); pulse:SetToAlpha(0.15)
            pulse:SetDuration(0.7); pulse:SetSmoothing("IN_OUT")
            d.resGlow = ov
            d.resGlowAG = ag
        end
        return d.resGlow, d.resGlowAG
    end

    local function _resGlowStart(btn)
        local ov, ag = _resGlowGet(btn)
        if not ov then return end
        -- Color resolved every start so re-shows follow the current element color setting (same source as the popup skin).
        local EG = EllesmereUI.ELLESMERE_GREEN
        if _PP and _PP.SetBorderColor then
            if _accentEnabled() and EG then
                _PP.SetBorderColor(ov, EG.r, EG.g, EG.b, 1)
            else
                _PP.SetBorderColor(ov, 1, 1, 1, 1)
            end
        end
        ov:SetAlpha(1)
        ov:Show()
        if ag and not ag:IsPlaying() then ag:Play() end
    end

    -- Raw FFD read (not GetFFD): stopping must never allocate state for a button that never glowed.
    local function _resGlowStop(btn)
        local d = btn and FFD[btn]
        local ov = d and d.resGlow
        if ov then
            if d.resGlowAG then d.resGlowAG:Stop() end
            ov:Hide()
        end
    end

    local function _resGlowRefresh(popup)
        local btn = _resGlowButton(popup)
        if not btn then return end
        if _resGlowEnabled() and RES_WHICH[popup.which] and popup:IsShown() then
            _resGlowStart(btn)
        else
            _resGlowStop(btn)
        end
    end

    local function _resGlowRefreshAll()
        for i = 1, STATICPOPUP_NUMDIALOGS or 4 do
            local popup = _G["StaticPopup" .. i]
            if popup and not popup:IsForbidden() then _resGlowRefresh(popup) end
        end
    end

    -- Install OnShow/OnHide hooks once. Hooks cannot be uninstalled, so they self-gate (OnShow early-returns when off, OnHide is a raw weak-table lookup); never called before the first enable.
    local function _resGlowInit()
        if _resGlowHooked or EllesmereUI.BlizzSkinPadStandDown() then return end
        _resGlowHooked = true
        for i = 1, STATICPOPUP_NUMDIALOGS or 4 do
            local popup = _G["StaticPopup" .. i]
            if popup then
                popup:HookScript("OnShow", function(self)
                    if not _resGlowEnabled() then return end
                    _resGlowRefresh(self)
                end)
                popup:HookScript("OnHide", function(self)
                    _resGlowStop(_resGlowButton(self))
                end)
            end
        end
    end

    -- Options-panel entry point: installs hooks on first enable and syncs visible popups on any flip, so no reload is needed.
    EllesmereUI._EnsureResurrectGlow = function()
        if _resGlowEnabled() then _resGlowInit() end
        if _resGlowHooked then _resGlowRefreshAll() end
    end

    do
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_LOGIN")
        f:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            -- customTooltips is the master for ALL EUI tooltip handling (visual reskin
            -- AND data additions); off leaves tooltips alone, matching the grayed-out
            -- options. Context menu/static popup reskins (reskinPopupsMenus) and
            -- per-window reskins use their own keys, seeded from the old master once by the
            -- blizzskin_reskin_master_split_v1 migration at parent ADDON_LOADED.
            if _enabled() then
                _ttInitData()
                _ttInitVisual()
            end
            if EllesmereUI.SyncAuraTooltipSkin then EllesmereUI.SyncAuraTooltipSkin() end
            if _pmEnabled() then
                _menuInit()
                _popupInit()
            end
            -- Independent of both reskin masters. Default OFF; disabled users pay only this boolean check (no hooks, no frames).
            if _resGlowEnabled() then
                _resGlowInit()
            end
        end)
    end
    EllesmereUI._initTooltipSkins = function() _ttInit(); _menuInit(); _popupInit() end

    -- Mirror the tooltip skin onto the ENGINE aura tooltip (AuraButtonTooltip,
    -- the forbidden GameTooltip clone every aura container button uses -- addon
    -- hooks can never touch it directly). Build 68914 exposes global styling entry
    -- points for it: resolved DEFENSIVELY (public-env reachability is a field-verify
    -- item) and pcall'd throughout. Applied at login and from tooltip-skin setters; skin off restores the engine default style.
    function EllesmereUI.SyncAuraTooltipSkin()
        local inb = _G.AuraContainerInbound
        if not inb then return end
        if _enabled() then
            if not inb.SetTooltipBackdrop then return end
            local cr, cg, cb, ca = EllesmereUI.GetTooltipBg()
            local br, bgc, bb, ba, size = EllesmereUI.GetTooltipBorder()
            local info = {
                backdropInfo = {
                    bgFile = "Interface\\Buttons\\WHITE8X8",
                    insets = { left = 0, right = 0, top = 0, bottom = 0 },
                },
                centerColor = CreateColor(cr or 0, cg or 0, cb or 0, ca or 0.9),
            }
            if (size or 0) > 0 then
                info.backdropInfo.edgeFile = "Interface\\Buttons\\WHITE8X8"
                info.backdropInfo.edgeSize = size
                info.borderColor = CreateColor(br or 0, bgc or 0, bb or 0, ba or 1)
            end
            pcall(inb.SetTooltipBackdrop, info)
        elseif inb.ResetTooltipStyle then
            pcall(inb.ResetTooltipStyle)
        end
    end

    ---------------------------------------------------------------------------
    --  LFG Queue Accept Popup: reskin + countdown timer bar
    --  Skins LFGDungeonReadyPopup the same way we skin StaticPopups, and
    --  adds an accent-colored countdown bar below the popup.
    ---------------------------------------------------------------------------
    do
        local TIMER_DURATION = 40
        local timerBar, timerText, timerEndTime

        -- Independent toggle, default on: this is a popup, not a window, so no master reskin setting (including window-skins style) governs it.
        local function IsQueueReskinOn()
            return not EllesmereUIDB or EllesmereUIDB.reskinQueuePopup ~= false
        end

        -- popup/dialog/closeBtn default to the LFG dungeon trio. The params
        -- exist so a caller can pass a different popup/dialog pair; PvP support
        -- was built on that and then SCRAPPED by maintainer call, so the LFG popup
        -- is currently the only caller and the defaults are always used.
        local function SkinQueuePopup(popup, dialog, closeBtn)
            popup = popup or LFGDungeonReadyPopup
            if not popup then return end

            -- Strip Blizzard border/decoration on popup and dialog, preserving dialog.background (the dungeon art image).
            dialog = dialog or LFGDungeonReadyDialog
            local keepTextures = {}
            if dialog and dialog.background then keepTextures[dialog.background] = true end
            if dialog and dialog.bottomArt then keepTextures[dialog.bottomArt] = true end
            -- Kept, but KNOCKED BACK. The dungeon art is dim and atmospheric so
            -- it sat behind the skin fine; the arena/BG art is bright and busy
            -- and fought it. Dimming keeps every queue type consistent (they all
            -- still show their own art) while letting the dark skin dominate.
            -- Re-applied every show: Blizzard re-sets the texture per pop.
            for _, frame in ipairs({ popup, dialog }) do
                if frame then
                    for i = 1, _select("#", frame:GetRegions()) do
                        local r = _select(i, frame:GetRegions())
                        if r and r:IsObjectType("Texture") and not GetFFD(r).owned and not keepTextures[r] then
                            r:SetTexture(nil)
                            if r.SetAtlas then r:SetAtlas("") end
                        end
                    end
                    if frame.BG then frame.BG:SetAlpha(0) end
                    if frame.NineSlice then frame.NineSlice:SetAlpha(0) end
                    if frame.Border then frame.Border:SetAlpha(0) end
                end
            end

            closeBtn = closeBtn or _G.LFGDungeonReadyDialogCloseButton
            if closeBtn then
                for i = 1, _select("#", closeBtn:GetRegions()) do
                    local r = _select(i, closeBtn:GetRegions())
                    if r and r:IsObjectType("Texture") and not GetFFD(r).owned then
                        r:SetAlpha(0)
                    end
                end
                if not GetFFD(closeBtn).icon then
                    local icoW, icoH = closeBtn:GetSize()
                    local ico = closeBtn:CreateTexture(nil, "OVERLAY", nil, 7)
                    ico:SetSize((icoW or 16) - 2, (icoH or 16) - 2)
                    ico:SetPoint("CENTER", closeBtn, "CENTER", -4, 4)
                    ico:SetAtlas("UI-QuestTrackerButton-Secondary-Collapse-Pressed")
                    GetFFD(ico).owned = true
                    GetFFD(closeBtn).icon = ico
                end
                GetFFD(closeBtn).icon:Show()
            end

            -- Our dark background + border (create once), anchored to the dialog (not the popup wrapper) so the skin follows if a mover addon drags LFGDungeonReadyDialog independently.
            if not GetFFD(popup).bg then
                local RS = EllesmereUI.RESKIN
                if not _PP then _PP = EllesmereUI and EllesmereUI.PP end
                local anchor = dialog or popup
                -- SIBLING, not a child. A child frame draws ABOVE its parent's
                -- own texture regions even at the same frame level, and
                -- genuinely went below it and this was invisible there.)
                --
                -- Parented to the dialog's own parent and one level down, it is
                -- a true sibling and draws underneath.
                local bgFrame = CreateFrame("Frame", nil, anchor)
                bgFrame:SetAllPoints(anchor)
                bgFrame:SetFrameLevel(math.max(1, anchor:GetFrameLevel() - 1))
                -- VISIBILITY MUST BE TIED MANUALLY. As a child of the dialog it
                -- inherited hide for free; as a SIBLING (which is what makes it
                -- draw below their art) it does not, so it survived the dialog
                -- closing and left a black box -- with the timer bar, which is
                -- parented to it, still ticking inside.
                GetFFD(popup).bgFrame = bgFrame
                GetFFD(popup).bg = bgFrame:CreateTexture(nil, "ARTWORK")
                GetFFD(popup).bg:SetAllPoints()
                GetFFD(popup).bg:SetColorTexture(RS.BG_R, RS.BG_G, RS.BG_B, RS.QT_ALPHA)
                GetFFD(GetFFD(popup).bg).owned = true
            end
            _applyConfiguredBorder(GetFFD(popup).bgFrame, "popupMenu", 1)

            -- Enter Dungeon / Leave Queue. Textures are re-stripped every show (Blizzard re-applies art per popup); bg/border created once.
            if dialog then
                for _, btnName in ipairs({ "enterButton", "leaveButton" }) do
                    local btn = dialog[btnName]
                    if btn then
                        -- Named Left/Middle/Right textures are swapped by C++ on mouse down, so SetTexture alone does not stick.
                        local regions = { btn:GetRegions() }
                        for j = 1, #regions do
                            local r = regions[j]
                            if r and r:IsObjectType("Texture") and not GetFFD(r).owned and r ~= btn:GetFontString() then
                                r:SetAlpha(0)
                            end
                        end
                        if btn.Left then btn.Left:SetAlpha(0) end
                        if btn.Middle then btn.Middle:SetAlpha(0) end
                        if btn.Right then btn.Right:SetAlpha(0) end
                        if not GetFFD(btn).skinned then
                            GetFFD(btn).skinned = true
                            -- Hook SetAlpha on the named textures so C++ press state changes cannot make them visible again.
                            for _, texKey in ipairs({ "Left", "Middle", "Right" }) do
                                local tex = btn[texKey]
                                if tex and tex.SetAlpha then
                                    hooksecurefunc(tex, "SetAlpha", function(self, a)
                                        if a > 0 then self:SetAlpha(0) end
                                    end)
                                end
                            end
                            local EG = EllesmereUI.ELLESMERE_GREEN
                            local useAccent = _accentEnabled() and EG
                            local RS2 = EllesmereUI.RESKIN
                            local btnBg = btn:CreateTexture(nil, "BACKGROUND", nil, -6)
                            btnBg:SetAllPoints()
                            GetFFD(btnBg).owned = true
                            GetFFD(btn).bg = btnBg
                            -- 10% white wash; marked owned so the every-show re-strip above leaves it alone.
                            local hov = btn:CreateTexture(nil, "HIGHLIGHT")
                            hov:SetColorTexture(1, 1, 1, 0.1)
                            hov:SetAllPoints()
                            GetFFD(hov).owned = true
                        end
                        -- Colors re-applied every show.
                        local c = EllesmereUIDB and EllesmereUIDB.popupMenuButtonBackgroundColor or { r=.1,g=.1,b=.1,a=.8 }
                        if GetFFD(btn).bg then GetFFD(btn).bg:SetColorTexture(c.r,c.g,c.b,c.a == nil and .8 or c.a) end
                        _applyConfiguredBorder(btn, "popupMenuButton", 1)
                        local fs = btn:GetFontString()
                        if fs then
                            -- Native mode text is plain white.
                            if _elementColorMode() == "native" then
                                fs:SetTextColor(1, 1, 1, 1)
                            else
                                local r, g, b = _getElementColor()
                                fs:SetTextColor(r, g, b, 1)
                            end
                        end
                    end
                end
            end
        end

        local timerBorder, timerBg

        -- True once the user has touched ANY Queue Timer Style setting. Gates the
        -- unified style below off the Blizzard-style branch: reskin-off users chose
        -- the stock look, so an untouched profile keeps the legacy rendering
        -- byte-identically; the first setting they touch activates the unified
        -- style in both modes (and a section reset returns them to legacy).
        local function QueueTimerCustomized()
            local db = EllesmereUIDB
            return (db and (db.queueTimerTextColor ~= nil or db.queueTimerTextSize ~= nil
                or db.queueTimerBarHeight ~= nil or db.queueTimerTextOffsetY ~= nil))
                and true or false
        end

        -- Applied after either style branch, so the look holds with the reskin on or off.
        local function ApplyTimerStyle()
            if not timerBar then return end
            if GetFFD(timerBar).style == false and not QueueTimerCustomized() then
                -- Legacy stock rendering, exactly as before the style controls existed.
                timerText:SetFontObject("GameFontHighlight")
                timerText:ClearAllPoints()
                timerText:SetPoint("CENTER", timerBar, "CENTER", 0, 0)
                timerBar:SetHeight(9)
                return
            end
            local db = EllesmereUIDB or {}
            local QT = EllesmereUI.QUEUE_TIMER
            local c = db.queueTimerTextColor
            local fontPath = (EllesmereUI.GetFontPath("extras"))
                or "Fonts\\FRIZQT__.TTF"
            EllesmereUI.PrimeFontShadow(timerText, true)
            timerText:SetFont(fontPath, db.queueTimerTextSize or QT.TEXT_SIZE, "")
            timerText:SetTextColor((c and c.r) or QT.TEXT_R, (c and c.g) or QT.TEXT_G,
                (c and c.b) or QT.TEXT_B, 1)
            timerText:ClearAllPoints()
            timerText:SetPoint("CENTER", timerBar, "CENTER", 0,
                db.queueTimerTextOffsetY or QT.TEXT_OFFSET_Y)
            timerBar:SetHeight(db.queueTimerBarHeight or QT.BAR_HEIGHT)
        end
        EllesmereUI.RefreshQueueTimerStyle = ApplyTimerStyle

        local function ShowQueueTimer(useEuiStyle)
            local popup = LFGDungeonReadyPopup
            if not popup then return end

            if not timerBar then
                local timerParent = GetFFD(popup).bgFrame or popup
                timerBar = CreateFrame("StatusBar", nil, timerParent)
                timerBar:SetMinMaxValues(0, TIMER_DURATION)

                timerBg = timerBar:CreateTexture(nil, "BACKGROUND")
                timerBg:SetAllPoints()
                timerBg:SetColorTexture(0, 0, 0, 0.7)

                -- Blizzard-style casting bar border (hidden in EUI style).
                timerBorder = timerBar:CreateTexture(nil, "OVERLAY")
                timerBorder:SetTexture(130874)
                timerBorder:SetSize(256, 64)
                timerBorder:SetPoint("TOP", timerBar, 0, 28)

                timerText = timerBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")

                EllesmereUI.RegAccent({ type = "callback", fn = function()
                    if GetFFD(timerBar).style then
                        local r, g, b = EllesmereUI.GetAccentColor()
                        timerBar:SetStatusBarColor(r, g, b, 0.75)
                    end
                end })
            end

            -- Anchor to the dialog, not the popup wrapper, so the timer follows it when a mover addon drags the dialog independently.
            local dialog = LFGDungeonReadyDialog
            local anchorFrame = dialog or popup

            -- The bar's parent sits a level below the dialog so its backdrop draws under the dialog art; a raised countdown must not.
            timerBar:SetFrameLevel(anchorFrame:GetFrameLevel() + 5)

            timerBar:ClearAllPoints()
            if useEuiStyle then
                timerBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
                local mult = (_PP and _PP.mult) or 1
                timerBar:SetPoint("BOTTOMLEFT", anchorFrame, "BOTTOMLEFT", mult, mult)
                timerBar:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMRIGHT", -mult, mult)
                local ar, ag, ab = EllesmereUI.GetAccentColor()
                timerBar:SetStatusBarColor(ar, ag, ab, 0.75)
                timerBg:SetColorTexture(0, 0, 0, 0.5)
                timerBorder:Hide()
                timerBg:Show()
                GetFFD(timerBar).style = true
            else
                -- Blizzard style: stock bar texture + casting-bar border art.
                timerBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
                timerBar:SetPoint("TOP", anchorFrame, "BOTTOM", 0, -5)
                timerBar:SetWidth(190)
                timerBar:SetStatusBarColor(1, 0.1, 0)
                timerBorder:Show()
                timerBg:Show()
                GetFFD(timerBar).style = false
            end

            ApplyTimerStyle()

            -- Hide any other addon's timer bar parented to the popup.
            for _, child in ipairs({ popup:GetChildren() }) do
                if child ~= timerBar and child.GetObjectType
                   and child:GetObjectType() == "StatusBar" then
                    child:Hide()
                end
            end

            timerEndTime = GetTime() + TIMER_DURATION
            timerBar:SetValue(TIMER_DURATION)
            timerText:SetText(format("%d", TIMER_DURATION))
            timerBar:Show()

            timerBar:SetScript("OnUpdate", function(self)
                local remaining = timerEndTime - GetTime()
                if remaining <= 0 then
                    self:SetScript("OnUpdate", nil)
                    self:Hide()
                    return
                end
                self:SetValue(remaining)
                timerText:SetText(format("%d", math.ceil(remaining)))
            end)
        end

        -- The "queue missed" / role check status popup.
        local function SkinQueueStatus()
            local status = _G.LFGDungeonReadyStatus
            if not status or not IsQueueReskinOn() then return end
            -- Textures re-stripped every show.
            for i = 1, _select("#", status:GetRegions()) do
                local r = _select(i, status:GetRegions())
                if r and r:IsObjectType("Texture") and not GetFFD(r).owned then
                    r:SetTexture(nil)
                    if r.SetAtlas then r:SetAtlas("") end
                end
            end
            if status.BG then status.BG:SetAlpha(0) end
            if status.NineSlice then status.NineSlice:SetAlpha(0) end
            if status.Border then status.Border:SetAlpha(0) end
            if not GetFFD(status).bg then
                local RS = EllesmereUI.RESKIN
                GetFFD(status).bg = status:CreateTexture(nil, "BACKGROUND", nil, -8)
                GetFFD(status).bg:SetAllPoints()
                GetFFD(status).bg:SetColorTexture(RS.BG_R, RS.BG_G, RS.BG_B, RS.QT_ALPHA)
                GetFFD(GetFFD(status).bg).owned = true
                if not _PP then _PP = EllesmereUI and EllesmereUI.PP end
                if _PP and _PP.CreateBorder then
                    _PP.CreateBorder(status, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
                end
            end
        end

        -- Hook OnShow so the skin applies the moment the acceptance panel appears, before any specific event fires.
        local _statusHooked = false
        local function HookStatusOnShow()
            if _statusHooked or EllesmereUI.BlizzSkinPadStandDown() then return end
            local status = _G.LFGDungeonReadyStatus
            if not status then return end
            _statusHooked = true
            status:HookScript("OnShow", function() SkinQueueStatus() end)
        end

        -- Accept/Decline both inherit stock UIPanelButtonTemplate and were never
        -- touched, same treatment as SkinQueuePopup's enterButton/leaveButton.
        local function SkinRoleCheckButton(btn)
            if not btn then return end
            local regions = { btn:GetRegions() }
            for j = 1, #regions do
                local r = regions[j]
                if r and r:IsObjectType("Texture") and not GetFFD(r).owned and r ~= btn:GetFontString() then
                    r:SetAlpha(0)
                end
            end
            if btn.Left then btn.Left:SetAlpha(0) end
            if btn.Middle then btn.Middle:SetAlpha(0) end
            if btn.Right then btn.Right:SetAlpha(0) end
            if not GetFFD(btn).skinned then
                GetFFD(btn).skinned = true
                for _, texKey in ipairs({ "Left", "Middle", "Right" }) do
                    local tex = btn[texKey]
                    if tex and tex.SetAlpha then
                        hooksecurefunc(tex, "SetAlpha", function(self, a)
                            if a > 0 then self:SetAlpha(0) end
                        end)
                    end
                end
                local btnBg = btn:CreateTexture(nil, "BACKGROUND", nil, -6)
                btnBg:SetAllPoints()
                GetFFD(btnBg).owned = true
                GetFFD(btn).bg = btnBg
                local hov = btn:CreateTexture(nil, "HIGHLIGHT")
                hov:SetColorTexture(1, 1, 1, 0.1)
                hov:SetAllPoints()
                GetFFD(hov).owned = true
            end
            local c = EllesmereUIDB and EllesmereUIDB.popupMenuButtonBackgroundColor or { r=.1,g=.1,b=.1,a=.8 }
            if GetFFD(btn).bg then GetFFD(btn).bg:SetColorTexture(c.r,c.g,c.b,c.a == nil and .8 or c.a) end
            _applyConfiguredBorder(btn, "popupMenuButton", 1)
            local fs = btn:GetFontString()
            if fs then
                if _elementColorMode() == "native" then
                    fs:SetTextColor(1, 1, 1, 1)
                else
                    local r, g, b = _getElementColor()
                    fs:SetTextColor(r, g, b, 1)
                end
            end
        end

        -- The "Confirm your role" popup shown to the whole party when ANYONE queues
        -- (leader or otherwise) and roles aren't already locked in. LFG_PROPOSAL_SHOW
        -- only fires for the later group-found step, so this frame is hooked directly.
        -- Only the outer chrome is stripped; the role icons live on separate child
        -- buttons (RoleButtonTank/Healer/DPS), never direct regions of this frame.
        local function SkinRoleCheckPopup()
            local popup = _G.LFDRoleCheckPopup
            if not popup or not IsQueueReskinOn() then return end
            for i = 1, _select("#", popup:GetRegions()) do
                local r = _select(i, popup:GetRegions())
                if r and r:IsObjectType("Texture") and not GetFFD(r).owned then
                    r:SetTexture(nil)
                    if r.SetAtlas then r:SetAtlas("") end
                end
            end
            if popup.BG then popup.BG:SetAlpha(0) end
            if popup.NineSlice then popup.NineSlice:SetAlpha(0) end
            if popup.Border then popup.Border:SetAlpha(0) end
            if not GetFFD(popup).bg then
                local RS = EllesmereUI.RESKIN
                GetFFD(popup).bg = popup:CreateTexture(nil, "BACKGROUND", nil, -8)
                GetFFD(popup).bg:SetAllPoints()
                GetFFD(popup).bg:SetColorTexture(RS.BG_R, RS.BG_G, RS.BG_B, RS.QT_ALPHA)
                GetFFD(GetFFD(popup).bg).owned = true
                if not _PP then _PP = EllesmereUI and EllesmereUI.PP end
                if _PP and _PP.CreateBorder then
                    _PP.CreateBorder(popup, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
                end
            end
            SkinRoleCheckButton(_G.LFDRoleCheckPopupAcceptButton)
            SkinRoleCheckButton(_G.LFDRoleCheckPopupDeclineButton)
        end

        -- Not gated behind any LFG event: unlike the proposal/status popups above,
        -- this frame is part of the always-loaded base UI and can show independently
        -- of any Dungeon Finder UI ever being opened locally, so it is hooked directly.
        local _roleCheckHooked = false
        local function HookRoleCheckOnShow()
            if _roleCheckHooked or EllesmereUI.BlizzSkinPadStandDown() then return end
            local popup = _G.LFDRoleCheckPopup
            if not popup then return end
            _roleCheckHooked = true
            popup:HookScript("OnShow", function() SkinRoleCheckPopup() end)
            -- Blizzard may have already called :Show() before we got here (e.g. a
            -- party member who never opened the LFG UI themselves) -- HookScript
            -- only catches future shows, so skin the current one too.
            if popup:IsShown() then SkinRoleCheckPopup() end
        end
        HookRoleCheckOnShow()

        local lfgFrame = CreateFrame("Frame")
        lfgFrame:RegisterEvent("LFG_PROPOSAL_SHOW")
        lfgFrame:RegisterEvent("LFG_PROPOSAL_FAILED")
        lfgFrame:RegisterEvent("LFG_PROPOSAL_SUCCEEDED")
        -- Fallback retry only: HookRoleCheckOnShow already ran once at load. If
        -- LFDRoleCheckPopup somehow didn't exist yet at that point, this catches it
        -- the first time a role check actually happens, before the popup shows.
        lfgFrame:RegisterEvent("LFG_ROLE_CHECK_SHOW")
        lfgFrame:SetScript("OnEvent", function(_, event)
            if not EllesmereUIDB then return end
            if event == "LFG_ROLE_CHECK_SHOW" then
                HookRoleCheckOnShow()
            elseif event == "LFG_PROPOSAL_SHOW" then
                local reskinOn = IsQueueReskinOn()
                if reskinOn then
                    SkinQueuePopup()
                    HookStatusOnShow()
                end
                if EllesmereUIDB.showQueueTimer ~= false then
                    ShowQueueTimer(reskinOn)
                end
            else
                -- FAILED/SUCCEEDED: the status popup shows
                SkinQueueStatus()
            end
        end)

    end
end)()

I.last = "TooltipSkin"
