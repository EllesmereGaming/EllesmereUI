if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIBlizzardSkin.lua
--  Umbrella addon for themed Blizzard UI frames. Hosts the Character Sheet
--  rework (EllesmereUIBlizzardSkin_CharacterSheet.lua) plus the tooltip,
--  context menu and static popup reskinning below.
-------------------------------------------------------------------------------
local ADDON_NAME = ...
if not (EllesmereUI and EllesmereUI._ModuleNS) then EUI_CLIENT_BLOCKED = true; return end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring
EllesmereUI._ModuleNS[ADDON_NAME] = select(2, ...)  -- LOD options files read this module ns via the registry

-- External weak-keyed lookup table for frame state (prevents tainting Blizzard frames)
local FFD = setmetatable({}, { __mode = "k" })
local function GetFFD(frame)
    local d = FFD[frame]
    if not d then d = {}; FFD[frame] = d end
    return d
end

-------------------------------------------------------------------------------
--  Per-window skin style ("eui"|"modern"|"off"). Enable keys are the on/off
--  source of truth (key false = "off"); blizzWindowSkinStyles only records
--  WHICH style an enabled window uses (nil = "eui"). "modern" currently
--  renders identically to "eui" (reserved for a future skin set).
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
    itemupgrade     = "reskinItemUpgrade",
    loot            = "reskinLoot",
    loottoast       = "reskinLootToast",
    lootroll        = "reskinLootRoll",
    loothistory     = "reskinLootHistory",
    groupinvite     = "reskinGroupInvite",
    readycheck      = "reskinReadyCheck",
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
    socialui        = "reskinSocialUI",
    -- delvepicker is the Delves TIER PICKER, a separate frame from the
    -- companion configuration window that `delves` above covers.
    queuestatus     = "reskinQueueStatus",
    delvepicker     = "reskinDelvePicker",
    playerchoice    = "reskinPlayerChoice",
    trade           = "reskinTrade",
}
--- Master PER-PROFILE kill switch for ALL Blizzard window skinning: window engine
--- + every pack, plus CharacterSheet/Inspect, SocketPanel, LFG skins. Lives at
--- profiles[name].disableWindowSkins, resolved live (follows profile switches,
--- rides exports); nil/false = enabled. Per-window enable keys and style picks are
--- PRESERVED while killed. Skins install at load, so crossings need a reload
--- (callers show the popup). Queue Popup, Pause Menu, and Dragon Riding are not windows and stay untouched.
function EllesmereUI.BlizzWindowSkinsKilled()
    local prof = EllesmereUI.GetActiveProfileData and EllesmereUI.GetActiveProfileData()
    return (prof and prof.disableWindowSkins) and true or false
end

-------------------------------------------------------------------------------
--  One-time style seed for window keys added after the fact: each adopts
--  whichever style (EUI/Modern/off) the user already runs MOST windows with,
--  instead of defaulting ON in EUI. Counts RAW stored state (not GetBlizzWindowStyle)
--  so the kill switch cannot skew the vote; touched keys are left alone; ties fall to
--  EUI. Marker-gated to once per account, at ADDON_LOADED (parent SVs are in by then, before PLAYER_LOGIN apply).
--
--  One BATCH per shipment, each with its OWN marker: a spent marker is never
--  revisited, so a later batch riding the older one would silently skip every
--  account that already ran it.
-------------------------------------------------------------------------------
do
    local BATCHES = {
        { marker = "lootSkinStyleSeeded",  keys = { "lootroll", "loothistory", "groupinvite" } },
        { marker = "readyCheckStyleSeeded", keys = { "readycheck" } },
        { marker = "queueChoiceTradeStyleSeeded",
          keys = { "queuestatus", "delvepicker", "playerchoice", "trade" } },
    }
    local function SeedBatch(marker, newKeys)
        if EllesmereUIDB[marker] then return end
        EllesmereUIDB[marker] = true
        local styles = EllesmereUIDB.blizzWindowSkinStyles
        local isNew = {}
        for _, k in ipairs(newKeys) do isNew[k] = true end
        local off, modern, eui = 0, 0, 0
        for winKey, ek in pairs(WINDOW_ENABLE_KEYS) do
            if not isNew[winKey] then
                if EllesmereUIDB[ek] == false then
                    off = off + 1
                elseif styles and styles[winKey] == "modern" then
                    modern = modern + 1
                else
                    eui = eui + 1
                end
            end
        end
        for _, winKey in ipairs(newKeys) do
            local ek = WINDOW_ENABLE_KEYS[winKey]
            local touched = EllesmereUIDB[ek] ~= nil
                or (styles and styles[winKey] ~= nil)
            if not touched then
                if off > eui and off > modern then
                    EllesmereUIDB[ek] = false
                elseif modern > eui and modern >= off then
                    if not styles then
                        styles = {}
                        EllesmereUIDB.blizzWindowSkinStyles = styles
                    end
                    styles[winKey] = "modern"
                end
                -- EUI majority (or tie): nil already means EUI-on.
            end
        end
    end
    local seedFrame = CreateFrame("Frame")
    seedFrame:RegisterEvent("ADDON_LOADED")
    seedFrame:SetScript("OnEvent", function(self, _, name)
        if name ~= ADDON_NAME then return end
        self:UnregisterEvent("ADDON_LOADED")
        if not EllesmereUIDB then EllesmereUIDB = {} end
        for _, batch in ipairs(BATCHES) do SeedBatch(batch.marker, batch.keys) end
    end)
end

function EllesmereUI.GetBlizzWindowStyle(winKey)
    -- Third-party virtual keys ("tp:<AddonName>", RegisterSkin API) resolve by majority
    -- vote and bypass the kill switch: third-party skinning is its own opt-in, so window-skin settings only pick WHICH theme, never whether it runs.
    if type(winKey) == "string" and winKey:sub(1, 3) == "tp:" then
        return EllesmereUI.GetThirdPartySkinStyle()
    end
    if EllesmereUI.BlizzWindowSkinsKilled() then return "off" end
    local ek = WINDOW_ENABLE_KEYS[winKey]
    if ek and EllesmereUIDB and EllesmereUIDB[ek] == false then return "off" end
    local styles = EllesmereUIDB and EllesmereUIDB.blizzWindowSkinStyles
    if styles and styles[winKey] == "modern" then return "modern" end
    return "eui"
end

--- Style for third-party addon skins: majority vote across the user's own window
--- styles. Modern majority -> "modern"; else (EUI majority, tie, or nothing skinned,
--- incl. under the kill switch where every window reports "off") -> "eui". Never
--- returns "off": whether third-party skinning runs is decided by its own toggles in
--- the SkinAPI dispatcher (reload-bound there), so live refreshes only ever swap between the two themes.
function EllesmereUI.GetThirdPartySkinStyle()
    local eui, modern = 0, 0
    for winKey in pairs(WINDOW_ENABLE_KEYS) do
        local s = EllesmereUI.GetBlizzWindowStyle(winKey)
        if s == "modern" then modern = modern + 1
        elseif s == "eui" then eui = eui + 1 end
    end
    return (modern > eui) and "modern" or "eui"
end

-- Turn off every window reskin at once (feature-intro popup's "Disable"). Writes explicit
-- false to each enable key (GetBlizzWindowStyle -> "off"); blizzWindowSkinStyles is left intact so re-enable restores styles. Reskins install at load, so the caller must reload.
function EllesmereUI.DisableAllBlizzWindowSkins()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    for _, ek in pairs(WINDOW_ENABLE_KEYS) do
        EllesmereUIDB[ek] = false
    end
end

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
        EllesmereUI.ApplyBorderStyle(data.configBorder, size, color.r, color.g, color.b, alpha,
            db[prefix .. "BorderTexture"] or "solid", db[prefix .. "BorderOffsetX"],
            db[prefix .. "BorderOffsetY"], db[prefix .. "BorderShiftX"], db[prefix .. "BorderShiftY"],
            "blizzardSkin", key)
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

    local function _ttFonts(tt, startFrom)
        if not tt or tt:IsForbidden() or not _enabled() then return end
        local fp = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("blizzardSkin") or STANDARD_TEXT_FONT
        local ol = EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag("blizzardSkin") or ""
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
        _ttSkinned[tt] = true
        tt:HookScript("OnShow", _ttOnShow)
    end

    local function _accentEnabled()
        -- False in native mode so gated surfaces keep their else-branch look (unrecolored/plain white).
        return _elementColorMode() ~= "native"
    end

    -- Unified inspect system: one NotifyInspect per GUID, one INSPECT_READY handler that feeds both tooltip ilvl cache and inspect sheet reskin.
    local _ilvlCache = {}       -- guid -> { ilvl = number, time = GetTime() }
    local _ilvlCacheTTL = 120
    -- Mount-name cache: short TTL, just enough to survive one hover's refresh ticks so an unmounted player is scanned once, not per tick. name=false means "scanned, none".
    local _mountCache = {}      -- guid -> { name = string|false, collected = bool|nil, time = GetTime() }
    local _mountCacheTTL = 3
    local _inspectPendingGUID = nil
    local _userInspectUntil = 0
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
    hooksecurefunc("InspectUnit", function()
        _userInspectUntil = GetTime() + 2
    end)
    local _inspectFrame = CreateFrame("Frame")
    _inspectFrame:SetScript("OnEvent", function(self, _, guid)
        self:UnregisterEvent("INSPECT_READY")
        _inspectPendingGUID = nil
        if not guid or (_isSecret and _isSecret(guid)) then return end
        -- Read item level through a token derived from THAT GUID, so it is captured even after the cursor left the unit and cached under the right GUID.
        if C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel and _G.UnitTokenFromGUID then
            local u = _G.UnitTokenFromGUID(guid)
            if u and not (_isSecret and _isSecret(u)) and UnitExists(u) then
                local val = C_PaperDollInfo.GetInspectItemLevel(u)
                if val and not (_isSecret and _isSecret(val)) and val > 0 then
                    _ilvlCache[guid] = { ilvl = math.floor(val), time = GetTime() }
                end
            end
        end
        -- Append only while the tooltip still shows this GUID and the line is not already present.
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
    -- Shared with the inspect sheet.
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
                and not _tipHasLine(tt, "M+ Score") then
                local sColor = C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor
                    and C_ChallengeMode.GetDungeonScoreRarityColor(score)
                local r, g, b = 1, 1, 1
                if sColor then r, g, b = sColor.r, sColor.g, sColor.b end
                tt:AddDoubleLine("M+ Score:", score, 1, 1, 1, r, g, b)
            end
        end
        -- Mount name from the live helpful aura MountJournal recognizes. Opt-in (default off); per-GUID cached so refresh ticks on an unmounted player never re-walk the aura list.
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
                -- Green check / red X for whether YOU own this mount (nil = unknown, no marker).
                local valText = mountName
                if mountCollected == true then
                    valText = mountName .. " |TInterface\\RaidFrame\\ReadyCheck-Ready:0|t"
                elseif mountCollected == false then
                    valText = mountName .. " |TInterface\\RaidFrame\\ReadyCheck-NotReady:0|t"
                end
                tt:AddDoubleLine("Mount:", valText, 1, 1, 1, 1, 1, 1)
            end
        end
        -- Who the hovered player currently targets (opt-in, default off).
        _ttTargetLine(tt, unit)
        -- Item Level. Cache keyed strictly by the authoritative GUID so reads/writes can never land under a different person.
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
        -- Re-apply our font to lines added after OnShow.
        _ttFonts(tt, nLinesBefore)
    end

    -- Visual reskin: dark bg/border (via _ttHook -> _ttSkin), EUI fonts, and restyled status bar. Gated on "Reskin Tooltip" (customTooltips).
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
            -- Deferred: SharedTooltip_SetBackdropStyle can fire from secure Blizzard code
            -- (casting bar, combat UI); a synchronous _ttSkin in the hook would taint the call stack (BackdropTemplate OnLoad propagates to CastingBarFrame).
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
    -- toggle (tooltipPlayerTitles/tooltipMythicScore/tooltipItemLevel/accentReskinElements),
    -- gated by the customTooltips master (PLAYER_LOGIN calls this only when _enabled()),
    -- so disabling the reskin stops every tooltip option too. Idempotent: safe for the live re-apply path to call again.
    local _ttDataInited = false
    local function _ttInitData()
        if _ttDataInited then return end
        _ttDataInited = true
        -- Clear the recorded identity on hide so a late inspect result can never append to a closed/switched tooltip. HookScript (never SetScript) keeps the secure OnHide handler intact.
        _GameTooltip:HookScript("OnHide", function() _tipShownGUID = nil end)
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
                for j = 1, select("#", btn:GetRegions()) do
                    local r = select(j, btn:GetRegions())
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
        for i = 1, STATICPOPUP_NUMDIALOGS or 4 do
            local popup = _G["StaticPopup" .. i]
            if popup then
                popup:HookScript("OnShow", function(self) _popupSkin(self) end)
            end
        end
    end

    ---------------------------------------------------------------------------
    --  Resurrect Accept Glow (resurrectAcceptGlow, default OFF)
    --  Pulsating border around button1 of the RESURRECT StaticPopups. Independent
    --  of reskinPopupsMenus. Zero cost until first enable: no hooks or frames exist
    --  before then. The overlay is our own frame (state in FFD); the pulse is a C-side Alpha AnimationGroup, so no per-frame Lua.
    ---------------------------------------------------------------------------
    local RES_WHICH = {
        RESURRECT             = true,
        RESURRECT_NO_SICKNESS = true,
        RESURRECT_NO_TIMER    = true,
    }
    local _resGlowHooked = false

    local function _resGlowEnabled()
        return EllesmereUIDB and EllesmereUIDB.resurrectAcceptGlow or false
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
        if _resGlowHooked then return end
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

                -- Blizzard-style casting bar border (hidden in EUI style).
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

            -- Anchor to the dialog, not the popup wrapper, so the timer follows it when a mover addon drags the dialog independently.
            local dialog = LFGDungeonReadyDialog
            local anchorFrame = dialog or popup

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
                local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("extras"))
                    or "Fonts\\FRIZQT__.TTF"
                if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(timerText, true) end
                timerText:SetFont(fontPath, 9, "")
                timerText:SetTextColor(1, 0.831, 0, 1) -- #ffd400
                GetFFD(timerBar).style = true
            else
                -- Blizzard style: stock bar texture + casting-bar border art.
                timerBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
                timerBar:SetPoint("TOP", anchorFrame, "BOTTOM", 0, -5)
                timerBar:SetSize(190, 9)
                timerBar:SetStatusBarColor(1, 0.1, 0)
                timerBorder:Show()
                timerBg:Show()
                timerText:SetFontObject("GameFontHighlight")
                GetFFD(timerBar).style = false
            end

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
            if _statusHooked then return end
            local status = _G.LFGDungeonReadyStatus
            if not status then return end
            _statusHooked = true
            status:HookScript("OnShow", function() SkinQueueStatus() end)
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
        end

        -- Not gated behind any LFG event: unlike the proposal/status popups above,
        -- this frame is part of the always-loaded base UI and can show independently
        -- of any Dungeon Finder UI ever being opened locally, so it is hooked directly.
        local _roleCheckHooked = false
        local function HookRoleCheckOnShow()
            if _roleCheckHooked then return end
            local popup = _G.LFDRoleCheckPopup
            if not popup then return end
            _roleCheckHooked = true
            popup:HookScript("OnShow", function() SkinRoleCheckPopup() end)
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

-------------------------------------------------------------------------------
--  Quick Keybind Frame: dark reskin matching the queue popup style.
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

        -- The header is a Frame with sub-textures: strip art, raise level.
        if qkb.Header then
            qkb.Header:SetFrameLevel(qkb:GetFrameLevel() + 2)
            if qkb.Header.LeftBG then qkb.Header.LeftBG:SetAlpha(0) end
            if qkb.Header.CenterBG then qkb.Header.CenterBG:SetAlpha(0) end
            if qkb.Header.RightBG then qkb.Header.RightBG:SetAlpha(0) end
        end
        -- Raise the instruction/output text above our bg.
        if qkb.InstructionText then
            qkb.InstructionText:SetDrawLayer("OVERLAY", 6)
        end
        if qkb.OutputText then
            qkb.OutputText:SetDrawLayer("OVERLAY", 6)
        end
        if qkb.CancelDescriptionText then
            qkb.CancelDescriptionText:SetDrawLayer("OVERLAY", 6)
        end

        local btnNames = { "OkayButton", "CancelButton", "DefaultsButton" }
        -- Native mode leaves button text un-recolored.
        local er,eg,eb=EllesmereUI._getPopupMenuButtonTextColor(); local EG={r=er,g=eg,b=eb}
        local useAccent = (EllesmereUI._getPopupMenuElementMode() ~= "native") and EG
        for _, name in ipairs(btnNames) do
            local btn = qkb[name]
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
                -- C++ swaps these on press, so re-suppress via a SetAlpha hook.
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
                btnBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
                GetFFD(btnBg).owned = true
                if _PP and _PP.CreateBorder then
                    if useAccent then
                        _PP.CreateBorder(btn, EG.r, EG.g, EG.b, 0.5, 1, "OVERLAY", 7)
                    else
                        _PP.CreateBorder(btn, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
                    end
                end
                -- Accent the text; Blizzard's hover turns it white.
                local fs = btn:GetFontString()
                if fs and useAccent then
                    fs:SetTextColor(EG.r, EG.g, EG.b, 1)
                end
            end
        end

        -- UseCharacterBindingsButton is a CheckButton: left functional, only its label is raised for legibility.
        if qkb.UseCharacterBindingsButton and qkb.UseCharacterBindingsButton.SetCheckedTexture then
            local cbText = qkb.UseCharacterBindingsButton.Text or qkb.UseCharacterBindingsButton.text
            if cbText then
                cbText:SetDrawLayer("OVERLAY", 6)
            end
        end
    end

    -- Blizzard_QuickKeybind is LoadOnDemand, so the frame may not exist at login: try after login, with ADDON_LOADED as the late-load fallback.
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

        -- Border/decoration only; role icon and content are preserved.
        if dialog.Bg then dialog.Bg:SetAlpha(0) end
        if dialog.BG then dialog.BG:SetAlpha(0) end
        if dialog.NineSlice then dialog.NineSlice:SetAlpha(0) end
        if dialog.Border then dialog.Border:SetAlpha(0) end

        local bg = dialog:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(RS.BG_R, RS.BG_G, RS.BG_B, RS.QT_ALPHA)
        GetFFD(bg).owned = true
        if _PP and _PP.CreateBorder then
            _PP.CreateBorder(dialog, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
        end

        local function _accentOn()
            -- Native mode leaves text/border un-accented.
            return EllesmereUI._getPopupMenuElementMode() ~= "native"
        end
        for _, btnName in ipairs({ "AcceptButton", "DeclineButton", "AcknowledgeButton" }) do
            local btn = dialog[btnName]
            if btn then
                -- Re-stripped every show; Blizzard re-applies the art.
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
                    local er,eg,eb=EllesmereUI._getPopupMenuButtonTextColor(); local EG={r=er,g=eg,b=eb}
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
                -- Text accent re-applied every show.
                local er,eg,eb=EllesmereUI._getPopupMenuButtonTextColor(); local EG={r=er,g=eg,b=eb}
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

        -- Border/decoration only; content is preserved.
        if dialog.Bg then dialog.Bg:SetAlpha(0) end
        if dialog.BG then dialog.BG:SetAlpha(0) end
        if dialog.NineSlice then dialog.NineSlice:SetAlpha(0) end
        if dialog.Border then dialog.Border:SetAlpha(0) end

        local bg = dialog:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(RS.BG_R, RS.BG_G, RS.BG_B, RS.QT_ALPHA)
        GetFFD(bg).owned = true
        if _PP and _PP.CreateBorder then
            _PP.CreateBorder(dialog, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
        end

        local desc = _G.LFGListApplicationDialogDescription
        if desc then
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
            -- Native mode leaves text/border un-accented.
            return EllesmereUI._getPopupMenuElementMode() ~= "native"
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
                local er,eg,eb=EllesmereUI._getPopupMenuButtonTextColor(); local EG={r=er,g=eg,b=eb}
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
        -- Independent toggle, default on: this is a popup menu, not a window, so no master reskin setting (window-skins style included) governs it.
        if EllesmereUIDB and EllesmereUIDB.reskinGameMenu == false then return end

        local RS = EllesmereUI.RESKIN

        for i = 1, select("#", GameMenuFrame:GetRegions()) do
            local r = select(i, GameMenuFrame:GetRegions())
            if r and r:IsObjectType("Texture") then r:SetAlpha(0) end
        end
        if GameMenuFrame.NineSlice then GameMenuFrame.NineSlice:SetAlpha(0) end
        if GameMenuFrame.Border then GameMenuFrame.Border:SetAlpha(0) end
        -- Header: strip art, accent the title, nudge down.
        local header = GameMenuFrame.Header
        if header then
            for i = 1, select("#", header:GetRegions()) do
                local r = select(i, header:GetRegions())
                if r and r:IsObjectType("Texture") then r:SetAlpha(0) end
            end
            local headerText = header.Text or (header.GetRegions and select(1, header:GetRegions()))
            if headerText and headerText.SetTextColor then
                local r, g, b = EllesmereUI._getPopupMenuButtonTextColor()
                headerText:SetTextColor(r, g, b, 1)
                local euiFont = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("blizzardSkin") or "Fonts\\FRIZQT__.TTF"
                local _, hSize = headerText:GetFont()
                headerText:SetFont(euiFont, hSize or 16, "")
            end
            header:ClearAllPoints()
            header:SetPoint("TOP", GameMenuFrame, "TOP", 0, -10)
        end
        local gmBg = GameMenuFrame:CreateTexture(nil, "BACKGROUND")
        gmBg:SetAllPoints()
        gmBg:SetColorTexture(RS.BG_R, RS.BG_G, RS.BG_B, RS.QT_ALPHA)
        local function ApplyButtonStyle(btn)
            local d = GetFFD(btn)
            -- Blizzard's pooled buttons keep skin data in this addon's FFD; EUI's two custom
            -- Game Menu buttons are created by the parent addon and keep theirs in ITS FFD. Fall back to that store so live option changes also reach the EllesmereUI button.
            if not d.gameMenuInset and EllesmereUI._GetFFD then
                d = EllesmereUI._GetFFD(btn)
            end
            if not d.gameMenuInset then return end
            local c = EllesmereUIDB and EllesmereUIDB.popupMenuButtonBackgroundColor or { r=.1,g=.1,b=.1,a=.8 }
            d.gameMenuButtonBg:SetColorTexture(c.r, c.g, c.b, c.a == nil and .8 or c.a)
            EllesmereUI._applyBlizzardConfiguredBorder(d.gameMenuInset, "popupMenuButton", 1)
            local fs = btn:GetFontString()
            -- Native mode keeps Blizzard's own gold on our dark inset.
            if fs and EllesmereUI._getPopupMenuElementMode() ~= "native" then
                local r, g, b = EllesmereUI._getPopupMenuButtonTextColor()
                fs:SetTextColor(r, g, b, 1)
            end
        end
        local function ApplyMenuStyle()
            EllesmereUI._applyBlizzardConfiguredBorder(GameMenuFrame, "popupMenu", 1)
            if GameMenuFrame.buttonPool then
                for btn in GameMenuFrame.buttonPool:EnumerateActive() do ApplyButtonStyle(btn) end
            end
            -- The EUI/Unlock custom buttons are created by the PARENT addon and stored in ITS namespace FFD (EllesmereUI._GetFFD), not this file's local FFD; wrong table = dead code.
            local pd = EllesmereUI._GetFFD and EllesmereUI._GetFFD(GameMenuFrame)
            if pd and pd.euiBtn then ApplyButtonStyle(pd.euiBtn) end
            if pd and pd.unlockBtn then ApplyButtonStyle(pd.unlockBtn) end
        end
        ApplyMenuStyle()
        GameMenuFrame:HookScript("OnShow", ApplyMenuStyle)
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
                    -- Inset container: bg + border sit 2px inside the button edges for a tighter look.
                    local inset = CreateFrame("Frame", nil, menuBtn)
                    inset:SetPoint("TOPLEFT", 2, -2)
                    inset:SetPoint("BOTTOMRIGHT", -2, 2)
                    inset:SetFrameLevel(menuBtn:GetFrameLevel())
                    local btnBg = inset:CreateTexture(nil, "BACKGROUND", nil, -6)
                    btnBg:SetAllPoints()
                    GetFFD(menuBtn).gameMenuInset = inset
                    GetFFD(menuBtn).gameMenuButtonBg = btnBg
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
                ApplyButtonStyle(menuBtn)
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
--  Re-owns the default GameTooltip to a 1x1 frame tracking the mouse, so the
--  tooltip follows the cursor at a user-chosen position + X/Y offset, via
--  GameTooltip_SetDefaultAnchor (the post-hook every default-anchored tooltip --
--  units, world objects, action buttons -- runs through). Installed on first
--  enable; a no-op (Blizzard's anchor stands) when toggled off, and the tracking frame only ticks while a tooltip is shown.
-------------------------------------------------------------------------------

-- Is a tooltip owner handed to us by a Blizzard hook safe to anchor to? It can
-- be a FORBIDDEN frame: Blizzard's nameplate aura buttons are forbidden and call
-- GameTooltip_SetDefaultAnchor on hover, so passing one straight to SetOwner from
-- our tainted hook raises "Attempt to access forbidden object from code tainted
-- by an AddOn". Testing the tooltip alone is NOT enough -- it is the OWNER that
-- is off limits, not GameTooltip itself. Nothing can be anchored to a forbidden
-- frame, so both anchor modes must leave Blizzard's anchoring alone there;
-- IsForbidden is the only method safe to call on such a frame, so it is asked
-- first and nothing else is touched. File scope on purpose: the cursor and fixed anchor modes (separate do-blocks) both need it.
local function TooltipOwnerUsable(parent)
    if not parent then return false end
    local fn = parent.IsForbidden
    if type(fn) == "function" and fn(parent) then return false end
    return true
end

-- Stand-in tooltips: taint-sensitive callers that cannot touch the global
-- GameTooltip build their own GameTooltipTemplate frame and flag it
-- LIKE_GLOBAL_GAMETOOLTIP -- the ecosystem convention asking to be treated
-- as _G.GameTooltip. They still route through GameTooltip_SetDefaultAnchor,
-- so honour the flag for the ANCHOR decision only. The armed-state
-- bookkeeping stays strict-identity: it gates SetPoint enforcement hooked
-- onto GameTooltip's OWN setters, so arming it for a stand-in would enforce
-- against another frame's state. A stand-in needs no ongoing enforcement:
-- GameTooltip_SetDefaultAnchor is a pure one-shot (SetOwner + corner
-- SetPoint, no registration), so nothing Blizzard-side ever re-anchors a
-- stand-in -- every re-build re-enters these hooks.
local function TooltipIsGlobalLike(tooltip)
    if tooltip == GameTooltip then return true end
    return type(tooltip) == "table" and tooltip.LIKE_GLOBAL_GAMETOOLTIP == true
end

do
    -- Selected position = where the tooltip sits relative to the cursor, so the tooltip corner touching the cursor is the opposite one.
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

    -- Show + position the tracking frame at the pointer NOW: the OnUpdate alone only
    -- repositions it next frame, so a tooltip anchored to it and shown synchronously this frame (as the custom CDM frames do) would have no valid rect yet and render nothing.
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
        if not TooltipIsGlobalLike(tooltip) then return end
        -- Gated by the customTooltips master (matches the grayed-out option), so disabling the reskin restores the default tooltip position.
        if EllesmereUIDB and EllesmereUIDB.customTooltips == false then return end
        if not (EllesmereUIDB and EllesmereUIDB.tooltipAnchorCursor) then return end
        -- Owner checked as well as the tooltip: a forbidden owner cannot be passed to SetOwner below. See TooltipOwnerUsable.
        if not TooltipOwnerUsable(parent) or tooltip:IsForbidden() then return end
        -- "Show Tooltips" suppression parks the tip in a hidden host (below): it stays alive and invisible so the peek modifier can reveal it, so anchor it normally -- it must already ride the cursor when revealed.
        local cf = EnsureCursorFrame()
        PositionCursorFrameNow(cf)
        local point = POINT_FOR_POS[EllesmereUIDB.tooltipCursorPosition or "top"] or "BOTTOM"
        tooltip:SetOwner(parent, "ANCHOR_NONE")
        tooltip:ClearAllPoints()
        tooltip:SetPoint(point, cf, "CENTER",
            EllesmereUIDB.tooltipCursorOffsetX or 0,
            EllesmereUIDB.tooltipCursorOffsetY or 0)
    end

    -- Re-assert the cursor anchor WITHOUT re-owning the tooltip (SetOwner would
    -- wipe content). A content-setter that clears/hides the tip mid-build (e.g.
    -- SetItemByID) fires OnHide, hiding the tracking frame and leaving the tip
    -- anchored to a hidden/unpositioned frame so it never appears. Call this
    -- AFTER content is set and before Show: re-shows + repositions the tracker
    -- and re-points the tooltip. No-op (safe unconditionally) when the cursor anchor or reskin master is off.
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
        -- World-unit tooltips fade out (~1-2s) on mouse-off instead of hiding instantly like
        -- unitframe/item/buff/CDM tips; while riding the cursor that lingering fade trails the pointer, so collapse it to an instant hide -- only while the cursor anchor is on.
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
--  Fixed Tooltip Position (EUI-owned, movable in Unlock Mode)
--  EUI permanently owns the default GameTooltip's screen position: every default-anchored
--  tooltip is re-pointed onto OUR anchor frame, dragged via a real Unlock Mode mover.
--  Position is PER PROFILE (profiles[name].tooltipFixedPos); a profile with none gets a
--  ONE-TIME seed captured from wherever Blizzard's Edit Mode container currently sits, so
--  the takeover is visually a no-op until the user drags the box. GameTooltipDefaultContainer
--  is only ever READ, never written, so the user's Edit Mode position survives intact and
--  stands again if the reskin master is off. Same GameTooltip_SetDefaultAnchor post-hook
--  family as the cursor anchor and growth direction (tooltip unprotected, content never
--  touched, no taint surface); Anchor to Cursor takes precedence. Placed BEFORE the growth-direction block so its hook registers first and growth enforcement composes on top of our corner.
-------------------------------------------------------------------------------
do
    -- Representative mover-box size; real tooltips vary, but they pin corner-to-corner to the box so they render inside this footprint.
    local FIXED_W, FIXED_H = 280, 165
    local anchorFrame

    local function ActiveProfile()
        return EllesmereUI.GetActiveProfileData and EllesmereUI.GetActiveProfileData()
    end

    -- Fixed mode is the permanent baseline: no toggle. Only the reskin master (off = vanilla tooltips) and Anchor to Cursor sideline it.
    local function WantFixed()
        if EllesmereUIDB and EllesmereUIDB.customTooltips == false then return false end
        if EllesmereUIDB and EllesmereUIDB.tooltipAnchorCursor then return false end
        return true
    end

    local function EnsureFixedFrame()
        if anchorFrame then return anchorFrame end
        anchorFrame = CreateFrame("Frame", "EllesmereUI_TooltipFixedAnchor", UIParent)
        anchorFrame:SetSize(FIXED_W, FIXED_H)
        anchorFrame:EnableMouse(false)
        -- Placeholder point; PositionFromSaved overrides from the profile pos.
        anchorFrame:SetPoint("CENTER", UIParent, "CENTER", -350, -150)
        return anchorFrame
    end

    -- One-time per-profile seed: store where Blizzard's Edit Mode container puts
    -- the tooltip RIGHT NOW, so the takeover changes nothing visually until the
    -- user drags the mover. READ only, container never modified. Retries
    -- harmlessly until the container has a real rect (Edit Mode layouts land
    -- after login); a stored position (seeded or dragged) is never overwritten, so this runs at most once per profile.
    local function EnsureSeeded()
        local prof = ActiveProfile()
        if not prof or prof.tooltipFixedPos then return end
        -- Adopt a position left under the old account-global key.
        if EllesmereUIDB and EllesmereUIDB.tooltipFixedPos then
            prof.tooltipFixedPos = EllesmereUIDB.tooltipFixedPos
            EllesmereUIDB.tooltipFixedPos = nil
            return
        end
        local c = _G.GameTooltipDefaultContainer
        if not c or not c.GetLeft then return end
        local l, b = c:GetLeft(), c:GetBottom()
        if not l or not b then return end
        local w, ch = c:GetWidth() or 0, c:GetHeight() or 0
        local us = UIParent:GetEffectiveScale() or 1
        if us <= 0 then return end
        local r = (c:GetEffectiveScale() or us) / us
        -- Blizzard pins the tooltip's corner to the container corner nearest the
        -- closest screen corner. Find that point, then park our box so ITS
        -- matching corner sits exactly there; an idle container may be
        -- collapsed to a sliver (corners coincide), still correct.
        local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
        local ccx = (l + w / 2) * r - uw / 2
        local ccy = (b + ch / 2) * r - uh / 2
        local px = (ccx < 0) and (l * r) or ((l + w) * r)
        local py = (ccy < 0) and (b * r) or ((b + ch) * r)
        prof.tooltipFixedPos = {
            centerX = px + ((ccx < 0) and (FIXED_W / 2) or (-FIXED_W / 2)) - uw / 2,
            centerY = py + ((ccy < 0) and (FIXED_H / 2) or (-FIXED_H / 2)) - uh / 2,
        }
    end

    -- Park the anchor frame at the ACTIVE profile's position (center offsets from UIParent
    -- center, matching how the mover stores CENTER coords). Reading the profile live every call makes profile switches self-heal on the next tooltip show, with zero extra wiring.
    local function PositionFromSaved()
        local af = EnsureFixedFrame()
        EnsureSeeded()
        local prof = ActiveProfile()
        local pos = prof and prof.tooltipFixedPos
        af:ClearAllPoints()
        if pos and pos.centerX and pos.centerY then
            af:SetPoint("CENTER", UIParent, "CENTER", pos.centerX, pos.centerY)
        else
            af:SetPoint("CENTER", UIParent, "CENTER", -350, -150)
        end
    end

    -- Corner of the box the tooltip pins to: the one nearest the closest screen corner, so
    -- growth always runs INTO the screen (and the box). Growth Direction, when set, forces the vertical component -- the same rule its own enforcement block applies, so the two never fight.
    local function CornerFor(af)
        local cx, cy = -350, -150
        local l, b = af:GetLeft(), af:GetBottom()
        if l and b then
            cx = l + (af:GetWidth() or 0) / 2 - UIParent:GetWidth() / 2
            cy = b + (af:GetHeight() or 0) / 2 - UIParent:GetHeight() / 2
        else
            local prof = ActiveProfile()
            local pos = prof and prof.tooltipFixedPos
            if pos and pos.centerX and pos.centerY then cx, cy = pos.centerX, pos.centerY end
        end
        local dir = EllesmereUIDB and EllesmereUIDB.tooltipGrowthDirection
        local vert = (dir == "down" and "TOP") or (dir == "up" and "BOTTOM")
            or ((cy < 0) and "BOTTOM" or "TOP")
        return vert .. ((cx < 0) and "LEFT" or "RIGHT")
    end

    -- Blizzard's container logic can re-anchor a default-anchored tooltip a few
    -- frames after show WITHOUT clearing points first (see Growth Direction
    -- below), pinning a second corner and stretching the tooltip between our
    -- box and Blizzard's container. Enforcement rides the same armed/disarmed
    -- SetPoint pattern: NEVER reads hook args (hooked secure setters can receive secret values), re-derives everything, rewrites only on deviation.
    local _fixedEnforcing = false
    local _fixedArmed = false

    local function EnforceFixed(tooltip)
        if not WantFixed() then return end
        if tooltip:IsForbidden() then return end
        local af = anchorFrame
        if not af then return end
        local corner = CornerFor(af)
        local point, relTo = tooltip:GetPoint(1)
        if tooltip:GetNumPoints() == 1 and point == corner and relTo == af then return end
        _fixedEnforcing = true
        tooltip:ClearAllPoints()
        tooltip:SetPoint(corner, af, corner, 0, 0)
        _fixedEnforcing = false
    end

    local function ApplyFixedAnchor(tooltip, parent)
        if not TooltipIsGlobalLike(tooltip) then return end
        if not WantFixed() then return end
        if tooltip:IsForbidden() then return end
        -- A forbidden owner (nameplate aura button) cannot be anchored to:
        -- leave Blizzard's anchoring alone AND disarm SetPoint enforcement.
        -- Arming happens in the SetDefaultAnchor hook before this runs; leaving
        -- it armed would let EnforceFixed yank the tooltip into our box with no matching SetOwner. See TooltipOwnerUsable.
        if not TooltipOwnerUsable(parent) then
            _fixedArmed = false
            return
        end
        -- An open Unlock Mode session owns the anchor frame (live drags + uncommitted edits): re-parking from saved would snap it back mid-session, so pin to wherever the session has it.
        if EllesmereUI._unlockActive then
            EnsureSeeded()
        else
            PositionFromSaved()
        end
        tooltip:SetOwner(parent, "ANCHOR_NONE")
        EnforceFixed(tooltip)
    end

    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
        if not TooltipIsGlobalLike(tooltip) then return end
        -- Only the global tooltip can be armed: the SetPoint enforcement below
        -- is hooked onto GameTooltip's own setters. See TooltipIsGlobalLike.
        if tooltip == GameTooltip then _fixedArmed = true end
        ApplyFixedAnchor(tooltip, parent)
    end)
    -- Every explicit tooltip build starts with SetOwner, which runs BEFORE the SetDefaultAnchor post-hook re-arms the flag, so explicitly-anchored uses (bags, other addons) never get their anchors rewritten.
    hooksecurefunc(GameTooltip, "SetOwner", function()
        _fixedArmed = false
    end)
    hooksecurefunc(GameTooltip, "SetPoint", function(tt)
        if _fixedEnforcing or not _fixedArmed then return end
        if tt ~= GameTooltip then return end
        EnforceFixed(tt)
    end)

    -- Reposition (and seed if needed) now: login, world entry, reset paths.
    EllesmereUI._applyTooltipFixedAnchor = function()
        PositionFromSaved()
    end

    -- Unlock Mode element: a real draggable mover for the tooltip position. Writes ONLY
    -- our per-profile key, never Blizzard's tooltip container. Hidden while Anchor to Cursor is on or the reskin master is off (both leave the fixed anchor inactive).
    local function RegisterUnlock()
        if not (EllesmereUI and EllesmereUI.RegisterUnlockElements and EllesmereUI.MakeUnlockElement) then return end
        local MK = EllesmereUI.MakeUnlockElement
        EllesmereUI:RegisterUnlockElements({
            MK({
                key      = "EUI_TooltipAnchor",
                label    = "Tooltip",
                group    = "Blizzard Windows",
                order    = 650,
                subtitle = "Fixed Position",
                noResize          = true,  -- tooltip size is dynamic; nothing to resize
                noAnchorTarget    = true,
                noAnchorTo        = true,
                noSizeMatchTarget = true,
                isHidden = function()
                    return not WantFixed()
                end,
                getFrame = function()
                    -- MUST stay side-effect-free: unlock mode calls getFrame from its drag
                    -- machinery (OnUpdate/OnDragStop), so parking from saved here would snap a live drag back on release. Boot/applyPos/loadPos do parking + seeding.
                    return EnsureFixedFrame()
                end,
                getSize  = function() return FIXED_W, FIXED_H end,
                savePos = function(_, _point, _relPoint, x, y)
                    local prof = ActiveProfile()
                    if not prof then return end
                    local af = EnsureFixedFrame()
                    if af:GetLeft() then
                        local fw, fh = af:GetSize()
                        local cx = af:GetLeft() + fw / 2 - UIParent:GetWidth() / 2
                        local cy = af:GetBottom() + fh / 2 - UIParent:GetHeight() / 2
                        prof.tooltipFixedPos = { centerX = cx, centerY = cy }
                    else
                        prof.tooltipFixedPos = { centerX = x, centerY = y }
                    end
                end,
                loadPos = function()
                    EnsureSeeded()
                    local prof = ActiveProfile()
                    local pos = prof and prof.tooltipFixedPos
                    if pos and pos.centerX and pos.centerY then
                        return { point = "CENTER", relPoint = "CENTER", x = pos.centerX, y = pos.centerY }
                    end
                    return nil
                end,
                clearPos = function()
                    -- Clearing the profile key makes the next apply re-seed from Blizzard's CURRENT Edit Mode spot, so "reset position" = wherever Blizzard would put it today.
                    local prof = ActiveProfile()
                    if prof then prof.tooltipFixedPos = nil end
                    PositionFromSaved()
                end,
                applyPos = function()
                    PositionFromSaved()
                end,
            })
        })
    end

    local boot = CreateFrame("Frame")
    boot:RegisterEvent("PLAYER_LOGIN")
    boot:RegisterEvent("PLAYER_ENTERING_WORLD")
    boot:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_LOGIN" then
            EnsureFixedFrame()
            PositionFromSaved()
            RegisterUnlock()
        else
            -- Edit Mode layouts land after login, so the one-time seed may have found no container rect yet. Retry once in-world, then stop listening (later seeds happen lazily at tooltip show).
            self:UnregisterAllEvents()
            PositionFromSaved()
        end
    end)
end

-------------------------------------------------------------------------------
--  Growth Direction (default screen-anchored tooltip)
--  Blizzard picks the default tooltip's anchored corner dynamically from the
--  container's screen position, and the pinned corner decides which way added lines
--  grow (TOP pinned = expands down, BOTTOM pinned = expands up). tooltipGrowthDirection
--  "up"/"down" forces the vertical component of whatever corner Blizzard chose,
--  keeping its horizontal side; "default" (or unset) leaves Blizzard's dynamic pick
--  alone. Re-point only, same GameTooltip_SetDefaultAnchor post-hook family as the
--  cursor anchor (no taint surface: tooltip unprotected, content never touched). Cursor-anchored mode re-points the tooltip itself and takes precedence.
-------------------------------------------------------------------------------
do
    local function WantForcedDir()
        if EllesmereUIDB and EllesmereUIDB.customTooltips == false then return nil end
        local dir = EllesmereUIDB and EllesmereUIDB.tooltipGrowthDirection
        if dir ~= "up" and dir ~= "down" then return nil end
        if EllesmereUIDB.tooltipAnchorCursor then return nil end
        return dir
    end

    -- Blizzard's container logic RE-ANCHORS the tooltip a few frames after show (and
    -- on size changes) WITHOUT clearing points first. SetPoint only replaces a
    -- same-keyword point, so its re-assert ADDED a second corner next to the forced
    -- one -- top and bottom both pinned, tooltip stretched to fill the gap.
    -- Enforcement rides a SetPoint hook instead: any anchor write that isn't ours
    -- while a default-anchored tooltip is up gets collapsed back to the single
    -- forced corner. The hook never reads its args (hooked setters can receive
    -- secret values), re-deriving everything from GetPoint; _growthEnforcing guards re-entry from our own SetPoint inside the hook.
    local _growthEnforcing = false
    local _growthDefaultAnchored = false

    local function Enforce(tooltip)
        local dir = WantForcedDir()
        if not dir then return end
        if tooltip:IsForbidden() then return end
        local point, relTo, _, x, y = tooltip:GetPoint(1)
        if not point then return end
        relTo = relTo or GameTooltipDefaultContainer
        if not relTo then return end
        local horiz = (point:find("LEFT") and "LEFT") or (point:find("RIGHT") and "RIGHT") or ""
        local newPoint = ((dir == "down") and "TOP" or "BOTTOM") .. horiz
        if tooltip:GetNumPoints() == 1 and point == newPoint then return end
        _growthEnforcing = true
        tooltip:ClearAllPoints()
        tooltip:SetPoint(newPoint, relTo, newPoint, x or 0, y or 0)
        _growthEnforcing = false
    end

    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip)
        if not TooltipIsGlobalLike(tooltip) then return end
        -- Only the global tooltip can be armed: the SetPoint enforcement below
        -- is hooked onto GameTooltip's own setters. See TooltipIsGlobalLike.
        if tooltip == GameTooltip then _growthDefaultAnchored = true end
        Enforce(tooltip)
    end)
    -- Every tooltip build starts with SetOwner (runs BEFORE the SetDefaultAnchor post-hook re-arms the flag), so explicitly-anchored uses (bags, other addons) never get their anchors rewritten.
    hooksecurefunc(GameTooltip, "SetOwner", function()
        _growthDefaultAnchored = false
    end)
    hooksecurefunc(GameTooltip, "SetPoint", function(tt)
        if _growthEnforcing or not _growthDefaultAnchored then return end
        Enforce(tt)
    end)
end

-------------------------------------------------------------------------------
--  Show Tooltips (global visibility mode). The "Blizzard Tooltip" dropdown
--  (EllesmereUIDB.tooltipShowMode, default "always") suppresses the game tooltip
--  by combat state, applied to every default-anchored tooltip via the same
--  GameTooltip_SetDefaultAnchor post-hook the cursor anchor uses. Action tooltip
--  paths can re-own the tooltip explicitly after that hook, so action owners are
--  recognized separately before SetAction builds the tooltip.
--    always          -> never suppressed (default; the hook early-outs)
--    outOfCombat     -> hidden while in combat lockdown
--    outOfBossCombat -> hidden while a boss encounter is in progress
--    never           -> hidden always
--  IsEncounterInProgress() is queried inline (outOfBossCombat only) for the visibility
--  decision. Comparison cleanup support is installed lazily only when a non-default
--  mode is active; the default mode adds no comparison hooks or state events. An optional
--  "peek" modifier
--  (tooltipShowModifier) lifts suppression while held, so a suppressed tip can be
--  read on hover mid-combat. Suppression keeps the tooltip SHOWN but parked in a
--  hidden host frame (never Hide, never alpha) so peek is a pure reparent flip:
--  rebuilding a hidden tooltip from insecure code errors on secret cooldown data in combat, and alpha is engine-owned (FadeOut snaps it back and leaks the tip).
-------------------------------------------------------------------------------
do
    local function ShowModifierHeld()
        local mod = (EllesmereUIDB and EllesmereUIDB.tooltipShowModifier) or "none"
        if mod == "none" then return false end
        if mod == "control" then return IsControlKeyDown() end
        if mod == "alt" then return IsAltKeyDown() end
        return IsShiftKeyDown()
    end

    -- Exposed so modules with their own tooltip suppression (e.g. raid/party frames, whose OnEnter hides tips per its own combat mode) can let the same peek modifier reveal their tips.
    function EllesmereUI._tooltipPeekHeld()
        return ShowModifierHeld()
    end

    local EnsureComparisonSupport
    local UpdateStateWatcher
    local _comparisonSupportActive = false
    local _comparisonStateWatcherRegistered = false

    local function ComparisonSuppressionModeEnabled()
        if EllesmereUIDB and EllesmereUIDB.customTooltips == false then return false end
        return ((EllesmereUIDB and EllesmereUIDB.tooltipShowMode) or "always") ~= "always"
    end

    local function ComparisonStateWatcherNeeded()
        local mode = (EllesmereUIDB and EllesmereUIDB.tooltipShowMode) or "always"
        return ComparisonSuppressionModeEnabled()
            and (mode == "outOfCombat" or mode == "outOfBossCombat")
    end

    -- Shared decision: should GameTooltip be suppressed right now given the user's "Show
    -- Tooltips" mode + combat state? Exposed on EllesmereUI so the cursor-anchor hook can honor it too (else cursor re-anchor would re-show a tooltip this hook just hid).
    function EllesmereUI._tooltipSuppressedByMode(tooltip)
        if tooltip ~= GameTooltip then return false end
        if tooltip.IsForbidden and tooltip:IsForbidden() then return false end
        -- Gated by the "Reskin Tooltip" master (matches the grayed-out "Show Tooltips" option), so disabling the reskin never leaves tooltips stuck suppressed at, e.g., "Never".
        if EllesmereUIDB and EllesmereUIDB.customTooltips == false then
            if UpdateStateWatcher and (_comparisonSupportActive or _comparisonStateWatcherRegistered) then
                UpdateStateWatcher()
            end
            return false
        end
        local mode = (EllesmereUIDB and EllesmereUIDB.tooltipShowMode) or "always"
        if mode == "always" then
            if UpdateStateWatcher and (_comparisonSupportActive or _comparisonStateWatcherRegistered) then
                UpdateStateWatcher()
            end
            return false
        end
        if EnsureComparisonSupport then EnsureComparisonSupport() end
        if UpdateStateWatcher then UpdateStateWatcher() end
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

    -- Item comparisons are rendered by separate ShoppingTooltip frames. Parking
    -- GameTooltip alone therefore leaves the side-by-side comparison visible in
    -- combat when alwaysCompareItems is enabled. Keep the cleanup in this global
    -- tooltip controller rather than in ActionBars: bags, world items, and every
    -- other default-anchored item tooltip use the same comparison manager.
    -- Use Blizzard's existing comparison-suppression control field; addon-owned
    -- state stays in the shared weak-keyed FFD table so no custom state is stored
    -- on Blizzard frames.
    local _comparisonTooltips
    local _comparisonClearPending = false

    local function GetComparisonTooltips()
        if not _comparisonTooltips then
            _comparisonTooltips = { ShoppingTooltip1, ShoppingTooltip2 }
        end
        return _comparisonTooltips
    end

    local _comparisonFlagOwned = false
    local _parked = false
    local _modeEligible = false
    local function GetComparisonState(tooltip, create)
        local state = FFD[tooltip]
        if not state and create then
            state = {}
            FFD[tooltip] = state
        end
        return state
    end

    local function ReadComparisonSuppressionFlag(tooltip)
        return tooltip.suppressAutomaticCompareItem
    end

    local function WriteComparisonSuppressionFlag(tooltip, value)
        -- Blizzard exposes this field as the per-tooltip opt-out for automatic
        -- comparisons. It is a Blizzard control input, not addon-owned state.
        tooltip.suppressAutomaticCompareItem = value
    end

    local function ForgetComparisonSuppression(tooltip)
        if not _comparisonFlagOwned or tooltip ~= GameTooltip then return end
        local state = GetComparisonState(tooltip, false)
        if state then
            state.comparisonFlagPrevious = nil
            state.comparisonFlagOwned = nil
        end
        _comparisonFlagOwned = false
    end

    local function ReleaseComparisonSuppression(tooltip)
        if not _comparisonFlagOwned or tooltip ~= GameTooltip then return end
        local state = GetComparisonState(tooltip, false)
        if not state or not state.comparisonFlagOwned then
            _comparisonFlagOwned = false
            return
        end
        if not pcall(WriteComparisonSuppressionFlag, tooltip, state.comparisonFlagPrevious) then return end
        ForgetComparisonSuppression(tooltip)
    end

    local function ArmComparisonSuppression(tooltip)
        if tooltip ~= GameTooltip then return end
        local state = GetComparisonState(tooltip, true)
        local owned = _comparisonFlagOwned and state.comparisonFlagOwned
        if not owned then
            local readOK, previous = pcall(ReadComparisonSuppressionFlag, tooltip)
            if not readOK then return end
            state.comparisonFlagPrevious = previous
            state.comparisonFlagOwned = true
            _comparisonFlagOwned = true
        end
        -- Arm at the default anchor and again from the item pre-call below. Item
        -- setters can fire OnHide while rebuilding content, which resets this
        -- Blizzard field after the anchor hook but before comparison finalization.
        if not pcall(GameTooltip_SuppressAutomaticCompareItem, tooltip) and not owned then
            ForgetComparisonSuppression(tooltip)
        end
    end

    local function OnItemTooltipPreCall(tooltip)
        -- Parking is the authoritative scope: default-anchored tips suppressed by
        -- this controller are parked, while SetOwner unparks explicit tooltip paths
        -- before they process item data. This also survives action-button owner reuse.
        if tooltip ~= GameTooltip or not _parked then return end
        ArmComparisonSuppression(tooltip)
    end

    local function RegisterComparisonPreCall()
        TooltipDataProcessor.AddTooltipPreCall(Enum.TooltipDataType.Item, OnItemTooltipPreCall)
    end

    local _comparisonPreCallAttempted = false
    local function InstallComparisonPreCall()
        if _comparisonPreCallAttempted then return end
        _comparisonPreCallAttempted = true
        -- Midnight provides this processor before addon code loads. Keep the
        -- registration protected so a missing API falls back to after-show cleanup.
        pcall(RegisterComparisonPreCall)
    end

    local function ClearSuppressedComparisons()
        if not EllesmereUI._tooltipSuppressedByMode(GameTooltip) then return end

        -- Clear the manager's state and its owned shopping frames through the
        -- same public method Blizzard calls from GameTooltip_OnHide.  Fall back
        -- to Blizzard's helper only when the manager is unavailable, does not
        -- own GameTooltip, or errors; avoid a third direct Hide pass over global
        -- shopping frames that may belong to another tooltip path.
        local managerCleared = false
        if TooltipComparisonManager
            and TooltipComparisonManager.tooltip == GameTooltip
            and type(TooltipComparisonManager.Clear) == "function" then
            managerCleared = pcall(TooltipComparisonManager.Clear, TooltipComparisonManager, GameTooltip)
        end
        if not managerCleared and GameTooltip_HideShoppingTooltips then
            pcall(GameTooltip_HideShoppingTooltips, GameTooltip)
        end
    end

    local function RunSuppressedComparisonClear()
        _comparisonClearPending = false
        ClearSuppressedComparisons()
    end
    local function QueueSuppressedComparisonClear()
        if not _comparisonSupportActive then return end
        if not ComparisonSuppressionModeEnabled()
            or not EllesmereUI._tooltipSuppressedByMode(GameTooltip) then return end
        if _comparisonClearPending then return end
        _comparisonClearPending = true
        -- This hook can run from Blizzard's protected tooltip/action-button path.
        -- Defer all Hide/Clear calls out of that stack, matching the existing EUI
        -- tooltip-skin deferral rules.
        C_Timer.After(0, RunSuppressedComparisonClear)
    end

    local _comparisonTooltipHooksInstalled = false
    local _comparisonManagerHookInstalled = false
    local _comparisonLifecycleHooksInstalled = false
    local function InstallComparisonHooks()
        InstallComparisonPreCall()

        if not _comparisonLifecycleHooksInstalled then
            -- SetOwner starts a new build, so restore the previous build before a
            -- following default-anchor hook can arm suppression again. The main
            -- SetOwner hook below already restores before an explicit action path
            -- arms, so do not immediately undo that new ownership here.
            hooksecurefunc(GameTooltip, "SetOwner", function(tooltip)
                if not _modeEligible then
                    ReleaseComparisonSuppression(tooltip)
                end
            end)
            -- Blizzard resets the field itself before hooks run, so only forget
            -- our ownership; restoring would overwrite Blizzard's reset.
            GameTooltip:HookScript("OnHide", ForgetComparisonSuppression)
            _comparisonLifecycleHooksInstalled = true
        end

        if not _comparisonTooltipHooksInstalled then
            for _, comparisonTooltip in ipairs(GetComparisonTooltips()) do
                if comparisonTooltip and comparisonTooltip.HookScript then
                    comparisonTooltip:HookScript("OnShow", function()
                        if not _comparisonSupportActive then return end
                        if EllesmereUI._tooltipSuppressedByMode(GameTooltip) then
                            QueueSuppressedComparisonClear()
                        end
                    end)
                end
            end
            _comparisonTooltipHooksInstalled = true
        end

        if not _comparisonManagerHookInstalled
            and TooltipComparisonManager
            and type(TooltipComparisonManager.AnchorShoppingTooltips) == "function" then
            hooksecurefunc(TooltipComparisonManager, "AnchorShoppingTooltips", QueueSuppressedComparisonClear)
            _comparisonManagerHookInstalled = true
        end
    end

    EnsureComparisonSupport = function()
        if not ComparisonSuppressionModeEnabled() then return false end
        _comparisonSupportActive = true
        InstallComparisonHooks()
        return true
    end

    -- Suppression parks the tooltip in a hidden host frame -- NOT Hide(), NOT alpha.
    -- Hide()-based suppression forced peek to REBUILD the tooltip from our insecure
    -- execution: in combat, action tooltips read secret cooldown data and the rebuild
    -- hard-errors ("secret values are only allowed during untainted execution"),
    -- silently swallowed by FireHoveredOnEnter's pcall -- peek looked dead in combat
    -- on action bars. Alpha-based suppression fought the engine: FadeOut (hover-off
    -- on world units) snaps alpha back to full and animates it down, leaking the tip.
    -- Parking wins both ways: the tooltip stays SHOWN (secure hover path keeps
    -- building/refreshing it), visibility inherits from the hidden host regardless of
    -- engine alpha, and peek is a pure reparent flip. OnHide never fires while parked
    -- (frame not visible), so restore relies on the SetOwner hook below instead: every
    -- tooltip build starts with SetOwner, so an explicitly-anchored use (bags, other
    -- addons) that never passes SetDefaultAnchor can't inherit a parked tooltip;
    -- default-anchored builds re-park right after in the SetDefaultAnchor post-hook (its internal SetOwner runs first).
    local _suppressHost = CreateFrame("Frame", nil, UIParent)
    _suppressHost:Hide()
    local _origParent
    local function ParkTooltip(tt)
        if _parked then return end
        _parked = true
        _origParent = tt:GetParent()
        if _origParent == _suppressHost then _origParent = nil end
        tt:SetParent(_suppressHost)
    end
    local function UnparkTooltip(tt)
        if not _parked then return end
        _parked = false
        tt:SetParent(_origParent or UIParent)
        -- SetParent can demote strata; the tooltip must stay topmost.
        -- GetFrameStrata() returns a secret string once the tooltip carries
        -- secret unit data, and SetFrameStrata rejects secrets from addons.
        tt:SetFrameStrata("TOOLTIP")
    end
    local function ApplySuppression(tt)
        if EllesmereUI._tooltipSuppressedByMode(tt) then
            ArmComparisonSuppression(tt)
            ParkTooltip(tt)
            QueueSuppressedComparisonClear()
        else
            UnparkTooltip(tt)
        end
    end
    local function SuppressTooltipByMode(tooltip)
        if tooltip ~= GameTooltip then return end
        _modeEligible = true
        ApplySuppression(tooltip)
    end
    if GameTooltip_SetDefaultAnchor then
        hooksecurefunc("GameTooltip_SetDefaultAnchor", SuppressTooltipByMode)
    end
    local function ReadActionOwner(owner)
        return owner.GetAttribute and owner:GetAttribute("action") ~= nil
    end
    local function IsActionOwner(owner)
        if not owner then return false end
        local ok, result = pcall(ReadActionOwner, owner)
        return ok and result
    end
    hooksecurefunc(GameTooltip, "SetOwner", function(tt, owner)
        -- Restore the previous build before classifying the new owner. The flag
        -- makes this a single branch until comparison support has owned it.
        if _comparisonFlagOwned then
            ReleaseComparisonSuppression(tt)
        end
        _modeEligible = false
        UnparkTooltip(tt)
        -- Custom action buttons and tooltip-anchor addons can use an explicit
        -- owner after the default-anchor hook. Recognize the action attribute
        -- itself instead of inferring the path from the UberTooltips CVar.
        if ComparisonSuppressionModeEnabled() and IsActionOwner(owner) then
            _modeEligible = true
            ApplySuppression(tt)
        end
    end)
    GameTooltip:HookScript("OnHide", function(tt)
        -- Only fires for unparked hides (a parked tooltip is never visible).
        _modeEligible = false
        if not (_comparisonSupportActive or _comparisonStateWatcherRegistered) then return end
        if EllesmereUI._tooltipSuppressedByMode(tt) then
            QueueSuppressedComparisonClear()
        end
    end)

    -- Re-apply the mode when combat/encounter state changes while a tooltip is
    -- already alive.  Install these events only for the two modes that need
    -- transition handling; "Never" is handled by the tooltip hooks alone.
    local stateWatcher
    local function UnregisterStateWatcher()
        if not _comparisonStateWatcherRegistered then return end
        stateWatcher:UnregisterAllEvents()
        _comparisonStateWatcherRegistered = false
    end
    local function StateWatcherOnEvent()
        if not ComparisonStateWatcherNeeded() then
            UpdateStateWatcher()
            return
        end
        -- Only act when the new state requires suppression.  Do not unpark on
        -- combat/encounter end: the cursor may have left the owner while the
        -- parked tooltip remained logically shown, and unpark would resurrect
        -- stale content.  The next SetOwner path restores it normally.
        if not EllesmereUI._tooltipSuppressedByMode(GameTooltip) then return end
        if _modeEligible then
            ApplySuppression(GameTooltip)
        end
        QueueSuppressedComparisonClear()
    end
    UpdateStateWatcher = function()
        if not ComparisonSuppressionModeEnabled() then
            ReleaseComparisonSuppression(GameTooltip)
            _comparisonSupportActive = false
            UnregisterStateWatcher()
            return
        end
        EnsureComparisonSupport()
        if not ComparisonStateWatcherNeeded() then
            UnregisterStateWatcher()
            return
        end
        if not stateWatcher then
            stateWatcher = CreateFrame("Frame")
            stateWatcher:SetScript("OnEvent", StateWatcherOnEvent)
        end
        if not _comparisonStateWatcherRegistered then
            stateWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
            stateWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
            stateWatcher:RegisterEvent("ENCOUNTER_START")
            stateWatcher:RegisterEvent("ENCOUNTER_END")
            _comparisonStateWatcherRegistered = true
        end
    end
    UpdateStateWatcher()

    -- Live peek: pressing the modifier while already hovering reveals the tip
    -- for the current frame; releasing hides it again. Moving onto other frames
    -- while held reveals each in turn through the normal hover path -- suppression is lifted while held (globally via
    -- _tooltipSuppressedByMode, and per-module via _tooltipPeekHeld, honored by raid/party frames in their own OnEnter).
    local function KeyMatchesModifier(key, mod)
        return (mod == "shift"   and (key == "LSHIFT" or key == "RSHIFT"))
            or (mod == "control" and (key == "LCTRL"  or key == "RCTRL"))
            or (mod == "alt"     and (key == "LALT"   or key == "RALT"))
    end
    -- Reveal the tooltip for whatever the cursor is over. First re-run the
    -- hovered frame's OnEnter (buttons, icons, unit frames build their own tip)
    -- -- the topmost mouse-focus frame is often an overlay without one, so scan
    -- every frame under the cursor and walk up parents. Nameplates' clickable
    -- frame has an OnEnter that builds nothing (its tip comes from the engine's
    -- mouseover unit on a real hover), so fall back to driving the unit tooltip directly when one is up.
    -- Skip forbidden frames entirely; any access (even GetScript/GetParent) hard-errors.
    local function IsFrameForbidden(frame)
        return frame and frame.IsForbidden and frame:IsForbidden()
    end
    -- Skip protected frames; firing their secure OnEnter from insecure code is
    -- ADDON_ACTION_BLOCKED (not pcall-catchable). Nothing is lost: their tips are
    -- built by the secure hover path and revealed via the parked lane, and unit
    -- buttons still land a tip through the mouseover fallback below.
    local function IsFrameProtected(frame)
        return frame and frame.IsProtected and frame:IsProtected()
    end
    local function FireHoveredOnEnter()
        local foci = (GetMouseFoci and GetMouseFoci()) or (GetMouseFocus and { GetMouseFocus() })
        local anchorFrame = foci and foci[1]
        if IsFrameForbidden(anchorFrame) then anchorFrame = nil end
        if foci then
            for _, focus in ipairs(foci) do
                local frame = focus
                while frame and frame ~= WorldFrame and frame ~= UIParent do
                    if IsFrameForbidden(frame) then
                        break
                    end
                    if not IsFrameProtected(frame) and frame.GetScript then
                        local ok, onEnter = pcall(frame.GetScript, frame, "OnEnter")
                        if ok and onEnter then
                            pcall(onEnter, frame)
                            if GameTooltip:IsShown() then return end
                            anchorFrame = frame
                            break
                        end
                    end
                    if not frame.GetParent then break end
                    local okParent, parent = pcall(frame.GetParent, frame)
                    if not okParent or IsFrameForbidden(parent) then break end
                    frame = parent
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
                -- The parked tip is alive and current under the cursor (built by the secure hover path): just reveal it, never rebuild from here (see the parking note above).
                ReleaseComparisonSuppression(GameTooltip)
                UnparkTooltip(GameTooltip)
            else
                -- No live tip: module-built tips (raid frames, CDM) skip building while suppressed, so re-drive the hovered frame's OnEnter -- with the modifier now held they build normally.
                FireHoveredOnEnter()
            end
        elseif GameTooltip:IsShown() and EllesmereUI._tooltipSuppressedByMode(GameTooltip) then
            if _modeEligible then
                ArmComparisonSuppression(GameTooltip)
                ParkTooltip(GameTooltip)
                QueueSuppressedComparisonClear()
            else
                GameTooltip:Hide()
            end
        end
    end)
end

-------------------------------------------------------------------------------
--  Hide Unit Health Strip. GameTooltipStatusBar is Blizzard's health bar at
--  the bottom of unit tooltips; suppressed with a single SetAlpha(0) -- fully
--  taint-safe (only the top-level bar touched, never Shown/Hidden or given
--  custom keys, observed via hooksecurefunc never SetScript). The hook fires
--  only when Blizzard shows the bar, covering every anchor path (default,
--  cursor, unit-frame), and early-outs when off (one table read when
--  disabled, one SetAlpha when enabled). Default ENABLED (nil/true = hidden); independent of the reskin, works on default Blizzard tooltips too.
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
        -- Re-assert alpha 0 each time Blizzard shows the bar so it can never flash back into view (SetAlpha doesn't call Show, so no recursion).
        hooksecurefunc(GameTooltipStatusBar, "Show", function(bar)
            if _healthStripHidden() then bar:SetAlpha(0) end
        end)
        EllesmereUI._applyTooltipHealthStrip()
    end
end

-------------------------------------------------------------------------------
--  Blizzard HUD reskins: tooltip progress/status bars, UI widget status bar
--  covers, and the extra action button.
--
--  These are not WINDOWS -- no shell, no per-window style dropdown -- so they
--  live here rather than in a window pack.
--
--  The engine is resolved LAZILY. This file loads BEFORE
--  EllesmereUIBlizzardSkin_WindowEngine.lua (see the .toc), so ns.WSkin does
--  not exist at main-chunk time and a `local ADDON_NAME, ns = ...` capture at
--  the top of the file would hand this block a nil engine. WS() below resolves
--  on first use through EllesmereUI._ModuleNS, the registry this file itself
--  populates near line 10. That deliberately removes a re-port landmine: there
--  is no second capture line to remember after an EUI update, and therefore no
--  silent fallback to hand-rolled fonts and colors when someone misses it.
-------------------------------------------------------------------------------
;(function()
    local _WS
    local function WS()
        if _WS then return _WS end
        local mod = EllesmereUI._ModuleNS and EllesmereUI._ModuleNS[ADDON_NAME]
        _WS = mod and mod.WSkin
        -- Force the theme on first use: a tooltip bar on the very first hover
        -- can reach WSkin.Font before the engine's own PLAYER_LOGIN boot and
        -- hand SetFont a nil font path.
        if _WS and _WS.ResolveTheme and not (_WS.Theme and _WS.Theme.fontPath) then
            pcall(_WS.ResolveTheme)
        end
        return _WS
    end

    local FLAT = "Interface\\Buttons\\WHITE8X8"
    local _isSecretV = issecretvalue

    -- House font, with a REPAIR for nonsense sizes. A FontString created with
    -- no font object reports a garbage height (-1566.5 in the field), and any
    -- helper that PRESERVES the current size feeds that straight back, which
    -- surfaces as a flood of "Invalid font height (-1.000000): height must be
    -- > 0". An `or 11` fallback does NOT catch this -- the value is a number,
    -- just a nonsensical one -- so the test is on the SIGN.
    local function HouseFont(fs, white)
        if not fs or not fs.GetFont then return end
        local path, size, flags = fs:GetFont()
        if type(size) ~= "number" or size <= 0 then
            fs:SetFont(path or STANDARD_TEXT_FONT, 11, flags or "")
        end
        local W = WS()
        if W then
            if white then W.White(fs) else W.Font(fs) end
        elseif white and fs.SetTextColor then
            fs:SetTextColor(1, 1, 1)
        end
    end

    -- Tiny 1px BLACK outline. Deliberately not WSkin.AddBorder: that draws the
    -- themed accent border, which on a 15px bar is heavy chrome (the thing that
    -- kept getting rejected). Black at 1px reads as a crisp edge, not a frame.
    -- Idempotent via FFD; drawn on OVERLAY so the fill cannot cover it.
    local function ThinBorder(frame, inset)
        if not frame then return end
        local d = GetFFD(frame)
        if d.thinBorder then return end
        d.thinBorder = true
        -- Recorded as OURS: StripBarArt clears every texture on the bar, and
        -- these live on the bar.
        d.owned = d.owned or {}
        local i = inset or 0
        local edges = {
            { "TOPLEFT", -i, i, "TOPRIGHT", i, i, true },
            { "BOTTOMLEFT", -i, -i, "BOTTOMRIGHT", i, -i, true },
            { "TOPLEFT", -i, i, "BOTTOMLEFT", -i, -i, false },
            { "TOPRIGHT", i, i, "BOTTOMRIGHT", i, -i, false },
        }
        for n = 1, #edges do
            local e = edges[n]
            local t = frame:CreateTexture(nil, "OVERLAY", nil, 7)
            t:SetColorTexture(0, 0, 0, 1)
            t:SetPoint(e[1], frame, e[1], e[2], e[3])
            t:SetPoint(e[4], frame, e[4], e[5], e[6])
            if e[7] then t:SetHeight(1) else t:SetWidth(1) end
            d.owned[t] = true
        end
    end

    local function BarFill(bar)
        local W = WS()
        if W and W.ApplyBarFill then
            W.ApplyBarFill(bar)
        elseif bar.SetStatusBarColor then
            local EG = EllesmereUI.ELLESMERE_GREEN or { r = 0.047, g = 0.824, b = 0.616 }
            bar:SetStatusBarColor(EG.r * 0.8, EG.g * 0.8, EG.b * 0.8, 0.95)
        end
    end

    ---------------------------------------------------------------------------
    --  Tooltip progress + status bars.
    --
    --  Two different templates, both POOLED per tooltip, so the same bar frame
    --  comes back over and over and the skin has to survive reuse:
    --    TooltipProgressBarTemplate -- world quest / callings progress ("0%").
    --      A Frame wrapper whose .Bar is the StatusBar, with Border{Left,Mid,
    --      Right} and Left/RightDivider art and a .Bar.Label.
    --    TooltipStatusBarTemplate -- achievement category counts (the green
    --      201/295 bar). The StatusBar itself, with a .Text and one anonymous
    --      border texture. Its green comes from a SetStatusBarColor(0,1,0) in
    --      the template's OnLoad, so it MUST be re-colored per acquire.
    --
    --  Pools live on EACH tooltip (GameTooltip, EmbeddedItemTooltip, ...), so
    --  the hooks read the pool off the tooltip they were handed rather than
    --  assuming GameTooltip.
    ---------------------------------------------------------------------------
    -- `keepFill` is the live fill; OUR OWN textures are spared via FFD.
    --
    -- Without that second guard this wipes the trough and the border edges the
    -- moment a POOLED bar is reused: the first pass creates them (nothing to
    -- clear yet), the next pass clears them, and the bar renders once and then
    -- goes blank.
    local function StripBarArt(bar, keepFill)
        local owned = GetFFD(bar).owned
        -- Regions taken ONCE. select(i, bar:GetRegions()) inside the loop
        -- rebuilds the entire vararg every iteration.
        local regions = { bar:GetRegions() }
        for i = 1, #regions do
            local r = regions[i]
            if r and r ~= keepFill and not (owned and owned[r]) and r.IsObjectType then
                if r:IsObjectType("Texture") and r:GetDrawLayer() ~= "HIGHLIGHT" then
                    -- CLEARED, not alpha'd: these bars flare on change through
                    -- animations that drive alpha every frame and win over a
                    -- SetAlpha(0). An animation can animate nothing.
                    if r.SetAtlas then r:SetAtlas("") end
                    if r.SetTexture then r:SetTexture("") end
                    r:SetAlpha(0)
                end
            end
        end
    end

    local function SkinBarCommon(bar, keys)
        if not bar or bar:IsForbidden() or not bar.SetStatusBarTexture then return end
        -- Fill installed FIRST, then re-read, so the "clear everything that is
        -- not the fill" sweep below can never clear the live fill whatever art
        -- Blizzard happened to have there.
        bar:SetStatusBarTexture(FLAT)
        local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
        StripBarArt(bar, fill)
        for i = 1, #keys do
            local t = bar[keys[i]]
            if t and t.SetTexture then
                if t.SetAtlas then t:SetAtlas("") end
                t:SetTexture("")
                t:SetAlpha(0)
            end
        end
        local d = GetFFD(bar)
        if not d.hudTrough then
            -- OPAQUE and lighter than the widget covers' trough. These sit on
            -- the tooltip's own dark backplate rather than over the world, so
            -- 0.12 at 85% was invisible against it: an EMPTY bar (a world quest
            -- at 0%) read as a gap in the tooltip rather than as a bar. It
            -- needs to be legible with NO fill in it at all.
            local trough = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
            trough:SetColorTexture(0.22, 0.22, 0.22, 1)
            trough:SetAllPoints(bar)
            d.hudTrough = trough
            d.owned = d.owned or {}
            d.owned[trough] = true
            -- Same 1px black edge as the widget covers. NOT WSkin.AddBorder:
            -- the themed border is what made these read as thick chrome.
            ThinBorder(bar)
        end
        BarFill(bar)
    end

    local PROGRESS_ART = {
        "BorderLeft", "BorderRight", "BorderMid", "LeftDivider", "RightDivider",
    }

    local function SkinProgressBar(frame)
        local bar = frame and frame.Bar
        if not bar then return end
        SkinBarCommon(bar, PROGRESS_ART)
        HouseFont(bar.Label, true)
    end

    local function SkinStatusBar(bar)
        SkinBarCommon(bar, {})
        HouseFont(bar.Text, true)
    end

    local function SweepPool(pool, fn)
        if not (pool and pool.EnumerateActive) then return end
        local ok, iter = pcall(pool.EnumerateActive, pool)
        if ok and iter then
            for f in iter do pcall(fn, f) end
        end
    end

    -- Post-hooks on the ADD functions, not the SHOW ones: ShowProgressBar and
    -- ShowStatusBar both delegate to Add*, and only Add* runs for the second
    -- and later bars on one tooltip.
    if type(_G.GameTooltip_AddProgressBar) == "function" then
        hooksecurefunc("GameTooltip_AddProgressBar", function(self)
            if self then SweepPool(self.progressBarPool, SkinProgressBar) end
        end)
    end
    if type(_G.GameTooltip_AddStatusBar) == "function" then
        hooksecurefunc("GameTooltip_AddStatusBar", function(self)
            if self then SweepPool(self.statusBarPool, SkinStatusBar) end
        end)
    end

    ---------------------------------------------------------------------------
    --  UI widget status bars -- COVERS, never writes.
    --
    --  Widget values are SECRET inside instanced content. An insecure write
    --  anywhere in a widget tree resurfaces later as "attempt to compare a
    --  secret number value" out of LayoutFrame, far from the code that caused
    --  it. So Blizzard's bar is never touched: an EUI-owned StatusBar parented
    --  to UIParent is merely ANCHORED to it (a write on ours, none on theirs)
    --  and mirrors min/max/value/label through pcall. Any failed or secret read
    --  RETIRES that cover and Blizzard's own bar shows through again;
    --  retirement clears on PLAYER_ENTERING_WORLD.
    --
    --  Containers are DISCOVERED, not hardcoded: the bars in the field are
    --  mostly on NAMEPLATES (NamePlateN.UnitFrame.WidgetContainer.<anon>.Bar),
    --  not on any screen container. ObjectiveTrackerUIWidgetContainer is
    --  deliberately EXCLUDED -- its bars sit inside the tracker's clipped
    --  scrolling layout, where a UIParent-parented cover would float free.
    --
    --  PERFORMANCE (this subsystem caused a real CPU complaint once). The
    --  house standard is TWO separate promises: nothing at all while the
    --  setting is off, and event-driven -- never polled -- while it is on.
    --   - OFF means the events are never REGISTERED. The gate is at
    --     PLAYER_LOGIN, not inside the handlers: an early return in a live
    --     handler still pays for the registration and the dispatch. With the
    --     setting off, hudEv ends up with no events and no script at all.
    --   - There is NO TIMER. Sweeps run from the widget system's own events,
    --     coalesced to at most one per frame, plus a hook on each covered
    --     bar's own DisplayBarValue for the two cases that move a bar with no
    --     event to listen for (see Adopt).
    --   - children taken ONCE per frame, never select(i, f:GetChildren()) in a
    --     loop, which is O(n^2) and lethal on a container walk;
    --   - discovery is LOGIN/ZONE work and never hangs off a per-update event;
    --   - nameplates are tracked via NAME_PLATE_UNIT_ADDED/REMOVED, because
    --     C_NamePlate.GetNamePlates() allocates a fresh table on every call.
    ---------------------------------------------------------------------------
    local HUD = {
        covers   = setmetatable({}, { __mode = "k" }),  -- blizz bar -> our cover
        retired  = setmetatable({}, { __mode = "k" }),
        plates   = setmetatable({}, { __mode = "k" }),
        -- Containers a window pack handed us explicitly. Kept SEPARATE from
        -- `containers` because Discover() wipes that list on every zone, and
        -- these cannot be rediscovered -- they are nested inside a window, not
        -- children of UIParent.
        adopted  = setmetatable({}, { __mode = "k" }),
        -- OUR OWN cover frames. Load-bearing since covers became children of
        -- Blizzard's frames: a cover is itself a StatusBar sitting inside a
        -- widget container, so without this the next sweep DISCOVERS IT as a
        -- bar to cover, and does so again every tick -- the bar visibly grows
        -- forever. Nothing in this set is ever treated as a Blizzard bar.
        owned    = setmetatable({}, { __mode = "k" }),
        -- Bars whose own DisplayBarValue we have already hooked, so a re-adopt
        -- of a pooled bar cannot stack a second hook on it.
        hooked   = setmetatable({}, { __mode = "k" }),
        containers = {},
        -- Foreign-set gate state. setIds = the widgetSetIDs currently owned by
        -- containers the sweep actually walks, rebuilt as a side-read of every
        -- sweep; setHooked = containers whose RegisterForWidgetSet is hooked
        -- (a mid-life re-registration books a sweep, which re-records);
        -- setIdsExact = whether every container's set id was readable last
        -- sweep. While false the gate stands down and every widget event
        -- sweeps, exactly as before the gate existed.
        setIds   = {},
        setHooked = setmetatable({}, { __mode = "k" }),
        setIdsExact = false,
        -- Set at PLAYER_LOGIN only when the setting is on. Nothing here has
        -- run while this is false.
        installed = false,
        -- Minimum on-screen height for plate-hosted covers, cached from the
        -- setting (0 = off). Seeded at login, re-read only when the cog writes it.
        minPx = 0,
    }

    local NAMED_CONTAINERS = {
        "UIWidgetTopCenterContainerFrame",
        "UIWidgetBelowMinimapContainerFrame",
        "UIWidgetPowerBarContainerFrame",
        "UIWidgetCenterDisplayFrame",
    }

    -- Existing accounts get an EXPLICIT boolean seeded once by the
    -- blizzskin_widget_bars_seed_v1 migration (on only when Reskin Tooltips
    -- AND Reskin Popups and Menus are both on); nil survives only on fresh
    -- installs, where both of those masters default on too -- so nil = on.
    local function CoverEnabled()
        return not EllesmereUIDB or EllesmereUIDB.reskinWidgetBars ~= false
    end

    -- FORWARD DECLARATION, filled in far below. Adopt installs a hook that has
    -- to call the debounced refresh; that refresh cannot be written until
    -- Sweep exists, and Sweep cannot be written until Adopt does. A
    -- `local function Refresh` written below would NOT be in scope up here --
    -- the name would resolve to a nil global, and the pcall wrapped round the
    -- hook would swallow the failure without a word.
    local Refresh

    -- Read a value and reject it if it is secret. Returns ok, value. Reads
    -- resolve into a LOCAL before any comparison -- a getter called mid-`and`
    -- chain throws on the spot rather than being skipped.
    local function SafeRead(obj, method)
        local fn = obj and obj[method]
        if type(fn) ~= "function" then return false end
        local ok, a, b = pcall(fn, obj)
        if not ok then return false end
        if _isSecretV then
            if a ~= nil and _isSecretV(a) then return false end
            if b ~= nil and _isSecretV(b) then return false end
        end
        return true, a, b
    end

    local function RetireCover(bar)
        local c = HUD.covers[bar]
        if c then
            c:Hide()
            HUD.covers[bar] = nil
        end
        HUD.retired[bar] = true
    end

    -- Blizzard's frame art extends BEYOND the bar's own rect: in
    -- UIWidgetTemplateStatusBar, BorderLeft sits at LEFT x=-8 and BorderRight at
    -- RIGHT x=+8, both useAtlasSize (so their HEIGHT is whatever the widget
    -- style ships), and GlowLeft/Right/Center anchor to those borders and PULSE
    -- through GlowPulseAnim. A cover sized to the bar rect therefore leaves a
    -- ring of Blizzard border art visible around it -- which is exactly what
    -- turned up on nameplate bars in game.
    --
    -- The MASK is a separate texture from the trough for a reason: the cover
    -- StatusBar keeps the bar's true rect so the fill proportion stays honest,
    -- while the mask alone spreads out to swallow the frame art. Textures are
    -- not clipped to their parent's bounds, so it can extend past the cover.
    --
    -- Anchored to the border TEXTURES when they exist, so it tracks whatever
    -- atlas size the style uses instead of guessing. Anchoring OUR texture to
    -- THEIRS is still a write on ours only -- the widget tree is untouched.
    local COVER_PAD_X = 9   -- fallback horizontal reach: template border offset + 1px
    -- Ceiling on the vertical overhang the cover will absorb. Blizzard's border
    -- run is a couple of px taller than the bar; a decorative END CAP atlas can
    -- be far taller, and following that is what made the bar giant.
    --
    -- Lowered 5 -> 2 because the bar read as chunky: at 5 a bar whose art is
    -- oversized ends up bar+10, and the pad is pure thickness. The real floor is
    -- Blizzard's own bar height -- the cover cannot go under that without
    -- exposing the art it exists to hide, and shrinking their bar would mean
    -- writing into the widget tree. 2 keeps the common border covered and
    -- refuses anything decorative; a 1px sliver on an unusual style is a better
    -- trade than a permanently fat bar.
    -- ONE small pad, everywhere. THIN IS THE PRIORITY.
    --
    -- A 10px "panel" pad was tried so the cover would fully occlude Blizzard's
    -- border art (31px of texture around a 15px bar) and it made the bars
    -- chunky -- for a benefit nobody asked for. The border art is mostly
    -- transparent padding; chasing its full extent buys nothing and costs
    -- height on every bar. 2px covers the drawn edge.
    --
    -- If a sliver of Blizzard's frame ever shows, raise THIS number -- do not
    -- reintroduce a per-context split. Thin beats perfectly occluded.
    local MAX_VPAD = 2
    -- Plain indexed read, passed BY ARGUMENT to pcall (no closure allocated).
    -- Field access on a widget frame can throw, so even fetching a texture
    -- reference off one has to be guarded.
    local function HUDGet(t, k)
        return t[k]
    end

    -- Anchor the COVER ITSELF out to Blizzard's border art, not to the bar's
    -- inner rect.
    --
    -- Two earlier builds got this wrong in opposite directions. Sizing the
    -- cover to the bar rect left Blizzard's border ring showing around it.
    -- Adding a wider MASK behind the cover hid the ring but produced a dark
    -- margin all the way round, because the fill only ever reached the inner
    -- rect -- which read as an even bigger border.
    --
    -- So the cover takes the whole footprint and the fill spans it. The fill
    -- then represents value/max across a rect ~8px wider each side than
    -- Blizzard's own, but nothing is left on screen to compare it against and
    -- the scale is internally consistent (0% empty, 100% full). A clean bar
    -- beats a technically-truer one wearing a frame.
    -- How much taller Blizzard's border art is than the bar it wraps, halved
    -- (the art is centered on the bar, so the overhang is split top and bottom).
    --
    -- MEASURED, not guessed. A /framestack over a live bar showed the real
    -- shape: the cover sits at frame level 8 over a Bar at level 6, so layering
    -- was never the problem -- but `Bar.BorderCenter` is its own texture and is
    -- TALLER than the Bar, so a cover matching the Bar's height leaves a thin
    -- line of it above and below. That is the "weird small outline".
    --
    -- Capped at MAX_VPAD because BorderLeft/BorderRight are useAtlasSize end
    -- CAPS whose atlas can be far larger than the bar; taking their full height
    -- is what produced the giant-bar round.
    local function VPad(bar)
        local okB, barH = pcall(bar.GetHeight, bar)
        if not okB or type(barH) ~= "number" or barH <= 0 then return 0 end
        local tallest = barH
        for _, k in ipairs({ "BorderCenter", "BorderLeft", "BorderRight" }) do
            local okT, t = pcall(HUDGet, bar, k)
            if okT and t then
                local okH, h = pcall(t.GetHeight, t)
                if okH and type(h) == "number" and h > tallest then tallest = h end
            end
        end
        local pad = (tallest - barH) / 2
        if pad < 0 then pad = 0 end
        if pad > MAX_VPAD then pad = MAX_VPAD end
        return pad
    end

    -- EVERY point comes from the BAR. Nothing is anchored to Blizzard's border
    -- textures any more.
    --
    -- Anchoring to them was an attempt to track arbitrary atlas sizes, and it
    -- kept producing garbage. On the PlayerChoice style BorderLeft/BorderRight
    -- EXIST but are EMPTY -- no atlas, degenerate rect -- so they are neither
    -- nil (which would take the fallback) nor meaningful. Anchoring LEFT/RIGHT
    -- to them stretched one cover across the entire screen. They are also
    -- invisible to /framestack, which only lists hit-testable regions, so they
    -- read as "absent" while still being present.
    --
    -- A fixed pad is deterministic and cannot blow up: the template offsets the
    -- border art 8px past each end of the bar, so 9 covers it with a pixel to
    -- spare regardless of what the atlas does.
    -- The occluder reaches the FULL measured overhang -- uncapped by MAX_VPAD,
    -- which governs the VISIBLE bar's height only. Sanity-limited so a
    -- decorative end-cap atlas cannot spread a huge dark rectangle.
    local MAX_OCCLUDE = 14
    local function AnchorOccluder(c, bar)
        local occ = c.euiOcc
        if not occ then return end
        local okB, barH = pcall(bar.GetHeight, bar)
        local grow = 0
        if okB and type(barH) == "number" and barH > 0 then
            local tallest = barH
            for _, k in ipairs({ "BorderCenter", "BGCenter", "BorderLeft", "BorderRight" }) do
                local okT, t = pcall(HUDGet, bar, k)
                if okT and t then
                    local okH, h = pcall(t.GetHeight, t)
                    if okH and type(h) == "number" and h > tallest then tallest = h end
                end
            end
            grow = (tallest - barH) / 2
            if grow < 0 then grow = 0 end
            if grow > MAX_OCCLUDE then grow = MAX_OCCLUDE end
        end
        occ:ClearAllPoints()
        occ:SetPoint("TOPLEFT", bar, "TOPLEFT", -COVER_PAD_X, grow)
        occ:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", COVER_PAD_X, -grow)
    end

    -- Minimum on-screen cover HEIGHT (real pixels) for PLATE-HOSTED bars, the cog
    -- on "Reskin Widget Bars". A nameplate carries its own scale, so a shrunken
    -- plate drags its widget bar and label down to unreadable; below the floor
    -- the cover SCALES up (label rides along). Growing past Blizzard's rect is
    -- safe only because HideBarArt alphas their art; the "never SMALLER" floor
    -- still stands. Panel bars never scale. 0 = OFF (mirror the rect exactly),
    -- and OFF is the default: opt-in, and it keeps instances -- where the plate
    -- lane is unregistered anyway -- at zero added cost.
    local DEFAULT_MIN_BAR_PX = 0
    local MAX_MIN_BAR_PX = 24
    -- Cap on the correction: a bar mid-fade at 1px would otherwise ask for a slab.
    local MAX_UPSCALE = 3

    -- Cached on HUD, never read per bar per pass (SyncCover can run every frame
    -- while a fill animates); the options cog re-reads it through the seam.
    local function ReadMinPx()
        local v = EllesmereUIDB and EllesmereUIDB.widgetBarMinSize
        if type(v) ~= "number" then return DEFAULT_MIN_BAR_PX end
        if v < 0 then return 0 end
        if v > MAX_MIN_BAR_PX then return MAX_MIN_BAR_PX end
        return v
    end

    -- Scale factor that lifts a plate cover to the floor; 1 = leave it alone
    -- (floor off, panel bar, or plate at readable scale).
    local function CoverScale(bar, c)
        local min = HUD.minPx
        if not (c.euiPlate and type(min) == "number" and min > 0) then return 1 end
        local okH, h = pcall(bar.GetHeight, bar)
        if not okH or type(h) ~= "number" or h <= 0 then return 1 end
        local okE, es = pcall(bar.GetEffectiveScale, bar)
        if not okE or type(es) ~= "number" or es <= 0 then return 1 end
        local px = h * es
        if px <= 0 or px >= min then return 1 end
        local s = min / px
        if s > MAX_UPSCALE then s = MAX_UPSCALE end
        return s
    end

    local function AnchorCover(c, bar, pad)
        local s = CoverScale(bar, c)
        c:ClearAllPoints()
        if s <= 1 then
            -- EXACTLY the bar's rect. With their art hidden there is nothing to
            -- reach past, so no pad, no overhang, no slab.
            if c.euiScale ~= 1 then c:SetScale(1); c.euiScale = 1 end
            c.euiMin = HUD.minPx
            c:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
            c:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
            return
        end
        -- Scaled: CENTER to CENTER with an explicit size, never the two-corner
        -- anchor. Corner anchors DERIVE the size from the bar, so they would
        -- undo the scale as fast as it was applied -- the cover would render
        -- the same size as before with a bigger font in it. CENTER with zero
        -- offsets is the one anchor that needs no scale conversion, so the
        -- cover stays centred on the bar it mirrors and grows symmetrically.
        local okW, w = pcall(bar.GetWidth, bar)
        local okH, h = pcall(bar.GetHeight, bar)
        if not (okW and okH) or type(w) ~= "number" or type(h) ~= "number"
           or w <= 0 or h <= 0 then
            if c.euiScale ~= 1 then c:SetScale(1); c.euiScale = 1 end
            c.euiMin = HUD.minPx
            c:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
            c:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
            return
        end
        c:SetScale(s)
        c.euiScale = s
        c.euiMin = HUD.minPx
        c:SetSize(w, h)
        c:SetPoint("CENTER", bar, "CENTER", 0, 0)
    end

    local function BuildCover(bar, isPlate)
        -- Parented to the BAR'S OWN PARENT, not UIParent.
        --
        -- UIParent parenting was the original design ("write on ours, none on
        -- theirs") and it does not reliably draw on top: inside a toplevel
        -- window, Blizzard's subtree and a UIParent child are different
        -- branches, and matching strata + level+2 was NOT enough -- covers
        -- shown, sized and reading fine while the stock bars stayed visible
        -- underneath.
        --
        -- SetParent on OUR OWN frame is still not a write into the widget tree;
        -- nothing on a Blizzard frame is modified. It also makes the cover
        -- inherit their scale and show/hide for free.
        local okP, parent = SafeRead(bar, "GetParent")
        local c = CreateFrame("StatusBar", nil, (okP and parent) or UIParent)
        -- Anchored, never re-parented: position needs no polling because the
        -- anchor does it, including when a nameplate moves.
        c.euiPad = VPad(bar)
        c.euiScale = 1
        -- Plate-hosted covers are the only ones the size floor applies to.
        c.euiPlate = isPlate and true or false
        AnchorCover(c, bar, c.euiPad)
        c:SetStatusBarTexture(FLAT)
        -- OPAQUE trough, not the usual 0.85: this one has to hide Blizzard's
        -- bar and border underneath rather than merely sit behind our own fill.
        -- Spans the whole cover, so there is no dark margin anywhere.
        local trough = c:CreateTexture(nil, "BACKGROUND", nil, -1)
        trough:SetColorTexture(0.10, 0.10, 0.10, 1)
        trough:SetAllPoints(c)
        -- Font OBJECT, not a bare CreateFontString: a template-less string
        -- reports a garbage height that any size-preserving helper feeds back
        -- into SetFont.
        local label = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("CENTER", c, "CENTER", 0, 0)
        c.euiLabel = label
        HouseFont(label, true)
        BarFill(c)
        -- Tiny black outline on EVERY bar, by maintainer call. The earlier "no border"
        -- call was about the THEMED accent border, which is heavy on a 15px
        -- bar; a 1px black edge is what actually defines it.
        ThinBorder(c)

        return c
    end

    -- Blizzard's own bar art, alpha'd to nothing.
    --
    -- This replaces the occluder -- a dark rectangle painted over their frame,
    -- which never blended and read as a patch rather than a skin.
    --
    -- The "never write into a widget tree" rule is about VALUES: widget values
    -- are secret, and reading or comparing one throws. SetAlpha on a TEXTURE
    -- touches no value, no layout and no Lua field, so it does not put secret
    -- data anywhere near our code. Every read of theirs still goes through
    -- SafeRead, and the cover still retires on a secret value.
    --
    -- Re-asserted each sync: these bars are pooled and re-textured per widget.
    -- "Label" is in this list because the COVER draws that text itself, so
    -- Blizzard's is a duplicate sitting underneath. It only shows on strings
    -- with a DESCENDER -- "Friendly" hung a stray y below the bar while
    -- "Revered" looked clean -- because that is the only part reaching past the
    -- cover's bottom edge. Hiding a FontString is the same alpha write as a
    -- texture: no value, no layout, no Lua field.
    local ART = { "BGLeft", "BGRight", "BGCenter", "BorderLeft", "BorderRight",
                  "BorderCenter", "Spark", "BackgroundGlow",
                  "GlowLeft", "GlowRight", "GlowCenter", "Label" }
    -- Plate art on the widget FRAME (the bar's parent), outside the bar's own
    -- rect: UIWidgetTemplateStatusBar puts LabelBG and LabelBGDivider there.
    -- Stripping only the bar leaves them showing as a stray background around
    -- it. The frame-level Label is deliberately NOT touched -- it is a separate
    -- caption above the bar, not the duplicate of the bar's own text.
    local PARENT_ART = { "LabelBG", "LabelBGDivider" }
    -- Local copy: KidsOf is declared further down, and a `local function` is
    -- not in scope for code written above it -- the reference would resolve to
    -- a nil global and the pcall around it would swallow the failure silently.
    local function BarKids(f) return { f:GetChildren() } end
    local function HideBarArt(bar)
        for i = 1, #ART do
            local okT, t = pcall(HUDGet, bar, ART[i])
            if okT and t then pcall(t.SetAlpha, t, 0) end
        end
        local okP, parent = SafeRead(bar, "GetParent")
        if okP and parent then
            for i = 1, #PARENT_ART do
                local okT, t = pcall(HUDGet, parent, PARENT_ART[i])
                if okT and t then pcall(t.SetAlpha, t, 0) end
            end
        end
        -- DIVIDER TICKS. Blizzard builds these at runtime
        -- (Blizzard_UIWidgetTemplateBase.lua) as ANONYMOUS child FRAMES of the
        -- bar, each holding a .Tex with a widgetstatusbar-bordertick atlas.
        -- Nothing named, so the key sweep above can never reach them and they
        -- survive as stray marks across the bar.
        --
        -- Our cover is parented to the bar's PARENT, not the bar, so it is
        -- never in this list -- no risk of hiding ourselves.
        local okK, kids = pcall(BarKids, bar)
        if okK and kids then
            for i = 1, #kids do
                local okT, t = pcall(HUDGet, kids[i], "Tex")
                if okT and t then pcall(t.SetAlpha, t, 0) end
            end
        end
    end

    local function SyncCover(bar, isPlate)
        if HUD.retired[bar] then return false end
        local c = HUD.covers[bar]
        if not c then return false end
        -- Pooled bars can migrate between hosts; keep the plate flag current.
        c.euiPlate = isPlate and true or false

        local shownOk, shown = SafeRead(bar, "IsVisible")
        if not shownOk then RetireCover(bar); return false end
        if not shown then
            if c:IsShown() then c:Hide() end
            return false
        end

        local mmOk, mn, mx = SafeRead(bar, "GetMinMaxValues")
        local vOk, v = SafeRead(bar, "GetValue")
        if not (mmOk and vOk) then RetireCover(bar); return false end

        -- Change-guarded: a ticker re-issuing these ten times a second per bar
        -- is pure waste.
        local cn, cx = c:GetMinMaxValues()
        local changed = false
        if cn ~= mn or cx ~= mx then c:SetMinMaxValues(mn, mx); changed = true end
        if c:GetValue() ~= v then c:SetValue(v); changed = true end

        local blabel = bar.Label
        local txt
        if blabel then
            local tOk, t = SafeRead(blabel, "GetText")
            if tOk then txt = t end
        end
        txt = txt or ""
        if c.euiLabel:GetText() ~= txt then c.euiLabel:SetText(txt); changed = true end

        -- HideBarArt ONLY on change, never every tick.
        --
        -- It is by far the most expensive thing here: ~13 pcall'd field reads
        -- plus a children walk that allocates a table, and at 10Hz per bar that
        -- is pure waste in the steady state. Blizzard only re-textures a bar
        -- when its widget updates -- which is exactly when a value or label
        -- moves -- so a change IS the re-texture signal. Adopt() also hides at
        -- creation, so a bar is never left showing its own art.
        if changed then HideBarArt(bar) end

        -- Follow the bar if it is re-parented (these frames are POOLED, so a
        -- reused bar can land under a different option).
        local pOk, bp = SafeRead(bar, "GetParent")
        if pOk and bp and c:GetParent() ~= bp then c:SetParent(bp) end

        -- STRATA FIRST, THEN LEVEL. SetFrameStrata RESETS a frame's level, so
        -- the reverse order silently threw the level away on the first pass and
        -- only self-corrected on the next tick.
        local stOk, st = SafeRead(bar, "GetFrameStrata")
        if stOk and st and c:GetFrameStrata() ~= st then c:SetFrameStrata(st) end
        local lvlOk, lvl = SafeRead(bar, "GetFrameLevel")
        if lvlOk and type(lvl) == "number" then
            local want = lvl + 2
            if c:GetFrameLevel() ~= want then c:SetFrameLevel(want) end
        end

        -- Re-anchor only when the measured overhang actually changed: Blizzard
        -- re-textures these bars per widget style, and the border height can
        -- differ between one use of a pooled bar and the next.
        -- VPad re-measures four textures; the answer only moves if the bar's
        -- own height does, so it is cached against that.
        local hOk, curH = pcall(bar.GetHeight, bar)
        local pad = c.euiPad
        if not hOk or curH ~= c.euiPadH then
            pad = VPad(bar)
            c.euiPadH = hOk and curH or nil
        end
        -- Second trigger, PLATE covers with the size floor ON only: the bar's
        -- effective scale moves with the plate while its local height does not.
        -- Panel bars and the floor-off default skip the probe entirely (this
        -- runs per bar per sweep, per frame while a fill animates). Thresholded:
        -- plate distance-scaling drifts continuously and an exact compare would
        -- re-anchor every frame.
        local es
        if c.euiPlate and HUD.minPx > 0 then
            local esOk, curES = pcall(bar.GetEffectiveScale, bar)
            if esOk and type(curES) == "number" then es = curES end
        end
        local esMoved = (es ~= nil) ~= (c.euiES ~= nil)
            or (es and c.euiES and math.abs(es - c.euiES) > 0.01)
        -- Third trigger: the floor itself (the cog's slider re-anchors live covers).
        if pad ~= c.euiPad or esMoved or c.euiMin ~= HUD.minPx then
            c.euiPad = pad
            c.euiES = es
            AnchorCover(c, bar, pad)
        end

        if not c:IsShown() then c:Show() end
        return true
    end

    -- The hook body runs INSIDE Blizzard's call stack, so anything thrown here
    -- surfaces as an error in THEIR widget update rather than ours. Every read
    -- inside Sweep is already pcall'd, but the wrapper is the cheap guarantee.
    --
    -- It asks for the DEBOUNCED refresh rather than syncing the bar on the
    -- spot, and that is load-bearing. DisplayBarValue is called from the
    -- middle of UIWidgetTemplateStatusBarMixin:Setup, which AFTERWARDS puts
    -- the glow textures back with SetAlpha(1). Syncing here would consume the
    -- value change -- and with it the HideBarArt trigger, which is
    -- change-guarded -- one step before the art that has to be hidden is
    -- restored, leaving the glows on show with nothing left to re-fire the
    -- hide. Next frame sees the finished widget, which is exactly where the
    -- old ticker saw it.
    local function OnBarValueDisplayed()
        pcall(Refresh)
    end

    local function Adopt(bar, isPlate)
        if not bar or HUD.retired[bar] then return end
        if HUD.covers[bar] then return end
        -- Never cover one of our own covers (see HUD.owned).
        if HUD.owned[bar] then return end
        if bar.IsForbidden and bar:IsForbidden() then return end
        -- Immediately, before the cover has values to show. Otherwise their bar
        -- is what you watch for the first few ticks while it animates in, which
        -- reads as the skin taking half a second to appear.
        HideBarArt(bar)
        local c = BuildCover(bar, isPlate)
        HUD.owned[c] = true
        HUD.covers[bar] = c

        -- FOLLOW THE BAR'S OWN UPDATE. This is what replaced the 0.1s ticker.
        --
        -- Two things move a widget bar with no event we could ever listen for,
        -- both visible in Blizzard_UIWidget* source:
        --   - a widget with hasTimer is re-processed by its own CONTAINER off
        --     a 1s C_Timer (UIWidgetContainerMixin:RegisterTimerWidget).
        --     UPDATE_UI_WIDGET does not fire for those ticks.
        --   - a fillMotionType other than Instant makes the bar set its OWN
        --     OnUpdate and walk displayedValue toward value over several
        --     frames (UIWidgetBaseStatusBarTemplateMixin:UpdateBar).
        -- Both funnel through DisplayBarValue, the single place the bar calls
        -- SetValue, so that is the update event the widget system actually
        -- has. Hooking it costs nothing when nothing moves and follows a
        -- smooth fill frame by frame when it does -- which is the whole shape
        -- a poll was faking.
        --
        -- hooksecurefunc on ONE FRAME'S method, not a write into the widget
        -- tree: no value is read, compared or stored, and it is the same call
        -- this file already makes on GameTooltipStatusBar. pcall'd because a
        -- field access on a widget frame can throw on its own.
        if not HUD.hooked[bar] and type(bar.DisplayBarValue) == "function" then
            HUD.hooked[bar] = true
            pcall(hooksecurefunc, bar, "DisplayBarValue", OnBarValueDisplayed)
        end
    end

    -- Children as a TABLE, passed by argument to pcall. The obvious spelling,
    -- pcall(function() return { f:GetChildren() } end), allocates a closure on
    -- every frame of every walk.
    local function KidsOf(f)
        return { f:GetChildren() }
    end

    -- Walk a container for StatusBars. Depth-capped and children taken once.
    local function CollectBars(frame, depth, out, seen)
        if not frame or depth > 4 then return end
        if seen[frame] then return end
        seen[frame] = true
        if not frame.GetChildren then return end
        local okKids, kids = pcall(KidsOf, frame)
        if not okKids or not kids then return end
        for i = 1, #kids do
            local ch = kids[i]
            -- Skip OUR OWN covers entirely -- not collected, not descended
            -- into. They are StatusBars living inside Blizzard's frames, so
            -- without this the sweep covers its own covers, every tick.
            if ch and HUD.owned[ch] then
                ch = nil
            end
            if ch and ch.GetObjectType and not (ch.IsForbidden and ch:IsForbidden()) then
                local okT, t = pcall(ch.GetObjectType, ch)
                if okT and t == "StatusBar" then
                    out[#out + 1] = ch
                else
                    CollectBars(ch, depth + 1, out, seen)
                end
            end
        end
    end

    -- Login / zone work ONLY. Never call this from a per-update event.
    local function Discover()
        wipe(HUD.containers)
        for i = 1, #NAMED_CONTAINERS do
            local f = _G[NAMED_CONTAINERS[i]]
            if f then HUD.containers[#HUD.containers + 1] = f end
        end
        -- Any other UIParent child that is a widget container. Children taken
        -- ONCE; UIParent has a few hundred of them.
        local up = _G.UIParent
        if up and up.GetChildren then
            local kids = { up:GetChildren() }
            for i = 1, #kids do
                local ch = kids[i]
                if ch and ch.GetName and not (ch.IsForbidden and ch:IsForbidden()) then
                    local okN, n = pcall(ch.GetName, ch)
                    local okP, pools = pcall(function() return ch.widgetPools end)
                    local isWidget = (okN and type(n) == "string" and n:find("^UIWidget"))
                                     or (okP and pools ~= nil)
                    -- The tracker's own widget container is excluded on
                    -- purpose: its bars live inside a clipped scrolling layout,
                    -- so a UIParent-parented cover would float free of it.
                    if isWidget and not (okN and n == "ObjectiveTrackerUIWidgetContainer") then
                        HUD.containers[#HUD.containers + 1] = ch
                    end
                end
            end
        end
        -- Re-add anything a window pack adopted: the wipe above would otherwise
        -- drop them on the first zone change and they can never be rediscovered.
        for f in pairs(HUD.adopted) do
            HUD.containers[#HUD.containers + 1] = f
        end
    end

    -- Scratch tables reused across passes: a sweep can run every frame while a
    -- smooth fill animates, and two fresh tables per pass is needless churn
    -- for the GC.
    HUD.scratchBars, HUD.scratchSeen = {}, {}

    -- Mid-life set changes on a container we sweep (vigor set arming when the
    -- player mounts, a pooled plate container re-targeted) book a sweep, and
    -- that sweep re-records the registry. Named function, created once.
    local function OnWidgetSetRegistered()
        HUD.setIdsExact = false
        Refresh()
    end

    -- Record one container's widget-set id into the gate registry and make
    -- sure its re-registrations are hooked. Returns the running exactness:
    -- an unreadable id (or a secret one) means the registry cannot prove a
    -- foreign event foreign, so the gate must stand down. A container with NO
    -- set (nil id) stays exact -- no widget event can belong to it.
    local function NoteContainerSet(c, exact)
        if not HUD.setHooked[c] then
            local okR, reg = pcall(HUDGet, c, "RegisterForWidgetSet")
            if okR then
                HUD.setHooked[c] = true
                if type(reg) == "function" then
                    pcall(hooksecurefunc, c, "RegisterForWidgetSet", OnWidgetSetRegistered)
                end
            end
        end
        local okS, sid = pcall(HUDGet, c, "widgetSetID")
        if not okS then return false end
        if sid == nil then return exact end
        if (_isSecretV and _isSecretV(sid)) or type(sid) ~= "number" then return false end
        HUD.setIds[sid] = true
        return exact
    end

    -- No CoverEnabled() check here on purpose. The setting is read ONCE, at
    -- login, and decides whether any of this is wired up at all; re-testing it
    -- per pass would only produce a half-state where the covers are still on
    -- screen but have stopped following their bars.
    local function Sweep()
        local live = 0
        local seen, bars = HUD.scratchSeen, HUD.scratchBars
        wipe(seen); wipe(bars)
        wipe(HUD.setIds)
        local exact = true
        for i = 1, #HUD.containers do
            exact = NoteContainerSet(HUD.containers[i], exact)
            CollectBars(HUD.containers[i], 0, bars, seen)
        end
        -- Everything collected past this index came from a plate container.
        local nStatic = #bars
        -- WIDGET CONTAINERS ONLY, never the whole plate. A nameplate base
        -- frame also hosts unit-frame trees (EllesmereUI's own health and cast
        -- bars are StatusBars parented under it), and a full walk adopts and
        -- art-strips those. The container is found by the same widgetPools
        -- probe Discover uses; with EUI nameplates off it sits one level down,
        -- under the Blizzard unit frame's WidgetContainer key instead.
        for plate in pairs(HUD.plates) do
            local okKids, kids = pcall(KidsOf, plate)
            if okKids and kids then
                for i = 1, #kids do
                    local ch = kids[i]
                    if ch and not (ch.IsForbidden and ch:IsForbidden()) then
                        local okP, pools = pcall(HUDGet, ch, "widgetPools")
                        if okP and pools ~= nil then
                            exact = NoteContainerSet(ch, exact)
                            CollectBars(ch, 0, bars, seen)
                        else
                            local okW, wc = pcall(HUDGet, ch, "WidgetContainer")
                            if okW and wc and not (wc.IsForbidden and wc:IsForbidden()) then
                                exact = NoteContainerSet(wc, exact)
                                CollectBars(wc, 0, bars, seen)
                            end
                        end
                    end
                end
            else
                -- A plate whose children could not be read holds containers
                -- the registry cannot see: gate stands down.
                exact = false
            end
        end
        HUD.setIdsExact = exact
        for i = 1, #bars do
            local isPlate = i > nStatic
            Adopt(bars[i], isPlate)
            if SyncCover(bars[i], isPlate) then live = live + 1 end
        end
        -- Covers whose bar has gone away this pass.
        for bar, c in pairs(HUD.covers) do
            if not seen[bar] then
                local ok, vis = SafeRead(bar, "IsVisible")
                if not ok or not vis then
                    if c:IsShown() then c:Hide() end
                end
            end
        end
        return live
    end

    -- ONE sweep per frame, on the TRAILING edge. This is what the 0.1s ticker
    -- turned into.
    --
    -- Deferred rather than immediate for two independent reasons:
    --   - UPDATE_UI_WIDGET fires once per widget and several times in a frame
    --     when a set refreshes. Every one of those asking for a full container
    --     walk is the CPU complaint all over again; the flag collapses a burst
    --     into a single pass.
    --   - our handler and the widget container's own are both plain event
    --     registrations, so the order between them is registration order.
    --     Sweeping on the spot can read the value that is ABOUT to change,
    --     and the same event will not come round again to correct it. Landing
    --     after the frame's handlers have all run removes the race.
    --
    -- Flush is created once and reused: no closure is allocated per fire, so a
    -- burst of events costs one boolean test each. Written with `function
    -- Refresh` and no `local` because it FILLS IN the forward declaration far
    -- above -- adding `local` here would create a second, different upvalue
    -- and leave the hook in Adopt calling a nil.
    local pending = false
    local function Flush()
        pending = false
        Sweep()
    end
    function Refresh()
        if pending then return end
        pending = true
        if C_Timer then C_Timer.After(0, Flush) else Flush() end
    end

    -- Seam for window packs. Discover() only walks UIParent's DIRECT children,
    -- so a widget container nested inside a window is invisible to it -- and
    -- every PlayerChoice OPTION owns one (that is where the reputation bars on
    -- the weekly cartel picker come from). The pack that knows the frame hands
    -- it over here rather than the sweep guessing at window internals.
    --
    -- Defined AFTER Refresh on purpose: a `local function` is not in scope for
    -- a closure written above it, so declaring this any earlier would capture
    -- a nil global instead of the real Refresh.
    --
    -- PUBLISHED at login and only when the feature is on. The caller in
    -- WindowPacks already tests `type(adopt) ~= "function"`, so leaving it nil
    -- is the honest way to say the system is not running.
    local function HUDWidgetAdopt(container)
        if not container or HUD.adopted[container] then return end
        HUD.adopted[container] = true
        HUD.containers[#HUD.containers + 1] = container
        Refresh()
    end

    -- ONE frame, and at load it listens for PLAYER_LOGIN and nothing else.
    --
    -- The setting is not safe to read while this file is executing.
    -- EllesmereUIDB is a saved variable of the EllesmereUI addon, not this
    -- one, so what is in it at our main-chunk time depends on that addon's
    -- load order and on whatever defaults or migrations it applies at login --
    -- which is exactly why CoverEnabled() has to treat a nil DB as "on". The
    -- window packs have the same problem and answer it the same way: the
    -- engine's boot frame waits for PLAYER_LOGIN, and a pack whose style is
    -- "off" simply never installs.
    --
    -- So the gate is at LOGIN and it gates the REGISTRATION, not the handler.
    -- With the feature off this frame is left with no events and no OnEvent
    -- script, the window-pack seam is never published, and not one cover is
    -- built. That makes the toggle reload-bound, and the options panel asks
    -- for the reload.
    local hudEv = CreateFrame("Frame")
    hudEv:RegisterEvent("PLAYER_LOGIN")
    hudEv:SetScript("OnEvent", function(self, event, unit)
        if event == "PLAYER_LOGIN" then
            if not CoverEnabled() then
                -- Inert from here on: nothing left to fire, nothing to skip.
                self:UnregisterAllEvents()
                self:SetScript("OnEvent", nil)
                return
            end
            HUD.installed = true
            self:UnregisterEvent("PLAYER_LOGIN")
            self:RegisterEvent("PLAYER_ENTERING_WORLD")
            self:RegisterEvent("NAME_PLATE_UNIT_ADDED")
            self:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
            self:RegisterEvent("UPDATE_UI_WIDGET")
            -- The full-refresh partner of UPDATE_UI_WIDGET: the container
            -- mixin registers BOTH, and re-processes every widget it owns on
            -- this one. Missing it left a whole set of bars unswept until
            -- something else happened to fire.
            self:RegisterEvent("UPDATE_ALL_UI_WIDGETS")
            EllesmereUI._HUDWidgetAdopt = HUDWidgetAdopt
            -- The options cog's write-through. Published on the same terms as
            -- the adopt seam -- at login, only with the feature on -- so with
            -- the reskin off it is nil and the cog is greyed out anyway.
            -- Re-reads the setting and books one refresh; SyncCover notices the
            -- floor moved and re-anchors every live cover.
            HUD.minPx = ReadMinPx()
            EllesmereUI._HUDWidgetSetMinSize = function()
                HUD.minPx = ReadMinPx()
                Refresh()
            end
            -- Looks redundant next to PLAYER_ENTERING_WORLD, which follows
            -- login and does the same two calls. Kept because it makes the
            -- install complete on its own: if the event order ever surprises
            -- us, the cost of being wrong here is the feature silently doing
            -- nothing until the first zone change, against one container walk
            -- per session for keeping it.
            Discover()
            Refresh()
        elseif event == "PLAYER_ENTERING_WORLD" then
            -- Retirement is per-instance: a bar that handed back secret data
            -- in a delve is fine again in the open world.
            wipe(HUD.retired)
            -- Plate-hosted widget bars are an OPEN-WORLD surface by decision
            -- (2026-08-16): inside instanced content the plate lane is fully
            -- off -- both plate events unregistered (they never enter Lua),
            -- the plate set empty (sweeps walk no plates), and unwalked plate
            -- containers never reach the set registry, so their widget events
            -- die at the foreign-set gate. The rare over-a-plate mechanic bar
            -- simply renders Blizzard-default in instances. Re-registering on
            -- the way out is complete on its own: every plate fires ADDED
            -- after the loading screen, so the set repopulates naturally.
            if IsInInstance() then
                self:UnregisterEvent("NAME_PLATE_UNIT_ADDED")
                self:UnregisterEvent("NAME_PLATE_UNIT_REMOVED")
                wipe(HUD.plates)
            else
                self:RegisterEvent("NAME_PLATE_UNIT_ADDED")
                self:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
            end
            Discover()
            Refresh()
        elseif event == "NAME_PLATE_UNIT_ADDED" then
            local plate = unit and C_NamePlate and C_NamePlate.GetNamePlateForUnit
                          and C_NamePlate.GetNamePlateForUnit(unit)
            if plate then
                HUD.plates[plate] = true
                Refresh()
            end
        elseif event == "NAME_PLATE_UNIT_REMOVED" then
            -- No refresh: the cover is a child of the bar's parent, so it
            -- leaves the screen with the plate on its own.
            local plate = unit and C_NamePlate and C_NamePlate.GetNamePlateForUnit
                          and C_NamePlate.GetNamePlateForUnit(unit)
            if plate then HUD.plates[plate] = nil end
        else
            -- UPDATE_UI_WIDGET / UPDATE_ALL_UI_WIDGETS. Discovery is NOT run
            -- from here: the first build of this system did, and that is
            -- precisely what caused the CPU complaint. Refresh is a flag test
            -- once the frame's pass is already booked.
            --
            -- Foreign-set gate: UPDATE_UI_WIDGET fires for EVERY widget
            -- update anywhere in the UI (tracker timers, scenario widgets,
            -- score frames), and most of those live in frames the sweep never
            -- walks -- each one bought a full container walk that could not
            -- find anything. The payload names its widget set, and Blizzard's
            -- own container gates on exactly this field, so an event whose
            -- set no swept container owns is skipped outright. Every doubt
            -- path (registry inexact, payload missing, unreadable or secret
            -- id) falls through to Refresh -- worst case is today's sweep.
            if event == "UPDATE_UI_WIDGET" and HUD.setIdsExact and unit ~= nil then
                local okS, sid = pcall(HUDGet, unit, "widgetSetID")
                if okS and sid ~= nil and not (_isSecretV and _isSecretV(sid))
                   and type(sid) == "number" and not HUD.setIds[sid] then
                    return
                end
            end
            Refresh()
        end
    end)

    ---------------------------------------------------------------------------
    --  Extra action button (ExtraActionButton1).
    --
    --  A SECURE action button: TEXTURES AND TEXCOORDS ONLY. Never Show, Hide,
    --  SetParent or SetPoint the button itself, and never write a field onto
    --  it -- all state goes in the external FFD table.
    --
    --  Blizzard's `style` texture is ~256px of brass ring around a 52px icon,
    --  and it is RE-ASSIGNED for every ability granted (each carries its own
    --  frame art), so the strip runs on OnShow, on UPDATE_EXTRA_ACTIONBAR, and
    --  on a short sweep after each. It CLEARS rather than alphas, because the
    --  button's flash animation drives alpha and would restore it.
    ---------------------------------------------------------------------------
    -- Detach every mask from a texture. ExtraActionButtonTemplate binds an
    -- IconMask to the icon, and a masked texture REJECTS SetTexCoord (hard
    -- error, swallowed by the pcall'd crop -- the icon stayed uncropped). Mask
    -- removal writes to the icon's own mask list, never the secure button.
    -- GetNumMaskTextures is SecretReturnsForAspect: reject before looping.
    local function Unmask(tex)
        if not tex or type(tex.GetNumMaskTextures) ~= "function" then return end
        local okN, n = pcall(tex.GetNumMaskTextures, tex)
        if not okN then return end
        if _isSecretV and n ~= nil and _isSecretV(n) then return end
        if type(n) ~= "number" or n <= 0 then return end
        for i = n, 1, -1 do
            local okM, m = pcall(tex.GetMaskTexture, tex, i)
            if okM and m then pcall(tex.RemoveMaskTexture, tex, m) end
        end
    end

    local function StripExtraAction()
        local btn = _G.ExtraActionButton1
        if not btn or btn:IsForbidden() then return end

        -- SCALE FIRST, ABOVE THE SKIN GATE. "Extra Action Button Size" is its
        -- own setting, and it used to sit below this gate -- so once the reskin
        -- defaulted OFF the slider would have silently done nothing for anyone
        -- on defaults. The two are independent settings and now behave that way.
        -- DEFAULT OFF (`== true`, not `~= false`): opt-in, by request. Nil means
        -- the user has never chosen, and that now means "leave Blizzard's
        -- button alone".
        if not (EllesmereUIDB and EllesmereUIDB.reskinExtraActionButton == true) then return end

        local d = GetFFD(btn)
        local style = btn.style
        if style then
            if style.SetAtlas then style:SetAtlas("") end
            if style.SetTexture then style:SetTexture("") end
            style:SetAlpha(0)
        end
        if btn.icon then
            -- Square the icon and stretch it corner to corner: with the brass
            -- ring gone the 52px art would otherwise float inside a ~256px
            -- frame. These are writes on the icon TEXTURE, never on the secure
            -- button. Re-asserted every pass (Blizzard re-arts the button per
            -- granted ability; a one-shot anchor gets clobbered silently).
            btn.icon:ClearAllPoints()
            btn.icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
            btn.icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
            -- Before the crop, never after: SetTexCoord on a masked texture
            -- throws, and the pcall around it would hide that it did nothing.
            Unmask(btn.icon)
            pcall(btn.icon.SetTexCoord, btn.icon, 0.08, 0.92, 0.08, 0.92)
        end
        if not d.border then
            -- 1px black edge on its own host frame above the icon, the same
            -- stacking every squared item tile uses. NOT AddBorder: its border
            -- container renders below same-level ARTWORK regions, and the icon
            -- stretched over the full button rect would hide the edge entirely.
            local W = WS()
            if W and W.QualityBorder then
                W.QualityBorder(btn, btn.icon or btn, 0, 0, 0)
                d.border = true
            end
        end
        -- Keybind and charge count are deliberately left in Blizzard's outlined
        -- number font: they sit over the icon, where the panel font is unreadable.
    end

    local eabEv = CreateFrame("Frame")
    local _eabUpdateHooked = false
    eabEv:RegisterEvent("PLAYER_LOGIN")
    eabEv:RegisterEvent("UPDATE_EXTRA_ACTIONBAR")
    eabEv:SetScript("OnEvent", function()
        -- Hook install is unconditional so a mid-session enable takes effect on
        -- the button's next show; the strip and its catch-up timers are gated
        -- here so the default-off state never allocates per event.
        local btn = _G.ExtraActionButton1
        if btn and not GetFFD(btn).showHook then
            GetFFD(btn).showHook = true
            btn:HookScript("OnShow", StripExtraAction)
        end
        -- ExtraActionBar_Update is where Blizzard re-arts the button (runs from
        -- ActionBarController's own UPDATE_EXTRA_ACTIONBAR handler); hooking it
        -- runs after it by construction instead of racing registration order.
        -- StripExtraAction gates on the setting at its head, so this costs one
        -- call per grant while off.
        if not _eabUpdateHooked and type(_G.ExtraActionBar_Update) == "function" then
            _eabUpdateHooked = true
            hooksecurefunc("ExtraActionBar_Update", StripExtraAction)
        end
        if not (EllesmereUIDB and EllesmereUIDB.reskinExtraActionButton == true) then return end
        StripExtraAction()
        if C_Timer then
            C_Timer.After(0, StripExtraAction)
            C_Timer.After(0.3, StripExtraAction)
        end
    end)

    ---------------------------------------------------------------------------
    --  Zone ability button (ZoneAbilityFrame).
    --
    --  Same secure rules as the extra action button: TEXTURES AND TEXCOORDS
    --  ONLY, no field writes onto the button. Three differences that matter:
    --   - the frame art is `.Style` (capital S, not `style`) and is driven by a
    --     per-zone TEXTURE KIT, so it is re-atlased on every ZONE CHANGE, not
    --     only when an ability is granted;
    --   - the buttons are POOLED into .SpellButtonContainer, so there can be
    --     several and they must be walked with EnumerateActive;
    --   - each button also carries a UI-Quickslot2 NORMAL texture -- a ~64px
    --     bevel around a 40px icon. Clearing .Style alone leaves that socket
    --     ring behind, which is most of the chrome in the screenshot.
    ---------------------------------------------------------------------------
    local function StripZoneAbility()
        local f = _G.ZoneAbilityFrame
        if not f or f:IsForbidden() then return end

        -- Shares the extra action button's toggle: both are granted-ability
        -- buttons and get identical treatment, so two settings was a
        -- distinction without a difference. DEFAULT OFF, by request.
        if not (EllesmereUIDB and EllesmereUIDB.reskinExtraActionButton == true) then return end

        local style = f.Style
        if style then
            if style.SetAtlas then style:SetAtlas("") end
            if style.SetTexture then style:SetTexture("") end
            style:SetAlpha(0)
        end

        local sc = f.SpellButtonContainer
        if not (sc and sc.EnumerateActive) then return end
        local okIter, iter = pcall(sc.EnumerateActive, sc)
        if not (okIter and iter) then return end
        for btn in iter do
            if btn and btn.IsForbidden and not btn:IsForbidden() then
                local d = GetFFD(btn)
                -- Both spellings: .NormalTexture is the parentKey, and
                -- GetNormalTexture() is the button's own accessor. They are
                -- normally the same object, but clearing whichever exists costs
                -- nothing and covers a template that only has one.
                local nt = btn.NormalTexture
                    or (btn.GetNormalTexture and btn:GetNormalTexture())
                if nt then
                    if nt.SetAtlas then nt:SetAtlas("") end
                    if nt.SetTexture then nt:SetTexture("") end
                    nt:SetAlpha(0)
                end
                if btn.Icon then
                    if not d.iconAnchored then
                        d.iconAnchored = true
                        btn.Icon:ClearAllPoints()
                        btn.Icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
                        btn.Icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
                    end
                    pcall(btn.Icon.SetTexCoord, btn.Icon, 0.08, 0.92, 0.08, 0.92)
                end
                if not d.border then
                    -- Same border as the extra action button, so the two
                    -- granted-ability buttons match. Guarded by d.border, which
                    -- matters here because these buttons are POOLED and this
                    -- runs per zone change.
                    local W = WS()
                    if W and W.QualityBorder then
                        W.QualityBorder(btn, btn.Icon or btn, 0, 0, 0)
                        d.border = true
                    end
                end
            end
        end
    end

    local zaEv = CreateFrame("Frame")
    zaEv:RegisterEvent("PLAYER_ENTERING_WORLD")
    -- The texture kit is per zone, so every zone crossing re-applies .Style.
    for _, e in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA",
                         "ZONE_CHANGED_INDOORS", "SPELLS_CHANGED" }) do
        pcall(zaEv.RegisterEvent, zaEv, e)
    end
    zaEv:SetScript("OnEvent", function()
        -- Same shape as the extra action button's handler: hooks install
        -- unconditionally (the strip self-gates at near-zero cost), the strip
        -- and its catch-up timers only run with the feature ON -- zone changes
        -- are frequent, and default-off must not allocate on every one.
        local f = _G.ZoneAbilityFrame
        if f and not GetFFD(f).zaHooks then
            GetFFD(f).zaHooks = true
            f:HookScript("OnShow", StripZoneAbility)
            -- The authoritative hook: this is the method that re-atlases
            -- .Style and refills the button pool.
            if type(f.UpdateDisplayedZoneAbilities) == "function" then
                hooksecurefunc(f, "UpdateDisplayedZoneAbilities", StripZoneAbility)
            end
        end
        if not (EllesmereUIDB and EllesmereUIDB.reskinExtraActionButton == true) then return end
        StripZoneAbility()
        if C_Timer then
            C_Timer.After(0, StripZoneAbility)
            C_Timer.After(0.3, StripZoneAbility)
        end
    end)
end)()
