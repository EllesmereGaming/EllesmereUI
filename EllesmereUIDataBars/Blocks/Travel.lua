if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- Blocks\Travel.lua
-- Travel block factory (hearthstones and M+ teleports).

local ADDON_NAME, ns = ...
local L = ns.L
local K = ns.BlockKit

-- Upvalues
local CreateFrame      = CreateFrame
local InCombatLockdown = InCombatLockdown
local C_Timer          = C_Timer
local GetTime          = GetTime
local ipairs           = ipairs
local type             = type
local pcall            = pcall
local floor            = math.floor
local max              = math.max
local min              = math.min
local mrandom          = math.random

local ICON_GAP             = K.ICON_GAP
local CONTENT_BASE         = K.CONTENT_BASE
local InstKey              = K.InstKey
local MakeEventFrame       = K.MakeEventFrame
local RegisterInstEvents   = K.RegisterInstEvents
local UnregisterInstEvents = K.UnregisterInstEvents
local HBudget              = K.HBudget
local VSlotW               = K.VSlotW
local MaybeRelayout        = K.MaybeRelayout
local AttachTextOffset     = K.AttachTextOffset
local BlockColorOf         = K.BlockColorOf
local IconColorOf          = K.IconColorOf
local ParkSecureFrame      = K.ParkSecureFrame

-------------------------------------------------------------------------------
--  TRAVEL (Hearthstone + M+ teleports; SECURE hearth button)
-------------------------------------------------------------------------------
-- Static hearthstone pool (all expansions) shared by every instance.
local HEARTHSTONE_IDS = {
    -- Midnight
    263933, 265100, 263489, 264367,
    -- The War Within
    257736, 246565, 245970, 228940, 212337, 209035, 208704, 210455,
    -- Dragonflight
    236687, 235016, 200630, 193588,
    -- Shadowlands
    190196, 190237, 188952, 184353, 182773, 180290, 183716, 172179,
    -- Seasonal / Holiday
    163045, 162973, 165669, 165670, 165802, 166746, 166747,
    -- Legacy / Misc
    6948, 64488, 28585, 93672, 142542, 142298, 168907, 54452,
}

-- Standalone travel-cooldown entries listed under the Hearthstone tooltip line
-- when owned. Each has its OWN cooldown, separate from the shared hearthstone
-- one -- why Astral Recall is here, not the pool above, despite also returning
-- to the bind point. Spell IDs: Dalaran 222695, Arcantina 1255801, Garrison 171253.
local TRAVEL_EXTRAS = {
    140192,  -- Dalaran Hearthstone
    253629,  -- Key to the Arcantina
    110560,  -- Garrison Hearthstone
    556,     -- Astral Recall (a spell, hence the per-entry kind probe below)
}

-- Hearthstones share one cooldown, so polling a single owned one suffices.
-- Engine-level cache: the underlying cooldown is shared game-wide.
local travelPrimaryHearthId

local function TravelIsUsable(id)
    if not id then return false end
    if PlayerHasToy(id) then return true end
    if IsPlayerSpell(id) then return true end
    return (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id) or 0) > 0
end

-- Options-side exports: the hearthstone dropdown lists owned pool entries.
ns.TravelHearthstoneIDs = HEARTHSTONE_IDS
ns.TravelIsUsable = TravelIsUsable

-- Returns remaining, known. In restricted combat cooldown numbers are SECRET: comparing
-- or dead-reckoning them throws (type() still says "number"), so those report 0, false and
-- callers degrade -- tooltip "-" on gray rows, block tints as cooling, probe keeps ticking and self-corrects on a clean read.
local function TravelGetRemainingCooldown(id, isSpell)
    local startTime, duration
    if isSpell then
        local info = C_Spell.GetSpellCooldown(id)
        if info then startTime, duration = info.startTime, info.duration end
    else
        if C_Item and C_Item.GetItemCooldown then
            startTime, duration = C_Item.GetItemCooldown(id)
        elseif C_Container and C_Container.GetItemCooldown then
            startTime, duration = C_Container.GetItemCooldown(id)
        end
    end
    if issecretvalue(startTime) or issecretvalue(duration) then
        return 0, false
    end
    if type(startTime) == "number" and type(duration) == "number" and duration > 0 then
        return max(0, startTime + duration - GetTime()), true
    end
    return 0, true
end

local _hearthList = {}
local _hearthListCount = 0
local function TravelGetAvailableHearthstones()
    _hearthListCount = 0
    for _, id in ipairs(HEARTHSTONE_IDS) do
        if TravelIsUsable(id) then
            _hearthListCount = _hearthListCount + 1
            _hearthList[_hearthListCount] = id
        end
    end
    for i = _hearthListCount + 1, #_hearthList do _hearthList[i] = nil end
    return _hearthList
end

local function TravelBuildMacro(id)
    if PlayerHasToy(id) then return "/use item:" .. id end
    if IsPlayerSpell(id) then
        local info = C_Spell.GetSpellInfo(id)
        if info and info.name then return "/cast " .. info.name end
    end
    return "/use item:" .. id
end

local function TravelPickHearthstone(randomize)
    local list = TravelGetAvailableHearthstones()
    if #list == 0 then return nil end
    if randomize then return list[mrandom(#list)] end
    for _, id in ipairs(list) do if id == 6948 then return id end end
    return list[1]
end

-- Negative-result cache: with NO usable hearthstone the 1s cooling probe would re-scan all
-- ~40 candidates every second forever. Ownership only changes via edges the block already
-- listens to (hearth bind, world entry, bag/spell changes), which clear this through ns.TravelInvalidateHearthCache.
local travelNoHearth
function ns.TravelInvalidateHearthCache()
    travelNoHearth = nil
    travelPrimaryHearthId = nil
end
local function TravelGetPrimaryCooldown()
    -- The cached id is trusted between ownership edges: re-validating per 1s probe costs a
    -- GetItemCount bag walk every second, and item loss always fires BAG_UPDATE_DELAYED
    -- (spells: SPELLS_CHANGED), which clears the cache via ns.TravelInvalidateHearthCache and forces a re-pick here.
    if not travelPrimaryHearthId then
        if travelNoHearth then return 0, true end
        travelPrimaryHearthId = TravelPickHearthstone(false)
        if not travelPrimaryHearthId then
            travelNoHearth = true
            return 0, true
        end
    end
    return TravelGetRemainingCooldown(travelPrimaryHearthId, false)
end

local function TravelResolveMythicId(idOrTable)
    if type(idOrTable) == "table" then
        for _, id in ipairs(idOrTable) do if IsPlayerSpell(id) then return id end end
        return nil
    end
    if IsPlayerSpell(idOrTable) then return idOrTable end
    return nil
end

-- Season M+ teleports from the shared season list (one update per season).
local SEASON_TELEPORTS = {}
for _, e in ipairs(EllesmereUI.SEASON_PORTALS) do
    local ids = e.spellID
    if e.altSpellIDs then
        ids = { e.spellID }
        for _, a in ipairs(e.altSpellIDs) do ids[#ids + 1] = a end
    end
    SEASON_TELEPORTS[#SEASON_TELEPORTS + 1] = { spellIds = ids, dungeonId = e.dungeonID }
end

ns.BlockFactories.travel = function(blockCfg, slot, content, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = content, ctx = barCtx }
    inst.key = InstKey(barCtx, blockCfg)
    -- BAG_UPDATE_DELAYED / SPELLS_CHANGED: ownership edges that must clear the negative hearthstone cache (rare at idle, cheap refresh).
    -- Cooldown-START edges ride a player-filtered UNIT_SPELLCAST_SUCCEEDED
    -- registered in Enable (RegisterInstEvents cannot unit-filter): every
    -- hearth start IS a player cast, and BAG_UPDATE_COOLDOWN measured
    -- idle-chatty (~0.7 Hz ambient with nothing cooling).
    inst.events = { "HEARTHSTONE_BOUND", "PLAYER_ENTERING_WORLD",
        "BAG_UPDATE_DELAYED", "SPELLS_CHANGED" }

    local _trvFitBuf1 = { "" }
    local _trvFitBuf2 = { "" }
    local mouseOver = false
    -- Heartbeat demand-gate: the 1s tick runs ONLY while something is cooling
    -- or the tooltip is open (live M:SS columns). Ready + un-hovered = no tick
    -- at all; BAG_UPDATE_COOLDOWN announces every start edge and re-arms.
    local ticking = false
    local TravelSyncTicker -- forward declaration, filled in after TravelTick

    -- Pre-allocated tooltip line buffers (no per-show garbage). `spellId` is the static teleport spell ID (click overlay attribute), not the shown `name`.
    local _mythicLinesBuf = {}
    for i = 1, #SEASON_TELEPORTS do _mythicLinesBuf[i] = { name = "", cd = 0, cdKnown = true, spellId = nil } end
    local _mythicLineCount = 0

    local function D() return blockCfg.settings or {} end
    local function BC() return barCtx.cfg end

    local built = false
    local hearthButton, hearthIcon, hearthText
    local placeholder

    local function RefreshTravelTooltip()
        local ar, ag, ab = 1, 1, 1
        ns.Tip_Begin(hearthButton)
        -- Hover-persistent like the spec tip: the cursor can travel onto it to click ready teleport rows, even when no row is clickable right now.
        ns.Tip_MarkInteractive()
        ns.Tip_AddLine("|cFFFFFFFF[|r" .. L["TRAVEL_COOLDOWNS"] .. "|cFFFFFFFF]|r", ar, ag, ab)
        ns.Tip_AddLine(" ")
        local cd2, cdKnown = TravelGetPrimaryCooldown()
        local cdStr
        if cdKnown then
            cdStr = ns.FormatCooldown(cd2)
            if not cdStr then cdStr = L["READY"] end
        else
            cdStr = "-"
        end
        local ready = cdKnown and cd2 <= 0
        local rr, rg, rb = 0.5, 0.5, 0.5
        if ready then rr, rg, rb = 0, 1, 0 end
        -- Hearthstone row is click-to-use when ready, firing the same macro the block's
        -- click seeds (selected or random) through the shared overlay. White while ready,
        -- M+ "On Cooldown" gray otherwise; plain label (no embedded codes) so state and hover
        -- color the whole line; the plain-state row is pad-marked to match the clickable row's spacing.
        local hsLabel = L["HEARTHSTONE"] .. " (" .. (GetBindLocation() or "?") .. ")"
        local hsMacro
        if ready then
            local dt = D()
            local choice = dt.hsChoice
            if choice == nil then choice = dt.randomizeHs and "random" or 6948 end
            local hsId
            if choice ~= "random" and TravelIsUsable(choice) then
                hsId = choice
            else
                hsId = TravelPickHearthstone(choice == "random")
            end
            if hsId then hsMacro = TravelBuildMacro(hsId) end
        end
        if hsMacro then
            ns.Tip_AddMacroActionDouble(hsLabel, cdStr, hsMacro, 1, 1, 1, rr, rg, rb)
        else
            local hg = ready and 1 or 0.65
            ns.Tip_AddDouble(hsLabel, cdStr, hg, hg, hg, rr, rg, rb)
            ns.Tip_PadRow()
        end

        -- Travel entries ride the same section, each with its own cooldown. A spell entry
        -- takes the spell-side name/cooldown/click overlay, and IsPlayerSpell gates it to its
        -- class. Name lookups can be nil on a cold cache: the row appears on the next tooltip refresh.
        for _, entryId in ipairs(TRAVEL_EXTRAS) do
            local isToy   = PlayerHasToy(entryId)
            local isSpell = not isToy and IsPlayerSpell(entryId)
            if isToy or isSpell then
                local entryName
                if isSpell then
                    local sInfo = C_Spell.GetSpellInfo(entryId)
                    entryName = sInfo and sInfo.name
                else
                    if C_ToyBox and C_ToyBox.GetToyInfo then
                        local _, tn = C_ToyBox.GetToyInfo(entryId)
                        entryName = tn
                    end
                    if not entryName and C_Item and C_Item.GetItemInfo then
                        entryName = C_Item.GetItemInfo(entryId)
                    end
                end
                if entryName then
                    local tcd, tKnown = TravelGetRemainingCooldown(entryId, isSpell)
                    local tstr
                    if tKnown then
                        tstr = ns.FormatCooldown(tcd)
                        if not tstr then tstr = L["READY"] end
                    else
                        tstr = "-"
                    end
                    local tready = tKnown and tcd <= 0
                    local tr, tg, tb = 0.5, 0.5, 0.5
                    if tready then tr, tg, tb = 0, 1, 0 end
                    if tready then
                        -- Ready: click-to-use, same secure overlay contract as the M+ rows
                        -- (degrades to text in combat). Both helpers take the same args; only the seeded secure attribute differs.
                        local AddActionRow = isSpell and ns.Tip_AddActionDouble
                                                      or ns.Tip_AddToyActionDouble
                        AddActionRow(entryName, tstr, entryId, 1, 1, 1, tr, tg, tb)
                    else
                        -- On cooldown: same gray as the M+ "On Cooldown" label.
                        ns.Tip_AddDouble(entryName, tstr, 0.65, 0.65, 0.65, tr, tg, tb)
                    end
                end
            end
        end

        -- Show M+ Portals: nil reads as shown (no migration needed). OFF skips the section and its spell-resolution work entirely.
        -- WoW Forever has no Mythic+ teleports: the section never builds there.
        _mythicLineCount = 0
        if not EllesmereUI.IS_FOREVER and D().clickableTeleports ~= false then
            for _, entry in ipairs(SEASON_TELEPORTS) do
                local spellId = TravelResolveMythicId(entry.spellIds)
                if spellId then
                    local dName = nil
                    if entry.dungeonId and GetLFGDungeonInfo then dName = GetLFGDungeonInfo(entry.dungeonId) end
                    local spInfo = C_Spell.GetSpellInfo(spellId)
                    local spName = spInfo and spInfo.name
                    local name2 = dName
                    if not name2 then name2 = spName end
                    if not name2 then name2 = tostring(spellId) end
                    _mythicLineCount = _mythicLineCount + 1
                    local mcd, mKnown = TravelGetRemainingCooldown(spellId, true)
                    _mythicLinesBuf[_mythicLineCount].name    = name2
                    _mythicLinesBuf[_mythicLineCount].cd      = mcd
                    _mythicLinesBuf[_mythicLineCount].cdKnown = mKnown
                    _mythicLinesBuf[_mythicLineCount].spellId = spellId
                end
            end
        end
        if _mythicLineCount > 0 then
            ns.Tip_AddLine(" ")
            ns.Tip_AddLine(L["MYTHIC_TELEPORTS"], ar, ag, ab)
            -- Insertion sort on active entries only (max ~8)
            for i = 2, _mythicLineCount do
                local j = i
                while j > 1 and _mythicLinesBuf[j].name < _mythicLinesBuf[j - 1].name do
                    _mythicLinesBuf[j].name,    _mythicLinesBuf[j - 1].name    = _mythicLinesBuf[j - 1].name,    _mythicLinesBuf[j].name
                    _mythicLinesBuf[j].cd,      _mythicLinesBuf[j - 1].cd      = _mythicLinesBuf[j - 1].cd,      _mythicLinesBuf[j].cd
                    _mythicLinesBuf[j].cdKnown, _mythicLinesBuf[j - 1].cdKnown = _mythicLinesBuf[j - 1].cdKnown, _mythicLinesBuf[j].cdKnown
                    _mythicLinesBuf[j].spellId, _mythicLinesBuf[j - 1].spellId = _mythicLinesBuf[j - 1].spellId, _mythicLinesBuf[j].spellId
                    j = j - 1
                end
            end
            -- Ready rows are always click-to-teleport (not configurable). On-cooldown teleports share one group, collapsing into one "On Cooldown" line (soonest remaining).
            local cdMin, cdUnknown
            for i = 1, _mythicLineCount do
                local e = _mythicLinesBuf[i]
                if not e.cdKnown then
                    -- Secret cooldown (restricted combat): state unknowable,
                    -- fold into the collapsed On Cooldown line below.
                    cdUnknown = true
                elseif e.cd <= 0 then
                    -- Ready teleport: left-click casts it (secure overlay button
                    -- keyed to the static spell ID; row highlights on hover).
                    ns.Tip_AddActionDouble(e.name, L["READY"], e.spellId, 0.8, 0.8, 0.8, 0, 1, 0)
                elseif not cdMin or e.cd < cdMin then
                    cdMin = e.cd
                end
            end
            if cdMin then
                local cs = ns.FormatCooldown(cdMin)
                if not cs then cs = L["READY"] end
                ns.Tip_AddDouble(L["ON_COOLDOWN"], cs, 0.65, 0.65, 0.65, 0.5, 0.5, 0.5)
            elseif cdUnknown then
                ns.Tip_AddDouble(L["ON_COOLDOWN"], "-", 0.65, 0.65, 0.65, 0.5, 0.5, 0.5)
            end
        end
        ns.Tip_AddLine(" ")
        ns.Tip_AddDouble(L["LEFT_CLICK"], L["USE_HEARTHSTONE"], 1, 1, 1, ar, ag, ab)
        ns.Tip_AddDouble(L["RIGHT_CLICK"], L["RANDOM_HEARTHSTONE"], 1, 1, 1, ar, ag, ab)
        ns.Tip_Show()
    end

    local function Build()
        if built then return end
        built = true
        if placeholder then placeholder:Hide() end

        hearthButton = CreateFrame("Button", "EllesmereUIDataBarsHearth_" .. inst.key, content, "SecureActionButtonTemplate")
        -- Up only + useOnKeyDown=false: registering both Up and Down lets the
        -- ActionButtonUseKeyDown CVar fire the macro twice (2nd /use cancels the cast).
        hearthButton:SetAllPoints()
        hearthButton:EnableMouse(true)
        hearthButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        hearthButton:SetAttribute("useOnKeyDown", false)
        -- One explicit pair per button rather than an unsuffixed fallback:
        -- 1 = the chosen hearthstone, 2 = always a random one.
        hearthButton:SetAttribute("*type1", "macro")
        hearthButton:SetAttribute("*macrotext1", "")
        hearthButton:SetAttribute("*type2", "macro")
        hearthButton:SetAttribute("*macrotext2", "")

        hearthIcon   = hearthButton:CreateTexture(nil, "OVERLAY")
        hearthText   = hearthButton:CreateFontString(nil, "OVERLAY")
        AttachTextOffset(inst, hearthText)

        local function SeedMacro()
            if InCombatLockdown() then return end
            local dt = D()
            -- Hearthstone choice: "random" or a pool item id. nil derives from
            -- the randomizeHs boolean (nil/false = plain hearthstone preferred).
            local choice = dt.hsChoice
            if choice == nil then
                choice = dt.randomizeHs and "random" or 6948
            end
            local id
            if choice ~= "random" and TravelIsUsable(choice) then
                id = choice
            else
                -- Random pick, or fallback when the chosen hearthstone is no longer owned/usable.
                id = TravelPickHearthstone(choice == "random")
            end
            if id then hearthButton:SetAttribute("*macrotext1", TravelBuildMacro(id)) end
            -- Right click ignores the choice and always rolls its own.
            local rid = TravelPickHearthstone(true)
            if rid then hearthButton:SetAttribute("*macrotext2", TravelBuildMacro(rid)) end
        end

        -- Reseed on every PreClick (OOC only) so the button always fires the currently
        -- owned/random hearthstone without a protected call from OnClick. SetScript is
        -- fine here: WE created this button.
        hearthButton:SetScript("PreClick", function()
            if InCombatLockdown() then return end
            SeedMacro()
        end)

        hearthButton:SetScript("OnEnter", function()
            mouseOver = true
            inst:Refresh()
            RefreshTravelTooltip()
        end)
        hearthButton:SetScript("OnLeave", function()
            mouseOver = false
            -- Interactive tip (clickable M+ rows): the keep-alive poll owns
            -- dismissal so the cursor can travel onto the tip to click a row.
            ns.Tip_HideUnlessInteractive(hearthButton)
            inst:Refresh()
        end)

        -- Seed macrotext shortly after build so a first-combat click works.
        C_Timer.After(1, SeedMacro)
    end

    -- Combat-deferred construction: dimmed non-interactive icon until OOC.
    if InCombatLockdown() then
        placeholder = content:CreateTexture(nil, "OVERLAY")
        K.SetBlockIcon(placeholder, blockCfg)
        placeholder:SetVertexColor(0.6, 0.6, 0.6, 0.6)
        placeholder:SetSize(16, 16)
        placeholder:SetPoint("CENTER")
        ns.DeferUntilOOC("edbbuild:" .. inst.key, function()
            if inst._dead then return end
            Build()
            inst:Refresh()
        end)
    else
        Build()
    end

    function inst:Refresh()
        if not built then return end
        K.SetBlockIcon(hearthIcon, blockCfg)
        local barCfg = BC()
        local barH = barCtx.GetThickness()
        local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
        local isSide = barCtx.IsVertical()

        local location = GetBindLocation() or "?"
        if isSide then
            local slotW = VSlotW(inst)
            local innerW = max(30, slotW - 8)
            _trvFitBuf1[1] = location
            _trvFitBuf2[1] = "00:00:00"
        end

        ns.SetFont(hearthText, fontSize, barCfg)

        hearthText:SetText(location)

        -- Block renders only icon + bind location; remaining cooldown lives in
        -- the tooltip. On cooldown (or an unknown/secret one) it dims to gray.
        local cd, cdKnown = TravelGetPrimaryCooldown()
        inst._lastCooling = (not cdKnown) or cd > 0
        TravelSyncTicker(mouseOver or inst._lastCooling)

        if mouseOver then
            local ar, ag, ab = ns.GetAccent()
            hearthText:SetTextColor(ar, ag, ab, 1); hearthIcon:SetVertexColor(ar, ag, ab, 1)
        elseif (not cdKnown) or cd > 0 then
            hearthText:SetTextColor(0.5, 0.5, 0.5, 1); hearthIcon:SetVertexColor(0.5, 0.5, 0.5, 1)
        else
            local br, bgr, bb = BlockColorOf(blockCfg)
            local ir, ig, ib = IconColorOf(blockCfg)
            hearthText:SetTextColor(br, bgr, bb, 1); hearthIcon:SetVertexColor(ir, ig, ib, 1)
        end

        if InCombatLockdown() then return end

        -- +2 icon size, -2 gap: hearthstone runs bigger and tighter than default.
        local iconSz, gap = fontSize + 2, ICON_GAP - 2
        if isSide then
            iconSz = min(iconSz, max(14, floor(CONTENT_BASE * 0.72 + 0.5)))
        end
        hearthIcon:ClearAllPoints()
        hearthIcon:SetSize(iconSz, iconSz)

        if isSide then
            local slotW = VSlotW(inst)
            local innerW = max(30, slotW - 8)
            local totalH = 8 + iconSz + 2

            content:SetWidth(slotW)
            hearthButton:SetWidth(slotW)
            hearthIcon:SetPoint("TOP", hearthButton, "TOP", 0, -4)

            ns.SetWrappedText(hearthText, innerW, "CENTER")
            hearthText:ClearAllPoints()
            hearthText:SetPoint("TOP", hearthIcon, "BOTTOM", 0, -2)
            totalH = totalH + ns.SnapToPixelGrid(hearthText:GetStringHeight())

            totalH = max(totalH, barH)
            content:SetHeight(totalH)
            hearthButton:SetHeight(totalH)
        else
            local slotW = HBudget(inst, 120)
            local textBudget = max(30, slotW - iconSz - gap - 8)
            _trvFitBuf1[1] = location
            _trvFitBuf2[1] = "00:00:00"
            ns.SetFont(hearthText, fontSize, barCfg)
            hearthText:SetText(location)
            -- +2 matches the top-of-Refresh sizing: this branch re-derives iconSz, which would otherwise silently swallow earlier size bumps.
            iconSz = min(fontSize + 2, max(14, floor(CONTENT_BASE * 0.72 + 0.5)))
            hearthIcon:SetSize(iconSz, iconSz)
            ns.ResetInlineText(hearthText, "LEFT")
            local tw = ns.SnapToPixelGrid(hearthText:GetStringWidth())
            local totalW = min(slotW, iconSz + gap + tw + 4)
            content:SetSize(totalW, barH)
            hearthButton:SetSize(totalW, barH)
            hearthIcon:SetPoint("LEFT", hearthButton, "LEFT", 0, 0)
            hearthText:ClearAllPoints(); hearthText:SetPoint("LEFT", hearthButton, "LEFT", iconSz + gap, 0)
        end
        MaybeRelayout(inst)
    end

    -- 1s heartbeat. Hovered: the open tooltip's M:SS columns need per-second full
    -- refreshes. Un-hovered: the block shows only icon+location+ready/cooling tint,
    -- so the tick is a cheap two-call cooling probe and Refresh runs only on the
    -- tint EDGE. Location changes arrive via HEARTHSTONE_BOUND.
    local function TravelTick()
        if built and mouseOver and ns.Tip_IsOwned(hearthButton) then
            inst:Refresh()
            RefreshTravelTooltip()
            return
        end
        -- Unknown (secret) cooldowns count as cooling: the probe keeps ticking through combat and self-corrects on the first clean read.
        local pcd, pKnown = TravelGetPrimaryCooldown()
        local cooling = (not pKnown) or pcd > 0
        if cooling ~= inst._lastCooling then
            inst._lastCooling = cooling
            inst:Refresh()
        elseif not cooling and not mouseOver then
            -- Settled ready with no edge to paint: nothing left to watch.
            TravelSyncTicker(false)
        end
    end

    -- Fills the forward declaration above. Register/unregister is flag-guarded
    -- so redundant syncs cost one boolean test.
    TravelSyncTicker = function(want)
        if want then
            if not ticking then
                ticking = true
                ns.RegisterHeartbeat("travel:" .. inst.key, TravelTick)
            end
        elseif ticking then
            ticking = false
            ns.UnregisterHeartbeat("travel:" .. inst.key)
        end
    end

    inst.eventFrame = MakeEventFrame(inst, function(self, event)
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            -- Cooldown-START lane (player casts only; every hearth start is
            -- one): never invalidates the hearthstone pick, and while the
            -- ticker already runs there is nothing to learn. One probe on a
            -- start edge re-arms the tick; zero fires standing idle.
            if not ticking then TravelTick() end
            return
        end
        ns.TravelInvalidateHearthCache()
        self:Refresh()
    end)

    function inst:Enable()
        content:Show()
        RegisterInstEvents(self)
        -- Player-filtered registration; Disable's UnregisterAllEvents drops it,
        -- so it re-registers here (re-registration is idempotent).
        pcall(self.eventFrame.RegisterUnitEvent, self.eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player")
        -- Armed at enable as a belt; the first settled ready read stands it
        -- down (TravelTick's else branch or any Refresh).
        TravelSyncTicker(true)
    end

    function inst:Disable()
        TravelSyncTicker(false)
        UnregisterInstEvents(self)
        content:Hide()
    end

    function inst:GetAutoLength()
        if not built then return 40 end
        local barH = barCtx.GetThickness()
        if barCtx.IsVertical() then
            local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
            local iconSz = fontSize
            local textH = hearthText:GetStringHeight() or fontSize
            return max(8 + iconSz + 2 + textH + 4, barH, 50)
        end
        return max(content:GetWidth() or 120, 40)
    end

    function inst:Destroy()
        self._dead = true
        if hearthButton then
            ParkSecureFrame(hearthButton, self.key .. "_hearth")
        end
        content:Hide()
    end

    return inst
end
