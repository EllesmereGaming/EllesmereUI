-------------------------------------------------------------------------------
--  EllesmereUIBlizzardSkin.lua
--  Umbrella addon for themed Blizzard UI frames. Hosts the Character Sheet
--  rework (EllesmereUIBlizzardSkin_CharacterSheet.lua) and the tooltip, context
--  menu, and static popup reskinning below.
-------------------------------------------------------------------------------
local ADDON_NAME = ...

-- External weak-keyed lookup table for frame state (prevents tainting Blizzard frames)
local FFD = setmetatable({}, { __mode = "k" })
local function GetFFD(frame)
    local d = FFD[frame]
    if not d then d = {}; FFD[frame] = d end
    return d
end

-------------------------------------------------------------------------------
--  Per-window skin style ("eui" | "modern" | "off"). The per-window enable
--  keys stay the on/off source of truth, so existing settings carry over
--  unchanged: enable key false = "off". EllesmereUIDB.blizzWindowSkinStyles
--  only records WHICH skin set an enabled window uses (nil = "eui").
--  "modern" is reserved for the upcoming skin set and currently renders
--  identically to "eui" -- skin files branch on this helper when it ships.
-------------------------------------------------------------------------------
local WINDOW_ENABLE_KEYS = {
    charsheet       = "themedCharacterSheet",
    inspect         = "themedInspectSheet",
    lfg             = "reskinLFGMenu",
    greatvault      = "reskinGreatVault",
    collections     = "reskinCollections",
    playerspells    = "reskinPlayerSpells",
    adventureguide  = "reskinAdventureGuide",
    professionsbook = "reskinProfessionsBook",
    guild           = "reskinGuild",
    calendar        = "reskinCalendar",
    achievements    = "reskinAchievements",
    mail            = "reskinMail",
    catalyst        = "reskinCatalyst",
    socket          = "reskinSocket",
    micromenu       = "reskinMicroMenu",
    housing         = "reskinHousing",
    professions     = "reskinProfessions",
    worldmap        = "reskinWorldMap",
    dressup         = "reskinDressUp",
    transmog        = "reskinTransmog",
    merchant        = "reskinMerchant",
    auctionhouse    = "reskinAuctionHouse",
    macros          = "reskinMacros",
    settings        = "reskinSettings",
    addonlist       = "reskinAddonList",
    craftorders     = "reskinCraftOrders",
    trainer         = "reskinTrainer",
    gossip          = "reskinGossip",
    quest           = "reskinQuest",
    inspectrecipe   = "reskinInspectRecipe",
    delves          = "reskinDelves",
}
--- Master PER-PROFILE kill switch for ALL Blizzard window skinning: the
--- window engine + every pack, plus the pre-engine CharacterSheet/Inspect,
--- SocketPanel and LFG/GroupFinder skins. Stored on the PROFILE ROOT
--- (EllesmereUIDB.profiles[name].disableWindowSkins) and resolved live, so
--- it follows profile switches and rides profile exports; nil/false =
--- enabled. Per-window enable keys and style picks are PRESERVED while
--- killed, so re-enabling restores the exact configuration. Skins install
--- at load: crossings require a reload (callers show the popup). The
--- Tooltips-page popup skins (Queue Popup, Pause Menu) and Dragon Riding
--- are deliberately NOT windows and stay untouched.
function EllesmereUI.BlizzWindowSkinsKilled()
    local prof = EllesmereUI.GetActiveProfileData and EllesmereUI.GetActiveProfileData()
    return (prof and prof.disableWindowSkins) and true or false
end

function EllesmereUI.GetBlizzWindowStyle(winKey)
    if EllesmereUI.BlizzWindowSkinsKilled() then return "off" end
    local ek = WINDOW_ENABLE_KEYS[winKey]
    if ek and EllesmereUIDB and EllesmereUIDB[ek] == false then return "off" end
    local styles = EllesmereUIDB and EllesmereUIDB.blizzWindowSkinStyles
    if styles and styles[winKey] == "modern" then return "modern" end
    return "eui"
end

-- Turn off every window reskin at once (used by the one-time feature-intro
-- popup's "Disable" button). Writes an explicit false to each window's enable
-- key so GetBlizzWindowStyle reports "off"; blizzWindowSkinStyles is left
-- intact, so a later re-enable restores each window's chosen style. Reskins
-- install at load, so the caller must reload for this to fully apply.
function EllesmereUI.DisableAllBlizzWindowSkins()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    for _, ek in pairs(WINDOW_ENABLE_KEYS) do
        EllesmereUIDB[ek] = false
    end
end

-------------------------------------------------------------------------------
--  Tooltip / Context Menu / Static Popup Skinning
--  Restyles Blizzard's GameTooltip and related frames with EUI's dark style.
--  Visual-only changes (alpha, backdrop color, font). No Hide/Show/SetParent
--  on Blizzard frames. All hooks are post-hooks via hooksecurefunc.
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
    -- Popups + context menus reskin (the generic right-click menus and Blizzard
    -- StaticPopups). Split out of the old customTooltips master, which now governs
    -- ONLY the game tooltip. reskinPopupsMenus is seeded from customTooltips once
    -- at login (see PLAYER_LOGIN) so existing users keep their state, then the two
    -- are independent. NOTE: the specific BLIZZARD WINDOW RESKINS (queue popup,
    -- game menu, group finder, great vault) are independent of BOTH masters.
    local function _pmEnabled()
        return not EllesmereUIDB or EllesmereUIDB.reskinPopupsMenus ~= false
    end

    local function _ttSkin(tt, _, isEmbedded)
        if not tt or tt:IsForbidden() or not _enabled() then return end
        -- Embedded tooltips (e.g. EmbeddedItemTooltip, the reward-item block
        -- inside a world-quest tooltip) render INSIDE a parent tooltip.
        -- Adding our bg + border to them makes the embedded block look like
        -- a standalone framed tooltip sitting inside the parent.
        if isEmbedded or tt.IsEmbedded then return end
        if _isSecret and _isSecret(tt:GetWidth()) then return end
        if not _PP then _PP = EllesmereUI and EllesmereUI.PP end
        if tt.NineSlice then tt.NineSlice:SetAlpha(0) end
        if not GetFFD(tt).bg then
            GetFFD(tt).bg = tt:CreateTexture(nil, "BACKGROUND", nil, -8)
            GetFFD(tt).bg:SetAllPoints()
            if _PP and _PP.CreateBorder then
                local bR, bG, bB, bA, bSize = EllesmereUI.GetTooltipBorder()
                _PP.CreateBorder(tt, bR, bG, bB, bA, bSize, "OVERLAY", 7)
            end
        end
        -- Unified, user-customizable background (shared with the EUI custom
        -- tooltips via EllesmereUI.GetTooltipBg). Re-applied each skin call so a
        -- settings change shows on the next tooltip.
        GetFFD(tt).bg:SetColorTexture(EllesmereUI.GetTooltipBg())
        GetFFD(tt).bg:Show()
        -- Border size + colour are user-customizable (Blizz UI Enhanced >
        -- Blizzard Tooltip > Border). Re-applied each call like the bg so a
        -- change shows on the next tooltip; size 0 hides the border.
        if _PP and _PP.GetBorders and _PP.GetBorders(tt) then
            local bR, bG, bB, bA, bSize = EllesmereUI.GetTooltipBorder()
            if bSize and bSize > 0 then
                _PP.SetBorderSize(tt, bSize)
                _PP.SetBorderColor(tt, bR, bG, bB, bA)
                _PP.ShowBorder(tt)
            else
                _PP.HideBorder(tt)
            end
        end
    end

    local function _ttFonts(tt, startFrom)
        if not tt or tt:IsForbidden() or not _enabled() then return end
        local fp = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("blizzardSkin") or STANDARD_TEXT_FONT
        local ol = EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag("blizzardSkin") or ""
        local scale = EllesmereUIDB and EllesmereUIDB.tooltipFontScale or 1.0
        local titleSize = math.floor(13 * scale + 0.5)
        local bodySize  = math.floor(11 * scale + 0.5)
        local name = tt.GetName and tt:GetName()
        if not name then return end
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
        -- Re-show so the frame recalculates size with the new fonts. Gated
        -- on the skin toggle: with it off the fonts above were never
        -- applied, and the hook (uninstallable) must stay zero-cost.
        if _enabled() and not _ttRelaying[self] then
            _ttRelaying[self] = true
            self:Show()
            _ttRelaying[self] = nil
        end
    end

    local function _ttHook(tt)
        if not tt or tt:IsForbidden() or _ttSkinned[tt] then return end
        _ttSkinned[tt] = true
        tt:HookScript("OnShow", _ttOnShow)
    end

    local function _accentEnabled()
        return EllesmereUIDB and EllesmereUIDB.accentReskinElements
    end

    -- Unified inspect system: one NotifyInspect per GUID, one INSPECT_READY
    -- handler that feeds both tooltip ilvl cache and inspect sheet reskin.
    local _ilvlCache = {}       -- guid -> { ilvl = number, time = GetTime() }
    local _ilvlCacheTTL = 120
    -- Mount-name cache. Short TTL: mount state changes often, but this only
    -- needs to survive a single hover's refresh ticks so an unmounted player
    -- is scanned once, not once per tick. name = false means "scanned, none".
    local _mountCache = {}      -- guid -> { name = string|false, collected = bool|nil, time = GetTime() }
    local _mountCacheTTL = 3
    local _inspectPendingGUID = nil
    local _userInspectUntil = 0
    -- GUID the visible GameTooltip was last populated for (set by the Unit
    -- post-call, cleared on hide). Lets the async inspect handler confirm the
    -- tooltip still shows the inspected person before touching it.
    local _tipShownGUID = nil
    -- True when any left line already shows label, so an appended score/ilvl
    -- line never duplicates an equivalent line another Unit post-call produced.
    -- label is matched as a plain (non-pattern) substring, so "+" is literal.
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

    -- Returns the mount name shown on a unit and whether the LOCAL player has
    -- that mount collected (true/false, or nil when unknown -- e.g. the name
    -- could only be read from the aura, not MountJournal). Collection state is
    -- the 11th return of GetMountInfoByID, which is per-character.
    local function _getMountedAuraName(unit)
        if not unit or (_isSecret and _isSecret(unit)) then return nil end
        if not UnitExists(unit) or not UnitIsPlayer(unit) then return nil end
        if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
        if not (C_MountJournal and C_MountJournal.GetMountFromSpell) then return nil end

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
    hooksecurefunc("InspectUnit", function()
        _userInspectUntil = GetTime() + 2
    end)
    local _inspectFrame = CreateFrame("Frame")
    _inspectFrame:SetScript("OnEvent", function(self, _, guid)
        self:UnregisterEvent("INSPECT_READY")
        _inspectPendingGUID = nil
        if not guid or (_isSecret and _isSecret(guid)) then return end
        -- Read the inspected GUID's item level through a token derived from THAT
        -- GUID, so the value is captured even when the cursor has already left
        -- the unit, and is always cached under the GUID we actually inspected.
        if C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel and _G.UnitTokenFromGUID then
            local u = _G.UnitTokenFromGUID(guid)
            if u and not (_isSecret and _isSecret(u)) and UnitExists(u) then
                local val = C_PaperDollInfo.GetInspectItemLevel(u)
                if val and not (_isSecret and _isSecret(val)) and val > 0 then
                    _ilvlCache[guid] = { ilvl = math.floor(val), time = GetTime() }
                end
            end
        end
        -- Append to the live tooltip only while it still shows this same GUID,
        -- and only if our line is not already present.
        local cached = _ilvlCache[guid]
        local ttd = GetFFD(_GameTooltip)
        if cached and _GameTooltip:IsShown() and _tipShownGUID == guid
            and not ttd.ilvlShown
            and EllesmereUIDB and EllesmereUIDB.tooltipItemLevel ~= false
            and not _tipHasLine(_GameTooltip, EllesmereUI.L("Item Level")) then
            local nBefore = _GameTooltip:NumLines() or 0
            _GameTooltip:AddDoubleLine(EllesmereUI.L("Item Level:"), cached.ilvl, 1, 1, 1, 1, 1, 1)
            _ttFonts(_GameTooltip, nBefore + 1)
            _GameTooltip:Show()
            ttd.ilvlShown = true
        end
    end)
    -- Guard InspectGuildFrame_Update against nil guildName (our NotifyInspect
    -- can trigger LOD load before guild data is available from server).

    -- Expose for inspect sheet to use
    EllesmereUI._inspectCache = _ilvlCache

    -- Re-derive a CLEAN literal group unit token for a GUID by matching it
    -- against tokens we build ourselves (player / raidN / partyN). On secure
    -- raid-frame unit tooltips, GameTooltip:GetUnit() and UnitTokenFromGUID can
    -- hand back a secret/unusable token even though the member's GUID is clean,
    -- which starves the token-based APIs (M+ summary, inspect item level). A
    -- literal token string we construct here is never secret, so those work.
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

    -- Resolve who this unit tooltip was populated for. GameTooltip:SetUnit(u)
    -- drives the Unit data pass and stamps u's GUID into data.guid before this
    -- post-call runs, so data.guid is the one authoritative identity and is
    -- already correct on the very first hover. The cursor-focus "mouseover"
    -- token is NOT trusted for identity: the secure focus system updates it on
    -- its own schedule, so during fast frame movement and on the first hover it
    -- can still point at the previously hovered frame's unit (the wrong person).
    -- Returns (guid, token). token, when present, always maps to guid and is
    -- only used by token-based APIs (class fallback, M+ summary, inspect).
    -- Either may be nil, in which case callers skip our extras and leave a
    -- stock (plus any foreign) tooltip rather than attributing the wrong unit.
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
        -- Clean literal group token: covers our raid/party frames, where
        -- GetUnit()/UnitTokenFromGUID return secret tokens but the GUID is clean.
        if guid and not token then
            token = _CleanTokenForGUID(guid)
        end
        if guid and not token and _G.UnitTokenFromGUID then
            local tu = _G.UnitTokenFromGUID(guid)
            if tu and not (_isSecret and _isSecret(tu)) and UnitExists(tu) then token = tu end
        end
        -- Last resort: accept "mouseover" ONLY when it provably maps to the same
        -- authoritative guid. Recovers a usable token (for M+/ilvl/title) in
        -- restricted contexts where UnitTokenFromGUID hands back a secret token,
        -- without ever risking the cursor-lag wrong-person attribution.
        if guid and not token and UnitExists("mouseover") then
            local mg = UnitGUID("mouseover")
            if mg and not (_isSecret and _isSecret(mg)) and mg == guid then
                token = "mouseover"
            end
        end
        return guid, token
    end

    local function _ttUnitColor(tt, data)
        if tt ~= _GameTooltip or tt:IsForbidden() then return end
        local nLinesBefore = tt.NumLines and tt:NumLines() or 0
        -- Identity comes from the tooltip's own SetUnit data pass (data.guid),
        -- never the cursor-focus token, so it is correct on the first hover and
        -- never lags to the previously hovered frame.
        local guid, unit = _resolveTipIdentity(tt, data)
        -- Record who this render is for (so a late INSPECT_READY can confirm the
        -- tooltip still shows this person) and start this render's ilvl marker
        -- clean, before any early return.
        _tipShownGUID = guid
        local ttd = GetFFD(tt)
        ttd.ilvlShown = false
        if not guid then return end
        -- Class and plain name straight from the authoritative GUID, with a
        -- live-token fallback. Non-players get no additions, matching a stock
        -- hover (GetPlayerInfoByGUID returns no class for non-player GUIDs).
        local classFile, pname, prealm
        if GetPlayerInfoByGUID then
            local _, eClass, _, _, _, n, r = GetPlayerInfoByGUID(guid)
            if eClass and not (_isSecret and _isSecret(eClass)) then
                classFile, pname, prealm = eClass, n, r
            end
        end
        if not classFile and unit then
            if not UnitIsPlayer(unit) then return end
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
        -- Title hiding is the default (tooltipPlayerTitles is opt-in). Only
        -- rewrite line 1 when a title is genuinely present, so the common
        -- no-title case never clobbers name formatting Blizzard or another
        -- addon produced on line 1.
        if not (db and db.tooltipPlayerTitles) and pname
            and not (_isSecret and _isSecret(pname)) then
            local display = (prealm and prealm ~= "") and (pname .. "-" .. prealm) or pname
            local cur = _nameL1:GetText()
            -- Line 1 carries a title (or other decoration) when it differs from
            -- the plain name. With a clean unit token, confirm precisely via
            -- UnitPVPName so an equivalent plain-name form is never rewritten.
            -- Without a token -- e.g. our raid/party frames, whose unit token is
            -- secret in Midnight so only the GUID resolves -- fall back to the
            -- name-difference check so titles are still stripped there.
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
        -- Recolor only (never replaces text): name line and the health bar.
        local cc = _RAID_CC and _RAID_CC[classFile]
        if cc then
            _nameL1:SetTextColor(cc.r, cc.g, cc.b)
            if GameTooltipStatusBar then
                GameTooltipStatusBar:SetStatusBarColor(cc.r, cc.g, cc.b)
            end
        end
        -- Add guild rank next to guild name : Name-Realm [Rank]. The guild
        -- line is re-found on every call -- its index varies per unit (titles
        -- shift it), so a cached line would decorate the wrong row on other
        -- tooltips. Deduped like the M+ line below: refresh cycles re-run
        -- this postprocessor on text that may already carry the rank.
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
        -- M+ Score (append-only, deduped against any equivalent foreign line).
        if unit and db and db.tooltipMythicScore ~= false
            and C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary then
            local info = C_PlayerInfo.GetPlayerMythicPlusRatingSummary(unit)
            local score = info and info.currentSeasonScore
            if score and not (_isSecret and _isSecret(score)) and score > 0
                and not _tipHasLine(tt, "M+ Score") then
                local sColor = C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor
                    and C_ChallengeMode.GetDungeonScoreRarityColor(score)
                local r, g, b = 1, 1, 1
                if sColor then r, g, b = sColor.r, sColor.g, sColor.b end
                tt:AddDoubleLine("M+ Score:", score, 1, 1, 1, r, g, b)
            end
        end
        -- Mount name from the live helpful aura that MountJournal recognizes.
        -- Opt-in (default off). Per-GUID cached so refresh ticks on an
        -- unmounted player never re-walk the whole aura list.
        if unit and guid and db and db.tooltipShowMount and not _tipHasLine(tt, "Mount:") then
            local mountName, mountCollected
            local cached = _mountCache[guid]
            if cached and (GetTime() - cached.time) < _mountCacheTTL then
                mountName = cached.name
                mountCollected = cached.collected
            else
                local nm, col = _getMountedAuraName(unit)
                mountName = nm or false
                mountCollected = col
                _mountCache[guid] = { name = mountName, collected = mountCollected, time = GetTime() }
            end
            if mountName then
                -- Append a green check / red X for whether YOU own this mount
                -- (nil = unknown, so no marker) Credit for Fix: TipTac
                local valText = mountName
                if mountCollected == true then
                    valText = mountName .. " |TInterface\\RaidFrame\\ReadyCheck-Ready:0|t"
                elseif mountCollected == false then
                    valText = mountName .. " |TInterface\\RaidFrame\\ReadyCheck-NotReady:0|t"
                end
                tt:AddDoubleLine("Mount:", valText, 1, 1, 1, 1, 1, 1)
            end
        end
        -- Item Level. Cache is keyed strictly by the authoritative GUID so a
        -- read or write can never land under a different person than is shown.
        if db and db.tooltipItemLevel ~= false then
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
                    if not ilvl and not inspOpen and GetTime() > _userInspectUntil
                        and guid ~= _inspectPendingGUID and CanInspect(unit) and not InCombatLockdown() then
                        _inspectPendingGUID = guid
                        ClearInspectPlayer()
                        _inspectFrame:RegisterEvent("INSPECT_READY")
                        NotifyInspect(unit)
                    end
                end
            end
            if ilvl and not _tipHasLine(tt, EllesmereUI.L("Item Level")) then
                tt:AddDoubleLine(EllesmereUI.L("Item Level:"), ilvl, 1, 1, 1, 1, 1, 1)
                ttd.ilvlShown = true
            end
        end
        -- Re-apply our font to lines added after the OnShow pass.
        _ttFonts(tt, nLinesBefore)
    end

    -- Visual reskin: the dark bg/border (via _ttHook -> _ttSkin), EUI fonts, and
    -- the restyled tooltip status bar. Gated on "Reskin Tooltip" (customTooltips).
    local function _ttInitVisual()
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
            -- Deferred: SharedTooltip_SetBackdropStyle can fire from
            -- secure Blizzard code (casting bar, combat UI). Running
            -- _ttSkin synchronously inside the hook taints the call stack
            -- (BackdropTemplate OnLoad propagates to CastingBarFrame).
            hooksecurefunc("SharedTooltip_SetBackdropStyle", function(tt)
                C_Timer.After(0, function() _ttSkin(tt) end)
            end)
        end
        if GameTooltipStatusBar then
            GameTooltipStatusBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
            local sbBg = GameTooltipStatusBar:CreateTexture(nil, "BACKGROUND")
            sbBg:SetAllPoints(); sbBg:SetColorTexture(0, 0, 0, 0.5)
            GameTooltipStatusBar:ClearAllPoints()
            GameTooltipStatusBar:SetPoint("BOTTOMLEFT", _GameTooltip, "BOTTOMLEFT", 1, 1)
            GameTooltipStatusBar:SetPoint("BOTTOMRIGHT", _GameTooltip, "BOTTOMRIGHT", -1, 1)
            GameTooltipStatusBar:SetHeight(3)
        end
    end

    -- Tooltip DATA additions: class-colored names, player-title control, M+ score,
    -- item level (via _ttUnitColor) and accent spell/macro titles. Each has its own
    -- toggle (tooltipPlayerTitles / tooltipMythicScore / tooltipItemLevel /
    -- accentReskinElements), but the whole set is gated by the "Reskin Tooltip"
    -- master (customTooltips) -- the PLAYER_LOGIN handler only calls this when
    -- _enabled() -- so disabling the reskin grays out AND stops every tooltip
    -- option together. Idempotent so the live re-apply path can never double-register.
    local _ttDataInited = false
    local function _ttInitData()
        if _ttDataInited then return end
        _ttDataInited = true
        -- Clear the recorded identity when the tooltip hides so a late inspect
        -- result can never append to a tooltip that has since closed or switched
        -- to non-unit content. HookScript (never SetScript) keeps the secure
        -- OnHide handler intact.
        _GameTooltip:HookScript("OnHide", function() _tipShownGUID = nil end)
        -- Accent-color the title line for spells/macros (not items or units)
        local function _ttAccentTitle(tt)
            if tt ~= _GameTooltip or tt:IsForbidden() or not _accentEnabled() then return end
            if not _nameL1 then _nameL1 = _G.GameTooltipTextLeft1 end
            if _nameL1 then
                local EG = EllesmereUI.ELLESMERE_GREEN
                if EG then _nameL1:SetTextColor(EG.r, EG.g, EG.b) end
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

    -- Context menu skinning
    local _menuSkinned = {}

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
        if not _menuSkinned[frame] then
            _menuSkinned[frame] = true
            if _PP and _PP.CreateBorder then
                local RS = EllesmereUI.RESKIN
                _PP.CreateBorder(frame, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
            end
        end
    end

    local function _menuOnOpen(manager, _, menuDescription)
        if not _pmEnabled() then return end
        -- Defer out of the secure context. The post-hook runs inside
        -- Blizzard's protected menu pipeline; touching Blizzard objects
        -- here propagates taint to action bar buttons. 
        -- By the next frame the secure execution
        -- has finished so AddMenuAcquiredCallback is safe.
        C_Timer.After(0, function()
            local menu = manager.GetOpenMenu and manager:GetOpenMenu()
            if menu then
                _menuSkinFrame(menu)
            end
            if menuDescription and menuDescription.AddMenuAcquiredCallback then
                menuDescription:AddMenuAcquiredCallback(function(frame)
                    C_Timer.After(0, function()
                        _menuSkinFrame(frame)
                    end)
                end)
            end
        end)
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
    end

    -- Static popup skinning
    local function _popupSkin(popup)
        if not popup or popup:IsForbidden() then return end
        if not _pmEnabled() then return end
        -- Strip textures on the popup frame itself
        for i = 1, _select("#", popup:GetRegions()) do
            local r = _select(i, popup:GetRegions())
            if r and r:IsObjectType("Texture") and not GetFFD(r).owned then
                r:SetTexture(nil)
                if r.SetAtlas then r:SetAtlas("") end
            end
        end
        -- Hide the BG border frame (StaticPopupN.BG)
        if popup.BG then popup.BG:SetAlpha(0) end
        if popup.NineSlice then popup.NineSlice:SetAlpha(0) end
        -- Our dark background + border (once)
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
        -- Skin buttons (1-4 plus the optional extra action button)
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
                for j = 1, select("#", btn:GetRegions()) do
                    local r = select(j, btn:GetRegions())
                    if r and r:IsObjectType("Texture") and r ~= btn:GetFontString() then
                        r:SetTexture(nil)
                        if r.SetAtlas then r:SetAtlas("") end
                    end
                end
                local RS = EllesmereUI.RESKIN
                local EG = EllesmereUI.ELLESMERE_GREEN
                local useAccent = _accentEnabled() and EG
                local btnBg = btn:CreateTexture(nil, "BACKGROUND", nil, -6)
                btnBg:SetAllPoints()
                btnBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
                GetFFD(btnBg).owned = true
                GetFFD(btn).bg = btnBg
                if not _PP then _PP = EllesmereUI and EllesmereUI.PP end
                if _PP and _PP.CreateBorder then
                    if useAccent then
                        _PP.CreateBorder(btn, EG.r, EG.g, EG.b, 0.5, 1, "OVERLAY", 7)
                    else
                        _PP.CreateBorder(btn, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
                    end
                end
                -- House hover: 10% white wash (HIGHLIGHT layer only renders
                -- while the button is enabled and hovered).
                local hov = btn:CreateTexture(nil, "HIGHLIGHT")
                hov:SetColorTexture(1, 1, 1, 0.1)
                hov:SetAllPoints()
                GetFFD(hov).owned = true

                -- Mirror Blizzard's enabled/disabled state so buttons visibly
                -- dim when locked out (e.g. Release in boss combat).
                local function _euiRefreshEnabled(self)
                    local fs = self:GetFontString()
                    local enabled = (self.IsEnabled and self:IsEnabled()) and true or false
                    if fs then
                        if enabled then
                            local EG2 = EllesmereUI.ELLESMERE_GREEN
                            if _accentEnabled() and EG2 then
                                fs:SetTextColor(EG2.r, EG2.g, EG2.b, 1)
                            else
                                fs:SetTextColor(1, 1, 1, 1)
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
        end

        -- Hook UpdateRecapButton once per popup so our per-button enabled
        -- visual stays in sync with Blizzard's enable/disable state swaps.
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
        -- Skin edit box if present
        local eb = popup.editBox or (popup.GetName and _G[popup:GetName() .. "EditBox"])
        if eb and not GetFFD(eb).skinned then
            GetFFD(eb).skinned = true
            for j = 1, select("#", eb:GetRegions()) do
                local r = select(j, eb:GetRegions())
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
            -- Border matching the popup buttons (accent or white).
            local RS2 = EllesmereUI.RESKIN
            local EG3 = EllesmereUI.ELLESMERE_GREEN
            if not _PP then _PP = EllesmereUI and EllesmereUI.PP end
            if _PP and _PP.CreateBorder then
                if _accentEnabled() and EG3 then
                    _PP.CreateBorder(eb, EG3.r, EG3.g, EG3.b, 0.5, 1, "OVERLAY", 7)
                else
                    _PP.CreateBorder(eb, 1, 1, 1, RS2.BRD_ALPHA, 1, "OVERLAY", 7)
                end
            end
        end
    end

    local function _popupInit()
        for i = 1, STATICPOPUP_NUMDIALOGS or 4 do
            local popup = _G["StaticPopup" .. i]
            if popup then
                popup:HookScript("OnShow", function(self) _popupSkin(self) end)
            end
        end
    end

    do
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_LOGIN")
        f:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            -- "Reskin Tooltip" (customTooltips) is the master for ALL of EUI's
            -- tooltip handling: the visual reskin AND the data additions (class
            -- colors, player titles, M+ score, item level). When off, EUI leaves
            -- tooltips alone, matching the grayed-out tooltip options. The generic
            -- context menu / static popup reskins are independent (reskinPopupsMenus)
            -- and the per-window reskins use their own keys -- all seeded from the
            -- old master once by the blizzskin_reskin_master_split_v1 migration at
            -- parent ADDON_LOADED.
            if _enabled() then
                _ttInitData()
                _ttInitVisual()
            end
            if _pmEnabled() then
                _menuInit()
                _popupInit()
            end
        end)
    end
    EllesmereUI._initTooltipSkins = function() _ttInit(); _menuInit(); _popupInit() end

    ---------------------------------------------------------------------------
    --  LFG Queue Accept Popup: reskin + countdown timer bar
    --  Skins LFGDungeonReadyPopup the same way we skin StaticPopups, and
    --  adds an accent-colored countdown bar below the popup.
    ---------------------------------------------------------------------------
    do
        local TIMER_DURATION = 40
        local timerBar, timerText, timerEndTime

        -- Independent toggle, default on (not tied to any master reskin setting,
        -- including the window-skins style: this is a popup, not a window).
        local function IsQueueReskinOn()
            return not EllesmereUIDB or EllesmereUIDB.reskinQueuePopup ~= false
        end

        local function SkinQueuePopup()
            local popup = LFGDungeonReadyPopup
            if not popup then return end

            -- Strip Blizzard border/decoration textures on popup and dialog.
            -- Preserve dialog.background (the dungeon art image).
            local dialog = LFGDungeonReadyDialog
            local keepTextures = {}
            if dialog and dialog.background then keepTextures[dialog.background] = true end
            if dialog and dialog.bottomArt then keepTextures[dialog.bottomArt] = true end
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

            -- Reskin the close button (X)
            local closeBtn = _G.LFGDungeonReadyDialogCloseButton
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

            -- Our dark background + border (create once).
            -- Anchored to the dialog (not the popup wrapper) so the skin
            -- follows the dialog when a mover addon (DeModal, BlizzMove)
            -- lets the user drag LFGDungeonReadyDialog independently.
            if not GetFFD(popup).bg then
                local RS = EllesmereUI.RESKIN
                if not _PP then _PP = EllesmereUI and EllesmereUI.PP end
                local anchor = dialog or popup
                local bgFrame = CreateFrame("Frame", nil, anchor)
                bgFrame:SetAllPoints(anchor)
                bgFrame:SetFrameLevel(math.max(1, anchor:GetFrameLevel() - 1))
                GetFFD(popup).bgFrame = bgFrame
                GetFFD(popup).bg = bgFrame:CreateTexture(nil, "ARTWORK")
                GetFFD(popup).bg:SetAllPoints()
                GetFFD(popup).bg:SetColorTexture(RS.BG_R, RS.BG_G, RS.BG_B, RS.QT_ALPHA)
                GetFFD(GetFFD(popup).bg).owned = true
                if _PP and _PP.CreateBorder then
                    _PP.CreateBorder(bgFrame, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
                end
            end

            -- Skin buttons (Enter Dungeon / Leave Queue).
            -- Re-strip textures every show (Blizzard re-applies art on each popup).
            -- Only create bg/border once.
            if dialog then
                for _, btnName in ipairs({ "enterButton", "leaveButton" }) do
                    local btn = dialog[btnName]
                    if btn then
                        -- Force all Blizzard texture regions invisible (every show).
                        -- Named Left/Middle/Right textures are swapped by C++ on
                        -- mouse down so SetTexture alone doesn't stick.
                        for j = 1, select("#", btn:GetRegions()) do
                            local r = select(j, btn:GetRegions())
                            if r and r:IsObjectType("Texture") and not GetFFD(r).owned and r ~= btn:GetFontString() then
                                r:SetAlpha(0)
                            end
                        end
                        -- Named template textures
                        if btn.Left then btn.Left:SetAlpha(0) end
                        if btn.Middle then btn.Middle:SetAlpha(0) end
                        if btn.Right then btn.Right:SetAlpha(0) end
                        -- Create our bg/border + hook texture suppression once
                        if not GetFFD(btn).skinned then
                            GetFFD(btn).skinned = true
                            -- Hook SetAlpha on named textures so C++ press
                            -- state changes can't make them visible again
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
                            btnBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
                            GetFFD(btnBg).owned = true
                            if _PP and _PP.CreateBorder then
                                if useAccent then
                                    _PP.CreateBorder(btn, EG.r, EG.g, EG.b, 0.5, 1, "OVERLAY", 7)
                                else
                                    _PP.CreateBorder(btn, 1, 1, 1, RS2.BRD_ALPHA, 1, "OVERLAY", 7)
                                end
                            end
                            -- House hover: 10% white wash (owned, so the
                            -- every-show re-strip above leaves it alone).
                            local hov = btn:CreateTexture(nil, "HIGHLIGHT")
                            hov:SetColorTexture(1, 1, 1, 0.1)
                            hov:SetAllPoints()
                            GetFFD(hov).owned = true
                        end
                        -- Accent-color the button text (every show)
                        local EG = EllesmereUI.ELLESMERE_GREEN
                        local useAccent = _accentEnabled() and EG
                        local fs = btn:GetFontString()
                        if fs and useAccent then
                            fs:SetTextColor(EG.r, EG.g, EG.b, 1)
                        end
                    end
                end
            end
        end

        local timerBorder, timerBg

        local function ShowQueueTimer(useEuiStyle)
            local popup = LFGDungeonReadyPopup
            if not popup then return end

            if not timerBar then
                local timerParent = GetFFD(popup).bgFrame or dialog or popup
                timerBar = CreateFrame("StatusBar", nil, timerParent)
                timerBar:SetMinMaxValues(0, TIMER_DURATION)

                timerBg = timerBar:CreateTexture(nil, "BACKGROUND")
                timerBg:SetAllPoints()
                timerBg:SetColorTexture(0, 0, 0, 0.7)

                -- Blizzard-style casting bar border (hidden when EUI style)
                timerBorder = timerBar:CreateTexture(nil, "OVERLAY")
                timerBorder:SetTexture(130874)
                timerBorder:SetSize(256, 64)
                timerBorder:SetPoint("TOP", timerBar, 0, 28)

                timerText = timerBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                timerText:SetPoint("CENTER", timerBar, "CENTER", 0, 0)

                if EllesmereUI.RegAccent then
                    EllesmereUI.RegAccent({ type = "callback", fn = function()
                        if GetFFD(timerBar).style then
                            local r, g, b = EllesmereUI.GetAccentColor()
                            timerBar:SetStatusBarColor(r, g, b, 0.75)
                        end
                    end })
                end
            end

            -- Anchor to the dialog (not the popup wrapper) so the timer
            -- follows the dialog when a mover addon drags it independently.
            local dialog = LFGDungeonReadyDialog
            local anchorFrame = dialog or popup

            -- Switch style based on whether the popup reskin is active
            timerBar:ClearAllPoints()
            if useEuiStyle then
                timerBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
                local mult = (_PP and _PP.mult) or 1
                timerBar:SetHeight(11)
                timerBar:SetPoint("BOTTOMLEFT", anchorFrame, "BOTTOMLEFT", mult, mult)
                timerBar:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMRIGHT", -mult, mult)
                local ar, ag, ab = EllesmereUI.GetAccentColor()
                timerBar:SetStatusBarColor(ar, ag, ab, 0.75)
                timerBg:SetColorTexture(0, 0, 0, 0.5)
                timerBorder:Hide()
                timerBg:Show()
                -- Apply EUI font
                local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("extras"))
                    or "Fonts\\FRIZQT__.TTF"
                if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(timerText, true) end
                timerText:SetFont(fontPath, 9, "")
                timerText:SetTextColor(1, 0.831, 0, 1) -- #ffd400
                GetFFD(timerBar).style = true
            else
                -- Blizzard style (matches BigWigs look)
                timerBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
                timerBar:SetPoint("TOP", anchorFrame, "BOTTOM", 0, -5)
                timerBar:SetSize(190, 9)
                timerBar:SetStatusBarColor(1, 0.1, 0)
                timerBorder:Show()
                timerBg:Show()
                timerText:SetFontObject("GameFontHighlight")
                GetFFD(timerBar).style = false
            end

            -- Hide other addons' timer bars (BigWigs etc.)
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

        -- Skin the "queue missed" / role check status popup
        local function SkinQueueStatus()
            local status = _G.LFGDungeonReadyStatus
            if not status or not IsQueueReskinOn() then return end
            -- Strip textures (every show)
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
            -- Our bg + border (once)
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

        -- Hook LFGDungeonReadyStatus OnShow so the skin applies the moment
        -- the acceptance panel appears (before any specific event fires).
        local _statusHooked = false
        local function HookStatusOnShow()
            if _statusHooked then return end
            local status = _G.LFGDungeonReadyStatus
            if not status then return end
            _statusHooked = true
            status:HookScript("OnShow", function() SkinQueueStatus() end)
        end

        local lfgFrame = CreateFrame("Frame")
        lfgFrame:RegisterEvent("LFG_PROPOSAL_SHOW")
        lfgFrame:RegisterEvent("LFG_PROPOSAL_FAILED")
        lfgFrame:RegisterEvent("LFG_PROPOSAL_SUCCEEDED")
        lfgFrame:SetScript("OnEvent", function(_, event)
            if not EllesmereUIDB then return end
            if event == "LFG_PROPOSAL_SHOW" then
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

-------------------------------------------------------------------------------
--  Quick Keybind Frame: dark reskin matching the queue popup style.
--  Strips Blizzard decoration and applies dark bg + border + button reskin.
-------------------------------------------------------------------------------
do
    local _qkbSkinned = false
    local function SkinQuickKeybindFrame()
        if _qkbSkinned then return end
        local qkb = QuickKeybindFrame
        if not qkb then return end
        _qkbSkinned = true

        local RS = EllesmereUI.RESKIN
        local _PP = EllesmereUI and EllesmereUI.PP

        -- Strip all Blizzard background/border textures
        if qkb.NineSlice then qkb.NineSlice:SetAlpha(0) end
        if qkb.BG then qkb.BG:SetAlpha(0) end
        if qkb.Border then qkb.Border:SetAlpha(0) end
        if qkb.Bg then qkb.Bg:SetAlpha(0) end
        for i = 1, select("#", qkb:GetRegions()) do
            local r = select(i, qkb:GetRegions())
            if r and r:IsObjectType("Texture") and not GetFFD(r).owned then
                r:SetAlpha(0)
            end
        end

        -- Our dark background + border
        local bgFrame = CreateFrame("Frame", nil, qkb)
        bgFrame:SetAllPoints(qkb)
        bgFrame:SetFrameLevel(math.max(1, qkb:GetFrameLevel() - 1))
        local bg = bgFrame:CreateTexture(nil, "ARTWORK")
        bg:SetAllPoints()
        bg:SetColorTexture(RS.BG_R, RS.BG_G, RS.BG_B, RS.QT_ALPHA)
        GetFFD(bg).owned = true
        if _PP and _PP.CreateBorder then
            _PP.CreateBorder(bgFrame, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
        end

        -- Title header: it's a Frame with sub-textures; strip art, raise level
        if qkb.Header then
            qkb.Header:SetFrameLevel(qkb:GetFrameLevel() + 2)
            if qkb.Header.LeftBG then qkb.Header.LeftBG:SetAlpha(0) end
            if qkb.Header.CenterBG then qkb.Header.CenterBG:SetAlpha(0) end
            if qkb.Header.RightBG then qkb.Header.RightBG:SetAlpha(0) end
        end
        -- Instruction/output text: raise above our bg
        if qkb.InstructionText then
            qkb.InstructionText:SetDrawLayer("OVERLAY", 6)
        end
        if qkb.OutputText then
            qkb.OutputText:SetDrawLayer("OVERLAY", 6)
        end
        if qkb.CancelDescriptionText then
            qkb.CancelDescriptionText:SetDrawLayer("OVERLAY", 6)
        end

        -- Reskin buttons (Okay, Cancel, Defaults, UseCharacterBindings)
        local btnNames = { "OkayButton", "CancelButton", "DefaultsButton" }
        local EG = EllesmereUI.ELLESMERE_GREEN
        local useAccent = (EllesmereUIDB and EllesmereUIDB.accentReskinElements) and EG
        for _, name in ipairs(btnNames) do
            local btn = qkb[name]
            if btn and not GetFFD(btn).skinned then
                GetFFD(btn).skinned = true
                -- Strip button textures
                for j = 1, select("#", btn:GetRegions()) do
                    local r = select(j, btn:GetRegions())
                    if r and r:IsObjectType("Texture") and not GetFFD(r).owned and r ~= btn:GetFontString() then
                        r:SetAlpha(0)
                    end
                end
                if btn.Left then btn.Left:SetAlpha(0) end
                if btn.Middle then btn.Middle:SetAlpha(0) end
                if btn.Right then btn.Right:SetAlpha(0) end
                -- Hook texture suppression
                for _, texKey in ipairs({ "Left", "Middle", "Right" }) do
                    local tex = btn[texKey]
                    if tex and tex.SetAlpha then
                        hooksecurefunc(tex, "SetAlpha", function(self, a)
                            if a > 0 then self:SetAlpha(0) end
                        end)
                    end
                end
                -- Dark bg + border
                local btnBg = btn:CreateTexture(nil, "BACKGROUND", nil, -6)
                btnBg:SetAllPoints()
                btnBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
                GetFFD(btnBg).owned = true
                if _PP and _PP.CreateBorder then
                    if useAccent then
                        _PP.CreateBorder(btn, EG.r, EG.g, EG.b, 0.5, 1, "OVERLAY", 7)
                    else
                        _PP.CreateBorder(btn, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
                    end
                end
                -- Accent-color the button text (Blizzard hover turns it white)
                local fs = btn:GetFontString()
                if fs and useAccent then
                    fs:SetTextColor(EG.r, EG.g, EG.b, 1)
                end
            end
        end

        -- Checkbox styling (UseCharacterBindingsButton is a CheckButton)
        if qkb.UseCharacterBindingsButton and qkb.UseCharacterBindingsButton.SetCheckedTexture then
            -- Leave checkbox functional but ensure text is legible
            local cbText = qkb.UseCharacterBindingsButton.Text or qkb.UseCharacterBindingsButton.text
            if cbText then
                cbText:SetDrawLayer("OVERLAY", 6)
            end
        end
    end

    -- Hook QuickKeybindFrame show to apply skin. The addon is LoadOnDemand
    -- so the frame may not exist at login. Try after login, and also listen
    -- for ADDON_LOADED as a fallback for late loading.
    local _qkbHooked = false
    local function TryHookQKB()
        if _qkbHooked then return end
        if not EllesmereUIDB then return end
        if EllesmereUIDB.reskinQueuePopup == false then return end
        local qkb = QuickKeybindFrame
        if qkb then
            _qkbHooked = true
            qkb:HookScript("OnShow", SkinQuickKeybindFrame)
        end
    end
    local qkbSkinFrame = CreateFrame("Frame")
    qkbSkinFrame:RegisterEvent("PLAYER_LOGIN")
    qkbSkinFrame:RegisterEvent("ADDON_LOADED")
    qkbSkinFrame:SetScript("OnEvent", function(self, event, arg1)
        if event == "PLAYER_LOGIN" then
            self:UnregisterEvent("PLAYER_LOGIN")
            C_Timer.After(2, TryHookQKB)
        elseif event == "ADDON_LOADED" and arg1 == "Blizzard_QuickKeybind" then
            self:UnregisterEvent("ADDON_LOADED")
            C_Timer.After(0, TryHookQKB)
        end
    end)
end

-------------------------------------------------------------------------------
--  Premade Group Invite Popup: same dark skin as the LFG queue popup.
--  LFGListInviteDialog appears when a group leader accepts your application.
-------------------------------------------------------------------------------
do
    local function SkinPremadeInvite()
        local dialog = _G.LFGListInviteDialog
        if not dialog then return end
        if not EllesmereUIDB or not EllesmereUIDB.reskinQueuePopup then return end
        if GetFFD(dialog).skinned then return end
        GetFFD(dialog).skinned = true

        local RS = EllesmereUI.RESKIN
        local _PP = EllesmereUI and EllesmereUI.PP

        -- Strip Blizzard border/decoration only (preserve role icon + content)
        if dialog.Bg then dialog.Bg:SetAlpha(0) end
        if dialog.BG then dialog.BG:SetAlpha(0) end
        if dialog.NineSlice then dialog.NineSlice:SetAlpha(0) end
        if dialog.Border then dialog.Border:SetAlpha(0) end

        -- Dark bg + border
        local bg = dialog:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(RS.BG_R, RS.BG_G, RS.BG_B, RS.QT_ALPHA)
        GetFFD(bg).owned = true
        if _PP and _PP.CreateBorder then
            _PP.CreateBorder(dialog, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
        end

        -- Skin buttons
        local function _accentOn()
            return EllesmereUIDB and EllesmereUIDB.accentReskinElements
        end
        for _, btnName in ipairs({ "AcceptButton", "DeclineButton", "AcknowledgeButton" }) do
            local btn = dialog[btnName]
            if btn then
                -- Strip all texture regions (every show, Blizzard re-applies)
                for j = 1, select("#", btn:GetRegions()) do
                    local r = select(j, btn:GetRegions())
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
                    local EG = EllesmereUI.ELLESMERE_GREEN
                    local useAccent = _accentOn() and EG
                    local btnBg = btn:CreateTexture(nil, "BACKGROUND", nil, -6)
                    btnBg:SetAllPoints()
                    btnBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
                    GetFFD(btnBg).owned = true
                    if _PP and _PP.CreateBorder then
                        if useAccent then
                            _PP.CreateBorder(btn, EG.r, EG.g, EG.b, 0.5, 1, "OVERLAY", 7)
                        else
                            _PP.CreateBorder(btn, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
                        end
                    end
                end
                -- Accent text (every show)
                local EG = EllesmereUI.ELLESMERE_GREEN
                local useAccent = _accentOn() and EG
                local fs = btn:GetFontString()
                if fs and useAccent then
                    fs:SetTextColor(EG.r, EG.g, EG.b, 1)
                end
            end
        end
    end

    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(self, _, addon)
        if _G.LFGListInviteDialog then
            self:UnregisterAllEvents()
            _G.LFGListInviteDialog:HookScript("OnShow", SkinPremadeInvite)
        end
    end)
end

-------------------------------------------------------------------------------
--  LFG Application Dialog (Sign Up popup): same dark skin.
-------------------------------------------------------------------------------
do
    local function SkinApplicationDialog()
        local dialog = _G.LFGListApplicationDialog
        if not dialog then return end
        if not EllesmereUIDB or not EllesmereUIDB.reskinQueuePopup then return end
        if GetFFD(dialog).skinned then return end
        GetFFD(dialog).skinned = true

        local RS = EllesmereUI.RESKIN
        local _PP = EllesmereUI and EllesmereUI.PP

        -- Strip border/decoration only (preserve content)
        if dialog.Bg then dialog.Bg:SetAlpha(0) end
        if dialog.BG then dialog.BG:SetAlpha(0) end
        if dialog.NineSlice then dialog.NineSlice:SetAlpha(0) end
        if dialog.Border then dialog.Border:SetAlpha(0) end

        -- Dark bg + border
        local bg = dialog:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(RS.BG_R, RS.BG_G, RS.BG_B, RS.QT_ALPHA)
        GetFFD(bg).owned = true
        if _PP and _PP.CreateBorder then
            _PP.CreateBorder(dialog, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
        end

        -- Skin the description edit box
        local desc = _G.LFGListApplicationDialogDescription
        if desc then
            -- Strip all texture regions (edge textures, bg, etc.)
            for i = 1, select("#", desc:GetRegions()) do
                local r = select(i, desc:GetRegions())
                if r and r:IsObjectType("Texture") and not GetFFD(r).owned then
                    r:SetAlpha(0)
                end
            end
            if desc.NineSlice then desc.NineSlice:SetAlpha(0) end
            local descBg = desc:CreateTexture(nil, "BACKGROUND")
            descBg:SetAllPoints()
            descBg:SetColorTexture(0.06, 0.06, 0.06, 0.8)
            GetFFD(descBg).owned = true
            if _PP and _PP.CreateBorder then
                _PP.CreateBorder(desc, 1, 1, 1, 0.08, 1, "OVERLAY", 7)
            end
        end

        local function _accentOn()
            return EllesmereUIDB and EllesmereUIDB.accentReskinElements
        end
        for _, btnName in ipairs({ "SignUpButton", "CancelButton" }) do
            local btn = dialog[btnName]
            if btn and not GetFFD(btn).skinned then
                GetFFD(btn).skinned = true
                for j = 1, select("#", btn:GetRegions()) do
                    local r = select(j, btn:GetRegions())
                    if r and r:IsObjectType("Texture") and not GetFFD(r).owned and r ~= btn:GetFontString() then
                        r:SetAlpha(0)
                    end
                end
                if btn.Left then btn.Left:SetAlpha(0) end
                if btn.Middle then btn.Middle:SetAlpha(0) end
                if btn.Right then btn.Right:SetAlpha(0) end
                for _, texKey in ipairs({ "Left", "Middle", "Right" }) do
                    local tex = btn[texKey]
                    if tex and tex.SetAlpha then
                        hooksecurefunc(tex, "SetAlpha", function(self, a)
                            if a > 0 then self:SetAlpha(0) end
                        end)
                    end
                end
                local EG = EllesmereUI.ELLESMERE_GREEN
                local useAccent = _accentOn() and EG
                local btnBg = btn:CreateTexture(nil, "BACKGROUND", nil, -6)
                btnBg:SetAllPoints()
                btnBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
                GetFFD(btnBg).owned = true
                if _PP and _PP.CreateBorder then
                    if useAccent then
                        _PP.CreateBorder(btn, EG.r, EG.g, EG.b, 0.5, 1, "OVERLAY", 7)
                    else
                        _PP.CreateBorder(btn, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
                    end
                end
                local fs = btn:GetFontString()
                if fs and useAccent then
                    fs:SetTextColor(EG.r, EG.g, EG.b, 1)
                end
            end
        end
    end

    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(self, _, addon)
        if _G.LFGListApplicationDialog then
            self:UnregisterAllEvents()
            _G.LFGListApplicationDialog:HookScript("OnShow", SkinApplicationDialog)
        end
    end)
end

-------------------------------------------------------------------------------
--  Game Menu Skinning
--  Restyles the pause menu (GameMenuFrame) with EUI dark style + border.
--  Runs once on PLAYER_LOGIN so GameMenuFrame is available.
-------------------------------------------------------------------------------
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        if not GameMenuFrame then return end
        -- Independent toggle, default on (not tied to any master reskin setting,
        -- including the window-skins style: this is a popup menu, not a window).
        if EllesmereUIDB and EllesmereUIDB.reskinGameMenu == false then return end

        local RS = EllesmereUI.RESKIN
        local PP = EllesmereUI.PP
        local ELLESMERE_GREEN = EllesmereUI.ELLESMERE_GREEN or { r = 0.27, g = 0.86, b = 0.49 }

        -- Strip decorative textures
        for i = 1, select("#", GameMenuFrame:GetRegions()) do
            local r = select(i, GameMenuFrame:GetRegions())
            if r and r:IsObjectType("Texture") then r:SetAlpha(0) end
        end
        if GameMenuFrame.NineSlice then GameMenuFrame.NineSlice:SetAlpha(0) end
        if GameMenuFrame.Border then GameMenuFrame.Border:SetAlpha(0) end
        -- Strip header textures, accent-color the title, nudge down
        local header = GameMenuFrame.Header
        if header then
            for i = 1, select("#", header:GetRegions()) do
                local r = select(i, header:GetRegions())
                if r and r:IsObjectType("Texture") then r:SetAlpha(0) end
            end
            local headerText = header.Text or (header.GetRegions and select(1, header:GetRegions()))
            if headerText and headerText.SetTextColor then
                headerText:SetTextColor(ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, 1)
                local euiFont = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("blizzardSkin") or "Fonts\\FRIZQT__.TTF"
                local _, hSize = headerText:GetFont()
                headerText:SetFont(euiFont, hSize or 16, "")
            end
            header:ClearAllPoints()
            header:SetPoint("TOP", GameMenuFrame, "TOP", 0, -10)
        end
        -- Dark bg + border
        local gmBg = GameMenuFrame:CreateTexture(nil, "BACKGROUND")
        gmBg:SetAllPoints()
        gmBg:SetColorTexture(RS.BG_R, RS.BG_G, RS.BG_B, RS.QT_ALPHA)
        if PP and PP.CreateBorder then
            PP.CreateBorder(GameMenuFrame, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
        end
        -- Skin pooled buttons via InitButtons hook
        hooksecurefunc(GameMenuFrame, "InitButtons", function(menu)
            if not menu.buttonPool then return end
            for menuBtn in menu.buttonPool:EnumerateActive() do
                if not GetFFD(menuBtn).skinned then
                    GetFFD(menuBtn).skinned = true
                    for j = 1, select("#", menuBtn:GetRegions()) do
                        local r = select(j, menuBtn:GetRegions())
                        if r and r:IsObjectType("Texture") and r ~= menuBtn:GetFontString() then
                            r:SetAlpha(0)
                        end
                    end
                    if menuBtn.Left then menuBtn.Left:SetAlpha(0) end
                    if menuBtn.Middle then menuBtn.Middle:SetAlpha(0) end
                    if menuBtn.Right then menuBtn.Right:SetAlpha(0) end
                    for _, texKey in ipairs({ "Left", "Middle", "Right" }) do
                        local tex = menuBtn[texKey]
                        if tex and tex.SetAlpha then
                            hooksecurefunc(tex, "SetAlpha", function(self, a)
                                if a > 0 then self:SetAlpha(0) end
                            end)
                        end
                    end
                    -- Inset container: bg + border sit 2px inside the
                    -- button edges for a tighter, cleaner look.
                    local inset = CreateFrame("Frame", nil, menuBtn)
                    inset:SetPoint("TOPLEFT", 2, -2)
                    inset:SetPoint("BOTTOMRIGHT", -2, 2)
                    inset:SetFrameLevel(menuBtn:GetFrameLevel())
                    local btnBg = inset:CreateTexture(nil, "BACKGROUND", nil, -6)
                    btnBg:SetAllPoints()
                    btnBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
                    if PP and PP.CreateBorder then
                        PP.CreateBorder(inset, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
                    end
                    local hl = menuBtn:CreateTexture(nil, "HIGHLIGHT")
                    hl:SetAllPoints(inset)
                    hl:SetColorTexture(1, 1, 1, 0.1)
                    local fs = menuBtn:GetFontString()
                    if fs then
                        local euiFont = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("blizzardSkin") or nil
                        local _, size, flags = fs:GetFont()
                        fs:SetFont(euiFont or "Fonts\\FRIZQT__.TTF", (size or 14) - 2, flags or "")
                    end
                end
            end
        end)
    end)
end

-------------------------------------------------------------------------------
--  UberTooltips CVar enforcement (only if user has manually set it in EUI)
-------------------------------------------------------------------------------
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        if not EllesmereUIDB then EllesmereUIDB = {} end
        if EllesmereUIDB.uberTooltipsManual then
            SetCVar("UberTooltips", EllesmereUIDB.uberTooltips and "1" or "0")
        else
            SetCVar("UberTooltips", "1")
        end
    end)
end

-------------------------------------------------------------------------------
--  Anchor Tooltip to Cursor
--  Re-owns the default GameTooltip to a 1x1 frame that tracks the mouse, so the
--  tooltip follows the cursor with a user-chosen position + X/Y offset.
--  GameTooltip_SetDefaultAnchor is the post-hook every default-anchored tooltip
--  (units, world objects, action buttons) runs through, so re-pointing it there
--  covers them all. The hook is installed on first enable and re-checks the flag,
--  so it's a no-op (Blizzard's default anchor stands) when toggled back off, and
--  the cursor-tracking frame only ticks while a tooltip is actually shown.
-------------------------------------------------------------------------------
do
    -- Selected position = where the tooltip sits relative to the cursor, so the
    -- tooltip corner that touches the cursor is the opposite one.
    local POINT_FOR_POS = {
        bottomright = "TOPLEFT",
        bottomleft  = "TOPRIGHT",
        topright    = "BOTTOMLEFT",
        topleft     = "BOTTOMRIGHT",
        right       = "LEFT",
        left        = "RIGHT",
        top         = "BOTTOM",
        bottom      = "TOP",
        center      = "CENTER",
    }

    local cursorFrame
    local hooked = false

    local function EnsureCursorFrame()
        if cursorFrame then return cursorFrame end
        cursorFrame = CreateFrame("Frame", "EllesmereUI_TooltipCursorAnchor", UIParent)
        cursorFrame:SetSize(1, 1)
        cursorFrame:SetFrameStrata("TOOLTIP")
        cursorFrame:Hide()
        local lastX, lastY
        cursorFrame:SetScript("OnUpdate", function(self)
            local scale = UIParent:GetEffectiveScale()
            if scale <= 0 then return end
            local x, y = GetCursorPosition()
            if x ~= lastX or y ~= lastY then
                lastX, lastY = x, y
                self:ClearAllPoints()
                self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
            end
        end)
        return cursorFrame
    end

    -- Show + position the tracking frame at the pointer right now. The OnUpdate
    -- alone only repositions it on the NEXT frame, so a tooltip anchored to it
    -- and shown synchronously this frame (as the custom CDM frames do) would have
    -- no valid rect yet -- and nothing renders.
    local function PositionCursorFrameNow(cf)
        cf:Show()
        local scale = UIParent:GetEffectiveScale()
        if scale > 0 then
            local x, y = GetCursorPosition()
            cf:ClearAllPoints()
            cf:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
        end
    end

    local function ApplyCursorAnchor(tooltip, parent)
        if tooltip ~= GameTooltip then return end
        -- Gated by the "Reskin Tooltip" master (matches the grayed-out option), so
        -- disabling the reskin restores the default tooltip position.
        if EllesmereUIDB and EllesmereUIDB.customTooltips == false then return end
        if not (EllesmereUIDB and EllesmereUIDB.tooltipAnchorCursor) then return end
        if not parent or tooltip:IsForbidden() then return end
        -- "Show Tooltips" suppression parks the tip in a hidden host (see the
        -- Show Tooltips block below): it stays alive and invisible so the
        -- peek modifier can reveal it. Anchor it normally -- it must already
        -- be riding the cursor when revealed. (The old Hide()-based
        -- suppression needed an early-return here to avoid undoing its Hide.)
        local cf = EnsureCursorFrame()
        PositionCursorFrameNow(cf)
        local point = POINT_FOR_POS[EllesmereUIDB.tooltipCursorPosition or "top"] or "BOTTOM"
        tooltip:SetOwner(parent, "ANCHOR_NONE")
        tooltip:ClearAllPoints()
        tooltip:SetPoint(point, cf, "CENTER",
            EllesmereUIDB.tooltipCursorOffsetX or 0,
            EllesmereUIDB.tooltipCursorOffsetY or 0)
    end

    -- Re-assert the cursor anchor on GameTooltip WITHOUT re-owning it (SetOwner
    -- would wipe the content). A custom frame whose tooltip content-setter
    -- (e.g. SetItemByID) clears/hides the tip mid-build can fire GameTooltip's
    -- OnHide -- which hides the tracking frame -- leaving the tip anchored to a
    -- hidden/unpositioned frame so it never appears. Calling this AFTER the
    -- content is set (and before Show) re-shows + repositions the tracking frame
    -- and re-points the tooltip so it reliably renders at the cursor. No-op when
    -- the cursor anchor (or the reskin master) is off, so callers can call it
    -- unconditionally.
    EllesmereUI._repointTooltipAtCursor = function(tooltip)
        if tooltip ~= GameTooltip then return end
        if EllesmereUIDB and EllesmereUIDB.customTooltips == false then return end
        if not (EllesmereUIDB and EllesmereUIDB.tooltipAnchorCursor) then return end
        if tooltip:IsForbidden() then return end
        local cf = EnsureCursorFrame()
        PositionCursorFrameNow(cf)
        local point = POINT_FOR_POS[EllesmereUIDB.tooltipCursorPosition or "top"] or "BOTTOM"
        tooltip:ClearAllPoints()
        tooltip:SetPoint(point, cf, "CENTER",
            EllesmereUIDB.tooltipCursorOffsetX or 0,
            EllesmereUIDB.tooltipCursorOffsetY or 0)
    end

    local function InstallHook()
        if hooked then return end
        hooked = true
        EnsureCursorFrame()
        -- Stop the tracker when the tooltip closes; ApplyCursorAnchor reshows it.
        GameTooltip:HookScript("OnHide", function()
            if cursorFrame then cursorFrame:Hide() end
        end)
        hooksecurefunc("GameTooltip_SetDefaultAnchor", ApplyCursorAnchor)
        -- World-unit tooltips fade out (~1-2s) instead of hiding on mouse-off,
        -- unlike unitframe/item/buff/CDM tips which Hide() instantly. While the
        -- tip rides the cursor that lingering fade trails the pointer, so collapse
        -- it to an instant hide -- only while the cursor anchor is actually on.
        if GameTooltip.FadeOut then
            hooksecurefunc(GameTooltip, "FadeOut", function(self)
                if self ~= GameTooltip then return end
                if EllesmereUIDB and EllesmereUIDB.tooltipAnchorCursor then
                    self:Hide()
                end
            end)
        end
    end

    EllesmereUI._applyTooltipCursorAnchor = function()
        if EllesmereUIDB and EllesmereUIDB.tooltipAnchorCursor then
            InstallHook()
        elseif cursorFrame then
            cursorFrame:Hide()
        end
    end

    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        EllesmereUI._applyTooltipCursorAnchor()
    end)
end

-------------------------------------------------------------------------------
--  Show Tooltips (global visibility mode). The "Blizzard Tooltip" dropdown
--  (EllesmereUIDB.tooltipShowMode, default "always") suppresses the game tooltip
--  by combat state, applied to EVERY default-anchored tooltip via the same
--  GameTooltip_SetDefaultAnchor post-hook the cursor anchor uses (units, world
--  objects, action buttons). Deliberately no per-type logic -- kept light:
--    always          -> never suppressed (default; the hook early-outs)
--    outOfCombat     -> hidden while in combat lockdown
--    outOfBossCombat -> hidden while a boss encounter is in progress
--    never           -> hidden always
--  IsEncounterInProgress() is queried inline (only for the outOfBossCombat case)
--  so there is no ENCOUNTER event bookkeeping. Installed once at load; a no-op
--  for the default mode, costing one table read per tooltip when unused.
--  An optional "peek" modifier (tooltipShowModifier) lifts suppression while the
--  chosen key is held, so a suppressed tip can be read on hover (e.g. mid-combat).
--  Suppression keeps the tooltip SHOWN but parked in a hidden host frame (never
--  Hide, never alpha) so peek is a pure reparent flip -- rebuilding a hidden
--  tooltip from insecure code errors on secret cooldown data in combat, and
--  alpha is engine-owned (FadeOut snaps it back and leaks the tip).
-------------------------------------------------------------------------------
do
    local function ShowModifierHeld()
        local mod = (EllesmereUIDB and EllesmereUIDB.tooltipShowModifier) or "none"
        if mod == "none" then return false end
        if mod == "control" then return IsControlKeyDown() end
        if mod == "alt" then return IsAltKeyDown() end
        return IsShiftKeyDown()
    end

    -- Exposed so modules with their own tooltip suppression (e.g. the raid/party
    -- frames, whose OnEnter hides tips per its own combat mode) can let the same
    -- peek modifier reveal their tips through their normal hover path.
    function EllesmereUI._tooltipPeekHeld()
        return ShowModifierHeld()
    end

    -- Shared decision: should GameTooltip be suppressed right now given the
    -- user's "Show Tooltips" mode + combat state? Exposed on EllesmereUI so the
    -- cursor-anchor hook can honor it too (otherwise the cursor re-anchor would
    -- re-show a tooltip this hook just hid).
    function EllesmereUI._tooltipSuppressedByMode(tooltip)
        if tooltip ~= GameTooltip then return false end
        if tooltip.IsForbidden and tooltip:IsForbidden() then return false end
        -- Gated by the "Reskin Tooltip" master (matches the grayed-out "Show
        -- Tooltips" option), so disabling the reskin never leaves tooltips stuck
        -- suppressed at, e.g., "Never".
        if EllesmereUIDB and EllesmereUIDB.customTooltips == false then return false end
        local mode = (EllesmereUIDB and EllesmereUIDB.tooltipShowMode) or "always"
        if mode == "always" then return false end
        if ShowModifierHeld() then return false end
        if mode == "never" then
            return true
        elseif mode == "outOfCombat" then
            return InCombatLockdown()
        elseif mode == "outOfBossCombat" then
            return IsEncounterInProgress()
        end
        return false
    end

    -- Suppression parks the tooltip in a hidden host frame -- NOT Hide() and
    -- NOT alpha. Hide()-based suppression forced the peek path to REBUILD the
    -- tooltip from our insecure execution: in combat, action tooltips read
    -- secret cooldown data and that rebuild hard-errors ("secret values are
    -- only allowed during untainted execution"), which the FireHoveredOnEnter
    -- pcall silently swallowed -- peek looked dead in combat on action bars.
    -- Alpha-based suppression fought the engine: FadeOut (hover-off on world
    -- units) snaps alpha back to full and animates it down, leaking the tip.
    -- Parking wins both ways: the tooltip stays SHOWN (the secure hover path
    -- keeps building and refreshing it), visibility inherits from the hidden
    -- host regardless of what the engine does to alpha, and peek is a pure
    -- reparent flip. NOTE: OnHide never fires while parked (the frame is not
    -- visible), so restore CANNOT rely on it -- the SetOwner hook below is
    -- the restore point: every tooltip build starts with SetOwner, so an
    -- explicitly-anchored use (bags, other addons) that never passes
    -- SetDefaultAnchor can't inherit a parked tooltip; default-anchored
    -- builds re-park right after, in the SetDefaultAnchor post-hook (its
    -- internal SetOwner runs before that hook fires).
    local _suppressHost = CreateFrame("Frame", nil, UIParent)
    _suppressHost:Hide()
    local _parked = false
    local _defaultAnchored = false
    local _origParent, _origStrata
    local function ParkTooltip(tt)
        if _parked then return end
        _parked = true
        _origParent = tt:GetParent()
        if _origParent == _suppressHost then _origParent = nil end
        _origStrata = tt:GetFrameStrata()
        tt:SetParent(_suppressHost)
    end
    local function UnparkTooltip(tt)
        if not _parked then return end
        _parked = false
        tt:SetParent(_origParent or UIParent)
        -- SetParent can demote strata; the tooltip must stay topmost.
        tt:SetFrameStrata(_origStrata or "TOOLTIP")
    end
    local function ApplySuppression(tt)
        if EllesmereUI._tooltipSuppressedByMode(tt) then
            ParkTooltip(tt)
        else
            UnparkTooltip(tt)
        end
    end
    local function SuppressTooltipByMode(tooltip)
        if tooltip ~= GameTooltip then return end
        _defaultAnchored = true
        ApplySuppression(tooltip)
    end
    if GameTooltip_SetDefaultAnchor then
        hooksecurefunc("GameTooltip_SetDefaultAnchor", SuppressTooltipByMode)
    end
    hooksecurefunc(GameTooltip, "SetOwner", function(tt)
        _defaultAnchored = false
        UnparkTooltip(tt)
    end)
    GameTooltip:HookScript("OnHide", function(tt)
        -- Only fires for unparked hides (a parked tooltip is never visible);
        -- kept so a normal hide clears the default-anchored flag promptly.
        _defaultAnchored = false
    end)

    -- Live peek: pressing the modifier while already hovering reveals the tip
    -- for the current frame; releasing it hides it again. Moving onto other
    -- frames while the key stays held reveals each in turn through the normal
    -- hover path -- suppression is lifted while held (globally via
    -- _tooltipSuppressedByMode, and per-module via _tooltipPeekHeld, which the
    -- raid/party frames honor in their own OnEnter).
    local function KeyMatchesModifier(key, mod)
        return (mod == "shift"   and (key == "LSHIFT" or key == "RSHIFT"))
            or (mod == "control" and (key == "LCTRL"  or key == "RCTRL"))
            or (mod == "alt"     and (key == "LALT"   or key == "RALT"))
    end
    -- Reveal the tooltip for whatever the cursor is over. First re-run the
    -- hovered frame's OnEnter (buttons, icons, unit frames build their own
    -- tip) -- the topmost mouse-focus frame is often an overlay without one,
    -- so scan every frame under the cursor and walk up parents. Nameplates'
    -- clickable frame has an OnEnter that builds nothing (its tip comes from
    -- the engine's mouseover unit on a real hover), so fall back to driving
    -- the unit tooltip directly when one is up.
    local function FireHoveredOnEnter()
        local foci = (GetMouseFoci and GetMouseFoci()) or (GetMouseFocus and { GetMouseFocus() })
        local anchorFrame = foci and foci[1]
        if foci then
            for _, focus in ipairs(foci) do
                local frame = focus
                while frame and frame ~= WorldFrame and frame ~= UIParent do
                    if frame.GetScript then
                        local onEnter = frame:GetScript("OnEnter")
                        if onEnter then
                            pcall(onEnter, frame)
                            if GameTooltip:IsShown() then return end
                            anchorFrame = frame
                            break
                        end
                    end
                    frame = frame.GetParent and frame:GetParent()
                end
            end
        end
        if not GameTooltip:IsShown() and UnitExists("mouseover") then
            GameTooltip_SetDefaultAnchor(GameTooltip, anchorFrame or UIParent)
            GameTooltip:SetUnit("mouseover")
            if EllesmereUI._repointTooltipAtCursor then
                EllesmereUI._repointTooltipAtCursor(GameTooltip)
            end
            GameTooltip:Show()
        end
    end
    local modWatcher = CreateFrame("Frame")
    modWatcher:RegisterEvent("MODIFIER_STATE_CHANGED")
    modWatcher:SetScript("OnEvent", function(_, _event, key, down)
        if EllesmereUIDB and EllesmereUIDB.customTooltips == false then return end
        local mod = (EllesmereUIDB and EllesmereUIDB.tooltipShowModifier) or "none"
        if mod == "none" or not KeyMatchesModifier(key, mod) then return end
        if down == 1 then
            if _parked and GameTooltip:IsShown() then
                -- The parked tip is alive and current under the cursor
                -- (built by the secure hover path): just reveal it. Never
                -- rebuild it from here -- see the parking note above.
                UnparkTooltip(GameTooltip)
            else
                -- No live tip: module-built tips (raid frames, CDM) skip
                -- building while suppressed, so re-drive the hovered frame's
                -- OnEnter -- with the modifier now held they build normally.
                FireHoveredOnEnter()
            end
        elseif GameTooltip:IsShown() and EllesmereUI._tooltipSuppressedByMode(GameTooltip) then
            if _defaultAnchored then
                ParkTooltip(GameTooltip)
            else
                GameTooltip:Hide()
            end
        end
    end)
end

-------------------------------------------------------------------------------
--  Hide Unit Health Strip. GameTooltipStatusBar is Blizzard's health bar at the
--  bottom of unit tooltips. We suppress it with a single SetAlpha(0) -- fully
--  taint-safe: only the one top-level bar is touched, it is never Shown/Hidden
--  or given custom keys, and observation is via hooksecurefunc (never SetScript).
--  The hook fires only when Blizzard shows the bar (unit tooltips), covering
--  every anchor path (default, cursor, unit-frame), and early-outs when the
--  feature is off -- so it costs one table read when disabled and one SetAlpha
--  when enabled. Default ENABLED (nil / true = hidden). Independent of the
--  reskin: works on default Blizzard tooltips too.
-------------------------------------------------------------------------------
do
    local function _healthStripHidden()
        -- Default enabled: hidden unless the user explicitly turned it off.
        return not (EllesmereUIDB and EllesmereUIDB.tooltipHideHealthStrip == false)
    end

    -- Live apply for the options toggle (immediate hide/restore) and login seed.
    EllesmereUI._applyTooltipHealthStrip = function()
        if not GameTooltipStatusBar then return end
        GameTooltipStatusBar:SetAlpha(_healthStripHidden() and 0 or 1)
    end

    if GameTooltipStatusBar then
        -- Re-assert alpha 0 each time Blizzard shows the bar so it can never
        -- flash back into view. SetAlpha does not call Show, so no recursion.
        hooksecurefunc(GameTooltipStatusBar, "Show", function(bar)
            if _healthStripHidden() then bar:SetAlpha(0) end
        end)
        EllesmereUI._applyTooltipHealthStrip()
    end
end
