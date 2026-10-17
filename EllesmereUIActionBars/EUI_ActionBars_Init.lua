if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ActionBars_Init.lua
--
--  OnInitialize, OnEnable and OnFirstLogin, and the slash commands.
--  Loads after EUI_ActionBars_Unlock.lua; reads ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...

local _G = _G
local ipairs, pairs, type, pcall = ipairs, pairs, type, pcall
local wipe = wipe
local InCombatLockdown = InCombatLockdown
local hooksecurefunc = hooksecurefunc
local C_Timer_After = C_Timer.After
local EFD = ns.EFD

local defaults, EAB, barButtons = ns.defaults, ns.EAB, ns.barButtons
local I = ns._internals
local BAR_CONFIG, BAR_LOOKUP = I.BAR_CONFIG, I.BAR_LOOKUP
local CaptureBlizzardDefaults = I.CaptureBlizzardDefaults
local ApplyKeyDownCVar = I.ApplyKeyDownCVar
local ApplyAll = I.ApplyAll
local RestoreBarPositions = I.RestoreBarPositions

-------------------------------------------------------------------------------
--  Initialization
-------------------------------------------------------------------------------
function EAB:OnInitialize()
    -- Detect first install BEFORE AceDB creates the saved variable.
    -- We use a dedicated flag so "Reset to Defaults" also re-captures.
    local rawDB = EllesmereUIActionBarsDB
    local isFirstInstall = not rawDB or not rawDB.profiles
        or (rawDB.profiles and not next(rawDB.profiles))

    self.db = EllesmereUI.Lite.NewDB("EllesmereUIActionBarsDB", defaults, true)

    -- Copy the main bar's Masque setting to the stance bar for older profiles.
    self.db.profile.bars.StanceBar.masqueEnabled = self.db.profile.bars.MainBar.masqueEnabled == true

    -- Expose for ApplyAnchorPosition's growth-direction edge read.
    EllesmereUI._abBarPositions = self.db.profile.barPositions

    -- Slot-export safety net: a session that ended with that addon's window
    -- open (e.g. /reload) left the real bar visibility settings swapped to
    -- "always". Restore before any bar is built so the swap can never
    -- persist. Unconditional (see EAB:SetMyslotForceShow).
    self:RestoreMyslotBackup()

    -- Mark whether we need to capture Blizzard layout on first install; the capture
    -- itself is deferred to PLAYER_ENTERING_WORLD, when Edit Mode has fully applied bar
    -- positions/sizes. Per-install flag on the SV root, not per-profile.
    local sv = self.db.sv
    self._needsCapture = not sv._capturedOnce_EAB

    -- Expose apply hook for PP scale change re-apply
    _G._EAB_RecalcFlyouts = function()
        for _, info in ipairs(BAR_CONFIG) do
            EAB:RecalcFlyoutDirection(info.key)
        end
    end

    -- MicroBar position is fully Blizzard-owned (Edit Mode). No anchor
    -- flipping needed. Stubs kept so callers don't error.
    _G._EAB_UnlockModeOpen = function() end
    _G._EAB_UnlockModeClose = function() end

    _G._EAB_ApplyKeyDown = function() ApplyKeyDownCVar() end
    _G._EAB_Apply = function()
        -- Re-point the exposed barPositions view at the active profile's table.
        -- Profile swaps replace db.profile wholesale and the unlock system reads
        -- saved growth edges / follow baselines through this reference; a stale
        -- pointer would read and write another profile's saved positions.
        if EAB.db and EAB.db.profile and EAB.db.profile.barPositions then
            EllesmereUI._abBarPositions = EAB.db.profile.barPositions
        end
        ApplyAll()
        -- Data bars: ApplyAll never lays them out, so a profile swap, an import
        -- or a spec override repaints their size, texture, text and Custom
        -- Border here (our own plain frames: safe in combat). Not in ApplyAll,
        -- which also runs at login, where creation already laid them out.
        for _, info in ipairs(ns.EXTRA_BARS) do
            if info.isDataBar then ns.ApplyDataBarLayout(info.key) end
        end
        if not InCombatLockdown() then
            RestoreBarPositions()
            -- Recalculate flyout directions now that bars are at their final
            -- positions: LayoutBar (inside ApplyAll) runs before
            -- RestoreBarPositions, so it used the default position.
            C_Timer_After(0, function()
                for _, info in ipairs(BAR_CONFIG) do
                    EAB:RecalcFlyoutDirection(info.key)
                end
            end)
        end
    end


    -- Rank (crafted quality) icons: EAB paints its own overlay per button. Blizzard's
    -- ProfessionQualityOverlayFrame is created lazily inside the secure button Update
    -- and our buttons no longer receive ACTIONBAR_SLOT_CHANGED (central dispatcher owns
    -- it), so it only ever appeared after a mouseover -- and forcing
    -- UpdateProfessionQuality() from addon code writes the lazily-created frame onto
    -- the secure button's table (tainted field on a protected frame). Self-painting
    -- from EFD avoids both: no button-table writes, no reliance on Blizzard's update
    -- timing. Their overlay stays hidden everywhere (apply pass + scan +
    -- OnShow hook) so the two renderers never double-draw. Coalesced:
    -- SLOT_CHANGED storms collapse into one deferred scan per frame.
    do
        local qf = ns.TakeShell()
        local _qPending = false
        local _rankAtlas = {}       -- quality -> atlas name (false = none found)
        local QueueQualityScan

        local function RankAtlasFor(q)
            local hit = _rankAtlas[q]
            if hit ~= nil then return hit or nil end
            local probe = C_Texture and C_Texture.GetAtlasInfo
            local names = {
                "Professions-Icon-Quality-Tier" .. q .. "-Inv-Small",
                "Professions-Icon-Quality-Tier" .. q .. "-Small",
                "Professions-Icon-Quality-Tier" .. q,
            }
            for i = 1, #names do
                if probe and probe(names[i]) then
                    _rankAtlas[q] = names[i]
                    return names[i]
                end
            end
            _rankAtlas[q] = false
            return nil
        end

        local function SetRankShown(btn, atlas)
            local fd = EFD(btn)
            if not atlas then
                if fd.rankIconTex then fd.rankIconTex:Hide() end
                return
            end
            local tex = fd.rankIconTex
            if not tex then
                -- First paint creates the holder. A new cosmetic child frame
                -- writes nothing onto the secure button's table; skip only
                -- in combat lockdown (next out-of-combat scan paints it).
                if InCombatLockdown() then return end
                local holder = CreateFrame("Frame", nil, btn)
                holder:SetAllPoints(btn)
                holder:SetFrameLevel((btn:GetFrameLevel() or 1) + 18)
                holder:EnableMouse(false)
                tex = holder:CreateTexture(nil, "OVERLAY", nil, 7)
                fd.rankIconHolder = holder
                fd.rankIconTex = tex
            end
            if fd.rankIconAtlas ~= atlas then
                fd.rankIconAtlas = atlas
                -- The atlas name comes straight from Blizzard's quality info
                -- (or the probe-verified fallback), but guard anyway: an
                -- unknown atlas must read as no-rank, not an error.
                if not pcall(tex.SetAtlas, tex, atlas, true) then
                    fd.rankIconAtlas = nil
                    tex:Hide()
                    return
                end
                if EllesmereUI._RANKDEBUG then
                    print("|cff33ff99[Rank]|r atlas", atlas)
                end
            end
            -- Mirror Blizzard's overlay anchor: its template centers an
            -- atlas-sized texture 14,-14 from the button's TOPLEFT (designed for
            -- the default 45px button, so scale with the button).
            local sc = (btn:GetWidth() or 45) / 45
            tex:ClearAllPoints()
            tex:SetPoint("CENTER", btn, "TOPLEFT", 14 * sc, -14 * sc)
            tex:SetScale(sc)
            tex:Show()
            fd.rankIconHolder:Show()
        end

        local function ScanButton(btn, featureOn)
            local rankAtlas
            if featureOn then
                local action = btn:GetAttribute("action") or 0
                if action > 0 then
                    -- Blizzard's own source, from live ActionButton.lua
                    -- UpdateProfessionQuality: a dedicated action API that
                    -- returns the overlay atlas directly. Every other
                    -- surface is dead from an action slot on live
                    -- (verified via in-game debug 2026-07-19):
                    -- C_TradeSkillUI reads off the bare itemID are nil (the
                    -- reagent one returns a flat 2 for every ranked item),
                    -- GetActionLink returns nil, and the tooltip's name
                    -- line carries no quality markup.
                    local ab = C_ActionBar
                    if ab and ab.GetProfessionQualityInfo
                       and (not ab.IsItemAction or ab.IsItemAction(action)) then
                        local qi = ab.GetProfessionQualityInfo(action)
                        rankAtlas = qi and qi.iconInventory
                    end
                    -- Older-client fallback: crafted quality by
                    -- itemID, mapped through the atlas probe.
                    if not rankAtlas and GetActionInfo then
                        local aType, aID = GetActionInfo(action)
                        if aType == "item" and aID then
                            local ts = C_TradeSkillUI
                            local q = ts and ts.GetItemCraftedQualityByItemInfo
                                and ts.GetItemCraftedQualityByItemInfo(aID)
                            if type(q) == "number" and q >= 1 and q <= 5 then
                                rankAtlas = RankAtlasFor(q)
                            end
                        end
                    end
                    if EllesmereUI._RANKDEBUG and rankAtlas ~= nil then
                        pcall(function()
                            print("|cff33ff99[Rank]|r action", action,
                                "atlas", tostring(rankAtlas))
                        end)
                    end
                end
            end
            SetRankShown(btn, rankAtlas)
            -- Blizzard's overlay must never draw over ours: it can
            -- pre-exist this fix or get shown by a hover-driven
            -- lazy creation. Hide + install the permanent OnShow
            -- hide for overlays born after the apply pass ran.
            local ov = btn.ProfessionQualityOverlayFrame
            if ov then
                if ov:IsShown() then ov:SetShown(false) end
                if not EFD(btn).qualityHooked then
                    ov:HookScript("OnShow", function(self2)
                        self2:SetShown(false)
                    end)
                    EFD(btn).qualityHooked = true
                end
            end
        end

        -- A scan covers every button (_qFull) or only the buttons showing the
        -- slots that changed: a slot event or a hover names its slot, and
        -- empowered casts re-fire slot events many times a minute.
        local _qFull, _qSlots = false, {}
        local function QualityScan()
            _qPending = false
            local full = _qFull
            _qFull = false
            local bars = EAB.db and EAB.db.profile and EAB.db.profile.bars
            if bars then
                for _, info in ipairs(BAR_CONFIG) do
                    local btns = barButtons[info.key]
                    local s = bars[info.key]
                    if btns and s then
                        local featureOn = s.showRankIcon and true or false
                        for _, btn in ipairs(btns) do
                            if full or _qSlots[btn:GetAttribute("action") or 0] then
                                ScanButton(btn, featureOn)
                            end
                        end
                    end
                end
            end
            wipe(_qSlots)
        end

        local function ArmQualityScan()
            if not _qPending then
                _qPending = true
                C_Timer_After(0, QualityScan)
            end
        end
        -- Every button: spec swaps, settings changes, the first paint.
        QueueQualityScan = function()
            _qFull = true
            ArmQualityScan()
        end
        -- One slot. Slot 0, no slot or a secret one (Blizzard's own buttons
        -- pass a secret action to the tooltip) means every slot.
        local function QueueSlotQualityScan(slot)
            if type(slot) == "number" and not issecretvalue(slot) and slot > 0 then
                _qSlots[slot] = true
            else
                _qFull = true
            end
            ArmQualityScan()
        end
        EAB._QueueRankScan = QueueQualityScan

        qf:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
        -- Loadout/spec swap changes slot CONTENTS but does not reliably fire
        -- ACTIONBAR_SLOT_CHANGED for our EABButtons (same reason the spell
        -- refresh sweep exists), so a rank icon from the old spec's item can
        -- persist on a slot the new spec leaves empty or fills with a spell.
        -- SPELLS_CHANGED covers that swap; the macro name is handled by the
        -- ForceButtonRefresh sweep on the same event.
        qf:RegisterEvent("SPELLS_CHANGED")
        qf:SetScript("OnEvent", function(_, event, slot)
            if event == "ACTIONBAR_SLOT_CHANGED" then
                QueueSlotQualityScan(slot)
            else
                QueueQualityScan()
            end
        end)
        -- A hover is what makes Blizzard lazily CREATE its overlay (and shows it in the
        -- same breath) -- and no slot event fires from hovering, so the suppression +
        -- our repaint would otherwise lag until the next slot change. Re-scan off the
        -- tooltip hook (coalesced, deferred to a clean context; same GameTooltip hook
        -- pattern as tooltip suppression). Also converges anything the hover's
        -- item-data load just made resolvable.
        if GameTooltip then
            hooksecurefunc(GameTooltip, "SetAction", function(_, slot)
                QueueSlotQualityScan(slot)
            end)
        end
        -- Initial paint (login / reload): bars applied before this block ran.
        QueueQualityScan()
    end

    SLASH_ELLESMEREACTIONBARS1 = "/eab"
    SlashCmdList["ELLESMEREACTIONBARS"] = function(msg)
        EllesmereUI:ShowModule("EllesmereUIActionBars")
    end

    SLASH_EABQUICKKEYBIND1 = "/kb"
    SlashCmdList["EABQUICKKEYBIND"] = function(msg)
        if InCombatLockdown() then return end
        if not C_AddOns.IsAddOnLoaded("Blizzard_QuickKeybind") then
            C_AddOns.LoadAddOn("Blizzard_QuickKeybind")
        end
        if QuickKeybindFrame then
            QuickKeybindFrame:Show()
        end
    end

end

function EAB:OnEnable()
    -- If this is a first install (or reset), we need to capture Blizzard's
    -- Edit Mode layout BEFORE hiding bars. The capture must run once Edit
    -- Mode has applied bar positions/sizes, i.e. at/after PLAYER_ENTERING_WORLD.
    --
    -- OnEnable itself is dispatched from the Lite enable-flush, gated on IsLoggedIn()
    -- and deferred one tick past PLAYER_LOGIN (the Edit Mode secret-taint fix). So on a
    -- fresh install the login PLAYER_ENTERING_WORLD has ALREADY fired by the time we
    -- run here -- a plain RegisterEvent would then wait for the next zone change, so
    -- OnFirstLogin (and the FinishSetup it calls) would never run this session and the
    -- bars stay built-but-invisible.
    --
    -- Since the flush guarantees we're logged in and past the login PEW (Edit Mode has
    -- applied its layout), capture now. Keep the event as a backstop for the rare case
    -- we somehow enable before login; the _needsCapture guard keeps the two paths
    -- idempotent (OnFirstLogin clears it + unregisters PEW).
    if self._needsCapture then
        self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnFirstLogin")
        if IsLoggedIn() then
            C_Timer_After(0, function()
                if self._needsCapture then self:OnFirstLogin() end
            end)
        end
    else
        self:FinishSetup()
    end
end

-- Called on PLAYER_ENTERING_WORLD for first-install only.
-- At this point Edit Mode has applied bar positions/sizes/rows.
function EAB:OnFirstLogin()
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")

    -- A profile import can stamp the capture flag mid-session (imported data
    -- is a chosen layout). Honor the stamp here so a still-pending capture
    -- never overwrites the imported profile; just run the normal setup.
    if self.db.sv._capturedOnce_EAB then
        self._needsCapture = false
        self:FinishSetup()
        return
    end

    -- Capture Blizzard layout while bars are still visible
    local captured = CaptureBlizzardDefaults()
    for barKey, data in pairs(captured) do
        local s = self.db.profile.bars[barKey]
        if s and data then
            if data.numIcons then s.overrideNumIcons = data.numIcons end
            if data.numRows then s.overrideNumRows = data.numRows end
            if data.orientation then s.orientation = data.orientation end
            if data.blizzIconScale then
                -- Convert Blizzard's icon scale to explicit button dimensions.
                -- barBaseSize isn't populated yet (SetupBar runs later), so
                -- read the base size directly from the first Blizzard button.
                local info = BAR_LOOKUP[barKey]
                local baseW, baseH = 45, 45
                if info and info.blizzBtnPrefix then
                    local btn1 = _G[info.blizzBtnPrefix .. "1"]
                    if btn1 then
                        baseW = math.floor((btn1:GetWidth() or 45) + 0.5)
                        baseH = math.floor((btn1:GetHeight() or 45) + 0.5)
                    end
                end
                s.buttonWidth = math.floor(baseW * data.blizzIconScale + 0.5)
                s.buttonHeight = math.floor(baseH * data.blizzIconScale + 0.5)
            end
            if data.alwaysShowButtons ~= nil then
                s.alwaysShowButtons = data.alwaysShowButtons
            end
            -- Visibility: 3=Hidden, 1=InCombat, 2=OutOfCombat, 0=Always
            -- Keep barVisibility and boolean flags in sync so the
            -- options dropdown reflects the actual state.
            if data.visibility then
                if data.visibility == 3 then
                    EAB.VisibilityCompat.ApplyMode(s, "never")
                elseif data.visibility == 1 then
                    EAB.VisibilityCompat.ApplyMode(s, "in_combat")
                elseif data.visibility == 2 then
                    EAB.VisibilityCompat.ApplyMode(s, "out_of_combat")
                else
                    EAB.VisibilityCompat.ApplyMode(s, "always")
                end
            end
            if data.point then
                self.db.profile.barPositions[barKey] = {
                    point = data.point, relPoint = data.relPoint,
                    x = data.x, y = data.y,
                }
            end
        end
    end

    -- Action Bar 1's end caps go to the outer ends of a row of bars Blizzard
    -- placed directly beside it (WoW Forever: the micro menu and bags).
    do
        local p = self.db.profile
        p.endCapSpanLeft, p.endCapSpanRight = ns.AB_CaptureCapSpan(captured)
    end

    -- WoW Forever keeps Blizzard's XP / reputation bars (useBlizzardDataBars),
    -- which Edit Mode stacks right above action bar 1 and restacks as they come
    -- and go (a watched reputation, max level). The bars it stacks above them
    -- (2, 3, stance, pet; a hidden stance or pet bar at the slot it would
    -- take) were captured over the stack as it stood, so they are lifted by
    -- the steps its hidden containers would add (Edit Mode's
    -- UpdateBottomActionBarPositions: the secondary container height - 1, the
    -- main one height + 4), and a status bar that shows later never covers
    -- them. Only while the containers and the bar sit where Edit Mode puts them.
    if EllesmereUI.IS_FOREVER and self.db.profile.useBlizzardDataBars then
        local mainC, secC = _G.MainStatusTrackingBarContainer, _G.SecondaryStatusTrackingBarContainer
        local function AtDefault(f)
            if not f.IsInDefaultPosition then return true end
            local ok, v = pcall(f.IsInDefaultPosition, f)
            return not ok or v ~= false
        end
        if mainC and secC and AtDefault(mainC) and AtDefault(secC) then
            local lift = 0
            if not secC:IsShown() then lift = lift + (secC:GetHeight() or 0) - 1 end
            if not mainC:IsShown() then lift = lift + (mainC:GetHeight() or 0) + 4 end
            if lift > 0 then
                local STACKED = { MultiBarBottomLeft = true, MultiBarBottomRight = true,
                                  StanceBar = true, PetActionBar = true }
                local uiS = UIParent:GetEffectiveScale()
                for _, info in ipairs(BAR_CONFIG) do
                    local pos = self.db.profile.barPositions[info.key]
                    local bf = STACKED[info.blizzFrame] and _G[info.blizzFrame]
                    local cap = captured[info.key]
                    if pos and pos.y and bf and AtDefault(bf)
                        and (bf:IsShown() or (cap and cap.stackSlot)) then
                        pos.y = pos.y + lift * bf:GetEffectiveScale() / uiS
                    end
                end
            end
        end
    end

    -- Mark capture as done so we never read Edit Mode again (per-install flag)
    self.db.sv._capturedOnce_EAB = true
    self._needsCapture = false

    -- The stance and pet bars start at "Always": each shows and hides itself
    -- with its forms or its pet, so the Hidden captured while it had none (a
    -- new character, no pet out) must not stick. Through ApplyMode, since
    -- barVisibility wins over the legacy booleans.
    for _, key in ipairs({ "StanceBar", "PetBar" }) do
        local s = self.db.profile.bars[key]
        if s then EAB.VisibilityCompat.ApplyMode(s, "always") end
    end

    -- Now proceed with normal setup
    self:FinishSetup()
end
