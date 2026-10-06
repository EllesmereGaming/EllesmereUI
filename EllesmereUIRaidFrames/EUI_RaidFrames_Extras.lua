if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_RaidFrames_Extras.lua
--
--  The healer mana text display and the frame-provider APIs for external
--  trackers.
--  Reads the earlier Raid Frames files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIRaidFrames.lua or an earlier Raid Frames file failed to load.
if not I or I.broken then return end
I.broken = true

local pairs        = pairs
local ipairs       = ipairs
local type         = type
local select       = select
local UnitName              = UnitName
local UnitClass             = UnitClass
local UnitExists            = UnitExists
local UnitIsUnit            = UnitIsUnit
local IsInRaid              = IsInRaid
local IsInGroup             = IsInGroup
local InCombatLockdown      = InCombatLockdown
local C_Timer               = C_Timer
local issecretvalue         = issecretvalue
local CreateFrame           = CreateFrame
local RAID_CLASS_COLORS     = RAID_CLASS_COLORS

local allButtons, GetFFD, GetPowerColor = I.allButtons, I.GetFFD, I.GetPowerColor

local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end

-------------------------------------------------------------------------------
--  Healer Mana Text Display (Extras): one text row per group healer, riding
--  the EXISTING per-unit trackers. UpdatePowerEventRegistration keeps
--  UNIT_POWER_UPDATE registered for healers while enabled (same loop, same
--  role reads), the shared OnEvent feeds the rows, and the healer set
--  rebuilds on the same roster/roles cadence. Zero cost while disabled:
--  no rows map (the OnEvent tail is one nil test), no extra registrations,
--  container never built.
-------------------------------------------------------------------------------
do
    local container
    local rows = {}   -- i -> { nameFS, valFS, unit }

    local function HMSet()
        local prof = db.profile
        local hm = prof.healerMana
        if not hm then
            hm = { mode = "none" }
            prof.healerMana = hm
        end
        return hm
    end
    ns._HMSet = HMSet

    -- The display's mode gates on the CURRENT group type; solo counts as
    -- neither (the preview eyeball still works ungrouped).
    function ns._HMActive()
        local mode = HMSet().mode or "none"
        if mode == "none" then return false end
        if IsInRaid() then return mode == "raid" or mode == "both" end
        if IsInGroup() then return mode == "party" or mode == "both" end
        return false
    end

    local function EnsureContainer()
        if container then return container end
        container = CreateFrame("Frame", "ERF_HealerMana", UIParent)
        container:SetSize(50, 25)
        container:Hide()
        ns._hmContainer = container
        local pos = HMSet().unlockPos
        if pos and pos.point then
            container:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
        else
            container:SetPoint("CENTER", UIParent, "CENTER", 320, 0)
        end
        return container
    end
    ns._HMEnsureContainer = EnsureContainer

    -- Value repaint: the engine percent object straight into the display
    -- sink -- secret-safe, no Lua math (same source as the power bars).
    function ns._HMUpdateValue(unit)
        local r = ns._hmUnitRows and ns._hmUnitRows[unit]
        if not r then return end
        r.valFS:SetFormattedText("%d", UnitPowerPercent(unit, 0, true, CurveConstants.ScaleTo100))
    end

    -- Full rebuild: healer set, names, colors, layout. Runs on the roster/
    -- roles cadence (UpdatePowerEventRegistration tail) + settings changes.
    function ns.HM_Rebuild()
        local hm = HMSet()
        local preview = ns._hmPreview
        if not ns._HMActive() and not preview then
            if container then container:Hide() end
            ns._hmUnitRows = nil
            return
        end
        EnsureContainer()
        local size     = hm.textSize or 12
        local spacing  = hm.spacing or 2
        local alignR   = hm.align == "RIGHT"
        local alignC   = hm.align == "CENTER"
        local growUp   = hm.growth == "UP"
        local inRaid   = IsInRaid()
        local showNames = (hm.showNames ~= false) and (inRaid or preview)
        local classNames = hm.classNames ~= false
        local powerMode  = hm.colorMode == "power"
        local cc = hm.color
        local cr, cg, cb = (cc and cc.r) or 1, (cc and cc.g) or 1, (cc and cc.b) or 1
        local fontPath = (EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
        local outline = (EllesmereUI.GetFontOutlineFlag("raidFrames")) or "OUTLINE"
        local rowH = size + spacing
        local map = {}
        local count, widest = 0, 40

        local function addRow(unit, fakeName, fakeClass, fakeVal)
            count = count + 1
            local r = rows[count]
            if not r then
                r = { nameFS = container:CreateFontString(nil, "OVERLAY"),
                      valFS  = container:CreateFontString(nil, "OVERLAY") }
                rows[count] = r
            end
            r.unit = unit
            local nameFS, valFS = r.nameFS, r.valFS
            nameFS:SetFont(fontPath, size, outline)
            valFS:SetFont(fontPath, size, outline)
            -- Value color: power color per unit, or the custom color.
            if powerMode then
                local pr, pg, pb
                if unit then pr, pg, pb = GetPowerColor(unit) end
                valFS:SetTextColor(pr or 0.3, pg or 0.5, pb or 0.85, 1)
            else
                valFS:SetTextColor(cr, cg, cb, 1)
            end
            -- Name first (colors + text), so center alignment can measure it.
            local nameW = 0
            if showNames then
                local nr, ng, nb = cr, cg, cb
                if classNames then
                    local token = fakeClass
                    if not token and unit then
                        token = select(2, UnitClass(unit))
                        if issecretvalue and issecretvalue(token) then token = nil end
                    end
                    local col = token and ((EllesmereUI.GetClassColor(token))
                        or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]))
                    if col then nr, ng, nb = col.r, col.g, col.b end
                elseif powerMode then
                    nr, ng, nb = 1, 1, 1
                end
                nameFS:SetTextColor(nr, ng, nb, 1)
                if fakeName then
                    nameFS:SetText(fakeName)
                else
                    -- Display sink: a secret name renders raw, never inspected.
                    nameFS:SetFormattedText("%s", (unit and EllesmereUI.WithSurname(UnitName(unit))) or "")
                end
                nameFS:Show()
                local w = nameFS:GetStringWidth()
                if w and not (issecretvalue and issecretvalue(w)) then
                    nameW = w
                else
                    nameW = size * 5  -- secret name: estimated width
                end
            else
                nameFS:SetText("")
                nameFS:Hide()
            end
            -- Fixed value-width estimate: centering on the live value's real
            -- width would shift the row every tick.
            local valEst = size * 2.2
            local rowW = (showNames and (nameW + 4) or 0) + valEst
            if rowW > widest then widest = rowW end
            -- Growth: rows stack down from the top edge, or up from the
            -- bottom edge (anchor family flips with it).
            local yOff = (growUp and 1 or -1) * (count - 1) * rowH
            local pCorner = growUp and "BOTTOMLEFT" or "TOPLEFT"
            local pCornerR = growUp and "BOTTOMRIGHT" or "TOPRIGHT"
            local pEdge = growUp and "BOTTOM" or "TOP"
            nameFS:ClearAllPoints(); valFS:ClearAllPoints()
            if alignC then
                if showNames then
                    nameFS:SetPoint(pCorner, container, pEdge, -rowW / 2, yOff)
                    valFS:SetPoint("LEFT", nameFS, "RIGHT", 4, 0)
                    valFS:SetJustifyH("LEFT")
                else
                    valFS:SetPoint(pEdge, container, pEdge, 0, yOff)
                    valFS:SetJustifyH("CENTER")
                end
            elseif alignR then
                valFS:SetPoint(pCornerR, container, pCornerR, 0, yOff)
                valFS:SetJustifyH("RIGHT")
                if showNames then nameFS:SetPoint("RIGHT", valFS, "LEFT", -4, 0) end
            else
                if showNames then
                    nameFS:SetPoint(pCorner, container, pCorner, 0, yOff)
                    valFS:SetPoint("LEFT", nameFS, "RIGHT", 4, 0)
                else
                    valFS:SetPoint(pCorner, container, pCorner, 0, yOff)
                end
                valFS:SetJustifyH("LEFT")
            end
            if fakeVal then
                valFS:SetFormattedText("%d", fakeVal)
            end
            valFS:Show()
            if unit then map[unit] = r end
        end

        if preview then
            addRow(nil, "Thaldris", "PRIEST", 84)
            addRow(nil, "Kaelyra", "SHAMAN", 67)
            addRow(nil, "Morwenn", "DRUID", 92)
        else
            -- Ordered walk, roster order; the role read is the same cached
            -- resolver the power-bar registration uses.
            if inRaid then
                for i = 1, 40 do
                    local unit = "raid" .. i
                    if UnitExists(unit) and ns._ResolvePowerRole(unit) == "HEALER" then
                        addRow(unit)
                    end
                end
            else
                if ns._ResolvePowerRole("player") == "HEALER" then addRow("player") end
                for i = 1, 4 do
                    local unit = "party" .. i
                    if UnitExists(unit) and ns._ResolvePowerRole(unit) == "HEALER" then
                        addRow(unit)
                    end
                end
            end
        end

        -- Retire surplus rows from a previous, larger set.
        for i = count + 1, #rows do
            rows[i].nameFS:Hide()
            rows[i].valFS:Hide()
            rows[i].unit = nil
        end

        ns._hmUnitRows = (not preview and count > 0) and map or nil
        if count > 0 then
            -- Content-sized, with unlock-mover minimums (50x25).
            container:SetSize(math.max(widest, 50), math.max(count * rowH - spacing, 25))
            container:Show()
            -- Seed live values (the event path keeps them current after).
            if not preview then
                for unit in pairs(map) do ns._HMUpdateValue(unit) end
            end
        else
            container:Hide()
        end
    end

    -- Options preview (eyeball): fake rows at the saved position.
    function ns.HM_SetPreview(on)
        ns._hmPreview = on and true or nil
        ns.HM_Rebuild()
    end
end

ns.GetFFD = GetFFD

-------------------------------------------------------------------------------
--  External tracker integration (frame-provider APIs)
-------------------------------------------------------------------------------
-- Some cooldown/defensive tracker addons anchor icons onto party/raid unit
-- frames, found via a hardcoded addon list or a public provider API. EUI
-- frames are custom, so where a provider API exists we hand it our buttons;
-- the unit lives on the secure "unit" attribute (GetAttribute), so no plain
-- field on the button is needed. Name-scanning trackers (LibGetFrame) match our
-- button names from that library's default priority list, but the match only runs
-- against a frame list it caches (see ns._NotifyTrackerProviders).

-- Currently-visible EUI unit buttons with a unit assigned (party AND raid). Both sets
-- are pre-created once (the startingIndex -4 / Show / 1 trick) and never destroyed or
-- recycled -- the secure header only reassigns "unit" and shows/hides -- so a collected
-- list is exactly as stable for raid as for party; IsVisible + unit is what excludes a
-- button the header has parked.
--
-- Extra frames are skipped (deliberate DUPLICATES of units already on a real raid
-- button -- handing a tracker both leaves it choosing between two frames for one unit).
-- Boss frames never join allButtons for the same reason: not party/raid unit frames.
ns._CollectTrackerFrames = function()
    local out = {}
    local function Collect(list)
        if not list then return end
        for _, btn in ipairs(list) do
            if btn:IsVisible() and btn:GetAttribute("unit")
               and not GetFFD(btn)._isExtra then
                out[#out + 1] = btn
            end
        end
    end
    Collect(ns._partyAllButtons)
    Collect(allButtons)
    return out
end

-- Public unit -> frame lookup for any addon wanting our raid or party frame.
-- LibGetFrame cannot answer on an addon-restricted map: it keeps a cached frame
-- only when UnitIsUnit(frameUnit, target) is non-secret, and that call is
-- SecretWhenUnitComparisonRestricted, so every frame is skipped there however
-- fresh the cache. This compares nothing -- it reads the secure "unit"
-- attribute the header wrote. Extra frames answer last: they duplicate a unit
-- already on a real raid button.
function EllesmereUI.GetUnitFrame(unit)
    if type(unit) ~= "string" then return nil end
    local function Find(list)
        if not list then return nil end
        for _, btn in ipairs(list) do
            if btn:IsVisible() then
                local u = btn:GetAttribute("unit")
                -- type() reports a secret's underlying type, so a secret
                -- attribute would pass as a string and the compare would throw:
                -- probe for secrecy first, never compare a secret.
                if type(u) == "string" and not (issecretvalue and issecretvalue(u)) then
                    if u == unit then return btn end
                    -- The header gives the player's own button a raidN token, so
                    -- a literal compare never finds "player". UnitIsUnit answers
                    -- a SECRET boolean for a restricted pairing (or nil when the
                    -- compare is refused); only a plain true counts, and a secret
                    -- is never looked at.
                    if unit == "player" then
                        local ok, same = pcall(UnitIsUnit, u, "player")
                        if ok and not (issecretvalue and issecretvalue(same)) and same == true then
                            return btn
                        end
                    end
                end
            end
        end
        return nil
    end
    return Find(ns._partyAllButtons) or Find(allButtons) or ns._xfUnitToButton[unit]
end

-- Notifies subscribed providers that our frame set changed, debounced to one
-- refresh per frame. Driven from the visibility paths -- the one change a
-- provider cannot learn from its own roster events.
--
-- LibGetFrame resolves units against a frame list it caches, rebuilt only on its
-- own six events and recording only buttons visible at that instant. Our header
-- set builds lazily and defers combat-time changes to regen, so the cache can
-- miss the whole set with no event left to correct it; consumers then read nil
-- and silently do nothing. ScanForUnitFrames is its public invalidation (queued
-- and time-sliced). Resolved per call, not cached: either provider may load late.
-- Never asked for in combat: the library's walk reads every frame bare and our
-- aura containers deny tainted reads while auras are secret, so a mid-fight
-- scan can drop every EUI frame for the rest of the fight. The library
-- rescans on its own at PLAYER_REGEN_ENABLED, so the regen pass covers it.
ns._NotifyTrackerProviders = function()
    if ns._trackerRefreshPending then return end
    local cb = ns._trackerRefreshCb
    local lgf = LibStub and LibStub("LibGetFrame-1.0", true)
    if not cb and not (lgf and lgf.ScanForUnitFrames) then return end
    ns._trackerRefreshPending = true
    C_Timer.After(0, function()
        ns._trackerRefreshPending = false
        if cb then pcall(cb) end
        if lgf and not InCombatLockdown() then pcall(lgf.ScanForUnitFrames) end
    end)
end

-- Registers EUI as a frame provider with any installed, supported tracker.
-- Inert when none is present. Called once from OnEnable.
ns._RegisterTrackerProviders = function()
    -- MiniAuras: stable public global MiniAurasApi.v1, created at its file load and so
    -- present by PLAYER_LOGIN whenever MiniAuras is enabled. MiniCCApi is the
    -- pre-rename global (same v1 contract), kept as a fallback for older installs.
    local api = MiniAurasApi or MiniCCApi
    if api and api.v1 and api.v1.RegisterFrameProvider then
        pcall(function()
            api.v1:RegisterFrameProvider({
                Name = "EllesmereUI",
                GetFrames = ns._CollectTrackerFrames,
                RegisterRefreshFrames = function(cb) ns._trackerRefreshCb = cb end,
            })
        end)
    end
end

I.broken = false
