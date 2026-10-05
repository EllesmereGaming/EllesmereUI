if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_UnitFrames_Init.lua
--
--  InitializeFrames, published as I.InitializeFrames for EnableBody
--  (EUI_UnitFrames_Lifecycle.lua), which calls it once: spawns the unit frames,
--  takes over the Blizzard ones and builds the visibility pass. Reads the main
--  file and EUI_UnitFrames_Visibility.lua through ns and ns._internals; db is
--  set through I.dbSetters.
-------------------------------------------------------------------------------
local _, ns = ...

local issecretvalue = issecretvalue
local PP = EllesmereUI.PP
local CLASS_FULL_COORDS = EllesmereUI.CLASS_ICON_SPRITE_COORDS

local I = ns._internals
local frames, GetSettingsForUnit, UnsnapTex, SetFSFont = I.frames, I.GetSettingsForUnit, I.UnsnapTex, I.SetFSFont
local ApplyFramePosition, ReloadFrames, ApplyBlizzCastbarState = I.ApplyFramePosition, I.ReloadFrames, I.ApplyBlizzCastbarState
local ApplyAbsorbStyle, ApplyClassColor, ApplyDetachedPortraitShape =
    I.ApplyAbsorbStyle, I.ApplyClassColor, I.ApplyDetachedPortraitShape
local CreateCustomClassPower, DestroyCustomClassPower, IsKickCastbarUnit =
    I.CreateCustomClassPower, I.DestroyCustomClassPower, I.IsKickCastbarUnit
local StyleFullFrame, StyleFocusFrame, StyleSimpleFrame, StyleBossFrame =
    I.StyleFullFrame, I.StyleFocusFrame, I.StyleSimpleFrame, I.StyleBossFrame
local UnitFrame_OnEnter, UnitFrame_OnLeave = I.UnitFrame_OnEnter, I.UnitFrame_OnLeave
local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end

local function InitializeFrames()
    -- Sync EUI global power colors into oUF at init
    EllesmereUI.ApplyColorsToOUF()

    local classPowerStyle = db.profile.player.classPowerStyle or "none"
    -- Forever has no Blizzard class resource bar to adopt (see the ComboFrame
    -- note below) and the options page greys that entry out there: a stored
    -- "blizzard" builds as the modern style (ns.UF_ForeverCPStyle), and the
    -- options page shows and gates it as Modern. Read-side only: the stored
    -- style is never rewritten, so a spec override or an import that carries
    -- it keeps it. The Forever defaults themselves (modern, shown, above, 16)
    -- are IS_FOREVER conditionals in DEFAULTS.player; nothing is seeded or
    -- migrated here. Under the WoW Forever style that entry is the combo
    -- point arc on our target frame (ns.UF_ApplyForeverComboArc) and stands.
    if ns.UF_ForeverCPStyle then classPowerStyle = ns.UF_ForeverCPStyle(classPowerStyle) end
    -- Per-unit frame source, resolved once for this build. When a unit is set to
    -- "blizzard" (leave Blizzard's default frame) or "hidden", the EllesmereUI frame is
    -- not spawned at all -- the ONLY way to keep Blizzard's own frame alive, since
    -- oUF:Spawn() permanently disables it.
    local playerFrameSource = ns.GetUnitFrameSource("player")
    -- Per-class Blizzard class power bar frame names
    local BLIZZARD_CP_FRAMES = {
        DEATHKNIGHT = "RuneFrame",
        DRUID       = "DruidComboPointBarFrame",
        EVOKER      = "EssencePlayerFrame",
        MAGE        = "MageArcaneChargesFrame",
        MONK        = "MonkHarmonyBarFrame",
        PALADIN     = "PaladinPowerBarFrame",
        ROGUE       = "RogueComboPointBarFrame",
        WARLOCK     = "WarlockPowerFrame",
    }
    -- External state for Blizzard class power bars (never write onto
    -- Blizzard frames -- see CLAUDE.md _FFD rule).
    local _blizzCPState = {}  -- { origParent, hooked }
    local savedClassPowerBar = nil
    -- Only take over the Blizzard class power bar when the EUI player frame is
    -- actually being spawned; otherwise leave it to Blizzard's player frame.
    if classPowerStyle == "blizzard" and playerFrameSource == "eui" then
        local _, classFile = UnitClass("player")
        local frameName = BLIZZARD_CP_FRAMES[classFile]
        local cpFrame = frameName and _G[frameName]
        if cpFrame then
            savedClassPowerBar = cpFrame
            -- A Blizzard parent only: another owner's frame (Resource Bars' Blizzard
            -- Class Resource Art host) must never become the hand-back target.
            local cur = cpFrame:GetParent()
            _blizzCPState.origParent = (cur == cpFrame.layoutParent or cur == PlayerFrame) and cur
                or (cpFrame.layoutParent or PlayerFrame)
            cpFrame:SetParent(UIParent)
        end
    end

    local enabled = db.profile.enabledFrames

    local function SetupUnitMenu(frame, unit)
        -- Register ALL mouse buttons (matches raid/party's "AnyUp"), not just
        -- left/right. These frames bind nothing to middle/thumb themselves, so
        -- an unbound middle/thumb click still does nothing here -- but Blizzard's
        -- built-in click-casting (and Clique) sets its own type3/type4/type5
        -- attributes on frames registered in ClickCastFrames, and needs the
        -- click event to actually be delivered to fire. Left-button-only
        -- registration silently ate those clicks whenever EUI's own click-cast
        -- engine wasn't the one driving RegisterForClicks (i.e. EUI's engine
        -- disabled, native/Clique click-casting relied on instead).
        frame:RegisterForClicks("AnyUp")
        -- 12.0.7 gates SecureUnitButton's togglemenu; route right-click securely
        -- through a SecureActionButton proxy so the menu (and its protected items
        -- like Set Focus) work without taint.
        if EllesmereUI.AttachSecureUnitMenu then
            EllesmereUI.AttachSecureUnitMenu(frame)
        else
            frame:SetAttribute("*type2", "togglemenu")
        end
        frame:HookScript("OnEnter", UnitFrame_OnEnter)
        frame:HookScript("OnLeave", UnitFrame_OnLeave)
        -- Expose to click-casting via the standard global table. EUI unit frames
        -- replace the Blizzard ones, which the click-cast engine registers by name --
        -- but those are hidden, so the engine never reaches the visible frames.
        -- Registering ours here lets click-casting (EUI's engine when "All Unit
        -- Frames" is on, or Clique otherwise) apply the same bindings + unbound-click
        -- suppression it uses on raid/party. The engine captures/restores each
        -- frame's native click attrs, so these keep their own defaults (no forced
        -- left-click target) when click-cast is off.
        if type(ClickCastFrames) ~= "table" then ClickCastFrames = {} end
        ClickCastFrames[frame] = true
        -- NO ping mixin here, deliberately (three field rounds, 2026-08-24):
        -- an addon-installed PingableType mixin CANNOT serve secret-content
        -- units. Reading our tainted GetIsPingable inside PingManager's
        -- securecalled helper taints that execution, every unit value
        -- Blizzard's own mixin then fetches comes back tainted-restricted,
        -- and the secure caller's securecopy of the GetTargetInfo table
        -- hard-errors ("inaccessible secret") -- even with our getter
        -- returning nil. The reported enemy-target-frame ping error also
        -- reproduces with NO EUI receiver in the path (pre-mixin trace, No
        -- Lua Taint) and is upstream. Do not re-attempt.
    end

    -- Spawn each unit's EllesmereUI frame only when its source is "eui". A unit set to
    -- "blizzard" keeps Blizzard's own frame (we never spawn or suppress for it);
    -- "hidden" removes Blizzard's frame too.
    if playerFrameSource == "eui" then
        -- Spawning enables the Castbar element, which silences Blizzard's
        -- player/pet cast bars. Keep whatever a standalone cast bar addon set.
        EllesmereUI.CaptureBlizzCastBarEvents()
        frames.player = ns.Engine.SpawnUnitFrame("player", "EllesmereUIUnitFrames_Player")
        StyleFullFrame(frames.player, "player")
        ns.UF_AttachEngineFrame(frames.player, "player")
        EllesmereUI.RestoreBlizzCastBarEvents()
    elseif playerFrameSource == "hidden" then
        -- Wrapped for the same reason as the spawn above: the suppression
        -- unregisters PlayerFrame's cast bar child, and an unregister seen
        -- outside a capture window reads as a third-party addon claiming the
        -- frame -- EUI would mark its own silence as somebody else's and
        -- never hand the bar back.
        EllesmereUI.CaptureBlizzCastBarEvents()
        ns.Engine.HideBlizzardUnitFrame("player")
        EllesmereUI.RestoreBlizzCastBarEvents()
    end

    -- Visibility wrapper for the player frame only. Parent the player frame to a
    -- non-secure wrapper and drive visibility via the wrapper's alpha instead of the
    -- frame's own: alpha inherits multiplicatively down the parent chain, so the
    -- wrapper's alpha wins regardless of anything touching the inner frame's alpha
    -- directly (oUF elements, combat transitions, etc.). Target/focus/pet don't need
    -- this since RegisterUnitWatch already handles their visibility via unit
    -- existence. The wrapper is inserted between the player frame and whatever parent
    -- oUF originally gave it (PetBattleFrameHider), so the pet-battle state driver
    -- chain continues to work.
    if frames.player then
    local origParent = frames.player:GetParent() or UIParent
    local playerVisWrap = CreateFrame("Frame", nil, origParent)
    playerVisWrap:SetAllPoints(origParent)
    playerVisWrap:SetFrameStrata(frames.player:GetFrameStrata())
    frames.player:SetParent(playerVisWrap)
    frames.player._visWrap = playerVisWrap

    ApplyFramePosition(frames.player, "player")
    SetupUnitMenu(frames.player, "player")

    if enabled.player == false then
        frames.player:Hide()
        frames.player:SetAttribute("unit", nil)
    end
    end

    -- (Combat indicator overlay moved below the target/focus spawns -- the
    -- target frame does not exist yet at this point in the setup.)

    -- Rested indicator ("ZZZ") on player health bar top-left
    do
        local pf = frames.player
        if pf and pf.Health then
            if not pf._restHolder then
                pf._restHolder = CreateFrame("Frame", nil, pf.Health)
                local restText = pf._restHolder:CreateFontString(nil, "OVERLAY")
                SetFSFont(restText, 9)
                restText:SetTextColor(1, 1, 1)
                restText:SetText("ZZZ")
                restText:Hide()
                pf._restIndicator = restText

                pf._restEventFrame = CreateFrame("Frame", nil, pf)
                pf._restEventFrame:RegisterEvent("PLAYER_UPDATE_RESTING")
                pf._restEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
                pf._restEventFrame:SetScript("OnEvent", function()
                    local enabled = EllesmereUIDB and EllesmereUIDB.showRestedIndicator == true
                    if enabled and IsResting() then
                        pf._restIndicator:Show()
                    else
                        pf._restIndicator:Hide()
                    end
                end)
            end
            pf._restHolder:SetAllPoints(pf.Health)
            pf._restHolder:SetFrameLevel(pf.Health:GetFrameLevel() + 5)
            pf._restIndicator:ClearAllPoints()
            local rxOff = (EllesmereUIDB and EllesmereUIDB.restedIndicatorXOffset) or 0
            local ryOff = (EllesmereUIDB and EllesmereUIDB.restedIndicatorYOffset) or 0
            pf._restIndicator:SetPoint("TOPLEFT", pf.Health, "TOPLEFT", 3 + rxOff, -2 + ryOff)

            local restEnabled = EllesmereUIDB and EllesmereUIDB.showRestedIndicator == true
            if restEnabled and IsResting() then pf._restIndicator:Show() else pf._restIndicator:Hide() end
        end
    end


    -- Castbar state is managed by ApplyBlizzCastbarState (called here and also
    -- from ReloadFrames so toggling the setting works without a /reload).
    ApplyBlizzCastbarState()

    -- Re-apply after zone changes and after Edit Mode closes, both of which
    -- can cause Blizzard to reparent or re-hide the cast bar.
    if not frames._cbSuppressFrame then
        frames._cbSuppressFrame = CreateFrame("Frame")
        frames._cbSuppressFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        frames._cbSuppressFrame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
        frames._cbSuppressFrame:SetScript("OnEvent", function()
            -- Deferred: EDIT_MODE_LAYOUTS_UPDATED dispatches from inside Edit Mode's own
            -- operations; applying suppression state there writes cast bar state
            -- mid-pass (same taint mechanism as the DisableBlizzard override above).
            C_Timer.After(0, ApplyBlizzCastbarState)
        end)
        -- Edit Mode exit reparents the cast bar back into its layout frame
        -- (which gets hidden), so re-apply our state when the panel closes.
        if EditModeManagerFrame and not EllesmereUI._GetFFD(EditModeManagerFrame).castbarHooked then
            EllesmereUI._GetFFD(EditModeManagerFrame).castbarHooked = true
            hooksecurefunc(EditModeManagerFrame, "Hide", function()
                C_Timer.After(0, ApplyBlizzCastbarState)
            end)
        end
    end

    -- Resize frame and portrait to account for class power pips above health bar
    local function ResizeFrameForClassPower(cpAboveH)
        local frame = frames.player
        if not frame then return end
        -- A stock style's kit owns the frame size, the portrait and the health
        -- offsets (ns.UF_ApplyBlizzardLayout). In combat this would park the
        -- EllesmereUI size for regen with no stock pass after it.
        if ns.UF_Blizz() then return end
        local settings = GetSettingsForUnit("player")
        local ppPos = settings.powerPosition or "below"
        local ppIsAtt = (ppPos == "below" or ppPos == "above")
        local ppExtra = ppIsAtt and settings.powerHeight or 0
        local baseH = settings.healthHeight + ppExtra
        local btbPos2 = settings.btbPosition or "bottom"
        local btbIsAtt = (btbPos2 == "top" or btbPos2 == "bottom")
        local btbExtra = (settings.bottomTextBar and btbIsAtt) and (settings.bottomTextBarHeight or 16) or 0
        local totalH = baseH + cpAboveH + btbExtra

        local pStyle = settings.portraitStyle or db.profile.portraitStyle or "attached"
        local showPortrait = pStyle ~= "none" and settings.showPortrait ~= false
        local isAttached = pStyle == "attached"
        local pSizeAdj = settings.portraitSize or 0
        if not isAttached then pSizeAdj = pSizeAdj + 10 end
        local adjPortraitH = baseH + cpAboveH + pSizeAdj
        if adjPortraitH < 8 then adjPortraitH = 8 end

        local pSide = settings.portraitSide or "left"
        local effectiveSide = pSide
        if isAttached and pSide == "top" then effectiveSide = "left" end

        local totalWidth
        local portraitW = 0
        if not showPortrait then
            totalWidth = settings.frameWidth
        elseif isAttached then
            totalWidth = adjPortraitH + settings.frameWidth
            portraitW = adjPortraitH
        else
            totalWidth = settings.frameWidth
        end

        if not InCombatLockdown() then
            PP.Size(frame, totalWidth, totalH)
        else
            frame._pendingSize = { totalWidth, totalH }
            ns.CombatQueue.Defer("PlayerClassPowerSize", function()
                if frame._pendingSize and not InCombatLockdown() then
                    PP.Size(frame, frame._pendingSize[1], frame._pendingSize[2])
                end
                frame._pendingSize = nil
            end)
        end

        -- Update health bar xOffset when portrait width changes
        if frame.Health then
            local newXOff = (showPortrait and isAttached and effectiveSide == "left") and portraitW or 0
            local newRightInset = (showPortrait and isAttached and effectiveSide == "right") and portraitW or 0
            frame.Health._xOffset = newXOff
            frame.Health._rightInset = newRightInset
        end

        if frame.Portrait and frame.Portrait.backdrop and showPortrait and not frame.Portrait.backdrop._isInside then
            PP.Size(frame.Portrait.backdrop, adjPortraitH, adjPortraitH)
            frame.Portrait.backdrop:ClearAllPoints()
            if isAttached then
                if effectiveSide == "left" then
                    PP.Point(frame.Portrait.backdrop, "TOPLEFT", frame, "TOPLEFT", 0, 0)
                else
                    PP.Point(frame.Portrait.backdrop, "TOPRIGHT", frame, "TOPRIGHT", 0, 0)
                end
            end
            if frame.Portrait.backdrop._2d then
                UnsnapTex(frame.Portrait.backdrop._2d)
            end
            if frame:IsElementEnabled("Portrait") and frame.Portrait.ForceUpdate then
                frame.Portrait:ForceUpdate()
            end
        end
    end

    -- The expected parent for the Blizzard class power bar after positioning, set by
    -- PositionClassPowerBar so the SetParent hook knows what's correct. MUST be
    -- declared before PositionClassPowerBar, or the function assigns a global while
    -- the hook reads this always-nil local (falling back to frames.player even for
    -- UIParent-parented bars).
    local _cpExpectedParent = nil

    local function PositionClassPowerBar(bar)
        if not bar or not frames.player then return end
        bar:ClearAllPoints()
        -- Stock styles: the health bar keeps the kit's spot (the stock pass
        -- places it, and skips in combat), so only the pips move here.
        local stock = ns.UF_Blizz()
        local style = db.profile.player.classPowerStyle or "none"
        if ns.UF_ForeverCPStyle then style = ns.UF_ForeverCPStyle(style) end
        local position = db.profile.player.classPowerPosition or "top"
        local offsetX = db.profile.player.classPowerBarX or 0
        local offsetY = db.profile.player.classPowerBarY or 0

        -- Stop castbar watcher by default; only re-enabled in the "bottom" branch
        if bar._castbarWatcher then
            ns._cpWatchFn = nil
            ns._cpWatchTick.Stop()
            bar._castbarWatcher:Hide()
        end

        if style == "modern" and position == "above" then
            -- Above health bar, inside the frame -- pips stretch to fill health bar width
            -- Bottom of pips flush with top of health bar, top of pips flush with top of border
            _cpExpectedParent = frames.player
            bar:SetParent(frames.player)
            local anchorFrame = frames.player.Health
            local pipH = bar._pipH or 3
            -- Resize frame/portrait BEFORE anchoring health bar so _xOffset is correct
            ResizeFrameForClassPower(pipH)
            local btbOff = 0
            local btbPos2 = db.profile.player.btbPosition or "bottom"
            if btbPos2 == "top" and db.profile.player.bottomTextBar then
                btbOff = db.profile.player.bottomTextBarHeight or 16
            end
            local cpPush = pipH + btbOff
            if not stock then
                anchorFrame:ClearAllPoints()
                anchorFrame:SetPoint("TOPLEFT", frames.player, "TOPLEFT", anchorFrame._xOffset or 0, PP.Scale(-cpPush))
                anchorFrame:SetPoint("RIGHT", frames.player, "RIGHT", -(anchorFrame._rightInset or 0), 0)
            end
            PP.Point(bar, "BOTTOMLEFT", anchorFrame, "TOPLEFT", 0, 0)
            PP.Point(bar, "BOTTOMRIGHT", anchorFrame, "TOPRIGHT", 0, 0)
            local fw = db.profile.player.frameWidth or 181
            if bar._repositionForWidth then
                bar._repositionForWidth(fw)
            end
            -- Show 1px bottom border matching frame border color
            if bar._bottomBdrFrame then
                local bdrC = db.profile.player.borderColor or { r = 0, g = 0, b = 0 }
                bar._bottomBdr:SetColorTexture(bdrC.r, bdrC.g, bdrC.b, 1)
                bar._bottomBdrFrame:Show()
            end
            if ns.UF_Blizz() then ns.UF_ApplyBlizzardLayout(frames.player, "player") end
        elseif style == "modern" and position == "top" then
            -- "top" floats above the frame (like "bottom" floats below) -- does NOT become part of the frame
            _cpExpectedParent = frames.player
            bar:SetParent(frames.player)
            ResizeFrameForClassPower(0)
            -- Reset health bar to normal position
            if frames.player.Health and not stock then
                local btbOff = 0
                local btbPos2 = db.profile.player.btbPosition or "bottom"
                if btbPos2 == "top" and db.profile.player.bottomTextBar then
                    btbOff = db.profile.player.bottomTextBarHeight or 16
                end
                frames.player.Health:ClearAllPoints()
                frames.player.Health:SetPoint("TOPLEFT", frames.player, "TOPLEFT", frames.player.Health._xOffset or 0, PP.Scale(-btbOff))
                frames.player.Health:SetPoint("RIGHT", frames.player, "RIGHT", -(frames.player.Health._rightInset or 0), 0)
            end
            -- Center on health bar (ignores portrait)
            PP.Point(bar, "BOTTOM", frames.player.Health, "TOP", offsetX, offsetY)
            if bar._bottomBdrFrame then bar._bottomBdrFrame:Hide() end
            if ns.UF_Blizz() then ns.UF_ApplyBlizzardLayout(frames.player, "player") end
        elseif not db.profile.player.lockClassPowerToFrame then
            -- Reset health bar to normal position
            if frames.player.Health and not stock then
                local btbOff = 0
                local btbPos2 = db.profile.player.btbPosition or "bottom"
                if btbPos2 == "top" and db.profile.player.bottomTextBar then
                    btbOff = db.profile.player.bottomTextBarHeight or 16
                end
                frames.player.Health:ClearAllPoints()
                frames.player.Health:SetPoint("TOPLEFT", frames.player, "TOPLEFT", frames.player.Health._xOffset or 0, PP.Scale(-btbOff))
                frames.player.Health:SetPoint("RIGHT", frames.player, "RIGHT", -(frames.player.Health._rightInset or 0), 0)
            end
            _cpExpectedParent = UIParent
            bar:SetParent(UIParent)
            local pos = db.profile.positions.classPower
            if pos then
                PP.Point(bar, pos.point, UIParent, pos.point, pos.x, pos.y)
            else
                PP.Point(bar, "CENTER", UIParent, "CENTER", 0, -220)
            end
            ResizeFrameForClassPower(0)
            if bar._bottomBdrFrame then bar._bottomBdrFrame:Hide() end
            if ns.UF_Blizz() then ns.UF_ApplyBlizzardLayout(frames.player, "player") end
        else
            -- Reset health bar to normal position
            if frames.player.Health and not stock then
                local btbOff = 0
                local btbPos2 = db.profile.player.btbPosition or "bottom"
                if btbPos2 == "top" and db.profile.player.bottomTextBar then
                    btbOff = db.profile.player.bottomTextBarHeight or 16
                end
                frames.player.Health:ClearAllPoints()
                frames.player.Health:SetPoint("TOPLEFT", frames.player, "TOPLEFT", frames.player.Health._xOffset or 0, PP.Scale(-btbOff))
                frames.player.Health:SetPoint("RIGHT", frames.player, "RIGHT", -(frames.player.Health._rightInset or 0), 0)
            end
            -- "bottom" position -- flush with bottom of frame; shifts below castbar when visible (unless user set Y offset)
            _cpExpectedParent = frames.player
            bar:SetParent(frames.player)
            if bar._bottomBdrFrame then bar._bottomBdrFrame:Hide() end
            local function AnchorBottom()
                bar:ClearAllPoints()
                local baseY = -1 + offsetY
                if offsetY == 0 then
                    local castbarBg = frames.player.Castbar and frames.player.Castbar:GetParent()
                    local castVisible = castbarBg and castbarBg:IsShown() and db.profile.player.showPlayerCastbar
                    if castVisible then
                        local ch = castbarBg:GetHeight()
                        -- Secret while the holder rides the Blizzard Style aura block.
                        if issecretvalue(ch) then ch = db.profile.player.playerCastbarHeight or 14 end
                        baseY = -1 - ch
                    end
                end
                PP.Point(bar, "TOP", frames.player, "BOTTOM", offsetX, baseY)
            end
            AnchorBottom()
            -- Stock styles: the stock pass re-seats the kit.
            if ns.UF_Blizz() then ns.UF_ApplyBlizzardLayout(frames.player, "player") end
            -- Only run the castbar watcher if the player castbar is enabled
            if db.profile.player.showPlayerCastbar then
                if not bar._castbarWatcher then
                    -- Shared child-born shell (see ns._cpCastWatcher): a frame created
                    -- here would be born in whatever context triggered this rebuild and
                    -- could bill the parent for the 10 Hz poll below.
                    bar._castbarWatcher = ns._cpCastWatcher
                    bar._castbarWatcher:SetParent(bar)
                end
                local playerFrame = frames.player
                -- 10 Hz body on the shared anim ticker (see ns._cpWatchTick).
                ns._cpWatchFn = function()
                    local cb = playerFrame and playerFrame.Castbar
                    local castbarBg = cb and cb:GetParent()
                    local nowVis = castbarBg and castbarBg:IsShown() and db.profile.player.showPlayerCastbar
                    if nowVis ~= bar._lastCastVis then
                        bar._lastCastVis = nowVis
                        AnchorBottom()
                    end
                end
                bar._castbarWatcher:Show()
                ns._cpWatchTick.Start()
            end
            ResizeFrameForClassPower(0)
        end
        bar:SetFrameStrata(frames.player:GetFrameStrata())
        bar:SetFrameLevel(frames.player:GetFrameLevel() + 5)
        bar:Show()
    end

    -- Hook Blizzard class power bar so form/spec changes can't steal it back. Hooks
    -- SetParent to re-assert our parent, Show/Hide to keep it visible, and
    -- ClearAllPoints to catch anchors getting stripped without a reparent (seen
    -- during in-engine cutscenes/UI transitions -- parent and IsShown() stay
    -- correct, but GetNumPoints() drops to 0 and the frame renders nowhere).
    -- Only active while classPowerStyle == "blizzard".
    local _blizzCPHooked = false
    local _blizzCPActive = false  -- true while we own the bar

    local function HookBlizzardClassPower(cpFrame)
        if _blizzCPHooked then return end
        _blizzCPHooked = true
        local _cpSetParentGuard = false
        -- All hooks defer their re-assert work: they can fire inside Blizzard's
        -- secure Edit Mode layout pass (same taint mechanism as the DisableBlizzard
        -- override above), and wait for the manager to close before re-asserting.
        local _cpReassertQueued = false
        local ReassertClassPower
        ReassertClassPower = function(self)
            _cpReassertQueued = false
            if not _blizzCPActive then return end
            if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
                _cpReassertQueued = true
                C_Timer.After(0.25, function() ReassertClassPower(self) end)
                return
            end
            local wanted = _cpExpectedParent or frames.player or UIParent
            if self:GetParent() ~= wanted or (self:GetNumPoints() or 0) == 0 then
                _cpSetParentGuard = true
                PositionClassPowerBar(self)
                -- Blizzard may have re-stolen during PositionClassPowerBar.
                -- The anchor is already correct, so just fix the parent directly.
                if self:GetParent() ~= wanted then
                    self:SetParent(wanted)
                end
                _cpSetParentGuard = false
            end
            if not self:IsShown() and not InCombatLockdown() then self:Show() end
        end
        -- Re-assert position when Blizzard reparents (form/spec changes).
        hooksecurefunc(cpFrame, "SetParent", function(self, newParent)
            if not _blizzCPActive or _cpSetParentGuard or _cpReassertQueued then return end
            local wanted = _cpExpectedParent or frames.player or UIParent
            if newParent ~= wanted then
                _cpReassertQueued = true
                C_Timer.After(0, function() ReassertClassPower(self) end)
            end
        end)
        hooksecurefunc(cpFrame, "Hide", function(self)
            if not _blizzCPActive or _cpReassertQueued then return end
            _cpReassertQueued = true
            C_Timer.After(0, function() ReassertClassPower(self) end)
        end)
        -- Re-assert anchors when something strips them without a reparent (the
        -- cutscene case above). Guarded by _cpSetParentGuard the same way as
        -- SetParent so our own PositionClassPowerBar's internal ClearAllPoints
        -- doesn't recurse back into itself.
        hooksecurefunc(cpFrame, "ClearAllPoints", function(self)
            if not _blizzCPActive or _cpSetParentGuard or _cpReassertQueued then return end
            _cpReassertQueued = true
            C_Timer.After(0, function() ReassertClassPower(self) end)
        end)
    end

    -- Seed the built-style marker so the first reload does not mistake a nil
    -- marker for a change. Written ONLY at build sites (here and the toggle):
    -- PositionClassPowerBar is repositioning, called by ReassertClassPower from
    -- Blizzard's SetParent/Hide hooks with no rebuild behind it, and stamping
    -- there would suppress the rebuild this exists to trigger. frames.player
    -- guard matches _toggleClassPower.
    if frames.player then frames._classPowerBuiltStyle = classPowerStyle end
    if classPowerStyle ~= "none" and frames.player then
        if classPowerStyle == "blizzard" then
            if savedClassPowerBar then
                _blizzCPActive = true
                -- Runtime ownership mirrored on ns for Resource Bars (ns.UF_OwnsBlizzClassPower).
                ns._ufBlizzCPHeld = true
                savedClassPowerBar.ignoreFramePositionManager = true
                HookBlizzardClassPower(savedClassPowerBar)
                PositionClassPowerBar(savedClassPowerBar)
                frames._classPowerBar = savedClassPowerBar
            end
        else
            -- Modern custom style
            DestroyCustomClassPower()
            local custom = CreateCustomClassPower(frames.player, classPowerStyle)
            if custom then
                frames._customClassPower = custom
                frames._classPowerBar = custom
                PositionClassPowerBar(custom)
                if ns._WCUF_Sync then ns._WCUF_Sync(custom) end
            else
                -- Spec has no class resource: reset frame sizing
                ResizeFrameForClassPower(0)
            end
        end
    end

    -- Live toggle for class power bar (no reload needed)
    -- Called with the style string: "none", "modern", or "blizzard"
    frames._toggleClassPower = function(style)
        -- Class power is a player-frame feature; if the player is on Blizzard's
        -- default frame (or hidden), there is no EUI frame to attach it to.
        if not frames.player then return end
        style = style or db.profile.player.classPowerStyle or "none"
        -- What is actually BUILT right now. Read by the reload pass below to
        -- notice a style that changed through a path which never calls this
        -- function (see the reload hook).
        -- Resource Bars' Blizzard Class Resource Art defers to this style for
        -- Blizzard's class resource frame; it re-judges when the built style
        -- crosses "blizzard" (below) instead of waiting for its next rebuild.
        local wasBlizz = frames._classPowerBuiltStyle == "blizzard"
        frames._classPowerBuiltStyle = style
        -- Keep showClassPowerBar in sync with style
        db.profile.player.showClassPowerBar = (style ~= "none")
        db.profile.player.classPowerStyle = style
        -- WoW Forever: the saved style stays as given; its effective style
        -- (ns.UF_ForeverCPStyle) is what builds and what the marker records.
        if ns.UF_ForeverCPStyle then
            style = ns.UF_ForeverCPStyle(style)
            frames._classPowerBuiltStyle = style
        end
        -- WoW Forever: the "Blizzard" entry is the combo point arc on the
        -- target frame (returns at once everywhere else).
        ns.UF_ApplyForeverComboArc()

        -- Clean up existing
        _blizzCPActive = false
        ns._ufBlizzCPHeld = false
        if frames._customClassPower then
            DestroyCustomClassPower()
            frames._classPowerBar = nil
        elseif frames._classPowerBar then
            -- Handed on to Resource Bars' Blizzard Class Resource Art: left shown, so
            -- it appears there at once (Blizzard only re-shows it from its own Setup).
            if not (style ~= "blizzard" and _G._ERB_BlizzArtWanted and _G._ERB_BlizzArtWanted()) then
                frames._classPowerBar:Hide()
            end
            frames._classPowerBar:ClearAllPoints()
            frames._classPowerBar.ignoreFramePositionManager = nil
            local origParent = _blizzCPState.origParent or PlayerFrame or UIParent
            frames._classPowerBar:SetParent(origParent)
            frames._classPowerBar = nil
        end
        -- Handed Blizzard's class resource frame back: Resource Bars' Blizzard
        -- Class Resource Art (if on) claims it now rather than at its next rebuild.
        if wasBlizz and style ~= "blizzard" and _G._ERB_BlizzArtWanted and _G._ERB_BlizzArtWanted()
           and _G._ERB_Apply then
            _G._ERB_Apply()
        end

        if style == "none" then
            -- Reset health bar to normal position (a stock style's kit owns it)
            if frames.player and frames.player.Health and not ns.UF_Blizz() then
                local btbOff = 0
                local btbPos2 = db.profile.player.btbPosition or "bottom"
                if btbPos2 == "top" and db.profile.player.bottomTextBar then
                    btbOff = db.profile.player.bottomTextBarHeight or 16
                end
                frames.player.Health:ClearAllPoints()
                frames.player.Health:SetPoint("TOPLEFT", frames.player, "TOPLEFT", frames.player.Health._xOffset or 0, PP.Scale(-btbOff))
                frames.player.Health:SetPoint("RIGHT", frames.player, "RIGHT", -(frames.player.Health._rightInset or 0), 0)
            end
            ResizeFrameForClassPower(0)
            return
        end

        if style == "blizzard" then
            local _, classFile = UnitClass("player")
            local frameName = BLIZZARD_CP_FRAMES[classFile]
            local cpFrame = frameName and _G[frameName]
            if cpFrame then
                -- A Blizzard parent only (see the login takeover above).
                local cur = cpFrame:GetParent()
                _blizzCPState.origParent = (cur == cpFrame.layoutParent or cur == PlayerFrame) and cur
                    or (cpFrame.layoutParent or PlayerFrame)
                _blizzCPActive = true
                ns._ufBlizzCPHeld = true
                cpFrame.ignoreFramePositionManager = true
                HookBlizzardClassPower(cpFrame)
                cpFrame:SetParent(UIParent)
                frames._classPowerBar = cpFrame
            end
            if frames._classPowerBar and frames.player then
                PositionClassPowerBar(frames._classPowerBar)
            end
            -- Took Blizzard's class resource frame: Resource Bars' Blizzard Class
            -- Resource Art stands down now rather than at its next rebuild.
            if not wasBlizz and _G._ERB_BlizzArtHeld and _G._ERB_BlizzArtHeld() and _G._ERB_Apply then
                _G._ERB_Apply()
            end
        else
            -- Modern
            local custom = CreateCustomClassPower(frames.player, style)
            if custom then
                frames._customClassPower = custom
                frames._classPowerBar = custom
                PositionClassPowerBar(custom)
                if ns._WCUF_Sync then ns._WCUF_Sync(custom) end
            else
                -- Spec has no class resource: reset frame sizing
                ResizeFrameForClassPower(0)
            end
        end
    end

    -- Persistent spec-change watcher for class power rebuild.
    -- Lives outside the class power container so it survives DestroyCustomClassPower.
    local cpSpecWatcher = CreateFrame("Frame")
    local cpSpecInitDone = false
    -- WoW Forever keys the class resource by class alone (ClassPowerEntry), so
    -- a spec event there can never change the bar: no teardown on it.
    if EllesmereUI.IS_FOREVER ~= true then
        cpSpecWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
        cpSpecWatcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    end
    cpSpecWatcher:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_ENTERING_WORLD" then
            cpSpecInitDone = true
            cpSpecWatcher:UnregisterEvent("PLAYER_ENTERING_WORLD")
            return
        end
        if unit ~= "player" then return end
        if not cpSpecInitDone then return end
        DestroyCustomClassPower()
        if frames._classPowerBar then
            frames._classPowerBar.ignoreFramePositionManager = nil
        end
        frames._classPowerBar = nil
        C_Timer.After(0.1, function()
            if ns.ReloadFrames then ns.ReloadFrames() end
            if frames._toggleClassPower then
                frames._toggleClassPower()
            end
        end)
    end)

    -- Durably suppress a live Blizzard child frame (target-of-target/focus-target).
    -- These are PROTECTED CHILDREN of TargetFrame/FocusFrame: when the parent uses
    -- Blizzard's source it stays alive and re-drives the child (TargetOfTargetMixin:
    -- Update) on every target change, undoing a one-shot Hide. We unregister its
    -- events and re-hide on OnShow.
    --
    -- KNOWN LIMITATION (in-combat double frame): the child is protected, so Hide() is
    -- blocked in combat. If the player changes target mid-combat, Blizzard (secure)
    -- re-Shows the native child and our OnShow re-hide can't fire until
    -- PLAYER_REGEN_ENABLED -- so with the parent on Blizzard Default and this mini
    -- frame on EllesmereUI/Hidden, the native child stays visible for the WHOLE combat
    -- (not just a flash), sitting alongside the EllesmereUI frame (or showing despite
    -- "Hidden"). Not fixable without reparenting/overriding a secure frame in combat,
    -- so it's surfaced in the mini-frame "Frame Source" tooltip (BuildFoTToTOptions),
    -- which recommends matching the parent's source instead of mixing them.
    local _suppressedChildren, _rehidePending
    local function RehideSuppressedChildren()
        if InCombatLockdown() then return end
        for f in pairs(_suppressedChildren) do f:Hide() end
    end
    -- Deferred re-hide: OnShow fires inside whatever secure execution showed the parent
    -- (target swaps, Edit Mode's preview pass on a Blizzard-source TargetFrame/
    -- FocusFrame); hiding inline there taints the rest of that execution (same
    -- mechanism as the DisableBlizzard override above). While Edit Mode is open the
    -- re-hide waits for it to close.
    local _DeferredRehide
    _DeferredRehide = function(frame)
        _rehidePending[frame] = nil
        if not frame:IsShown() then return end
        if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
            _rehidePending[frame] = true
            C_Timer.After(0.25, function() _DeferredRehide(frame) end)
        elseif InCombatLockdown() then
            ns.CombatQueue.Defer("SuppressedChildRehide", RehideSuppressedChildren)
        else
            frame:Hide()
        end
    end
    local function SuppressBlizzardChildFrame(frame)
        if not frame then return end
        frame:UnregisterAllEvents()
        if not InCombatLockdown() then frame:Hide() end
        _suppressedChildren = _suppressedChildren or {}
        _rehidePending = _rehidePending or {}
        if not _suppressedChildren[frame] then
            _suppressedChildren[frame] = true
            frame:HookScript("OnShow", function(self)
                if not _rehidePending[self] then
                    _rehidePending[self] = true
                    C_Timer.After(0, function() _DeferredRehide(self) end)
                end
            end)
        end
    end

    local targetFrameSource = ns.GetUnitFrameSource("target")
    if targetFrameSource == "eui" then
        frames.target = ns.Engine.SpawnUnitFrame("target", "EllesmereUIUnitFrames_Target")
        StyleFullFrame(frames.target, "target")
        ns.UF_AttachEngineFrame(frames.target, "target")
        ApplyFramePosition(frames.target, "target")
        SetupUnitMenu(frames.target, "target")
    elseif targetFrameSource == "hidden" then
        ns.Engine.HideBlizzardUnitFrame("target")
    end

    -- Forever combo points belong to the target, and Blizzard draws them with the
    -- classic ComboFrame: parented to UIParent but only anchored to TargetFrame,
    -- so replacing that frame strands the art at a dead anchor instead of hiding
    -- it, and ComboFrame_Update re-anchors it there on every change, so it
    -- cannot be re-homed onto ours either. No BLIZZARD_CP_FRAMES global exists
    -- here, so the takeover above never reaches it. Our pips are the display: the
    -- classic frame goes to the hidden parent the way TargetFrame itself does,
    -- events unregistered, so it costs nothing. It is left alone only where
    -- Blizzard's own target frame is kept AND the class resource is off, the one
    -- case in which nothing else draws combo points (or the WoW Forever style's
    -- "Blizzard" class resource asks for exactly that arc, which Blizzard's own
    -- target frame then keeps). The hidden parent is pinned for the session,
    -- like every frame HandleFrame takes.
    if EllesmereUI.IS_FOREVER == true and _G.ComboFrame
       and (targetFrameSource ~= "blizzard"
            or (classPowerStyle ~= "none" and classPowerStyle ~= "blizzard")) then
        ns.UF_HideBlizzardFrame(_G.ComboFrame)
    end

    local focusFrameSource = ns.GetUnitFrameSource("focus")
    if focusFrameSource == "eui" then
        frames.focus = ns.Engine.SpawnUnitFrame("focus", "EllesmereUIUnitFrames_Focus")
        StyleFocusFrame(frames.focus, "focus")
        ns.UF_AttachEngineFrame(frames.focus, "focus")
        ApplyFramePosition(frames.focus, "focus")
        SetupUnitMenu(frames.focus, "focus")
    elseif focusFrameSource == "hidden" then
        ns.Engine.HideBlizzardUnitFrame("focus")
    end

    -- Combat indicator overlay on the player + target frames. Each shows its OWN
    -- unit's combat state: player via the exact regen events, target via UNIT_FLAGS
    -- (combat flag changes) + PLAYER_TARGET_CHANGED re-evaluation. Target defaults to
    -- "none" (opt-in); player keeps its legacy default. Must run after the target
    -- frame is spawned (right above).
    for _, ciDef in ipairs({
        { unit = "player", defStyle = "standard" },
        { unit = "target", defStyle = "none" },
    }) do
        local pf = frames[ciDef.unit]
        if pf then
        local ciUnit = ciDef.unit
        local ciDefStyle = ciDef.defStyle
        local ps = db.profile[ciUnit]
        local COMBAT_MEDIA = "Interface\\AddOns\\EllesmereUI\\media\\combat\\"

        -- Create holder + texture ONCE, reuse on subsequent calls
        if not pf._combatHolder then
            pf._combatHolder = CreateFrame("Frame", nil, pf)
            pf._combatHolder:SetAllPoints(pf)
            pf._combatIndicator = pf._combatHolder:CreateTexture(nil, "OVERLAY", nil, 7)
            pf._combatIndicator:Hide()
        end
        pf._combatHolder:SetFrameLevel(pf:GetFrameLevel() + 20)
        local combat = pf._combatIndicator

        -- Helper: resolve which texture file + coords to use
        local function ApplyCombatTexture()
            local style = ps.combatIndicatorStyle or ciDefStyle
            if style == "none" then combat:Hide(); return end

            local colorMode = ps.combatIndicatorColor or "custom"
            local sz = ps.combatIndicatorSize or 22
            local ox = ps.combatIndicatorX or 0
            local oy = ps.combatIndicatorY or 0
            local pos = ps.combatIndicatorPosition or "healthbar"

            combat:SetSize(sz, sz)
            combat:ClearAllPoints()

            -- "healthbar" is the stored value shown as "Center" in the dropdown;
            -- "center" is a render alias for it.
            if pos == "portrait" and pf.Portrait then
                combat:SetPoint("CENTER", pf.Portrait, "CENTER", ox, oy)
            elseif pos == "textbar" then
                combat:SetPoint("CENTER", pf._btb or pf, "CENTER", ox, oy)
            elseif pos == "healthbar" or pos == "center" then
                combat:SetPoint("CENTER", pf.Health or pf, "CENTER", ox, oy)
            else
                local anchor =
                    (pos == "topright"    and "TOPRIGHT")    or
                    (pos == "bottomleft"  and "BOTTOMLEFT")  or
                    (pos == "bottomright" and "BOTTOMRIGHT") or
                    "TOPLEFT"
                combat:SetPoint(anchor, pf.Health or pf, anchor, ox, oy)
            end

            -- Determine texture file (always use -custom / white base).
            -- Class theming resolves the FRAME's unit (player class on the
            -- player frame, current target's class on the target frame).
            local _, classToken = UnitClass(ciUnit)
            if issecretvalue(classToken) then classToken = nil end
            -- All custom combat icons (Arcade/Dungeoneer/Classic/Cross/Circle/Square =
            -- combat0..5) are shown exactly as authored: no class theming, no tint, no
            -- desaturation. Standard/Class Theme below are tinted by the colour mode.
            if style:find("^combat%d") then
                combat:SetTexture(COMBAT_MEDIA .. style .. ".tga")
                combat:SetTexCoord(0, 1, 0, 1)
                if combat.SetDesaturated then combat:SetDesaturated(false) end
                combat:SetVertexColor(1, 1, 1, 1)
            else
                if style == "class" then
                    combat:SetTexture(COMBAT_MEDIA .. "combat-indicator-class-custom.png")
                    local coords = classToken and CLASS_FULL_COORDS[classToken]
                    if coords then
                        combat:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
                    else
                        combat:SetTexCoord(0, 1, 0, 1)
                    end
                else
                    combat:SetTexture(COMBAT_MEDIA .. "combat-indicator-custom.png")
                    combat:SetTexCoord(0, 1, 0, 1)
                end

                -- Apply color tint
                if colorMode == "classcolor" then
                    local cc = (classToken and EllesmereUI.GetClassColor(classToken)) or { r = 1, g = 1, b = 1 }
                    combat:SetVertexColor(cc.r, cc.g, cc.b, 1)
                elseif colorMode == "custom" then
                    local cc = ps.combatIndicatorCustomColor or { r = 1, g = 1, b = 1 }
                    combat:SetVertexColor(cc.r, cc.g, cc.b, 1)
                else
                    combat:SetVertexColor(1, 1, 1, 1)
                end
            end
        end
        pf._applyCombatTexture = ApplyCombatTexture

        -- Event frame for combat state changes (reuse existing)
        if not pf._combatEventFrame then
            pf._combatEventFrame = CreateFrame("Frame", nil, pf)
            if ciUnit == "player" then
                pf._combatEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
                pf._combatEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            else
                -- UNIT_FLAGS fires on the unit's combat flag flips; target
                -- change re-evaluates for the new unit.
                pf._combatEventFrame:RegisterUnitEvent("UNIT_FLAGS", ciUnit)
                pf._combatEventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
            end
        end
        local combatFrame = pf._combatEventFrame
        combatFrame:SetScript("OnEvent", function()
            local style = ps.combatIndicatorStyle or ciDefStyle
            if style ~= "none" and UnitAffectingCombat(ciUnit) then
                ApplyCombatTexture()
                combat:Show()
            else
                combat:Hide()
            end
        end)

        -- Set correct initial state
        local style = ps.combatIndicatorStyle or ciDefStyle
        if style ~= "none" and UnitAffectingCombat(ciUnit) then
            ApplyCombatTexture()
            combat:Show()
        end
        end
    end

    -- Leader indicator (crown when unit is group/raid leader). oUF doesn't attach
    -- LeaderIndicator dynamically after Spawn(), so we drive the texture ourselves: own
    -- events, own UnitIsGroupLeader check, own show/hide. Must run after the target
    -- frame is spawned (above) so the texture can be parented to it.
    do
        local _leaderUnits = {}

        local function _leaderRefresh(uf)
            local s = uf and uf._leaderSettings
            if not (uf and uf._leaderIndicator and s) then return end
            local tex = uf._leaderIndicator
            if s.leaderIndicatorEnabled == false then tex:Hide(); return end
            -- The oUF unit token can still be unassigned when the setup-time
            -- refresh runs (login/reload timing), and the API rejects a nil
            -- unit outright. Hide and stand down: the leader/roster/target
            -- events below re-run this refresh once the unit exists.
            local unit = uf._euiUnit
            if not unit or (issecretvalue and issecretvalue(unit)) then tex:Hide(); return end
            local isLeader = UnitIsGroupLeader(unit)
            local isAssist = UnitIsGroupAssistant(unit)
            -- Icon Style: Blizzard's crown/assistant art or the Pixels pair.
            local art = ns.UF_LEADER_ART[s.leaderIndicatorStyle] or ns.UF_LEADER_ART.blizzard
            -- Secrecy check MUST run before any truthiness test: boolean-testing
            -- a secret errors, so "value and not issecretvalue(value)" crashes.
            if not issecretvalue(isLeader) and isLeader then
                tex:SetTexture(art.leader)
                tex:Show()
            elseif not issecretvalue(isAssist) and isAssist then
                tex:SetTexture(art.assist)
                tex:Show()
            else
                tex:Hide()
            end
        end

        local function _setupLeaderIndicator(uf, settings)
            if not (uf and uf.Health and settings) then return end
            if not uf._leaderIndicator then
                -- Parent to the health-bar text overlay (same frame level as the
                -- health text) on a higher OVERLAY sublevel than the text strings
                -- (which are sublevel 0), so the crown draws just above the text
                -- instead of beneath it. Falls back to the frame if the text
                -- overlay isn't present.
                local leaderParent = uf._textOverlay or uf
                local leaderTex = leaderParent:CreateTexture(nil, "OVERLAY", nil, 7)
                leaderTex:Hide()
                uf._leaderIndicator = leaderTex
                _leaderUnits[#_leaderUnits + 1] = uf
            end
            uf._leaderSettings = settings

            local function ApplyLeaderIndicator()
                local sz  = settings.leaderIndicatorSize or 16
                local pos = settings.leaderIndicatorPosition or "topleft"
                local ox  = settings.leaderIndicatorX or 0
                local oy  = settings.leaderIndicatorY or 0
                local leader = uf._leaderIndicator
                leader:SetSize(sz, sz)
                leader:ClearAllPoints()
                if pos == "portrait" and uf.Portrait and uf.Portrait.backdrop then
                    leader:SetPoint("CENTER", uf.Portrait.backdrop, "CENTER", ox, oy)
                else
                    local anchor =
                        (pos == "topright"    and "TOPRIGHT")    or
                        (pos == "bottomleft"  and "BOTTOMLEFT")  or
                        (pos == "bottomright" and "BOTTOMRIGHT") or
                        "TOPLEFT"
                    leader:SetPoint(anchor, uf.Health or uf, anchor, ox, oy)
                end
                _leaderRefresh(uf)
            end
            uf._applyLeaderIndicator = ApplyLeaderIndicator
            ApplyLeaderIndicator()
        end

        _setupLeaderIndicator(frames.player, db.profile.player)
        _setupLeaderIndicator(frames.target, db.profile.target)

        if #_leaderUnits > 0 then
            local leaderEvents = CreateFrame("Frame")
            leaderEvents:RegisterEvent("PARTY_LEADER_CHANGED")
            leaderEvents:RegisterEvent("GROUP_ROSTER_UPDATE")
            leaderEvents:RegisterEvent("PLAYER_TARGET_CHANGED")
            leaderEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
            leaderEvents:SetScript("OnEvent", function()
                for i = 1, #_leaderUnits do _leaderRefresh(_leaderUnits[i]) end
            end)
        end
    end

    -- Elite/Rare indicator (classification badge on the target frame), driven like the
    -- leader indicator above: own events, own refresh, own show/hide. Atlas mapping
    -- matches the nameplates classification badges exactly, so the two features read
    -- as one system. Show in Instances (default off) keeps it quiet in dungeons/raids, where most enemies are elite.
    -- A "wingless" style reads as off here: the Portrait Dragon draws that
    -- one (ns.UF_DragonLegacy).
    do
        local function _eliteAtlas(c)
            if c == "elite" or c == "worldboss" then
                return "nameplates-icon-elite-gold"
            elseif c == "rareelite" then
                return "nameplates-icon-elite-silver"
            elseif c == "rare" then
                return "nameplates-icon-rareelite"
            end
        end

        local _eliteFrames = {}
        local eliteEvents

        local function _eliteRefresh(uf)
            local s = uf and uf._eliteSettings
            if not (uf and uf._eliteIndicator and s) then return end
            local tex = uf._eliteIndicator
            -- Dragon texture: exists only once its style was first used.
            local dragon = uf._eliteDragon
            if s.eliteIndicatorEnabled ~= true or ns.UF_DragonLegacy(s)
                or (not s.eliteIndicatorShowInInstances and IsInInstance()) then
                tex:Hide()
                if dragon then dragon:Hide() end
                return
            end
            local c = UnitClassification(uf._euiUnit)
            if uf._eliteDragonOn then
                -- Classification art, or the Player art on a player target;
                -- both probes are secrecy-checked before any use.
                tex:Hide()
                local file = (not issecretvalue(c)) and ns.UF_ELITE_DRAGON_ART[c] or nil
                if not file then
                    local isPlayer = UnitIsPlayer(uf._euiUnit)
                    if not issecretvalue(isPlayer) and isPlayer then file = ns.UF_ELITE_DRAGON_ART.player end
                end
                if file then
                    dragon:SetTexture(file)
                    dragon:Show()
                else
                    dragon:Hide()
                end
                return
            end
            if dragon then dragon:Hide() end
            -- Secrecy check MUST run before any comparison, same rule as the
            -- leader checks above.
            local atlas = (not issecretvalue(c)) and _eliteAtlas(c) or nil
            if atlas then
                tex:SetAtlas(atlas)
                tex:Show()
            else
                tex:Hide()
            end
        end

        -- Events are registered only while the feature is enabled somewhere
        -- (zero cost while off) and re-armed from every settings apply.
        local function _eliteArmEvents()
            local on = false
            for i = 1, #_eliteFrames do
                local s = _eliteFrames[i]._eliteSettings
                if s and s.eliteIndicatorEnabled == true and not ns.UF_DragonLegacy(s) then on = true; break end
            end
            if on then
                if not eliteEvents then
                    eliteEvents = CreateFrame("Frame")
                    eliteEvents:SetScript("OnEvent", function()
                        for i = 1, #_eliteFrames do _eliteRefresh(_eliteFrames[i]) end
                    end)
                end
                eliteEvents:RegisterEvent("PLAYER_TARGET_CHANGED")
                eliteEvents:RegisterUnitEvent("UNIT_CLASSIFICATION_CHANGED", "target")
                eliteEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
            elseif eliteEvents then
                eliteEvents:UnregisterAllEvents()
            end
        end

        local function _setupEliteIndicator(uf, settings)
            if not (uf and uf.Health and settings) then return end
            if not uf._eliteIndicator then
                -- Same parent and layer choice as the leader crown above.
                local par = uf._textOverlay or uf
                local tex = par:CreateTexture(nil, "OVERLAY", nil, 7)
                tex:Hide()
                uf._eliteIndicator = tex
                _eliteFrames[#_eliteFrames + 1] = uf
            end
            uf._eliteSettings = settings

            local function ApplyEliteIndicator()
                local sz  = settings.eliteIndicatorSize or 16
                local pos = settings.eliteIndicatorPosition or "topleft"
                local ox  = settings.eliteIndicatorX or 0
                local oy  = settings.eliteIndicatorY or 0
                local tex = uf._eliteIndicator
                tex:SetSize(sz, sz)
                tex:ClearAllPoints()
                if pos == "portrait" and uf.Portrait and uf.Portrait.backdrop then
                    tex:SetPoint("CENTER", uf.Portrait.backdrop, "CENTER", ox, oy)
                else
                    local anchor =
                        (pos == "topright"    and "TOPRIGHT")    or
                        (pos == "bottomleft"  and "BOTTOMLEFT")  or
                        (pos == "bottomright" and "BOTTOMRIGHT") or
                        "TOPLEFT"
                    tex:SetPoint(anchor, uf.Health or uf, anchor, ox, oy)
                end
                -- Style "pixelsDragon": its own texture on a holder one level
                -- above the portrait backdrop (under the text layer), centred on
                -- and sized from the portrait. Needs a shown portrait; without
                -- one, and under a stock style, the badge above stands in.
                -- Built on first use.
                local bd = uf.Portrait and uf.Portrait.backdrop
                local onPortrait = settings.eliteIndicatorEnabled == true and not ns.UF_Blizz()
                    and bd and bd:IsShown()
                local useDragon = onPortrait and settings.eliteIndicatorStyle == "pixelsDragon"
                if useDragon then
                    local holder = uf._eliteDragonHolder
                    if not holder then
                        holder = CreateFrame("Frame", nil, bd)
                        holder:SetAllPoints(bd)
                        uf._eliteDragonHolder = holder
                    end
                    ns.UF_LiftDragonHolder(holder, bd)
                    local dragon = uf._eliteDragon
                    if not dragon then
                        dragon = holder:CreateTexture(nil, "OVERLAY")
                        dragon:SetPoint("CENTER", bd, "CENTER", 0, 0)
                        dragon:Hide()
                        uf._eliteDragon = dragon
                    end
                    local d = bd:GetHeight() * ns.UF_ELITE_DRAGON_SCALE
                    dragon:SetSize(d, d)
                end
                uf._eliteDragonOn = useDragon and true or false
                _eliteArmEvents()
                _eliteRefresh(uf)
            end
            uf._applyEliteIndicator = ApplyEliteIndicator
            ApplyEliteIndicator()
        end

        _setupEliteIndicator(frames.target, db.profile.target)
    end

    -- Portrait Dragon (Player Frame Dragon, Elite Enemy Dragon): nothing is
    -- built, and no event registered, while every frame's is off.
    ns.UF_ApplyPortraitDragons()

    -- Faction indicator (Horde/Alliance badge on the target and player frames), driven
    -- like the elite badge above. Mode "always" shows any Horde/Alliance unit;
    -- "opposite" (target) only one whose faction differs from the player's. Faction
    -- NPCs count unless Players Only is on. Neutral units and unreadable (secret)
    -- factions show nothing. PvP flag: "dim" greys the badge on unflagged units,
    -- "only" hides it on them (Blizzard's own rule; the player frame's default, which
    -- makes it a PvP-flagged indicator there), "ignore" draws both alike.
    -- UNIT_FACTION also fires on PvP flag changes. Art: the Icon Style setting, drawn
    -- by EllesmereUI.SetFactionArt (shared with the nameplates).
    do
        local _factionFrames = {}
        local factionEvents

        local function _factionRefresh(uf)
            local s = uf and uf._factionSettings
            if not (uf and uf._factionIndicator and s) then return end
            local tex = uf._factionIndicator
            local mode = s.factionIndicatorMode or "off"
            -- The frame's base unit, not its live token: the player frame swaps to
            -- "vehicle" on a ride, but this badge (like Blizzard's PvP icon) and
            -- the UNIT_FACTION registration below are about the player.
            local unit = uf._euiBaseUnit
            if mode == "off" or not unit or issecretvalue(unit) or not UnitExists(unit) then
                tex:Hide(); return
            end
            if s.factionIndicatorPlayersOnly then
                local isPlayer = UnitIsPlayer(unit)
                if issecretvalue(isPlayer) or not isPlayer then tex:Hide(); return end
            end
            -- Secrecy check MUST run before the lookup and comparisons, same rule
            -- as the leader checks above.
            local fac = UnitFactionGroup(unit)
            local atlas = (not issecretvalue(fac)) and (fac == "Horde" or fac == "Alliance")
            -- Mercenary mode: the player fights for the other faction, so the
            -- player's own badge shows that side (as Blizzard's player frame
            -- does) and "opposite" compares against it.
            if atlas and unit == "player" and UnitIsMercenary("player") then
                fac = (fac == "Horde") and "Alliance" or "Horde"
            end
            if atlas and mode == "opposite" and unit ~= "player" then
                local mine = UnitFactionGroup("player")
                if issecretvalue(mine) then
                    atlas = nil
                else
                    if UnitIsMercenary("player") then
                        if mine == "Horde" then mine = "Alliance" elseif mine == "Alliance" then mine = "Horde" end
                    end
                    if mine == fac then atlas = nil end
                end
            end
            local dim = false
            if atlas then
                local pvpMode = s.factionIndicatorPvP or "dim"
                if pvpMode ~= "ignore" then
                    -- Unreadable counts as flagged: never hide or grey on a guess.
                    local pvp = UnitIsPVP(unit)
                    local unflagged = not issecretvalue(pvp) and not pvp
                    if unflagged and pvpMode == "only" then atlas = nil end
                    dim = unflagged and pvpMode == "dim"
                end
            end
            if atlas then
                -- Paint only on a real change: faction, style and dim are the
                -- paint's only inputs (the texture is ours, so the memo lives on it).
                local style = s.factionIndicatorStyle or "pvp"
                if tex._facFac ~= fac or tex._facStyle ~= style or tex._facDim ~= dim then
                    tex._facFac, tex._facStyle, tex._facDim = fac, style, dim
                    EllesmereUI.SetFactionArt(tex, style, fac)
                    tex:SetDesaturated(dim)
                    tex:SetAlpha(dim and 0.6 or 1)
                end
                tex:Show()
            else
                tex:Hide()
            end
        end

        -- Events are registered only while the feature is on somewhere (zero cost
        -- while off) and re-armed from every settings apply.
        local function _factionArmEvents()
            local on, targetOn = false, false
            for i = 1, #_factionFrames do
                local uf = _factionFrames[i]
                local s = uf._factionSettings
                if s and (s.factionIndicatorMode or "off") ~= "off" then
                    on = true
                    if uf._euiBaseUnit == "target" then targetOn = true end
                end
            end
            if on then
                if not factionEvents then
                    factionEvents = CreateFrame("Frame")
                    -- Routed by event: a target change or a target flip touches only
                    -- the target badge; the player's own flip and a world load touch
                    -- both (Opposite compares against the player's faction).
                    factionEvents:SetScript("OnEvent", function(_, event, unit)
                        local all = event == "PLAYER_ENTERING_WORLD" or unit == "player"
                        for i = 1, #_factionFrames do
                            local uf = _factionFrames[i]
                            if all or uf._euiBaseUnit == "target" then _factionRefresh(uf) end
                        end
                    end)
                end
                if targetOn then
                    factionEvents:RegisterEvent("PLAYER_TARGET_CHANGED")
                else
                    factionEvents:UnregisterEvent("PLAYER_TARGET_CHANGED")
                end
                -- The target's flips only matter while its badge is on.
                if targetOn then
                    factionEvents:RegisterUnitEvent("UNIT_FACTION", "target", "player")
                else
                    factionEvents:RegisterUnitEvent("UNIT_FACTION", "player")
                end
                factionEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
            elseif factionEvents then
                factionEvents:UnregisterAllEvents()
            end
        end

        local function _setupFactionIndicator(uf, settings)
            if not (uf and uf.Health and settings) then return end
            if not uf._factionIndicator then
                -- Same parent and layer choice as the leader crown above.
                local par = uf._textOverlay or uf
                local tex = par:CreateTexture(nil, "OVERLAY", nil, 7)
                tex:Hide()
                uf._factionIndicator = tex
                _factionFrames[#_factionFrames + 1] = uf
            end
            uf._factionSettings = settings

            local function ApplyFactionIndicator()
                -- Re-read by unit key: a profile switch (RepointAllDBs) swaps
                -- db.profile, so the table captured at setup would go stale.
                settings = db.profile[uf._euiBaseUnit] or settings
                uf._factionSettings = settings
                local sz  = settings.factionIndicatorSize or 18
                local pos = settings.factionIndicatorPosition or "topright"
                local ox  = settings.factionIndicatorX or 0
                local oy  = settings.factionIndicatorY or 0
                local tex = uf._factionIndicator
                tex:SetSize(sz, sz)
                tex:ClearAllPoints()
                -- Same visibility rule as the frame layout (Blizzard/Classic Style
                -- always carries its portrait): never centre on a hidden backdrop.
                local pStyle = settings.portraitStyle or db.profile.portraitStyle or "attached"
                local portraitOn = ns.UF_Blizz() or (pStyle ~= "none" and settings.showPortrait ~= false)
                if pos == "portrait" and portraitOn and uf.Portrait and uf.Portrait.backdrop then
                    tex:SetPoint("CENTER", uf.Portrait.backdrop, "CENTER", ox, oy)
                else
                    local anchor =
                        (pos == "topleft"     and "TOPLEFT")     or
                        (pos == "bottomleft"  and "BOTTOMLEFT")  or
                        (pos == "bottomright" and "BOTTOMRIGHT") or
                        "TOPRIGHT"
                    -- Corners of the whole frame (portrait included), so "Top Left"
                    -- is the frame's top-left whichever side the portrait is on.
                    tex:SetPoint(anchor, uf, anchor, ox, oy)
                end
                _factionArmEvents()
                _factionRefresh(uf)
            end
            uf._applyFactionIndicator = ApplyFactionIndicator
            ApplyFactionIndicator()
        end

        _setupFactionIndicator(frames.player, db.profile.player)
        _setupFactionIndicator(frames.target, db.profile.target)
    end

    local petFrameSource = ns.GetUnitFrameSource("pet")
    if petFrameSource == "eui" then
        frames.pet = ns.Engine.SpawnUnitFrame("pet", "EllesmereUIUnitFrames_Pet")
        StyleSimpleFrame(frames.pet, "pet")
        ns.UF_AttachEngineFrame(frames.pet, "pet")
        ApplyFramePosition(frames.pet, "pet")
        SetupUnitMenu(frames.pet, "pet")
    elseif petFrameSource == "hidden" then
        ns.Engine.HideBlizzardUnitFrame("pet")
    end

    local totFrameSource = ns.GetUnitFrameSource("targettarget")
    if totFrameSource == "eui" then
        frames.targettarget = ns.Engine.SpawnUnitFrame("targettarget", "EllesmereUIUnitFrames_TargetTarget")
        StyleSimpleFrame(frames.targettarget, "targettarget")
        ns.UF_AttachEngineFrame(frames.targettarget, "targettarget", true)
        ApplyFramePosition(frames.targettarget, "targettarget")
        SetupUnitMenu(frames.targettarget, "targettarget")
    end
    -- Blizzard's target-of-target is a child of TargetFrame. When the target frame
    -- itself is EUI or hidden, TargetFrame is already disabled so the child is gone
    -- with it. Only needs suppressing when the target uses Blizzard's live frame but
    -- the user does NOT want Blizzard's ToT (EUI or hidden) -- else both would show.
    if totFrameSource ~= "blizzard" and targetFrameSource == "blizzard" then
        SuppressBlizzardChildFrame(TargetFrame and TargetFrame.totFrame)
    end

    local ftFrameSource = ns.GetUnitFrameSource("focustarget")
    if ftFrameSource == "eui" then
        frames.focustarget = ns.Engine.SpawnUnitFrame("focustarget", "EllesmereUIUnitFrames_FocusTarget")
        StyleSimpleFrame(frames.focustarget, "focustarget")
        ns.UF_AttachEngineFrame(frames.focustarget, "focustarget", true)
        ApplyFramePosition(frames.focustarget, "focustarget")
        SetupUnitMenu(frames.focustarget, "focustarget")
    end
    -- Same as target-of-target: FocusFrame's native focus-target is a child of
    -- FocusFrame, so it only needs suppressing when focus uses Blizzard's live frame
    -- and the user does not want the native focus-target.
    if ftFrameSource ~= "blizzard" and focusFrameSource == "blizzard" then
        SuppressBlizzardChildFrame(FocusFrame and FocusFrame.totFrame)
    end

    local bossFrameSource = ns.GetUnitFrameSource("boss")
    if bossFrameSource == "eui" then
    local bossPos = db.profile.positions.boss

    local spacing = ns.UF_BossSpacing()
    local bossStackDir = db.profile.boss and db.profile.boss.bossStackDirection or "down"
    for i = 1, 5 do
        local bossUnit = "boss" .. i
        local bossFrame = ns.Engine.SpawnUnitFrame(bossUnit, "EllesmereUIUnitFrames_Boss" .. i)
        StyleBossFrame(bossFrame, bossUnit)
        ns.UF_AttachEngineFrame(bossFrame, bossUnit)
        frames[bossUnit] = bossFrame

        -- boss1 anchors to UIParent; boss2..5 chain off boss1 with spacing.
        -- This keeps the whole stack moving together when unlock mode drags
        -- boss1 -- the only draggable boss frame.
        if i == 1 then
            if bossPos then
                bossFrame:ClearAllPoints()
                bossFrame:SetPoint(bossPos.point, UIParent, bossPos.relPoint or bossPos.point, bossPos.x, bossPos.y)
            end
        else
            local prev = frames["boss" .. (i - 1)]
            if prev then
                bossFrame:ClearAllPoints()
                if bossStackDir == "up" then
                    bossFrame:SetPoint("TOPLEFT", prev, "TOPLEFT", 0, spacing)
                else
                    bossFrame:SetPoint("TOPLEFT", prev, "TOPLEFT", 0, -spacing)
                end
            end
        end

        SetupUnitMenu(bossFrame, bossUnit)
    end
    elseif bossFrameSource == "hidden" then
        -- Suppressing boss1 takes the whole BossTargetFrameContainer with it
        -- (and all five Boss*TargetFrame children).
        ns.Engine.HideBlizzardUnitFrame("boss1")
    end

    -- Kill Blizzard's boss frames for every source except "blizzard" (where the
    -- user wants them). For "eui" oUF already disabled them at spawn; this pass
    -- is belt-and-suspenders and also runs for "hidden".
    if bossFrameSource ~= "blizzard" then
        for i = 1, 5 do
            local blizzBoss = _G["Boss" .. i .. "TargetFrame"]
            if blizzBoss then
                blizzBoss:UnregisterAllEvents()
                blizzBoss:Hide()
            end
        end
    end

    -- Apply user-selected frame strata to all unit frames
    local ufStrata = db.profile.frameStrata or "MEDIUM"
    for unitKey, frame in pairs(frames) do
        if type(frame) == "table" and frame.SetFrameStrata then
            -- Any unit with its own settings table can override the global
            -- strata; nil (the default) means "follow the global value". See
            -- the matching comment in the other frameStrata-apply pass for why
            -- this resolves through GetSettingsForUnit.
            local strata = ufStrata
            local us = GetSettingsForUnit(unitKey)
            if us and us.frameStrata then strata = us.frameStrata end
            frame:SetFrameStrata(strata)
            if frame.BottomTextBar and frame.BottomTextBar._isDetached then
                if db.profile.enableCustomBarStratas then
                    frame.BottomTextBar:SetFrameStrata(db.profile.detachedTextBarStrata or "DIALOG")
                else
                    frame.BottomTextBar:SetFrameStrata(strata)
                end
            end
            -- Same re-lift for a detached power bar -- see the matching comment
            -- in the other frameStrata-apply pass above for why this is needed.
            if frame.Power then
                local us2 = GetSettingsForUnit(unitKey)
                local ppPos = us2 and us2.powerPosition or "below"
                if ppPos == "detached_top" or ppPos == "detached_bottom" then
                    if db.profile.enableCustomBarStratas then
                        frame.Power:SetFrameStrata(db.profile.detachedPowerStrata or "HIGH")
                    else
                        frame.Power:SetFrameStrata("MEDIUM")
                    end
                end
            end
            -- The cast bar is a child of the frame, so SetFrameStrata above reset it to
            -- the frame's strata. Lift to HIGH so it never hides behind other MEDIUM-
            -- strata frames, unless "Raise Cast Bar Strata (All)" is off, in which case
            -- it's explicitly left at the frame's strata.
            if frame.Castbar and (unitKey == "player" or IsKickCastbarUnit(unitKey)) then
                local cbg = frame.Castbar:GetParent()
                if cbg then
                    if db.profile.raiseCastbarStrata ~= false then
                        cbg:SetFrameStrata("HIGH")
                    else
                        cbg:SetFrameStrata(strata)
                    end
                end
            end
            -- SetFrameStrata re-stacks children; lift the raid marker holder back
            -- above the text overlay so the marker is never hidden behind name/health text.
            if frame._raidMarkerHolder and frame._textOverlay then
                frame._raidMarkerHolder:SetFrameLevel(frame._textOverlay:GetFrameLevel() + 5)
            end
            -- Same for the dragon holders: the Portrait Dragon's carries its own
            -- strata and level (kept by its apply), the Pixels Dragon's rides
            -- one level over the portrait.
            local bd = frame.Portrait and frame.Portrait.backdrop
            local wh = bd and bd._winglessHolder
            if wh and wh._on then
                ns.UF_LiftDragonHolder(wh, bd, wh._strata, wh._level)
            end
            if bd and frame._eliteDragonHolder and frame._eliteDragonOn then
                ns.UF_LiftDragonHolder(frame._eliteDragonHolder, bd)
            end
        end
    end

    -- Disable oUF elements for frames where features are initially off.
    -- Portrait backdrop is already hidden by style functions, but oUF
    -- auto-enables the element at spawn time since frame.Portrait is always set.
    for unit, frame in pairs(frames) do
        if type(frame) ~= "table" or not frame.Portrait then -- skip non-frame entries
        elseif frame.Portrait.backdrop then
            local settings = GetSettingsForUnit(unit)
            if settings.showPortrait == false or (settings.portraitStyle or db.profile.portraitStyle or "attached") == "none" then
                if frame:IsElementEnabled("Portrait") then
                    frame:DisableElement("Portrait")
                end
            end
        end
    end

    -- Absorbs: apply style and hide if "none" for player, target, focus.
    -- Leave the oUF HealthPrediction element enabled so events keep flowing
    -- and the calculator stays in sync.
    for _, uKey in ipairs({ "player", "target", "focus" }) do
        local f = frames[uKey]
        if f and f.HealthPrediction and f.HealthPrediction.damageAbsorb then
            local absStyle = db.profile[uKey] and db.profile[uKey].showPlayerAbsorb
            if absStyle and absStyle ~= "none" then
                ApplyAbsorbStyle(f.HealthPrediction.damageAbsorb, absStyle, db.profile[uKey])
                f.HealthPrediction.damageAbsorb:Show()
                if f.HealthPrediction.damageAbsorb._forward then
                    f.HealthPrediction.damageAbsorb._forward:Show()
                end
            else
                f.HealthPrediction.damageAbsorb:Hide()
                if f.HealthPrediction.damageAbsorb._forward then
                    f.HealthPrediction.damageAbsorb._forward:Hide()
                end
            end
            -- Force oUF to re-run the HealthPrediction element so the new
            -- texture is visible immediately without waiting for a health event
            if f.HealthPrediction and f.HealthPrediction.ForceUpdate then
                f.HealthPrediction:ForceUpdate()
            end
        end
    end

    -- Boss frames: same absorb refresh, styled from the TARGET donor block
    -- and gated by the "Show on Boss Frames" toggle (nil = enabled).
    do
        local bossOff = db.profile.boss and db.profile.boss.showAbsorbs == false
        local donor = db.profile.target
        for i = 1, 5 do
            local f = frames["boss" .. i]
            if f and f.HealthPrediction and f.HealthPrediction.damageAbsorb then
                local absStyle
                if not bossOff and donor then absStyle = donor.showPlayerAbsorb end
                if absStyle and absStyle ~= "none" then
                    ApplyAbsorbStyle(f.HealthPrediction.damageAbsorb, absStyle, donor)
                    f.HealthPrediction.damageAbsorb:Show()
                    if f.HealthPrediction.damageAbsorb._forward then
                        f.HealthPrediction.damageAbsorb._forward:Show()
                    end
                else
                    f.HealthPrediction.damageAbsorb:Hide()
                    if f.HealthPrediction.damageAbsorb._forward then
                        f.HealthPrediction.damageAbsorb._forward:Hide()
                    end
                end
                if f.HealthPrediction.ForceUpdate then
                    f.HealthPrediction:ForceUpdate()
                end
            end
        end
    end

    -- Player castbar: disable oUF element if not wanted (always created now)
    if frames.player and frames.player.Castbar then
        if not db.profile.player.showPlayerCastbar then
            ns.SetCastbarElement(frames.player, false)
            frames.player.Castbar:Hide()
            local castbarBg = frames.player.Castbar:GetParent()
            if castbarBg then castbarBg:Hide() end
        elseif db.profile.player.showPlayerCastIcon == false and frames.player.Castbar._iconFrame then
            frames.player.Castbar._iconFrame:Hide()
        end
    end
    -- Hide While Using Gamepad: settle the flag and the pad watch.
    ns.UF_ApplyGamepadCastbar()

    -- Target castbar: disable oUF element if not wanted
    if frames.target and frames.target.Castbar then
        if db.profile.target.showCastbar == false then
            if frames.target:IsElementEnabled("Castbar") then
                frames.target:DisableElement("Castbar")
            end
            frames.target.Castbar:Hide()
            local castbarBg = frames.target.Castbar:GetParent()
            if castbarBg then castbarBg:Hide() end
        elseif db.profile.target.showCastIcon == false and frames.target.Castbar._iconFrame then
            frames.target.Castbar._iconFrame:Hide()
        end
    end

    -- Focus castbar: disable oUF element if not wanted
    if frames.focus and frames.focus.Castbar then
        if db.profile.focus.showCastbar == false then
            if frames.focus:IsElementEnabled("Castbar") then
                frames.focus:DisableElement("Castbar")
            end
            frames.focus.Castbar:Hide()
            local castbarBg = frames.focus.Castbar:GetParent()
            if castbarBg then castbarBg:Hide() end
        elseif db.profile.focus.showCastIcon == false and frames.focus.Castbar._iconFrame then
            frames.focus.Castbar._iconFrame:Hide()
        end
    end

    ---------------------------------------------------------------------------
    --  Group visibility: show/hide player/target/focus based on group state
    ---------------------------------------------------------------------------
    -- Companion mini frame for each main frame: the mini inherits its parent's FULL
    -- effective visibility (modes, multi-selections, hide options, fade, mouseover
    -- reveals, Never/disabled).
    ns.UF_MINI_OF = { player = "pet", target = "targettarget", focus = "focustarget" }

    local _ufInCombat = InCombatLockdown()
    local function UpdateFrameVisibility()
        -- Do NOT return early during combat lockdown. Alpha operations
        -- (SetAlpha) are not restricted and must run on combat transitions.
        -- Show/Hide and SetAttribute ARE restricted; those are guarded below.
        local isLocked = InCombatLockdown()
        local inRaid = IsInRaid()
        local inParty = not inRaid and IsInGroup()
        local solo = not inRaid and not inParty
        -- One state table per pass for the multi-select visibility engine
        local visState = { inCombat = _ufInCombat, inRaid = inRaid, inParty = inParty }
        for _, unitKey in ipairs({"player", "target", "focus"}) do
            local s = db.profile[unitKey]
            local frame = frames[unitKey]
            -- Visibility "never" no longer clears enabledFrames, so a frame hidden that
            -- way stays on this path and is hidden below, reversibly.
            if frame and not ns.VisUnitDisabled(db.profile, unitKey) and s then
                local hiddenByOpts = EllesmereUI.CheckVisibilityOptions(s)
                local vis = s.barVisibility or "always"

                -- Multi-select / dragonriding path: non-nil = engine-owned.
                -- nil = legacy single mode, untouched.
                local ext = EllesmereUI.EvalVisibilityExtended(s, "barVisibility", visState, EllesmereUI.VIS_CAPS_DEFAULT)

                -- Secure condition driver: an engine-owned selection compiles into a
                -- state-visibility driver (the action bar mechanism), replacing the
                -- frame's unit watch. A driver-hidden frame is TRULY hidden -- absorbs
                -- no clicks -- and the secure engine flips it mid-combat natively.
                -- Mouseover sets keep the frame shown while conditions pass (compiler
                -- ignores the mouseover key); the alpha bucket + hover handlers do the
                -- revealing. Registration is out-of-combat only; a selection changed
                -- during combat rides on alpha until the regen pass registers the driver.
                local drvSet = EllesmereUI.GetActiveVisibilityModes(s, "barVisibility")
                -- Condition scalars ride the driver too: dragonriding (engine owns it
                -- everywhere) and the combat pair, whose legacy alpha-hide left an
                -- invisible click-absorbing frame out of combat. Visibility is
                -- unchanged; the driver just hides for real and flips exactly at the combat edge.
                if not drvSet and (vis == "show_dragonriding" or vis == "show_not_dragonriding"
                    or vis == "in_combat" or vis == "out_of_combat") then
                    drvSet = { [vis] = true }
                end
                -- Tail built once and reused by the mini frame below (both compilers only
                -- PREPEND their prefix).
                local visTail
                -- An applied Visibility override replaces the whole setting, so the tail
                -- is a constant and the shared selection never reaches the driver.
                local visOv = EllesmereUI.VisOverrideValue(s)
                if visOv then
                    visTail = (visOv == "never") and "hide" or "show"
                elseif s.visibilityMatch == "any" and EllesmereUI.BuildAnyMatchTail then
                    local tail, _, liveAxes = EllesmereUI.BuildAnyMatchTail(s, "barVisibility", drvSet)
                    -- Gated on liveAxes: with no soft-target edge here, target/enemy axes
                    -- resolve in Lua, and a driver compiled from those alone would be a
                    -- frozen constant. Zero live axes keeps the frame on the live ext/alpha path.
                    if liveAxes > 0 then visTail = tail end
                elseif drvSet and EllesmereUI.BuildVisibilityDriverString then
                    visTail = EllesmereUI.BuildVisibilityDriverString("", drvSet)
                end
                -- Off the override, never the stored scalar: an override REPLACES the
                -- shared setting, so a profile-level "never" under an override of Always
                -- must not pin anything, and an override of "never" must pin even though
                -- the stored scalar says otherwise.
                local visNever = (visOv or vis) == "never"
                -- Health cannot be a secure macro condition. Keep the unit watch
                -- active and let the secret-safe alpha curve reveal injured units.
                if ns.HealthVisibilityEnabled(s, frame) then visTail = nil end
                local wantDriver
                if visNever then
                    -- Never is terminal, so it pins the secure driver instead of
                    -- riding the Show/Hide bucket below: that bucket is lockdown-
                    -- gated, and acquiring a target in combat would otherwise let
                    -- the unit watch show an alpha-0 click blocker until regen.
                    wantDriver = "hide"
                elseif visTail then
                    wantDriver = "[@" .. unitKey .. ",noexists] hide; " .. visTail
                end
                if frame._euiVisDriver ~= wantDriver and not isLocked then
                    if wantDriver then
                        UnregisterUnitWatch(frame)
                        RegisterAttributeDriver(frame, "state-visibility", wantDriver)
                    else
                        UnregisterAttributeDriver(frame, "state-visibility")
                        RegisterUnitWatch(frame)
                    end
                    frame._euiVisDriver = wantDriver
                end

                -- Combat-sensitive and mouseover modes use SetAlpha to show/hide
                -- (not a restricted API); the frame stays technically shown so it can
                -- transition instantly, alpha controls visibility. For the player frame
                -- we drive alpha on a non-secure wrapper (_visWrap) so nothing touching
                -- the inner frame's alpha (oUF updates, secure templates) can fight us --
                -- alpha inherits down the parent chain so wrapper alpha 0 always wins.
                local alphaTarget = frame._visWrap or frame
                -- Shared with both hover handlers. Forces 0 for the visHide* overrides too,
                -- so the frame looks hidden while the secure bucket below stays untouched:
                -- a dismount inside a lockdown would otherwise hide it permanently.
                -- _ufInCombat leads InCombatLockdown() on regen, so the ooc fade is instant.
                local bodyAlpha, hoverGated = ns.ResolveVisResting(s, frame, ext, hiddenByOpts, _ufInCombat)
                if s.showWhenHealthMissing and not hiddenByOpts then
                    bodyAlpha = ns.HealthVisibilityAlpha(s, frame, bodyAlpha, hoverGated, _ufInCombat)
                else
                    -- Off, or a Visibility Option hides it: health ticks must not reveal.
                    frame._healthVisLive = nil
                end
                alphaTarget:SetAlpha(bodyAlpha)

                -- 3D PlayerModel frames don't inherit parent alpha, so the model must
                -- mirror the EXACT body alpha computed above -- every alpha-hidden state
                -- (engine-owned, in_combat, out_of_combat, mouseover, hide-opts) would
                -- otherwise leave a floating portrait over an invisible frame. Hover
                -- handlers mirror it too when they reveal a mouseover frame.
                local bd3d = frame.Portrait and frame.Portrait.backdrop and frame.Portrait.backdrop._3d
                if bd3d then
                    bd3d:SetAlpha(bodyAlpha)
                end

                -- A class resource bar unlocked from the frame is parented to UIParent
                -- and so survives its owner being hidden. Only Never takes it along:
                -- that used to leave the player frame unspawned and the bar with it,
                -- and the other hiding modes have always kept their own bar visible.
                -- Written only when it moves: this pass runs on every target change,
                -- and for the "blizzard" style the bar is Blizzard's own frame. A bar
                -- locked to the frame is its child, so the Show When Health Missing
                -- reveal makes its alpha read secret: it is written blind then.
                if unitKey == "player" and frames._classPowerBar then
                    local cpWant = visNever and 0 or 1
                    local cpHave = frames._classPowerBar:GetAlpha()
                    if issecretvalue(cpHave) or cpHave ~= cpWant then
                        frames._classPowerBar:SetAlpha(cpWant)
                    end
                end

                -- Show/Hide and SetAttribute are restricted during lockdown.
                -- When a condition driver is registered it owns Show/Hide
                -- entirely -- a manual toggle would de-sync it until its
                -- next re-evaluation -- so this whole bucket steps aside.
                if not isLocked and not frame._euiVisDriver then
                    local shouldShow
                    if visNever then
                        -- Ahead of the engine verdict: Never is exclusive, but under
                        -- a leftover Any match the engine evaluates the scalar and
                        -- answers false rather than nil, which would keep the frame
                        -- secure-Shown at alpha 0 and still eating clicks.
                        shouldShow = false
                    elseif ns.HealthVisibilityEnabled(s, frame) then
                        shouldShow = true
                    elseif ext ~= nil then
                        -- Engine-owned: frame stays secure-Shown; the alpha
                        -- bucket above drives visibility.
                        shouldShow = true
                    elseif vis == "in_combat" or vis == "out_of_combat" or vis == "mouseover" then
                        -- Frame is kept shown; alpha (above) drives visibility.
                        shouldShow = true
                    elseif vis == "in_raid" then
                        shouldShow = inRaid
                    elseif vis == "in_party" then
                        shouldShow = inParty
                    elseif vis == "solo" then
                        shouldShow = solo
                    else
                        -- "always" is the default -- always Shown at secure
                        -- level; alpha controls actual visibility.
                        shouldShow = true
                    end

                    if shouldShow then
                        if not frame:IsShown() and UnitExists(unitKey) then
                            frame:SetAttribute("unit", unitKey)
                            -- Re-enable the engine elements that were disabled on hide.
                            -- Castbar is handled separately below to respect the
                            -- user's show/hide setting -- never blindly re-enable it.
                            for _, elem in ipairs({"Health", "Power", "Portrait", "HealthPrediction"}) do
                                if frame[elem] and not frame:IsElementEnabled(elem) then
                                    frame:EnableElement(elem)
                                end
                            end
                            -- Restore castbar state based on saved setting
                            if frame.Castbar then
                                local wantsCastbar
                                if unitKey == "player" then
                                    -- Hide While Using Gamepad keeps it off (ns.UF_ApplyGamepadCastbar).
                                    wantsCastbar = s.showPlayerCastbar and not ns._ufCastPadHidden
                                else
                                    wantsCastbar = s.showCastbar ~= false
                                end
                                if wantsCastbar then
                                    ns.SetCastbarElement(frame, true)
                                else
                                    ns.SetCastbarElement(frame, false)
                                    frame.Castbar:Hide()
                                    local castbarBg = frame.Castbar:GetParent()
                                    if castbarBg then castbarBg:Hide() end
                                end
                            end
                            frame:Show()
                            -- Full engine repaint: the SetAttribute above reuses
                            -- the same unit token, so the attribute hook sees no
                            -- change and never repaints on its own.
                            ns.Engine.RepaintAll(frame, "GroupVisibility")
                        end
                    else
                        if frame:IsShown() then
                            -- Disable the engine elements before hiding to prevent a
                            -- single-frame flash when the unit attribute is cleared
                            for _, elem in ipairs({"Health", "Power", "Portrait", "HealthPrediction"}) do
                                if frame[elem] and frame:IsElementEnabled(elem) then
                                    frame:DisableElement(elem)
                                end
                            end
                            ns.SetCastbarElement(frame, false)
                            frame:Hide()
                            frame:SetAttribute("unit", nil)
                        end
                    end
                end

                local mini = frames[ns.UF_MINI_OF[unitKey]]
                -- Always Show Pet Frame: the pet opts out of every parent
                -- visibility inheritance in this pass -- its own unit watch
                -- alone owns Show/Hide (visible whenever a pet exists).
                local miniAlways = (unitKey == "player") and db.profile.pet
                    and db.profile.pet.alwaysShow

                -- The companion mini frame gets its own condition driver
                -- (parent conditions + its own unit existence), so a
                -- condition-hidden mini absorbs no clicks either.
                if mini then
                    local miniWant
                    if (not miniAlways) and visNever then
                        -- The parent is hidden outright, so alpha 0 alone would leave
                        -- the mini an invisible click blocker; pin it like the
                        -- disabled-parent branch below does.
                        miniWant = "hide"
                    elseif (not miniAlways) and visTail then
                        miniWant = "[@" .. ns.UF_MINI_OF[unitKey] .. ",noexists] hide; " .. visTail
                    end
                    if mini._euiVisDriver ~= miniWant and not isLocked then
                        if miniWant then
                            UnregisterUnitWatch(mini)
                            RegisterAttributeDriver(mini, "state-visibility", miniWant)
                        else
                            UnregisterAttributeDriver(mini, "state-visibility")
                            RegisterUnitWatch(mini)
                        end
                        mini._euiVisDriver = miniWant
                    end
                end

                -- Mini-frame visibility inheritance: pet follows player, target-of-target
                -- follows target, focus-target follows focus. The mini mirrors the
                -- parent's effective state -- body alpha computed above (modes, multi-
                -- selections, hide options, ooc fade, mouseover default) plus the secure
                -- Show/Hide bucket via IsShown() -- so every way the parent hides takes
                -- its mini along. RegisterUnitWatch keeps owning the mini's own Show/Hide
                -- (unit existence); alpha never conflicts with it. Hover reveals mirror
                -- in the OnEnter/OnLeave handlers.
                if mini then
                    if miniAlways then
                        mini:SetAlpha(1)
                    elseif frame:IsShown() then
                        mini:SetAlpha(bodyAlpha)
                    else
                        mini:SetAlpha(0)
                    end
                end
            elseif frame then
                -- Parent disabled (the "Enable X Frame" toggles): a leftover condition
                -- driver must not keep re-showing the frame, so pin it to a constant
                -- hide. Frames that never had a driver keep the legacy disabled path
                -- untouched. The mini inherits both.
                if not isLocked and frame._euiVisDriver and frame._euiVisDriver ~= "hide" then
                    RegisterAttributeDriver(frame, "state-visibility", "hide")
                    frame._euiVisDriver = "hide"
                end
                local mini = frames[ns.UF_MINI_OF[unitKey]]
                if mini then
                    local miniAlways = (unitKey == "player") and db.profile.pet
                        and db.profile.pet.alwaysShow
                    if miniAlways then
                        -- Always Show Pet Frame survives a disabled player
                        -- frame: unpin any driver so the pet's own unit
                        -- watch shows it whenever a pet exists.
                        if not isLocked and mini._euiVisDriver then
                            UnregisterAttributeDriver(mini, "state-visibility")
                            RegisterUnitWatch(mini)
                            mini._euiVisDriver = nil
                        end
                        mini:SetAlpha(1)
                    else
                        if not isLocked and mini._euiVisDriver and mini._euiVisDriver ~= "hide" then
                            RegisterAttributeDriver(mini, "state-visibility", "hide")
                            mini._euiVisDriver = "hide"
                        end
                        mini:SetAlpha(0)
                    end
                end
            end
        end
        ns.SyncHealthVisibilityEvents()
    end
    ns.UpdateFrameVisibility = UpdateFrameVisibility

    if not frames._visFrame then
        frames._visFrame = CreateFrame("Frame")
        frames._visFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
        frames._visFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        frames._visFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        frames._visFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        frames._visFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
        frames._visFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
        -- Resting: IsResting() has no dedicated poll, so without this the Resting
        -- axis only re-evaluated when some unrelated event above happened to fire.
        frames._visFrame:RegisterEvent("PLAYER_UPDATE_RESTING")
        -- Vehicle edges for the In Vehicle axis (player-filtered; same reasoning).
        frames._visFrame:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
        frames._visFrame:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
        frames._visFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        frames._visFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
        -- The focus-target mini mirrors the focus frame's alpha below, so a
        -- focus set while the pass last saw that frame hidden left the mini at
        -- alpha 0 until some other trigger ran. Same deferral as target changes.
        frames._visFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
        -- Dragonriding visibility modes: capability edge plus the airborne
        -- edge (probed at load in EllesmereUI_Visibility.lua)
        frames._visFrame:RegisterEvent("PLAYER_CAN_GLIDE_CHANGED")
        if EllesmereUI._hasGlidingEvent then
            frames._visFrame:RegisterEvent("PLAYER_IS_GLIDING_CHANGED")
        end
    end
    frames._visFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            _ufInCombat = true
            -- Alpha-only update (SetAlpha is not restricted during lockdown).
            -- Show/Hide paths inside UpdateFrameVisibility are guarded by isLocked.
            UpdateFrameVisibility()
        elseif event == "PLAYER_REGEN_ENABLED" then
            _ufInCombat = false
            UpdateFrameVisibility()
        else
            -- Defer to next frame to avoid taint from secure execution paths
            C_Timer.After(0, UpdateFrameVisibility)
        end
    end)
    UpdateFrameVisibility()

    ---------------------------------------------------------------------------
    --  Portrait border color: update when target/focus unit changes
    --  so "class color" mode reflects the new unit's color.
    ---------------------------------------------------------------------------
    if not frames._portraitBorderUpdater then
        frames._portraitBorderUpdater = CreateFrame("Frame")
        frames._portraitBorderUpdater:RegisterEvent("PLAYER_TARGET_CHANGED")
        frames._portraitBorderUpdater:RegisterEvent("PLAYER_FOCUS_CHANGED")
    end
    frames._portraitBorderUpdater:SetScript("OnEvent", function(_, event)
        local unitKey = (event == "PLAYER_TARGET_CHANGED") and "target" or "focus"
        local frame = frames[unitKey]
        if frame and (unitKey == "target" or unitKey == "focus") then
            ns.UF_RecolorTexts(frame, unitKey, db.profile[unitKey])
        end
        if not frame or not frame.Portrait then return end
        local backdrop = frame.Portrait.backdrop
        if not backdrop then return end
        local uSettings = db.profile[unitKey]
        -- Refresh detached portrait border class color
        if uSettings and uSettings.detachedPortraitClassColor then
            ApplyDetachedPortraitShape(backdrop, uSettings, unitKey)
        end
    end)

    ---------------------------------------------------------------------------
    --  Portrait art readiness for the OnUpdate-polled frames (Target of Target
    --  / Focus Target). PORTRAITS_UPDATED is how the client says portrait art
    --  finished loading, and PortraitOverride acts on it -- but the event is
    --  never registered on these frames: once __eventless is set, the unit
    --  frame library's RegisterEvent drops everything except
    --  UNIT_PORTRAIT_UPDATE and UNIT_MODEL_CHANGED. PLAYER_ENTERING_WORLD
    --  still reaches them (UpdateAllElements pushes it to every element), so
    --  they take the mid-loading blank paint with nothing to heal it: the poll
    --  just re-runs the same guid-gated Override. ForceUpdate is the trigger
    --  that gate always honors. 2D only -- a PlayerModel does not read portrait
    --  art, and repainting one costs a ClearModel + SetUnit reload.
    ---------------------------------------------------------------------------
    if not frames._portraitArtUpdater then
        frames._portraitArtUpdater = CreateFrame("Frame")
        frames._portraitArtUpdater:RegisterEvent("PORTRAITS_UPDATED")
    end
    frames._portraitArtUpdater:SetScript("OnEvent", function()
        for _, frame in pairs(frames) do
            if type(frame) == "table" and frame.__eventless and frame.IsElementEnabled then
                local p = frame.Portrait
                if p and p.ForceUpdate and not p:IsObjectType("PlayerModel")
                    and frame:IsElementEnabled("Portrait") then
                    p:ForceUpdate()
                end
            end
        end
    end)

    -- Target-of-target/focus-target/pet text class colors must re-apply when their unit
    -- changes or first becomes available (login/reload). Unlike target/focus, mini
    -- frames have no PLAYER_*_CHANGED of their own, so a class color set at style
    -- time -- when "targettarget"/"focustarget"/"pet" was not yet a resolvable unit --
    -- falls back to white/reaction-nil and never recovers. Re-apply on the parent's
    -- target change and on its UNIT_TARGET, and on UNIT_PET for the pet frame.
    local function ReapplyFrameTextClassColors(unitKey)
        local frame = frames[unitKey]
        local s = frame and db.profile[unitKey]
        if not s then return end
        if frame.LeftText and s.leftTextClassColor ~= nil then
            ApplyClassColor(frame.LeftText, unitKey, s.leftTextClassColor, s.leftTextColorR, s.leftTextColorG, s.leftTextColorB)
        end
        if frame.RightText and s.rightTextClassColor ~= nil then
            ApplyClassColor(frame.RightText, unitKey, s.rightTextClassColor, s.rightTextColorR, s.rightTextColorG, s.rightTextColorB)
        end
        if frame.CenterText and s.centerTextClassColor ~= nil then
            ApplyClassColor(frame.CenterText, unitKey, s.centerTextClassColor, s.centerTextColorR, s.centerTextColorG, s.centerTextColorB)
        end
    end
    if not frames._miniTextClassUpdater then
        frames._miniTextClassUpdater = CreateFrame("Frame")
        frames._miniTextClassUpdater:RegisterEvent("PLAYER_TARGET_CHANGED")
        frames._miniTextClassUpdater:RegisterEvent("PLAYER_FOCUS_CHANGED")
        frames._miniTextClassUpdater:RegisterUnitEvent("UNIT_TARGET", "target", "focus")
        frames._miniTextClassUpdater:RegisterUnitEvent("UNIT_PET", "player")
    end
    frames._miniTextClassUpdater:SetScript("OnEvent", function(_, event, arg1)
        if event == "PLAYER_TARGET_CHANGED" then
            ReapplyFrameTextClassColors("targettarget")
        elseif event == "PLAYER_FOCUS_CHANGED" then
            ReapplyFrameTextClassColors("focustarget")
        elseif event == "UNIT_PET" then
            ReapplyFrameTextClassColors("pet")
        elseif arg1 == "target" then
            ReapplyFrameTextClassColors("targettarget")
        elseif arg1 == "focus" then
            ReapplyFrameTextClassColors("focustarget")
        end
    end)

    -- Boss Hover/Target border: refresh each boss frame's target state when the
    -- player's target changes or boss units (dis)appear. Hover is handled by the
    -- OnEnter/OnLeave hooks; this only tracks target. Both borders default off, so
    -- this is a cheap no-op unless the user enabled one. On ns for the 200-local cap.
    ns.UpdateBossTargetBorders = function()
        local s = db.profile.boss
        for i = 1, 5 do
            local bUnit = "boss" .. i
            local f = frames[bUnit]
            if f then
                if f.unifiedBorder then
                    local isT = UnitIsUnit(bUnit, "target")
                    f._isTarget = (not issecretvalue(isT) and isT) and true or false
                    ns.ApplyBossBorderState(f)
                end
                if s then
                    if f.LeftText and s.leftTextClassColor ~= nil then
                        ApplyClassColor(f.LeftText, bUnit, s.leftTextClassColor, s.leftTextColorR, s.leftTextColorG, s.leftTextColorB)
                    end
                    if f.RightText and s.rightTextClassColor ~= nil then
                        ApplyClassColor(f.RightText, bUnit, s.rightTextClassColor, s.rightTextColorR, s.rightTextColorG, s.rightTextColorB)
                    end
                    if f.CenterText and s.centerTextClassColor ~= nil then
                        ApplyClassColor(f.CenterText, bUnit, s.centerTextClassColor, s.centerTextColorR, s.centerTextColorG, s.centerTextColorB)
                    end
                end
            end
        end
    end
    if not frames._bossTargetBorderUpdater then
        frames._bossTargetBorderUpdater = CreateFrame("Frame")
        frames._bossTargetBorderUpdater:RegisterEvent("PLAYER_TARGET_CHANGED")
        frames._bossTargetBorderUpdater:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
        frames._bossTargetBorderUpdater:RegisterEvent("UNIT_TARGETABLE_CHANGED")
        frames._bossTargetBorderUpdater:RegisterEvent("PLAYER_ENTERING_WORLD")
    end
    frames._bossTargetBorderUpdater:SetScript("OnEvent", ns.UpdateBossTargetBorders)
    ns.UpdateBossTargetBorders()

    -- Deferred normalization: some late-login updates can re-anchor power bars
    -- after frame construction. Re-apply two-point attached anchors once more.
    -- Not under Blizzard Style: its layout pass owns the power bar geometry
    -- (a health-width re-anchor here would undo the stock bar placement).
    C_Timer.After(0, function()
        if ns.UF_Blizz() then return end
        for _, unitKey in ipairs({"player", "target", "focus", "pet"}) do
            local frame = frames[unitKey]
            if frame and frame.Power and frame.Health then
                local s = GetSettingsForUnit(unitKey)
                if s then
                    local ppPos = s.powerPosition or "below"
                    if ppPos == "below" or ppPos == "above" then
                        frame.Power:ClearAllPoints()
                        if ppPos == "above" then
                            PP.Point(frame.Power, "BOTTOMLEFT", frame.Health, "TOPLEFT", 0, 0)
                            PP.Point(frame.Power, "BOTTOMRIGHT", frame.Health, "TOPRIGHT", 0, 0)
                        else
                            PP.Point(frame.Power, "TOPLEFT", frame.Health, "BOTTOMLEFT", 0, 0)
                            PP.Point(frame.Power, "TOPRIGHT", frame.Health, "BOTTOMRIGHT", 0, 0)
                        end
                    end
                end
            end
        end
        for i = 1, 5 do
            local bf = frames["boss" .. i]
            if bf and bf.Power and bf.Health then
                local s = GetSettingsForUnit("boss")
                if s then
                    local ppPos = s.powerPosition or "below"
                    if ppPos == "below" or ppPos == "above" then
                        bf.Power:ClearAllPoints()
                        if ppPos == "above" then
                            PP.Point(bf.Power, "BOTTOMLEFT", bf.Health, "TOPLEFT", 0, 0)
                            PP.Point(bf.Power, "BOTTOMRIGHT", bf.Health, "TOPRIGHT", 0, 0)
                        else
                            PP.Point(bf.Power, "TOPLEFT", bf.Health, "BOTTOMLEFT", 0, 0)
                            PP.Point(bf.Power, "TOPRIGHT", bf.Health, "BOTTOMRIGHT", 0, 0)
                        end
                    end
                end
            end
        end
    end)

    -- Apply all settings (cast bar colors, text, sizes, etc.) now that
    -- frames are spawned and anchored.
    ReloadFrames()
end

I.InitializeFrames = InitializeFrames
