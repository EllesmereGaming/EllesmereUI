if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_UnitFrames_Reload.lua
--
--  ReloadFrames, the settings pass over every spawned unit frame, published
--  as I.ReloadFrames (EUI_UnitFrames_Init.lua, EUI_UnitFrames_OptionsSetup.lua),
--  and the frame border pad that mirrors its unified border apply. Reads the
--  main file through ns and ns._internals; db is set through I.dbSetters.
-------------------------------------------------------------------------------
local _, ns = ...

local issecretvalue = issecretvalue
local PP = EllesmereUI.PP
local GetMiniDonorSettings = ns.GetMiniDonorSettings

local I = ns._internals
local frames, GetSettingsForUnit, UnitToSettingsKey = I.frames, I.GetSettingsForUnit, I.UnitToSettingsKey
local UnsnapTex, SetFSFont, ResolveFontPath = I.UnsnapTex, I.SetFSFont, I.ResolveFontPath
local ApplyDarkTheme, ApplyEnemyColors, ApplyBarGradient = I.ApplyDarkTheme, I.ApplyEnemyColors, I.ApplyBarGradient
local ApplyHealthBarTexture, ApplyHealthBarAlpha, ApplyPowerBarAlpha =
    I.ApplyHealthBarTexture, I.ApplyHealthBarAlpha, I.ApplyPowerBarAlpha
local ApplyFramePosition, CreateBottomTextBar, ReparentBarsToClip, UpdateBordersForScale =
    I.ApplyFramePosition, I.CreateBottomTextBar, I.ReparentBarsToClip, I.UpdateBordersForScale
local ApplyAbsorbStyle, UpdateAbsorbBarReverseFill, ApplyDetachedPortraitShape =
    I.ApplyAbsorbStyle, I.UpdateAbsorbBarReverseFill, I.ApplyDetachedPortraitShape
local SwapPortraitMode, SpecHasClassPower = I.SwapPortraitMode, I.SpecHasClassPower
local CastIconInWidth, CastIconOffsets, CastIconOnRight, CastIconShown, LayoutCastbarIcon =
    I.CastIconInWidth, I.CastIconOffsets, I.CastIconOnRight, I.CastIconShown, I.LayoutCastbarIcon
local GetCastbarColor, ApplyUnitFrameCastColor, IsKickCastbarUnit, UpdateUnitFrameKickTick =
    I.GetCastbarColor, I.ApplyUnitFrameCastColor, I.IsKickCastbarUnit, I.UpdateUnitFrameKickTick
local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end

-- Blizzard Style: the per-unit geometry re-applies inside a reload each run
-- the stock pass from UpdateBordersForScale's tail, only for the re-anchors
-- that follow to undo it; the sweep at the end of the reload is the pass that
-- counts, so the tail steps aside for the reload's duration (login is a hot
-- path). The flag is cleared on every exit, error included.
local ReloadFramesBody
local function ReloadFrames()
    ns._ufReloadSweep = true
    local ok, err = pcall(ReloadFramesBody)
    ns._ufReloadSweep = nil
    if not ok then geterrorhandler()(err) end
end
ReloadFramesBody = function()
    ResolveFontPath()
    -- Refresh the tag-readable decimal globals before the combat early-return so
    -- tags pick up the saved state at login and on any settings change.
    ns.ApplyTextDecimalGlobals()
    if InCombatLockdown() then
        return
    end

    ApplyEnemyColors()

    -- Normalize opacity values: old profiles stored 0-1 floats, new format is 0-100 integers
    do
        local prof = db.profile
        local UNITS = { "player", "target", "focus", "boss", "pet", "targettarget", "focustarget" }
        if prof.healthBarOpacity and prof.healthBarOpacity <= 1.0 then
            prof.healthBarOpacity = math.floor(prof.healthBarOpacity * 100 + 0.5)
        end
        if prof.powerBarOpacity and prof.powerBarOpacity <= 1.0 then
            prof.powerBarOpacity = math.floor(prof.powerBarOpacity * 100 + 0.5)
        end
        for _, uKey in ipairs(UNITS) do
            local s = prof[uKey]
            if s then
                if s.healthBarOpacity and s.healthBarOpacity <= 1.0 then
                    s.healthBarOpacity = math.floor(s.healthBarOpacity * 100 + 0.5)
                end
                if s.powerBarOpacity and s.powerBarOpacity <= 1.0 then
                    s.powerBarOpacity = math.floor(s.powerBarOpacity * 100 + 0.5)
                end
            end
        end
    end

    local profile = db.profile
    local castbarColor = GetCastbarColor()
    local castbarOpacity = profile.castbarOpacity
    local enabled = profile.enabledFrames

    -- Apply frame strata to all spawned unit frames
    local ufStrata = profile.frameStrata or "MEDIUM"
    for unitKey, frame in pairs(frames) do
        if type(frame) == "table" and frame.SetFrameStrata then
            -- Any unit with its own settings table can override the global
            -- strata; nil (the default) means "follow the global value".
            -- GetSettingsForUnit maps boss1..boss5 onto the shared boss table
            -- and falls back to the player's settings, which is what the
            -- non-unit entries in `frames` (the class power bar above all)
            -- should ride with anyway.
            local strata = ufStrata
            local us = GetSettingsForUnit(unitKey)
            if us and us.frameStrata then strata = us.frameStrata end
            frame:SetFrameStrata(strata)
            -- Re-apply or reset custom strata for detached bars
            if frame.BottomTextBar and frame.BottomTextBar._isDetached then
                if profile.enableCustomBarStratas then
                    frame.BottomTextBar:SetFrameStrata(profile.detachedTextBarStrata or "DIALOG")
                else
                    frame.BottomTextBar:SetFrameStrata(strata)
                end
            end
            -- Same re-lift for a detached power bar: frame:SetFrameStrata above just
            -- reset it to the frame's strata (same reason the cast bar needs re-lifting
            -- below), so without this it silently falls back to the frame's strata and
            -- can end up behind the frame's own border, however "Detached Power Bar" strata is configured.
            if frame.Power then
                local us2 = GetSettingsForUnit(unitKey)
                local ppPos = us2 and us2.powerPosition or "below"
                if ppPos == "detached_top" or ppPos == "detached_bottom" then
                    if profile.enableCustomBarStratas then
                        frame.Power:SetFrameStrata(profile.detachedPowerStrata or "HIGH")
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
                    if profile.raiseCastbarStrata ~= false then
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
        end
    end

    -- Uses global font
    local donorFontPath = EllesmereUI.GetFontPath("unitFrames")
        or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"

    -- Live enable/disable frames without reload
    local function ToggleFrame(unit, frame)
        if not frame then return end
        if frame._euiVisDriver then
            -- A secure condition driver owns this frame's Show/Hide (group gating
            -- included); manual toggling here would de-sync it until the next driver
            -- re-evaluation. The visibility pass converts the driver when disabled.
            return
        end
        local unitKey = unit:match("^boss%d$") and "boss" or unit
        local isEnabled = enabled[unitKey] ~= false
        -- Check group visibility for player/target/focus
        if isEnabled and (unitKey == "player" or unitKey == "target" or unitKey == "focus") then
            local s = profile[unitKey]
            if s then
                local inRaid = IsInRaid()
                local inParty = not inRaid and IsInGroup()
                local solo = not inRaid and not inParty
                local vis = (inRaid and (s.showInRaid ~= false))
                    or (inParty and (s.showInParty ~= false))
                    or (solo and (s.showSolo ~= false))
                if not vis then isEnabled = false end
            end
        end
        if isEnabled then
            if not frame:IsShown() and UnitExists(unit) then
                frame:SetAttribute("unit", unit)
                frame:Show()
                -- The engine repaints in full on show (OnShow hook) and drops
                -- events for hidden frames at dispatch, so nothing needs
                -- re-enabling; one explicit pass covers the pre-show window.
                ns.Engine.RepaintAll(frame, "ToggleFrame")
            end
        else
            if frame:IsShown() then
                -- Hidden frames already cost nothing: the engine drops their
                -- events at dispatch and the poller skips them.
                frame:SetAttribute("unit", nil)
                frame:Hide()
            end
        end
    end

    for unit, frame in pairs(frames) do
        if type(unit) == "string" and unit:sub(1,1) ~= "_" and not unit:match("^boss%d$") then
            ToggleFrame(unit, frame)
        end
    end
    -- Boss frames: the unit watch registered at spawn is their show/hide authority.
    -- ToggleFrame's Hide() left that watch armed, so a profile switch that disables
    -- them had the next boss re-show all five. The watch owner unregisters (or
    -- re-registers) the watch and parks a regen one-shot when this runs in combat.
    if ns.UF_SetBossFramesActive and frames.boss1 then
        ns.UF_SetBossFramesActive(enabled.boss ~= false)
    end

    for unit, frame in pairs(frames) do
        if type(unit) == "string" and unit:sub(1,1) ~= "_" and frame then
            local unitKey = unit:match("^boss%d$") and "boss" or unit
            if enabled[unitKey] == false then
                -- skip disabled frames
            else
            -- Restore position and scale from profile
            if unitKey == "boss" then
                local bossPos = db.profile.positions.boss
                local bossSpacing = ns.UF_BossSpacing()
                local bossIdx = tonumber(unit:match("(%d+)$"))
                local bossAnchored = EllesmereUI and EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored("boss")
                local canRepoBoss1 = bossPos
                                 and not (EllesmereUI and EllesmereUI._unlockActive)
                                 and (not bossAnchored or not frame:GetLeft())
                if bossIdx == 1 and canRepoBoss1 then
                    frame:ClearAllPoints()
                    frame:SetPoint(bossPos.point, UIParent, bossPos.relPoint or bossPos.point, bossPos.x, bossPos.y)
                elseif bossIdx and bossIdx > 1 and not (EllesmereUI and EllesmereUI._unlockActive) then
                    -- boss2..5 always re-chain off the previous boss with the
                    -- current Vertical Spacing value, regardless of saved pos.
                    local prev = frames["boss" .. (bossIdx - 1)]
                    if prev then
                        frame:ClearAllPoints()
                        local bossStackDir = db.profile.boss and db.profile.boss.bossStackDirection or "down"
                        if bossStackDir == "up" then
                            frame:SetPoint("TOPLEFT", prev, "TOPLEFT", 0, bossSpacing)
                        else
                            frame:SetPoint("TOPLEFT", prev, "TOPLEFT", 0, -bossSpacing)
                        end
                    end
                end
            else
                if not (EllesmereUI and EllesmereUI._unlockActive) then
                    -- Skip for unlock-anchored elements (anchor system is authority)
                    local anchored = EllesmereUI and EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored(unit)
                    if not anchored or not frame:GetLeft() then
                        ApplyFramePosition(frame, unit)
                    end
                end
            end
            local settings = GetSettingsForUnit(unit)
            local pStyle = settings.portraitStyle or db.profile.portraitStyle or "attached"
            -- Mini frames never use detached portraits
            local unitIsMini = unit == "pet" or unit == "targettarget" or unit == "focustarget" or unit:match("^boss%d$")
            if unitIsMini and pStyle == "detached" then pStyle = "attached" end
            local showPortrait = pStyle ~= "none" and settings.showPortrait ~= false

            -- Keep the cached portrait side in sync with user-edited settings. Downstream
            -- re-snap code (SnapLayout, health anchor math) reads this lookup, so without
            -- it the side toggle wouldn't flip until a full UI reload.
            if settings.portraitSide then
                EllesmereUI._ufPortraitSide[frame] = settings.portraitSide
            end

            -- Re-anchor portrait backdrop based on style + side.
            if frame.Portrait and frame.Portrait.backdrop and settings.portraitSide then
                local bd = frame.Portrait.backdrop
                local pSide = settings.portraitSide
                local isInsideNow = pSide == "insideleft" or pSide == "insideright" or pSide == "insidecenter"
                bd._isInside = isInsideNow
                if isInsideNow then
                    if bd._bg then bd._bg:Hide() end
                    local healthAnchor = frame.Health or frame
                    local pXO = settings.portraitX or 0
                    local pYO = settings.portraitY or 0
                    local pSizeAdj = settings.portraitSize or 0
                    local frameH = frame:GetHeight()
                    if frameH < 1 then frameH = 46 end
                    local pDim = frameH + pSizeAdj
                    if pDim < 8 then pDim = 8 end
                    bd:SetClipsChildren(true)
                    bd:SetFrameLevel(frame:GetFrameLevel() + 3)
                    -- Raise border above 3D model (PlayerModel ignores frame level):
                    -- a 3D portrait, or Class art whose non-player fallback is 3D.
                    local pMode = settings.portraitMode or "2d"
                    local is3d = pMode == "3d" or (pMode == "class" and ns.UF_ClassFallback(settings) == "3d")
                    if is3d and frame.unifiedBorder and not settings.borderBehind then
                        frame.unifiedBorder:SetFrameLevel(frame:GetFrameLevel() + 20)
                    end
                    bd:ClearAllPoints()
                    bd:SetWidth(pDim)
                    if pSide == "insideleft" then
                        bd:SetPoint("TOPLEFT", healthAnchor, "TOPLEFT", pXO, pYO)
                        bd:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", pXO, 0)
                    elseif pSide == "insideright" then
                        bd:SetPoint("TOPRIGHT", healthAnchor, "TOPRIGHT", pXO, pYO)
                        bd:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", pXO, 0)
                    else
                        bd:SetPoint("TOP", healthAnchor, "TOP", pXO, pYO)
                        bd:SetPoint("BOTTOM", frame, "BOTTOM", pXO, 0)
                    end
                elseif pStyle == "attached" then
                    if bd._bg then bd._bg:Show() end
                    bd:SetClipsChildren(false)
                    bd:ClearAllPoints()
                    if pSide == "left" then
                        PP.Point(bd, "TOPLEFT", frame, "TOPLEFT", 0, 0)
                    else
                        PP.Point(bd, "TOPRIGHT", frame, "TOPRIGHT", 0, 0)
                    end
                end
                -- Restore border level when not inside+3D
                if not isInsideNow and frame.unifiedBorder then
                    local bBehind = settings.borderBehind
                    frame.unifiedBorder:SetFrameLevel(bBehind and math.max(0, frame:GetFrameLevel() - 1) or (frame:GetFrameLevel() + 10))
                end
            end

            -- Swap 2D/3D portrait mode if changed (no reload needed)
            if frame.Portrait then
                SwapPortraitMode(frame)
                -- Always ForceUpdate so zoom/camDistanceScale applies even without mode change
                if frame:IsElementEnabled("Portrait") and frame.Portrait.ForceUpdate then
                    frame.Portrait:ForceUpdate()
                end
            end

            -- Show/hide portrait live (no reload needed)
            if frame.Portrait and frame.Portrait.backdrop then
                local uKey = UnitToSettingsKey(unit) or unit
                local uSettings = uKey and db.profile[uKey]
                local isClassMode = ((uSettings and uSettings.portraitMode) or "2d") == "class"
                if showPortrait then
                    frame.Portrait.backdrop:Show()
                    if not frame:IsElementEnabled("Portrait") then
                        frame:EnableElement("Portrait")
                        frame.Portrait:ForceUpdate()
                    end
                else
                    frame.Portrait.backdrop:Hide()
                    if frame:IsElementEnabled("Portrait") then
                        frame:DisableElement("Portrait")
                    end
                end
                -- Live-update detached portrait shape/mask/border
                ApplyDetachedPortraitShape(frame.Portrait.backdrop, uSettings, unit)
                -- Raise detached portrait above border/text/power
                local isDetachedNow = pStyle == "detached"
                if isDetachedNow then
                    frame.Portrait.backdrop:SetFrameLevel(frame:GetFrameLevel() + 15)
                else
                    frame.Portrait.backdrop:SetFrameLevel(frame:GetFrameLevel() + 1)
                end
            end

            if unit == "player" or unit == "target" then
                local ppPos = settings.powerPosition or "below"
                local ppIsAtt = (ppPos == "below" or ppPos == "above")
                local ppExtra = ppIsAtt and settings.powerHeight or 0
                local playerTargetHeight = settings.healthHeight + ppExtra
                -- Class power "above" adds height above health bar (player only, "top" floats outside)
                local cpAboveH = 0
                if unit == "player" and SpecHasClassPower() then
                    local cpSt = settings.classPowerStyle or "none"
                    if ns.UF_ForeverCPStyle then cpSt = ns.UF_ForeverCPStyle(cpSt) end
                    local cpPo = (cpSt == "modern") and (settings.classPowerPosition or "top") or "none"
                    if cpSt == "modern" and cpPo == "above" then
                        local cpSizeAdj = settings.classPowerSize or 8
                        local cpPipH = math.max(3, math.floor(cpSizeAdj * 0.375))
                        cpAboveH = cpPipH
                    end
                end
                local playerTargetHeightWithCp = playerTargetHeight + cpAboveH
                local btbPos = settings.btbPosition or "bottom"
                local btbIsAttached = (btbPos == "top" or btbPos == "bottom")
                local btbExtra = (settings.bottomTextBar and btbIsAttached) and (settings.bottomTextBarHeight or 16) or 0
                local targetFrameHeight = playerTargetHeight + btbExtra
                local portraitHeight = 0
                local totalWidth = 0
                local isAttached = pStyle == "attached"
                local pSizeAdj = settings.portraitSize or 0
                local pXOff = settings.portraitX or 0
                local pYOff = settings.portraitY or 0
                if not isAttached then pSizeAdj = pSizeAdj + 10; pYOff = pYOff + 5 end

                if unit == "player" then
                    local pSide = settings.portraitSide or "left"
                    local effectiveSide = pSide
                    if isAttached and pSide == "top" then effectiveSide = "left" end
                    local adjPortraitH = playerTargetHeightWithCp + pSizeAdj
                    if adjPortraitH < 8 then adjPortraitH = 8 end
                    if not showPortrait then
                        totalWidth = settings.frameWidth
                        portraitHeight = 0
                    elseif isAttached then
                        totalWidth = adjPortraitH + settings.frameWidth
                        portraitHeight = adjPortraitH
                    else
                        totalWidth = settings.frameWidth
                        portraitHeight = 0
                    end
                    -- Health bar xOffset: only offset when portrait is attached on the left
                    local healthXOffset = 0
                    local healthRightInset = 0
                    if showPortrait and isAttached and effectiveSide == "left" then
                        healthXOffset = portraitHeight
                    elseif showPortrait and isAttached and effectiveSide == "right" then
                        healthRightInset = portraitHeight
                    end

                    PP.Size(frame, totalWidth, playerTargetHeightWithCp + btbExtra)

                    if frame.Portrait and frame.Portrait.backdrop and not frame.Portrait.backdrop._isInside then
                        PP.Size(frame.Portrait.backdrop, adjPortraitH, adjPortraitH)
                        -- Reposition portrait for attached/detached
                        frame.Portrait.backdrop:ClearAllPoints()
                        local pBtbTopOff = (btbPos == "top" and settings.bottomTextBar) and (settings.bottomTextBarHeight or 16) or 0
                        if isAttached then
                            if effectiveSide == "left" then
                                PP.Point(frame.Portrait.backdrop, "TOPLEFT", frame, "TOPLEFT", 0, -pBtbTopOff)
                            else
                                PP.Point(frame.Portrait.backdrop, "TOPRIGHT", frame, "TOPRIGHT", 0, -pBtbTopOff)
                            end
                        else
                            if effectiveSide == "top" then
                                frame.Portrait.backdrop:SetPoint("BOTTOM", frame.Health or frame, "TOP", pXOff, 15 + pYOff)
                            elseif effectiveSide == "left" then
                                frame.Portrait.backdrop:SetPoint("TOPRIGHT", frame.Health or frame, "TOPLEFT", -15 + pXOff, pYOff)
                            else
                                frame.Portrait.backdrop:SetPoint("TOPLEFT", frame.Health or frame, "TOPRIGHT", 15 + pXOff, pYOff)
                            end
                        end
                        if frame.Portrait.backdrop._2d then
                            UnsnapTex(frame.Portrait.backdrop._2d)
                        end
                        if frame:IsElementEnabled("Portrait") and frame.Portrait.ForceUpdate then
                            frame.Portrait:ForceUpdate()
                        end
                    end
                    if frame.Health then
                        frame.Health:ClearAllPoints()
                        -- Use portrait's actual snapped width for flush alignment
                        if showPortrait and isAttached and frame.Portrait and frame.Portrait.backdrop then
                            local snappedPortW = frame.Portrait.backdrop:GetWidth()
                            healthXOffset = (effectiveSide == "left") and snappedPortW or 0
                            healthRightInset = (effectiveSide == "right") and snappedPortW or 0
                        end
                        frame.Health._xOffset = healthXOffset
                        frame.Health._rightInset = healthRightInset
                        local powerAboveOff = (ppPos == "above") and settings.powerHeight or 0
                        local hTopOff = cpAboveH + powerAboveOff + (btbPos == "top" and settings.bottomTextBar and (settings.bottomTextBarHeight or 16) or 0)
                        frame.Health._topOffset = hTopOff
                        frame.Health:SetPoint("TOPLEFT", frame, "TOPLEFT", healthXOffset, PP.Scale(-hTopOff))
                        frame.Health:SetPoint("RIGHT", frame, "RIGHT", -healthRightInset, 0)
                        PP.Height(frame.Health, settings.healthHeight)
                    end
                    if frame.Power then
                        local pw = settings.frameWidth
                        local ppIsDetached = (ppPos == "detached_top" or ppPos == "detached_bottom")
                        if ppIsDetached and (settings.powerWidth or 0) > 0 then
                            pw = settings.powerWidth
                        end
                        PP.Size(frame.Power, pw, settings.powerHeight)
                        -- Apply custom strata for detached power bar
                        if ppIsDetached and db.profile.enableCustomBarStratas then
                            frame.Power:SetFrameStrata(db.profile.detachedPowerStrata or "HIGH")
                        elseif ppIsDetached then
                            frame.Power:SetFrameStrata("MEDIUM")
                        end
                        frame.Power:ClearAllPoints()
                        if ppPos == "none" then
                            frame.Power:Hide()
                        elseif ppPos == "above" then
                            PP.Point(frame.Power, "BOTTOMLEFT", frame.Health, "TOPLEFT", 0, 0)
                            PP.Point(frame.Power, "BOTTOMRIGHT", frame.Health, "TOPRIGHT", 0, 0)
                            frame.Power:Show()
                        elseif ppPos == "detached_top" then
                            frame.Power:SetPoint("BOTTOM", frame.Health, "TOP", settings.powerX or 0, 15 + (settings.powerY or 0))
                            frame.Power:Show()
                        elseif ppPos == "detached_bottom" then
                            frame.Power:SetPoint("TOP", frame.Health, "BOTTOM", settings.powerX or 0, -15 + (settings.powerY or 0))
                            frame.Power:Show()
                        else
                            PP.Point(frame.Power, "TOPLEFT", frame.Health, "BOTTOMLEFT", 0, 0)
                            PP.Point(frame.Power, "TOPRIGHT", frame.Health, "BOTTOMRIGHT", 0, 0)
                            frame.Power:Show()
                        end
                        if frame.Power._applyPowerPercentText then frame.Power._applyPowerPercentText(settings) end

                        -- Update power bar border (detached only; lazily created)
                        ns.UpdatePowerBorder(frame.Power, settings)

                        -- Gray out power bar background for generic melee NPCs
                        if ppPos ~= "none" and (ppPos == "below" or ppPos == "above") then
                            local shouldGray = false
                            if unit ~= "player" and UnitExists(unit) and UnitCanAttack("player", unit) and not UnitIsPlayer(unit) then
                                local cls = UnitClassification(unit)
                                local isBoss = (cls == "worldboss")
                                local isElite = (cls == "elite" or cls == "rareelite")
                                local lvl = UnitLevel(unit)
                                local pLvl = UnitLevel("player")
                                local lvlOk = lvl and not (issecretvalue and issecretvalue(lvl))
                                local pLvlOk = pLvl and not (issecretvalue and issecretvalue(pLvl))
                                local isMB = isElite and lvlOk and (lvl == -1 or (pLvlOk and lvl >= pLvl + 1))
                                local isCst = UnitClassBase and UnitClassBase(unit); if issecretvalue(isCst) then isCst = nil end; isCst = (isCst == "PALADIN")
                                if not isBoss and not isMB and not isCst then shouldGray = true end
                            end
                            if shouldGray then
                                frame.Power._grayedOut = true
                                if frame.Power.bg then
                                    frame.Power.bg:SetColorTexture(0.25, 0.25, 0.25, 1)
                                    frame.Power.bg:SetAlpha(1)
                                end
                            else
                                frame.Power._grayedOut = false
                            end
                        end
                    end
                    if frame.Castbar then
                        local castbarBg = frame.Castbar:GetParent()
                        if settings.showPlayerCastbar then
                            -- Hide While Using Gamepad keeps the element off and the
                            -- holder hidden (ns.UF_ApplyGamepadCastbar); the style
                            -- below still lands, so the bar comes back current.
                            ns.SetCastbarElement(frame, not ns._ufCastPadHidden)
                            if castbarBg then
                                local cbW = db.profile.player.playerCastbarWidth or 181
                                local cbH = db.profile.player.playerCastbarHeight or 14
                                PP.Size(castbarBg, cbW, cbH)
                                if castbarBg._bgTex then
                                    local cbg = settings.castBgColor
                                    castbarBg._bgTex:SetColorTexture(cbg and cbg.r or 0, cbg and cbg.g or 0, cbg and cbg.b or 0, settings.castBgAlpha or 0.5)
                                end
                                local pIconOffX, pIconOffY = CastIconOffsets("player", settings)
                                LayoutCastbarIcon(frame.Castbar, CastIconInWidth("player", settings), settings.playerCastbarHeight or 14, CastIconOnRight("player", settings), pIconOffX, pIconOffY, CastIconShown("player", settings), settings.playerCastbarStockBorderScale,
                                    ns.UF_CastIconPortrait(frame.Castbar, frame, settings, "player"))
                                ns.UF_ApplyCastBorder(frame.Castbar, settings, nil, "player")
                                -- Resize cast icon to match castbar height
                                if frame.Castbar._iconFrame then
                                    PP.Size(frame.Castbar._iconFrame, cbH, cbH)
                                    if not frame.Castbar:IsShown() or settings.showPlayerCastIcon == false then
                                        frame.Castbar._iconFrame:Hide()
                                    end
                                end
                                -- Position owned by centralized unlock system (no manual anchor)
                                -- Respect hide-while-not-casting (and Hide While Using Gamepad)
                                if ns._ufCastPadHidden
                                    or (settings.castbarHideWhenInactive and not frame.Castbar:IsShown()) then
                                    castbarBg:Hide()
                                else
                                    castbarBg:Show()
                                end
                            end
                            -- Store per-unit settings for PostCastStart
                            frame.Castbar._eufSettings = settings
                            -- Resolve per-unit fill color
                            local pCbColor = castbarColor
                            if settings.castbarClassColored then
                                local _, classToken = UnitClass("player")
                                if classToken and EllesmereUI.GetClassColor then
                                    pCbColor = EllesmereUI.GetClassColor(classToken) or castbarColor
                                end
                            elseif settings.castbarFillColor then
                                pCbColor = settings.castbarFillColor
                            end
                            -- Fill Opacity below 100: the tint layer is the visible
                            -- fill at that opacity; zero the base fill so it cannot
                            -- bleed through the translucent tint.
                            frame.Castbar:SetStatusBarColor(pCbColor.r, pCbColor.g, pCbColor.b,
                                ((settings.castFillOpacity or 100) < 100) and 0 or castbarOpacity)
                            ns.ApplyCastFillOpacity(frame.Castbar, settings)
                            -- Apply cast bar text settings
                            if frame.Castbar.Text then
                                local snSz = settings.castSpellNameSize or 11
                                SetFSFont(frame.Castbar.Text, snSz)
                                local snC = settings.castSpellNameColor or { r=1, g=1, b=1 }
                                frame.Castbar.Text:SetTextColor(snC.r, snC.g, snC.b)
                            end
                            if frame.Castbar.Time then
                                local dtSz = settings.castDurationSize or 10
                                SetFSFont(frame.Castbar.Time, dtSz)
                                local dtC = settings.castDurationColor or { r=1, g=1, b=1 }
                                frame.Castbar.Time:SetTextColor(dtC.r, dtC.g, dtC.b)
                                frame.Castbar._showDuration = settings.showCastDuration ~= false
                                frame.Castbar._durationSize = dtSz
                                -- Show/hide immediately (covers both toggle directions)
                                if frame.Castbar._showDuration and frame.Castbar:IsShown() then
                                    frame.Castbar.Time:Show()
                                elseif not frame.Castbar._showDuration then
                                    frame.Castbar.Time:Hide()
                                end
                            end
                            if frame.Castbar.Target then
                                local tsSz = settings.castSpellTargetSize or 11
                                SetFSFont(frame.Castbar.Target, tsSz)
                                local tsC = settings.castSpellTargetColor or { r=1, g=1, b=1 }
                                frame.Castbar.Target:SetTextColor(tsC.r, tsC.g, tsC.b)
                                frame.Castbar._showTarget = settings.showCastTarget ~= false
                                if not frame.Castbar._showTarget then
                                    frame.Castbar.Target:Hide()
                                end
                                if frame.Castbar._syncOffsetsAndLayout then
                                    frame.Castbar:_syncOffsetsAndLayout(settings)
                                end
                            end
                        else
                            ns.SetCastbarElement(frame, false)
                            frame.Castbar:Hide()
                            if castbarBg then castbarBg:Hide() end
                        end
                    end

                    -- Live toggle + style player absorbs. Never Enable/Disable the oUF
                    -- HealthPrediction element here: tearing it down unregisters events
                    -- and resets the calculator, which goes stale on the player frame
                    -- specifically (target/focus don't do this toggle and stay accurate).
                    -- Just Show/Hide the bar -- the element keeps running in the
                    -- background and the value stays live either way.
                    if frame.HealthPrediction and frame.HealthPrediction.damageAbsorb then
                        -- Boss frames style from the TARGET donor block,
                        -- behind the "Show on Boss Frames" toggle (nil = on).
                        local absSettings = settings
                        local absStyle = settings.showPlayerAbsorb
                        if unit and unit:match("^boss") then
                            if db.profile.boss and db.profile.boss.showAbsorbs == false then
                                absStyle = nil
                            else
                                absSettings = db.profile.target or settings
                                absStyle = absSettings.showPlayerAbsorb
                            end
                        end
                        if absStyle and absStyle ~= "none" then
                            ApplyAbsorbStyle(frame.HealthPrediction.damageAbsorb, absStyle, absSettings)
                            frame.HealthPrediction.damageAbsorb:Show()
                            -- Force an immediate value update so the bar doesn't
                            -- show stale/uninitialized fill covering the full frame.
                            if frame.HealthPrediction.Override then
                                frame.HealthPrediction.Override(frame, "UNIT_ABSORB_AMOUNT_CHANGED", unit)
                            end
                        else
                            frame.HealthPrediction.damageAbsorb:Hide()
                            -- Decoupled heal absorb: hiding the shield bar above
                            -- cascades (via the backfill OnHide hook) into hiding
                            -- the heal-absorb bar too. Re-run the prediction so the
                            -- heal absorb re-shows immediately after a reload even
                            -- with the shield absorb off, instead of staying hidden
                            -- until the next UNIT_ABSORB_AMOUNT_CHANGED event.
                            if frame.HealthPrediction.Override then
                                frame.HealthPrediction.Override(frame, "UNIT_ABSORB_AMOUNT_CHANGED", unit)
                            end
                        end
                    end

                    -- Reposition name and health text (player)
                    if frame._applyTextTags then
                        frame._applyTextTags(settings.leftTextContent or "name", settings.rightTextContent or "both", settings.centerTextContent or "none")
                    end
                    if frame._applyTextPositions then
                        frame._applyTextPositions(settings)
                    end

                    -- Bottom Text Bar update (player)
                    if settings.bottomTextBar then
                        local btbPos2 = settings.btbPosition or "bottom"
                        local btbIsAtt = (btbPos2 == "top" or btbPos2 == "bottom")
                        local btbIsDetached = not btbIsAtt
                        local btbW2 = btbIsDetached and (settings.btbWidth or 0) or 0
                        local btbTW = (btbW2 > 0 and btbIsDetached) and btbW2 or totalWidth
                        -- Compute BTB xOffset for left-side portrait (attached only)
                        local btbXOff = 0
                        if btbIsAtt and showPortrait and isAttached and effectiveSide == "left" then
                            btbXOff = -adjPortraitH
                        end
                        local ppBtbAnchor = (ppIsAtt and frame.Power) or frame.Health
                        if not frame.BottomTextBar then
                            frame.BottomTextBar = CreateBottomTextBar(frame, unit, settings, ppBtbAnchor, btbXOff, totalWidth)
                            frame._btb = frame.BottomTextBar
                        else
                            local btb = frame.BottomTextBar
                            PP.Size(btb, btbTW, settings.bottomTextBarHeight or 16)
                            btb:ClearAllPoints()
                            if btbPos2 == "top" then
                                PP.Point(btb, "BOTTOMLEFT", frame.Health or frame, "TOPLEFT", btbXOff, 0)
                            elseif btbPos2 == "detached_top" then
                                btb:SetPoint("BOTTOM", frame, "TOP", settings.btbX or 0, 15 + (settings.btbY or 0))
                            elseif btbPos2 == "detached_bottom" then
                                btb:SetPoint("TOP", frame, "BOTTOM", settings.btbX or 0, -15 + (settings.btbY or 0))
                            else
                                PP.Point(btb, "TOPLEFT", ppBtbAnchor, "BOTTOMLEFT", btbXOff, 0)
                            end
                            -- Update BTB bg color
                            if btb.bg then
                                local bgc = settings.btbBgColor or { r = 0.2, g = 0.2, b = 0.2 }
                                local bga = settings.btbBgOpacity or 1.0
                                btb.bg:SetColorTexture(bgc.r, bgc.g, bgc.b, bga)
                            end
                            if btb._applyBTBTextTags then
                                btb._applyBTBTextTags(settings.btbLeftContent or "none", settings.btbRightContent or "none", settings.btbCenterContent or "none")
                            end
                            if btb._applyBTBTextPositions then
                                btb._applyBTBTextPositions(settings)
                                if btb._applyBTBClassIcon then btb._applyBTBClassIcon(settings) end
                            end
                            btb:Show()
                        end
                    elseif frame.BottomTextBar then
                        frame.BottomTextBar:Hide()
                    end

                    UpdateBordersForScale(frame, unit)
                    ReparentBarsToClip(frame, settings.powerPosition, settings)

                elseif unit == "target" then
                    local pSide = settings.portraitSide or "right"
                    local effectiveSide = pSide
                    if isAttached and pSide == "top" then effectiveSide = "right" end
                    local adjPortraitH = playerTargetHeight + pSizeAdj
                    if adjPortraitH < 8 then adjPortraitH = 8 end
                    if not showPortrait then
                        totalWidth = settings.frameWidth
                        portraitHeight = 0
                    elseif isAttached then
                        totalWidth = adjPortraitH + settings.frameWidth
                        portraitHeight = adjPortraitH
                    else
                        totalWidth = settings.frameWidth
                        portraitHeight = 0
                    end
                    -- Health bar xOffset: only offset when portrait is attached on the left
                    local healthXOffset = 0
                    local healthRightInset = 0
                    if showPortrait and isAttached and effectiveSide == "left" then
                        healthXOffset = portraitHeight
                    elseif showPortrait and isAttached and effectiveSide == "right" then
                        healthRightInset = portraitHeight
                    end

                    PP.Size(frame, totalWidth, targetFrameHeight)

                    if frame.Portrait and frame.Portrait.backdrop and not frame.Portrait.backdrop._isInside then
                        PP.Size(frame.Portrait.backdrop, adjPortraitH, adjPortraitH)
                        frame.Portrait.backdrop:ClearAllPoints()
                        local btbTopOff = (btbPos == "top" and settings.bottomTextBar) and (settings.bottomTextBarHeight or 16) or 0
                        if isAttached then
                            if effectiveSide == "left" then
                                PP.Point(frame.Portrait.backdrop, "TOPLEFT", frame, "TOPLEFT", 0, -btbTopOff)
                            else
                                PP.Point(frame.Portrait.backdrop, "TOPRIGHT", frame, "TOPRIGHT", 0, -btbTopOff)
                            end
                        else
                            if effectiveSide == "top" then
                                frame.Portrait.backdrop:SetPoint("BOTTOM", frame.Health or frame, "TOP", pXOff, 15 + pYOff)
                            elseif effectiveSide == "left" then
                                frame.Portrait.backdrop:SetPoint("TOPRIGHT", frame.Health or frame, "TOPLEFT", -15 + pXOff, pYOff)
                            else
                                frame.Portrait.backdrop:SetPoint("TOPLEFT", frame.Health or frame, "TOPRIGHT", 15 + pXOff, pYOff)
                            end
                        end
                        if frame.Portrait.backdrop._2d then
                            UnsnapTex(frame.Portrait.backdrop._2d)
                        end
                        if frame:IsElementEnabled("Portrait") and frame.Portrait.ForceUpdate then
                            frame.Portrait:ForceUpdate()
                        end
                    end
                    if frame.Health then
                        frame.Health:ClearAllPoints()
                        -- Use portrait's actual snapped width for flush alignment
                        if showPortrait and isAttached and frame.Portrait and frame.Portrait.backdrop then
                            local snappedPortW = frame.Portrait.backdrop:GetWidth()
                            healthXOffset = (effectiveSide == "left") and snappedPortW or 0
                            healthRightInset = (effectiveSide == "right") and snappedPortW or 0
                        end
                        local tBtbTopOff = (btbPos == "top" and settings.bottomTextBar and (settings.bottomTextBarHeight or 16) or 0)
                        local tPowerAboveOff = (ppPos == "above") and settings.powerHeight or 0
                        local tTopOff = tBtbTopOff + tPowerAboveOff
                        frame.Health._xOffset = healthXOffset
                        frame.Health._rightInset = healthRightInset
                        frame.Health._topOffset = tTopOff
                        frame.Health:SetPoint("TOPLEFT", frame, "TOPLEFT", healthXOffset, PP.Scale(-tTopOff))
                        frame.Health:SetPoint("RIGHT", frame, "RIGHT", -healthRightInset, 0)
                        PP.Height(frame.Health, settings.healthHeight)
                    end
                    if frame.Power then
                        local pw2 = settings.frameWidth
                        local ppIsDetached2 = (ppPos == "detached_top" or ppPos == "detached_bottom")
                        if ppIsDetached2 and (settings.powerWidth or 0) > 0 then
                            pw2 = settings.powerWidth
                        end
                        PP.Size(frame.Power, pw2, settings.powerHeight)
                        frame.Power:ClearAllPoints()
                        if ppPos == "none" then
                            frame.Power:Hide()
                        elseif ppPos == "above" then
                            PP.Point(frame.Power, "BOTTOMLEFT", frame.Health, "TOPLEFT", 0, 0)
                            PP.Point(frame.Power, "BOTTOMRIGHT", frame.Health, "TOPRIGHT", 0, 0)
                            frame.Power:Show()
                        elseif ppPos == "detached_top" then
                            frame.Power:SetPoint("BOTTOM", frame.Health, "TOP", settings.powerX or 0, 15 + (settings.powerY or 0))
                            frame.Power:Show()
                        elseif ppPos == "detached_bottom" then
                            frame.Power:SetPoint("TOP", frame.Health, "BOTTOM", settings.powerX or 0, -15 + (settings.powerY or 0))
                            frame.Power:Show()
                        else
                            PP.Point(frame.Power, "TOPLEFT", frame.Health, "BOTTOMLEFT", 0, 0)
                            PP.Point(frame.Power, "TOPRIGHT", frame.Health, "BOTTOMRIGHT", 0, 0)
                            frame.Power:Show()
                        end
                        if frame.Power._applyPowerPercentText then frame.Power._applyPowerPercentText(settings) end

                        -- Update power bar border (detached only; lazily created)
                        ns.UpdatePowerBorder(frame.Power, settings)

                        -- Gray out power bar background for generic melee NPCs
                        if ppPos ~= "none" and (ppPos == "below" or ppPos == "above") then
                            local shouldGray = false
                            if unit ~= "player" and UnitExists(unit) and UnitCanAttack("player", unit) and not UnitIsPlayer(unit) then
                                local cls = UnitClassification(unit)
                                local isBoss = (cls == "worldboss")
                                local isElite = (cls == "elite" or cls == "rareelite")
                                local lvl = UnitLevel(unit)
                                local pLvl = UnitLevel("player")
                                local lvlOk = lvl and not (issecretvalue and issecretvalue(lvl))
                                local pLvlOk = pLvl and not (issecretvalue and issecretvalue(pLvl))
                                local isMB = isElite and lvlOk and (lvl == -1 or (pLvlOk and lvl >= pLvl + 1))
                                local isCst = UnitClassBase and UnitClassBase(unit); if issecretvalue(isCst) then isCst = nil end; isCst = (isCst == "PALADIN")
                                if not isBoss and not isMB and not isCst then shouldGray = true end
                            end
                            if shouldGray then
                                frame.Power._grayedOut = true
                                if frame.Power.bg then
                                    frame.Power.bg:SetColorTexture(0.25, 0.25, 0.25, 1)
                                    frame.Power.bg:SetAlpha(1)
                                end
                            else
                                frame.Power._grayedOut = false
                            end
                        end
                    end

                    -- Reposition name and health text
                    if frame._applyTextTags then
                        frame._applyTextTags(settings.leftTextContent or "name", settings.rightTextContent or "both", settings.centerTextContent or "none")
                    end
                    if frame._applyTextPositions then
                        frame._applyTextPositions(settings)
                    end

                    -- Bottom Text Bar update (target) -- must come before castbar so castbar can anchor to it
                    local tPpBtbAnchor = (ppIsAtt and (settings.powerHeight or 0) > 0 and frame.Power and frame.Power:IsShown()) and frame.Power or frame.Health
                    if settings.bottomTextBar then
                        local btbPos2 = settings.btbPosition or "bottom"
                        local btbIsAtt = (btbPos2 == "top" or btbPos2 == "bottom")
                        local btbIsDetached = not btbIsAtt
                        local btbW2 = btbIsDetached and (settings.btbWidth or 0) or 0
                        local btbTW = (btbW2 > 0 and btbIsDetached) and btbW2 or totalWidth
                        local btbXOff = 0
                        if btbIsAtt and showPortrait and isAttached and effectiveSide == "left" then
                            btbXOff = -adjPortraitH
                        end
                        if not frame.BottomTextBar then
                            frame.BottomTextBar = CreateBottomTextBar(frame, unit, settings, tPpBtbAnchor, btbXOff, totalWidth)
                            frame._btb = frame.BottomTextBar
                        else
                            local btb = frame.BottomTextBar
                            PP.Size(btb, btbTW, settings.bottomTextBarHeight or 16)
                            btb:ClearAllPoints()
                            if btbPos2 == "top" then
                                PP.Point(btb, "BOTTOMLEFT", frame.Health or frame, "TOPLEFT", btbXOff, 0)
                            elseif btbPos2 == "detached_top" then
                                btb:SetPoint("BOTTOM", frame, "TOP", settings.btbX or 0, 15 + (settings.btbY or 0))
                            elseif btbPos2 == "detached_bottom" then
                                btb:SetPoint("TOP", frame, "BOTTOM", settings.btbX or 0, -15 + (settings.btbY or 0))
                            else
                                PP.Point(btb, "TOPLEFT", tPpBtbAnchor, "BOTTOMLEFT", btbXOff, 0)
                            end
                            if btb.bg then
                                local bgc = settings.btbBgColor or { r = 0.2, g = 0.2, b = 0.2 }
                                local bga = settings.btbBgOpacity or 1.0
                                btb.bg:SetColorTexture(bgc.r, bgc.g, bgc.b, bga)
                            end
                            if btb._applyBTBTextTags then
                                btb._applyBTBTextTags(settings.btbLeftContent or "none", settings.btbRightContent or "none", settings.btbCenterContent or "none")
                            end
                            if btb._applyBTBTextPositions then
                                btb._applyBTBTextPositions(settings)
                                if btb._applyBTBClassIcon then btb._applyBTBClassIcon(settings) end
                            end
                            btb:Show()
                        end
                    elseif frame.BottomTextBar then
                        frame.BottomTextBar:Hide()
                    end

                    -- Castbar (target)
                    if frame.Castbar then
                        local castbarBg = frame.Castbar:GetParent()
                        if castbarBg then
                            if settings.showCastbar ~= false then
                                if not frame:IsElementEnabled("Castbar") then
                                    frame:EnableElement("Castbar")
                                end
                                local cbW2 = settings.castbarWidth or 181
                                local cbH2 = settings.castbarHeight or 14
                                PP.Size(castbarBg, cbW2, cbH2)
                                if castbarBg._bgTex then
                                    local cbg = settings.castBgColor
                                    castbarBg._bgTex:SetColorTexture(cbg and cbg.r or 0, cbg and cbg.g or 0, cbg and cbg.b or 0, settings.castBgAlpha or 0.5)
                                end
                                local tIconOffX, tIconOffY = CastIconOffsets("target", settings)
                                LayoutCastbarIcon(frame.Castbar, CastIconInWidth("target", settings), settings.castbarHeight or 14, CastIconOnRight("target", settings), tIconOffX, tIconOffY, CastIconShown("target", settings), settings.castbarStockBorderScale,
                                    ns.UF_CastIconPortrait(frame.Castbar, frame, settings, "target"))
                                ns.UF_ApplyCastBorder(frame.Castbar, settings, nil, "target")
                                if frame.Castbar._iconFrame then
                                    PP.Size(frame.Castbar._iconFrame, cbH2, cbH2)
                                    if not frame.Castbar:IsShown() then
                                        frame.Castbar._iconFrame:Hide()
                                    elseif settings.showCastIcon == false then
                                        frame.Castbar._iconFrame:Hide()
                                    else
                                        frame.Castbar._iconFrame:Show()
                                    end
                                end
                                -- Position owned by centralized unlock system
                                -- Respect hide-while-not-casting: only show bg if inactive hiding is off or cast is active
                                if settings.castbarHideWhenInactive and not frame.Castbar:IsShown() then
                                    castbarBg:Hide()
                                else
                                    castbarBg:Show()
                                end
                            else
                                if frame:IsElementEnabled("Castbar") then
                                    frame:DisableElement("Castbar")
                                end
                                frame.Castbar:Hide()
                                castbarBg:Hide()
                            end
                        end
                        -- Store per-unit settings for PostCastStart
                        frame.Castbar._eufSettings = settings
                        -- A glow already showing takes new Important Cast Glow settings now.
                        if frame.Castbar._impGlowActive then ns.UpdateUnitFrameImportantGlow(frame.Castbar) end
                        -- Resolve per-unit fill color
                        local tCbColor = castbarColor
                        if settings.castbarFillColor then
                            tCbColor = settings.castbarFillColor
                        end
                        -- Fill Opacity below 100: tint layer carries the visible
                        -- fill; zero the base so it cannot bleed through.
                        frame.Castbar:SetStatusBarColor(tCbColor.r, tCbColor.g, tCbColor.b,
                            ((settings.castFillOpacity or 100) < 100) and 0 or castbarOpacity)
                        ns.ApplyCastFillOpacity(frame.Castbar, settings)
                        if frame.Castbar:IsShown() then
                            ApplyUnitFrameCastColor(frame.Castbar)
                            UpdateUnitFrameKickTick(frame.Castbar)
                        end
                        -- Apply cast bar text settings
                        if frame.Castbar.Text then
                            local snSz = settings.castSpellNameSize or 11
                            SetFSFont(frame.Castbar.Text, snSz)
                            local snC = settings.castSpellNameColor or { r=1, g=1, b=1 }
                            frame.Castbar.Text:SetTextColor(snC.r, snC.g, snC.b)
                        end
                        if frame.Castbar.Time then
                            local dtSz = settings.castDurationSize or 10
                            SetFSFont(frame.Castbar.Time, dtSz)
                            local dtC = settings.castDurationColor or { r=1, g=1, b=1 }
                            frame.Castbar.Time:SetTextColor(dtC.r, dtC.g, dtC.b)
                            frame.Castbar._showDuration = settings.showCastDuration ~= false
                            frame.Castbar._durationSize = dtSz
                            if frame.Castbar._showDuration and frame.Castbar:IsShown() then
                                frame.Castbar.Time:Show()
                            elseif not frame.Castbar._showDuration then
                                frame.Castbar.Time:Hide()
                            end
                        end
                        if frame.Castbar.Target then
                            local tsSz = settings.castSpellTargetSize or 11
                            SetFSFont(frame.Castbar.Target, tsSz)
                            local tsC = settings.castSpellTargetColor or { r=1, g=1, b=1 }
                            frame.Castbar.Target:SetTextColor(tsC.r, tsC.g, tsC.b)
                            frame.Castbar._showTarget = settings.showCastTarget ~= false
                            if not frame.Castbar._showTarget then
                                frame.Castbar.Target:Hide()
                            end
                            if frame.Castbar._syncOffsetsAndLayout then
                                frame.Castbar:_syncOffsetsAndLayout(settings)
                            end
                        end
                    end

                    UpdateBordersForScale(frame, unit)
                    ReparentBarsToClip(frame, settings.powerPosition, settings)
                end

                -- (health tag re-tagging now handled by _applyTextTags above)

            elseif unit == "focus" then
                local fPpPos = settings.powerPosition or "below"
                local fPpIsAtt = (fPpPos == "below" or fPpPos == "above")
                local powerHeight = fPpIsAtt and (settings.powerHeight or 6) or 0
                local focusBarHeight = settings.healthHeight + powerHeight
                local fBtbPos = settings.btbPosition or "bottom"
                local fBtbIsAtt = (fBtbPos == "top" or fBtbPos == "bottom")
                local fBtbExtra = (settings.bottomTextBar and fBtbIsAtt) and (settings.bottomTextBarHeight or 16) or 0
                local totalWidth = 0
                local focusPStyle = settings.portraitStyle or db.profile.portraitStyle or "attached"
                local isAttached = focusPStyle == "attached"
                local pSide = settings.portraitSide or "right"
                local effectiveSide = pSide
                if isAttached and pSide == "top" then effectiveSide = "right" end
                local pSizeAdj = settings.portraitSize or 0
                if not isAttached then pSizeAdj = pSizeAdj + 10 end
                local pXOff = settings.portraitX or 0
                local pYOff = settings.portraitY or 0
                if not isAttached then pYOff = pYOff + 5 end
                local adjPortraitH = focusBarHeight + pSizeAdj
                if adjPortraitH < 8 then adjPortraitH = 8 end

                if not showPortrait then
                    totalWidth = settings.frameWidth
                elseif isAttached then
                    totalWidth = adjPortraitH + settings.frameWidth
                else
                    totalWidth = settings.frameWidth
                end

                PP.Size(frame, totalWidth, focusBarHeight + fBtbExtra)

                if frame.Portrait and frame.Portrait.backdrop and not frame.Portrait.backdrop._isInside then
                    PP.Size(frame.Portrait.backdrop, adjPortraitH, adjPortraitH)
                    -- Trim portrait to stay within frame bounds
                    if showPortrait and isAttached then
                        local frameW = frame:GetWidth()
                        local frameH = frame:GetHeight()
                        local portW = frame.Portrait.backdrop:GetWidth()
                        local portH = frame.Portrait.backdrop:GetHeight()
                        if portW + settings.frameWidth > frameW + 0.01 then
                            PP.Width(frame.Portrait.backdrop, frameW - settings.frameWidth)
                        end
                        if portH > frameH + 0.01 then
                            PP.Height(frame.Portrait.backdrop, frameH)
                        end
                    end
                    -- Reposition portrait for attached/detached
                    frame.Portrait.backdrop:ClearAllPoints()
                    local fBtbTopOff = (fBtbPos == "top" and settings.bottomTextBar) and (settings.bottomTextBarHeight or 16) or 0
                    if isAttached then
                        if effectiveSide == "left" then
                            PP.Point(frame.Portrait.backdrop, "TOPLEFT", frame, "TOPLEFT", 0, -fBtbTopOff)
                        else
                            PP.Point(frame.Portrait.backdrop, "TOPRIGHT", frame, "TOPRIGHT", 0, -fBtbTopOff)
                        end
                    else
                        if effectiveSide == "top" then
                            frame.Portrait.backdrop:SetPoint("BOTTOM", frame.Health or frame, "TOP", pXOff, 15 + pYOff)
                        elseif effectiveSide == "left" then
                            frame.Portrait.backdrop:SetPoint("TOPRIGHT", frame.Health or frame, "TOPLEFT", -15 + pXOff, pYOff)
                        else
                            frame.Portrait.backdrop:SetPoint("TOPLEFT", frame.Health or frame, "TOPRIGHT", 15 + pXOff, pYOff)
                        end
                    end
                    -- Re-apply pixel snap disable after resize
                    if frame.Portrait.backdrop._2d then
                        UnsnapTex(frame.Portrait.backdrop._2d)
                    end
                    if frame:IsElementEnabled("Portrait") and frame.Portrait.ForceUpdate then
                        frame.Portrait:ForceUpdate()
                    end
                end
                if frame.Health then
                    frame.Health:ClearAllPoints()
                    local focusHealthXOff = (showPortrait and isAttached and effectiveSide == "left") and adjPortraitH or 0
                    local focusHealthRightInset = (showPortrait and isAttached and effectiveSide == "right") and adjPortraitH or 0
                    -- Use portrait's actual snapped width for flush alignment
                    if showPortrait and isAttached and frame.Portrait and frame.Portrait.backdrop then
                        local snappedPortW = frame.Portrait.backdrop:GetWidth()
                        focusHealthXOff = (effectiveSide == "left") and snappedPortW or 0
                        focusHealthRightInset = (effectiveSide == "right") and snappedPortW or 0
                    end
                    local fHTopOff = (fBtbPos == "top" and settings.bottomTextBar and (settings.bottomTextBarHeight or 16) or 0)
                    local fPowerAboveOff = (fPpPos == "above") and (settings.powerHeight or 6) or 0
                    fHTopOff = fHTopOff + fPowerAboveOff
                    frame.Health._xOffset = focusHealthXOff
                    frame.Health._rightInset = focusHealthRightInset
                    frame.Health._topOffset = fHTopOff
                    PP.Point(frame.Health, "TOPLEFT", frame, "TOPLEFT", focusHealthXOff, -fHTopOff)
                    PP.Point(frame.Health, "RIGHT", frame, "RIGHT", -focusHealthRightInset, 0)
                    PP.Height(frame.Health, settings.healthHeight)
                end
                if frame.Power then
                    local fpw = settings.frameWidth
                    local fPpIsDet = (fPpPos == "detached_top" or fPpPos == "detached_bottom")
                    if fPpIsDet and (settings.powerWidth or 0) > 0 then
                        fpw = settings.powerWidth
                    end
                    PP.Size(frame.Power, fpw, settings.powerHeight or 6)
                    frame.Power:ClearAllPoints()
                    if fPpPos == "none" then
                        frame.Power:Hide()
                    elseif fPpPos == "above" then
                        PP.Point(frame.Power, "BOTTOMLEFT", frame.Health, "TOPLEFT", 0, 0)
                        PP.Point(frame.Power, "BOTTOMRIGHT", frame.Health, "TOPRIGHT", 0, 0)
                        frame.Power:Show()
                    elseif fPpPos == "detached_top" then
                        frame.Power:SetPoint("BOTTOM", frame.Health, "TOP", settings.powerX or 0, 15 + (settings.powerY or 0))
                        frame.Power:Show()
                    elseif fPpPos == "detached_bottom" then
                        frame.Power:SetPoint("TOP", frame.Health, "BOTTOM", settings.powerX or 0, -15 + (settings.powerY or 0))
                        frame.Power:Show()
                    else
                        PP.Point(frame.Power, "TOPLEFT", frame.Health, "BOTTOMLEFT", 0, 0)
                        PP.Point(frame.Power, "TOPRIGHT", frame.Health, "BOTTOMRIGHT", 0, 0)
                        frame.Power:Show()
                    end
                    if frame.Power._applyPowerPercentText then frame.Power._applyPowerPercentText(settings) end
                    -- Update power bar border (detached only; lazily created)
                    ns.UpdatePowerBorder(frame.Power, settings)
                end
                if frame._applyTextTags then
                    frame._applyTextTags(settings.leftTextContent or "name", settings.rightTextContent or "perhp", settings.centerTextContent or "none")
                end
                if frame._applyTextPositions then
                    frame._applyTextPositions(settings)
                end

                -- Bottom Text Bar update (focus) -- must come before castbar so castbar can anchor to it
                local fPpBtbAnchor = (fPpIsAtt and frame.Power) or frame.Health
                if settings.bottomTextBar then
                    local btbPos2 = settings.btbPosition or "bottom"
                    local btbIsAtt2 = (btbPos2 == "top" or btbPos2 == "bottom")
                    local btbIsDet2 = not btbIsAtt2
                    local btbW2 = btbIsDet2 and (settings.btbWidth or 0) or 0
                    local btbTW = (btbW2 > 0 and btbIsDet2) and btbW2 or totalWidth
                    local btbXOff = 0
                    if btbIsAtt2 and showPortrait and isAttached and effectiveSide == "left" then
                        btbXOff = -adjPortraitH
                    end
                    if not frame.BottomTextBar then
                        frame.BottomTextBar = CreateBottomTextBar(frame, unit, settings, fPpBtbAnchor, btbXOff, totalWidth)
                        frame._btb = frame.BottomTextBar
                    else
                        local btb = frame.BottomTextBar
                        PP.Size(btb, btbTW, settings.bottomTextBarHeight or 16)
                        btb:ClearAllPoints()
                        if btbPos2 == "top" then
                            PP.Point(btb, "BOTTOMLEFT", frame.Health or frame, "TOPLEFT", btbXOff, 0)
                        elseif btbPos2 == "detached_top" then
                            btb:SetPoint("BOTTOM", frame, "TOP", settings.btbX or 0, 15 + (settings.btbY or 0))
                        elseif btbPos2 == "detached_bottom" then
                            btb:SetPoint("TOP", frame, "BOTTOM", settings.btbX or 0, -15 + (settings.btbY or 0))
                        else
                            PP.Point(btb, "TOPLEFT", fPpBtbAnchor, "BOTTOMLEFT", btbXOff, 0)
                        end
                        if btb.bg then
                            local bgc = settings.btbBgColor or { r = 0.2, g = 0.2, b = 0.2 }
                            local bga = settings.btbBgOpacity or 1.0
                            btb.bg:SetColorTexture(bgc.r, bgc.g, bgc.b, bga)
                        end
                        if btb._applyBTBTextTags then
                            btb._applyBTBTextTags(settings.btbLeftContent or "none", settings.btbRightContent or "none", settings.btbCenterContent or "none")
                        end
                        if btb._applyBTBTextPositions then
                            btb._applyBTBTextPositions(settings)
                            if btb._applyBTBClassIcon then btb._applyBTBClassIcon(settings) end
                        end
                        btb:Show()
                    end
                elseif frame.BottomTextBar then
                    frame.BottomTextBar:Hide()
                end

                -- Castbar (focus)
                if frame.Castbar then
                    local castbarBg = frame.Castbar:GetParent()
                    if castbarBg then
                        if settings.showCastbar ~= false then
                            if not frame:IsElementEnabled("Castbar") then
                                frame:EnableElement("Castbar")
                            end
                            local cbW3 = settings.castbarWidth or 181
                            local cbH3 = settings.castbarHeight or 14
                            PP.Size(castbarBg, cbW3, cbH3)
                            if castbarBg._bgTex then
                                local cbg = settings.castBgColor
                                castbarBg._bgTex:SetColorTexture(cbg and cbg.r or 0, cbg and cbg.g or 0, cbg and cbg.b or 0, settings.castBgAlpha or 0.5)
                            end
                            local fIconOffX, fIconOffY = CastIconOffsets("focus", settings)
                            LayoutCastbarIcon(frame.Castbar, CastIconInWidth("focus", settings), settings.castbarHeight or 14, CastIconOnRight("focus", settings), fIconOffX, fIconOffY, CastIconShown("focus", settings), settings.castbarStockBorderScale,
                                ns.UF_CastIconPortrait(frame.Castbar, frame, settings, "focus"))
                            ns.UF_ApplyCastBorder(frame.Castbar, settings, nil, "focus")
                            if frame.Castbar._iconFrame then
                                PP.Size(frame.Castbar._iconFrame, cbH3, cbH3)
                                if not frame.Castbar:IsShown() then
                                    frame.Castbar._iconFrame:Hide()
                                elseif settings.showCastIcon == false then
                                    frame.Castbar._iconFrame:Hide()
                                else
                                    frame.Castbar._iconFrame:Show()
                                end
                            end
                            -- Position owned by centralized unlock system
                            -- Respect hide-while-not-casting: only show bg if inactive hiding is off or cast is active
                            if settings.castbarHideWhenInactive and not frame.Castbar:IsShown() then
                                castbarBg:Hide()
                            else
                                castbarBg:Show()
                            end
                        else
                            if frame:IsElementEnabled("Castbar") then
                                frame:DisableElement("Castbar")
                            end
                            frame.Castbar:Hide()
                            castbarBg:Hide()
                        end
                    end
                    -- Store per-unit settings for PostCastStart
                    frame.Castbar._eufSettings = settings
                    -- A glow already showing takes new Important Cast Glow settings now.
                    if frame.Castbar._impGlowActive then ns.UpdateUnitFrameImportantGlow(frame.Castbar) end
                    -- Resolve per-unit fill color
                    local fCbColor = castbarColor
                    if settings.castbarFillColor then
                        fCbColor = settings.castbarFillColor
                    end
                    -- Fill Opacity below 100: tint layer carries the visible
                    -- fill; zero the base so it cannot bleed through.
                    frame.Castbar:SetStatusBarColor(fCbColor.r, fCbColor.g, fCbColor.b,
                        ((settings.castFillOpacity or 100) < 100) and 0 or castbarOpacity)
                    ns.ApplyCastFillOpacity(frame.Castbar, settings)
                    if frame.Castbar:IsShown() then
                        ApplyUnitFrameCastColor(frame.Castbar)
                        UpdateUnitFrameKickTick(frame.Castbar)
                    end
                    -- Apply cast bar text settings
                    if frame.Castbar.Text then
                        local snSz = settings.castSpellNameSize or 11
                        SetFSFont(frame.Castbar.Text, snSz)
                        local snC = settings.castSpellNameColor or { r=1, g=1, b=1 }
                        frame.Castbar.Text:SetTextColor(snC.r, snC.g, snC.b)
                    end
                    if frame.Castbar.Time then
                        local dtSz = settings.castDurationSize or 10
                        SetFSFont(frame.Castbar.Time, dtSz)
                        local dtC = settings.castDurationColor or { r=1, g=1, b=1 }
                        frame.Castbar.Time:SetTextColor(dtC.r, dtC.g, dtC.b)
                        frame.Castbar._showDuration = settings.showCastDuration ~= false
                        frame.Castbar._durationSize = dtSz
                        if frame.Castbar._showDuration and frame.Castbar:IsShown() then
                            frame.Castbar.Time:Show()
                        elseif not frame.Castbar._showDuration then
                            frame.Castbar.Time:Hide()
                        end
                    end
                    if frame.Castbar.Target then
                        local tsSz = settings.castSpellTargetSize or 11
                        SetFSFont(frame.Castbar.Target, tsSz)
                        local tsC = settings.castSpellTargetColor or { r=1, g=1, b=1 }
                        frame.Castbar.Target:SetTextColor(tsC.r, tsC.g, tsC.b)
                        frame.Castbar._showTarget = settings.showCastTarget ~= false
                        frame.Castbar._nameSide = settings.castSpellNameSide or "left"
                        frame.Castbar._tgtSide  = settings.castSpellTargetSide or "right"
                        frame.Castbar._durSide  = settings.castDurationSide or "right"
                        if not frame.Castbar._showTarget then
                            frame.Castbar.Target:Hide()
                        end
                        if frame.Castbar._layoutTextZones then
                            frame.Castbar:_layoutTextZones()
                        end
                    end
                end

                UpdateBordersForScale(frame, unit)
                ReparentBarsToClip(frame, settings.powerPosition, settings)

            elseif unit == "pet" or unit == "targettarget" or unit == "focustarget" then
                -- Pet, ToT and FoT all share the same simple-frame layout:
                -- optional portrait on either side, health bar filling the rest.
                -- A WoW Forever pet adds its own power bar (built at spawn): an
                -- attached bar grows the stack and the portrait squares off it.
                local miniPower = (unit == "pet" and ns.UF_PetHasPower and not ns.UF_Blizz()) and frame.Power or nil
                local miniPpPos = miniPower and (settings.powerPosition or "below") or "none"
                local miniPowerH = (miniPpPos == "below" or miniPpPos == "above") and (settings.powerHeight or 6) or 0
                local miniAboveOff = (miniPpPos == "above") and miniPowerH or 0
                local miniBarH = settings.healthHeight + miniPowerH
                local miniPStyle = settings.portraitStyle or db.profile.portraitStyle or "attached"
                local showMiniPortrait = miniPStyle ~= "none" and settings.showPortrait ~= false
                local miniSide = settings.portraitSide or "left"
                local miniW = settings.frameWidth
                local miniLeftOff = 0
                local miniRightInset = 0
                if showMiniPortrait then
                    miniW = miniBarH + settings.frameWidth
                    if miniSide == "right" then
                        miniRightInset = miniBarH
                    else
                        miniLeftOff = miniBarH
                    end
                end
                PP.Size(frame, miniW, miniBarH)
                if frame.Portrait and frame.Portrait.backdrop then
                    PP.Size(frame.Portrait.backdrop, miniBarH, miniBarH)
                end
                if frame.Health then
                    frame.Health:ClearAllPoints()
                    PP.Point(frame.Health, "TOPLEFT", frame, "TOPLEFT", miniLeftOff, -miniAboveOff)
                    PP.Point(frame.Health, "RIGHT", frame, "RIGHT", -miniRightInset, 0)
                    PP.Height(frame.Health, settings.healthHeight)
                    frame.Health._xOffset = miniLeftOff
                    frame.Health._rightInset = miniRightInset
                    frame.Health._topOffset = miniAboveOff
                end
                if miniPower then
                    local mpw = settings.frameWidth
                    if (miniPpPos == "detached_top" or miniPpPos == "detached_bottom") and (settings.powerWidth or 0) > 0 then
                        mpw = settings.powerWidth
                    end
                    PP.Size(miniPower, mpw, settings.powerHeight or 6)
                    miniPower:ClearAllPoints()
                    if miniPpPos == "none" then
                        miniPower:Hide()
                    elseif miniPpPos == "above" then
                        PP.Point(miniPower, "BOTTOMLEFT", frame.Health, "TOPLEFT", 0, 0)
                        PP.Point(miniPower, "BOTTOMRIGHT", frame.Health, "TOPRIGHT", 0, 0)
                        miniPower:Show()
                    elseif miniPpPos == "detached_top" then
                        miniPower:SetPoint("BOTTOM", frame.Health, "TOP", settings.powerX or 0, 15 + (settings.powerY or 0))
                        miniPower:Show()
                    elseif miniPpPos == "detached_bottom" then
                        miniPower:SetPoint("TOP", frame.Health, "BOTTOM", settings.powerX or 0, -15 + (settings.powerY or 0))
                        miniPower:Show()
                    else
                        PP.Point(miniPower, "TOPLEFT", frame.Health, "BOTTOMLEFT", 0, 0)
                        PP.Point(miniPower, "TOPRIGHT", frame.Health, "BOTTOMRIGHT", 0, 0)
                        miniPower:Show()
                    end
                    if miniPower._applyPowerPercentText then miniPower._applyPowerPercentText(settings) end
                    -- "none" parks the power painter (zero cost while hidden);
                    -- turning the bar back on repaints it at once.
                    local wantPower = miniPpPos ~= "none"
                    if frame:IsElementEnabled("Power") ~= wantPower then
                        if wantPower then frame:EnableElement("Power") else frame:DisableElement("Power") end
                    end
                end

                UpdateBordersForScale(frame, unit)
                ReparentBarsToClip(frame, settings.powerPosition, settings)

            elseif unit:match("^boss%d$") then
                local bPpPos = settings.powerPosition or "below"
                local bPpIsAtt = (bPpPos == "below" or bPpPos == "above")
                local powerHeight = bPpIsAtt and (settings.powerHeight or 6) or 0
                local bossBarHeight = settings.healthHeight + powerHeight
                local totalWidth = 0

                if not showPortrait then
                    totalWidth = settings.frameWidth
                else
                    totalWidth = bossBarHeight + settings.frameWidth
                end

                PP.Size(frame, totalWidth, bossBarHeight)

                if frame.Portrait and frame.Portrait.backdrop then
                    PP.Size(frame.Portrait.backdrop, bossBarHeight, bossBarHeight)
                    local bossPSide = settings.portraitSide or "right"
                    frame.Portrait.backdrop:ClearAllPoints()
                    if bossPSide == "left" then
                        PP.Point(frame.Portrait.backdrop, "TOPLEFT", frame, "TOPLEFT", 0, 0)
                    else
                        PP.Point(frame.Portrait.backdrop, "TOPRIGHT", frame, "TOPRIGHT", 0, 0)
                    end
                    EllesmereUI._ufPortraitSide[frame] = bossPSide
                end
                if frame.Health then
                    frame.Health:ClearAllPoints()
                    -- Use portrait's actual snapped width for flush alignment
                    local bossPortW = 0
                    if showPortrait then
                        if frame.Portrait and frame.Portrait.backdrop then
                            bossPortW = frame.Portrait.backdrop:GetWidth()
                        else
                            bossPortW = bossBarHeight
                        end
                    end
                    local bossPSide = settings.portraitSide or "right"
                    local bossLeftOff  = (showPortrait and bossPSide == "left")  and bossPortW or 0
                    local bossRightInset = (showPortrait and bossPSide == "right") and bossPortW or 0
                    local bPowerAboveOff = (bPpPos == "above") and (settings.powerHeight or 6) or 0
                    PP.Point(frame.Health, "TOPLEFT", frame, "TOPLEFT", bossLeftOff, -bPowerAboveOff)
                    PP.Point(frame.Health, "RIGHT", frame, "RIGHT", -bossRightInset, 0)
                    PP.Height(frame.Health, settings.healthHeight)
                    frame.Health._xOffset = bossLeftOff
                    frame.Health._rightInset = bossRightInset
                    frame.Health._topOffset = bPowerAboveOff
                end
                if frame.Power then
                    local bpw = settings.frameWidth
                    local bPpIsDet = (bPpPos == "detached_top" or bPpPos == "detached_bottom")
                    if bPpIsDet and (settings.powerWidth or 0) > 0 then
                        bpw = settings.powerWidth
                    end
                    frame.Power:SetSize(bpw, settings.powerHeight or 6)
                    frame.Power:ClearAllPoints()
                    if bPpPos == "none" then
                        frame.Power:Hide()
                    elseif bPpPos == "above" then
                        PP.Point(frame.Power, "BOTTOMLEFT", frame.Health, "TOPLEFT", 0, 0)
                        PP.Point(frame.Power, "BOTTOMRIGHT", frame.Health, "TOPRIGHT", 0, 0)
                        frame.Power:Show()
                    elseif bPpPos == "detached_top" then
                        frame.Power:SetPoint("BOTTOM", frame.Health, "TOP", settings.powerX or 0, 15 + (settings.powerY or 0))
                        frame.Power:Show()
                    elseif bPpPos == "detached_bottom" then
                        frame.Power:SetPoint("TOP", frame.Health, "BOTTOM", settings.powerX or 0, -15 + (settings.powerY or 0))
                        frame.Power:Show()
                    else
                        PP.Point(frame.Power, "TOPLEFT", frame.Health, "BOTTOMLEFT", 0, 0)
                        PP.Point(frame.Power, "TOPRIGHT", frame.Health, "BOTTOMRIGHT", 0, 0)
                        frame.Power:Show()
                    end
                    if frame.Power._applyPowerPercentText then frame.Power._applyPowerPercentText(settings) end

                    -- Gray out power bar background for generic melee NPCs
                    if bPpPos ~= "none" and (bPpPos == "below" or bPpPos == "above") then
                        local shouldGray = false
                        if UnitExists(unit) and UnitCanAttack("player", unit) and not UnitIsPlayer(unit) then
                            local cls = UnitClassification(unit)
                            local isBoss = (cls == "worldboss")
                            local isElite = (cls == "elite" or cls == "rareelite")
                            local lvl = UnitLevel(unit)
                            local pLvl = UnitLevel("player")
                            local isMB = isElite and (lvl == -1 or (pLvl and lvl >= pLvl + 1))
                            local isCst = UnitClassBase and UnitClassBase(unit); if issecretvalue(isCst) then isCst = nil end; isCst = (isCst == "PALADIN")
                            if not isBoss and not isMB and not isCst then shouldGray = true end
                        end
                        if shouldGray then
                            frame.Power._grayedOut = true
                            if frame.Power.bg then
                                frame.Power.bg:SetColorTexture(0.25, 0.25, 0.25, 1)
                                frame.Power.bg:SetAlpha(1)
                            end
                        else
                            frame.Power._grayedOut = false
                        end
                    end
                end

                -- Castbar (boss)
                if frame.Castbar then
                    local castbarBg = frame.Castbar:GetParent()
                    if castbarBg then
                        if castbarBg._bgTex then
                            local cbg = settings.castBgColor
                            castbarBg._bgTex:SetColorTexture(cbg and cbg.r or 0, cbg and cbg.g or 0, cbg and cbg.b or 0, settings.castBgAlpha or 0.5)
                        end
                        if settings.showCastbar ~= false then
                            if not frame:IsElementEnabled("Castbar") then
                                frame:EnableElement("Castbar")
                            end
                            -- castbarWidth > 0 = user-set custom width; 0 = match frame width.
                            -- Custom widths floor at 30: below the cast icon size the
                            -- icon-in-width inset inverts the bar's anchor rect.
                            local bCbW = settings.castbarWidth or 0
                            if bCbW > 0 and bCbW < 30 then bCbW = 30 end
                            PP.Size(castbarBg, bCbW > 0 and bCbW or totalWidth, settings.castbarHeight or 14)
                            local bIconOffX, bIconOffY = CastIconOffsets("boss1", settings)
                            LayoutCastbarIcon(frame.Castbar, CastIconInWidth("boss1", settings), settings.castbarHeight or 14, CastIconOnRight("boss1", settings), bIconOffX, bIconOffY, CastIconShown("boss1", settings), settings.castbarStockBorderScale)
                            ns.UF_ApplyCastBorder(frame.Castbar, settings, nil, "boss1")
                            if frame.Castbar._iconFrame then
                                local cbH = settings.castbarHeight or 14
                                PP.Size(frame.Castbar._iconFrame, cbH, cbH)
                                if not frame.Castbar:IsShown() then
                                    frame.Castbar._iconFrame:Hide()
                                elseif settings.showCastIcon == false then
                                    frame.Castbar._iconFrame:Hide()
                                else
                                    frame.Castbar._iconFrame:Show()
                                end
                            end
                            castbarBg:ClearAllPoints()
                            -- Anchor to the frame's own (pixel-snapped) bottom edge, not the
                            -- bar's bottom: health/power bars live in the sub-pixel-inset bar
                            -- clip, which left a ~1px gap below the frame. Cast bar is full
                            -- frame width, so frame bottom-center keeps it centered + flush.
                            -- castbarOffsetX/Y nudge the whole cast bar (positive = right/up).
                            -- Blizzard Style: hug the visible art's bottom, not the stock box.
                            local _, _, _, bossVisB = ns.UF_BlizzVis(frame)
                            castbarBg:SetPoint("TOP", frame, "BOTTOM", settings.castbarOffsetX or 0, (settings.castbarOffsetY or 0) + (bossVisB or 0))
                            if settings.castbarHideWhenInactive and not frame.Castbar:IsShown() then
                                castbarBg:Hide()
                            else
                                castbarBg:Show()
                            end
                        else
                            if frame:IsElementEnabled("Castbar") then
                                frame:DisableElement("Castbar")
                            end
                            frame.Castbar:Hide()
                            castbarBg:Hide()
                        end
                    end
                    frame.Castbar._eufSettings = settings
                    local bCbColor = castbarColor
                    if settings.castbarFillColor then
                        bCbColor = settings.castbarFillColor
                    end
                    frame.Castbar:SetStatusBarColor(bCbColor.r, bCbColor.g, bCbColor.b,
                        ((settings.castFillOpacity or 100) < 100) and 0 or castbarOpacity)
                    ns.ApplyCastFillOpacity(frame.Castbar, settings)
                    if frame.Castbar:IsShown() then
                        ApplyUnitFrameCastColor(frame.Castbar)
                        UpdateUnitFrameKickTick(frame.Castbar)
                    end
                    if frame.Castbar.Text then
                        local snSz = settings.castSpellNameSize or 11
                        SetFSFont(frame.Castbar.Text, snSz)
                        local snC = settings.castSpellNameColor or { r=1, g=1, b=1 }
                        frame.Castbar.Text:SetTextColor(snC.r, snC.g, snC.b)
                    end
                    if frame.Castbar.Time then
                        local dtSz = settings.castDurationSize or 10
                        SetFSFont(frame.Castbar.Time, dtSz)
                        local dtC = settings.castDurationColor or { r=1, g=1, b=1 }
                        frame.Castbar.Time:SetTextColor(dtC.r, dtC.g, dtC.b)
                        frame.Castbar._showDuration = settings.showCastDuration ~= false
                        frame.Castbar._durationSize = dtSz
                        if frame.Castbar._showDuration and frame.Castbar:IsShown() then
                            frame.Castbar.Time:Show()
                        elseif not frame.Castbar._showDuration then
                            frame.Castbar.Time:Hide()
                        end
                    end
                    if frame.Castbar.Target then
                        local tsSz = settings.castSpellTargetSize or 11
                        SetFSFont(frame.Castbar.Target, tsSz)
                        local tsC = settings.castSpellTargetColor or { r=1, g=1, b=1 }
                        frame.Castbar.Target:SetTextColor(tsC.r, tsC.g, tsC.b)
                        frame.Castbar._showTarget = settings.showCastTarget ~= false
                        frame.Castbar._nameSide = settings.castSpellNameSide or "left"
                        frame.Castbar._tgtSide  = settings.castSpellTargetSide or "right"
                        frame.Castbar._durSide  = settings.castDurationSide or "right"
                        if not frame.Castbar._showTarget then
                            frame.Castbar.Target:Hide()
                        end
                        if frame.Castbar._layoutTextZones then
                            frame.Castbar:_layoutTextZones()
                        end
                    end
                end

                UpdateBordersForScale(frame, unit)
                ReparentBarsToClip(frame, settings.powerPosition, settings)
            end

            -- Determine if this is a mini frame that inherits border/texture/font
            local isMiniFrame = (unit == "pet" or unit == "targettarget" or unit == "focustarget" or unit:match("^boss%d$"))
            local donorSettings = isMiniFrame and GetMiniDonorSettings(UnitToSettingsKey(unit)) or settings

            -- Apply health bar texture overlay (mini frames inherit the donor
            -- texture unless they set their own override).
            if isMiniFrame then
                local uKey = UnitToSettingsKey(unit)
                ApplyHealthBarTexture(frame.Health, uKey, ns.ResolveHealthBarTextureKey(settings, donorSettings))
                ApplyHealthBarAlpha(frame.Health, uKey)
            else
                ApplyHealthBarTexture(frame.Health, UnitToSettingsKey(unit))
                ApplyHealthBarAlpha(frame.Health, UnitToSettingsKey(unit))
            end
            -- Cast bar reuses the same bar texture as the health bar.
            if frame.Castbar then
                local cbTexKey
                if isMiniFrame then
                    cbTexKey = ns.ResolveHealthBarTextureKey(settings, donorSettings)
                else
                    cbTexKey = settings.healthBarTexture or db.profile.healthBarTexture or "none"
                end
                ns.ApplyCastBarTexture(frame.Castbar, cbTexKey)
            end
            frame.Health:SetReverseFill(settings.healthReverseFill and true or false)
            ns.ApplyHealthOrientation(frame.Health, settings)
            ApplyDarkTheme(frame.Health, unit)  -- re-anchors health.bg for the new axis
            UpdateAbsorbBarReverseFill(frame, settings.healthReverseFill and true or false, settings)
            ns.UF_HealPredApply(frame, unit, settings)
            ns.UF_AbsorbGlowApply(frame, unit)
            -- Smooth bar interpolation (live toggle without /reload)
            if settings.smoothBars then
                frame.Health.smoothing = Enum and Enum.StatusBarInterpolation
                    and Enum.StatusBarInterpolation.ExponentialEaseOut
            else
                frame.Health.smoothing = Enum and Enum.StatusBarInterpolation
                    and Enum.StatusBarInterpolation.Immediate
            end
            if frame.Health.ForceUpdate then
                frame.Health:ForceUpdate()
            end

            -- Apply power bar opacity
            if frame.Power then
                ApplyPowerBarAlpha(frame.Power, UnitToSettingsKey(unit))

                -- Re-apply power bar fill color based on powerPercentPowerColor toggle.
                -- Gradient (additive) layers on top of the resolved custom/power-type color.
                local usePowerColor = settings.powerPercentPowerColor ~= false
                frame.Power.colorPower = usePowerColor
                if not usePowerColor then
                    local customFill = settings.customPowerFillColor
                    if customFill then
                        frame.Power:SetStatusBarColor(customFill.r, customFill.g, customFill.b)
                    else
                        frame.Power:SetStatusBarColor(0, 0, 1)
                    end
                end
                frame.Power.PostUpdateColor = function(self)
                    local s2 = GetSettingsForUnit(unit)
                    if not s2 then return end
                    local useP = s2.powerPercentPowerColor ~= false
                    local bR, bG, bB
                    if not useP then
                        local cf = s2.customPowerFillColor
                        if cf then bR, bG, bB = cf.r, cf.g, cf.b else bR, bG, bB = 0, 0, 1 end
                    else
                        -- Secret-safe per-unit power color (player via token,
                        -- non-player via the clean integer type), so custom power
                        -- colors apply on EVERY unit independent of oUF's sync.
                        bR, bG, bB = EllesmereUI.ResolveUnitPowerColor(unit)
                    end
                    if s2.powerGradientEnabled and bR then
                        local gc = s2.powerGradientColor
                        local ga = s2.powerBarOpacity or 100
                        if ga > 1.0 then ga = ga / 100 end
                        ApplyBarGradient(self:GetStatusBarTexture(), s2.powerGradientDir or "HORIZONTAL",
                            bR, bG, bB, ga,
                            gc and gc.r or 0.20, gc and gc.g or 0.20, gc and gc.b or 0.80, ga)
                    elseif not useP then
                        local cf = s2.customPowerFillColor
                        if cf then self:SetStatusBarColor(cf.r, cf.g, cf.b) else self:SetStatusBarColor(0, 0, 1) end
                    elseif bR then
                        -- Power-color mode (no gradient): explicitly paint the bar so it
                        -- doesn't depend on oUF's colors.power being synced.
                        self:SetStatusBarColor(bR, bG, bB)
                    end
                    -- Bar Background: power-colored bg tracks this unit's power
                    -- color each update (mirrors the fill); see CreatePowerBar.
                    if s2.powerBgPowerColored and self.bg then
                        local pr, pg, pb = EllesmereUI.ResolveUnitPowerColor(unit)
                        if pr then
                            local f = EllesmereUI.GetPowerBgDarkenFactor()
                            self.bg:SetColorTexture(pr * f, pg * f, pb * f, 1)
                        end
                    end
                    -- Keep the power-percent text color in sync with this unit
                    -- (per-unit power color; set up in CreatePowerBar). Gated on
                    -- the feature being active (power-colored AND text shown) ->
                    -- short-circuits to no cost for every other frame.
                    if s2.powerPercentTextPowerColor and (s2.powerPercentText or "none") ~= "none" and self._applyPowerTextColor then
                        self._applyPowerTextColor(s2)
                    end
                    -- Same continuous re-application for the Bottom Text Bar's
                    -- power-colored text (per-slot early-out keeps it ~free).
                    local btb = frame.BottomTextBar
                    if btb and btb._applyBTBPowerColors then btb._applyBTBPowerColors(s2) end
                end
                local customBg = settings.customPowerBgColor
                if customBg and frame.Power.bg then
                    frame.Power.bg:SetColorTexture(customBg.r, customBg.g, customBg.b, 1)
                elseif frame.Power.bg then
                    frame.Power.bg:SetColorTexture(17/255, 17/255, 17/255, 1)
                end
                frame.Power:SetReverseFill(settings.powerReverseFill and true or false)
                -- Reverse-fill direction is only final here; re-derive Fill Opacity state
                -- (ApplyPowerBarAlpha above ran before this SetReverseFill, so a direction
                -- change would otherwise leave the bg anchored to the wrong side).
                ApplyPowerBarAlpha(frame.Power, UnitToSettingsKey(unit))
                if frame.Power.ForceUpdate then frame.Power:ForceUpdate() end
                if unit == "player" then
                    ns.UF_SetupPowerCost(frame.Power, settings)
                    ns.UF_PowerValSync(frame)
                end
                if unit == "player" and ns.UF_ForeverFormBar then ns.UF_ForeverFormBar(frame, frame.Power, settings) end
                -- WoW Forever mana regen spark (EllesmereUI_ManaRegenSpark.lua):
                -- attached while the bar draws. Below SetReverseFill, which the
                -- attach lays the spark out from. Power paints report mana only
                -- while attached, so the bar's power type (PaintPower's) is
                -- reported first and the attach never arms from a stale one.
                if unit == "player" and EllesmereUI.ManaRegenSpark then
                    if settings.manaRegenSpark and ns.UF_PowerBarDraws(settings) then
                        local pt = EllesmereUI.GetPlayerPowerOverride() or UnitPowerType("player")
                        EllesmereUI.ManaRegenSpark.SetMana("uf", not issecretvalue(pt) and pt == Enum.PowerType.Mana)
                        EllesmereUI.ManaRegenSpark.Attach("uf", frame.Power,
                            settings.manaRegenSparkMode == "ticks")
                        frame.Power._manaRegenSpark = true
                    else
                        EllesmereUI.ManaRegenSpark.Detach("uf")
                        frame.Power._manaRegenSpark = nil
                    end
                end
            end

            -- Apply castbar reverse fill
            if frame.Castbar then
                frame.Castbar:SetReverseFill(settings.castReverseFill and true or false)
            end

            if frame.unifiedBorder then
                frame.unifiedBorder:ClearAllPoints()
                -- Mini frames (ToT/Focus Target/Pet) may override ONLY the border
                -- size per frame (settings.borderSizeOverride); color and texture
                -- still inherit from the donor. nil = inherit the donor size.
                -- Boss frames paint from ns.UF_BossBorderSettings: the donor's
                -- border until the boss Border Style leaves Inherit.
                -- ns.UF_FrameBorderPad mirrors this apply for size matching: change the two together.
                local bsrc = donorSettings
                if unit:match("^boss%d$") then bsrc = ns.UF_BossBorderSettings() end
                local bs = settings.borderSizeOverride or bsrc.borderSize or 1
                local bc = bsrc.borderColor or { r = 0, g = 0, b = 0 }
                local btex = bsrc.borderTexture or "solid"
                -- The donor's exact size rides along only while the size IS the
                -- donor's own; a per-frame override is a substitute step (legacy path).
                local bpx = nil
                if not settings.borderSizeOverride then
                    bpx = EllesmereUI.BorderPx(bsrc.borderSizePx, bs, btex)
                end
                PP.Point(frame.unifiedBorder, "TOPLEFT", frame, "TOPLEFT", 0, 0)
                PP.Point(frame.unifiedBorder, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
                EllesmereUI.ApplyBorderStyle(frame.unifiedBorder, bs, bc.r, bc.g, bc.b, bsrc.borderAlpha or 1, btex, bsrc.borderTextureOffset, bsrc.borderTextureOffsetY, bsrc.borderTextureShiftX, bsrc.borderTextureShiftY, "unitframes", bs, nil, bpx)
            end
            -- Boss Hover/Target border: the border was just restyled to its normal
            -- color above, so re-apply the hover/target recolor (both default off,
            -- so this repaints the same normal color unless the user enabled one).
            if unit:match("^boss%d$") then
                local isT = UnitIsUnit(unit, "target")
                frame._isTarget = (not issecretvalue(isT) and isT) and true or false
                ns.ApplyBossBorderState(frame)
            end

            -- Helper: set font on a FontString, using donor font for mini frames
            local function SetMiniFont(fs, sz)
                if not fs or not fs.SetFont then return end
                if isMiniFrame then
                    EllesmereUI.ApplyModuleFont(fs, donorFontPath, sz or 12, "unitFrames")
                else
                    SetFSFont(fs, sz)
                end
            end

            if frame.NameText then
                local s = isMiniFrame and donorSettings or GetSettingsForUnit(unit)
                local rts = s.leftTextSize or s.textSize or 12
                SetMiniFont(frame.NameText, rts)
                frame.NameText:SetWordWrap(false)
            end
            if frame.HealthValue then
                local s = isMiniFrame and donorSettings or GetSettingsForUnit(unit)
                local rts = s.rightTextSize or s.textSize or 12
                SetMiniFont(frame.HealthValue, rts)
                frame.HealthValue:SetWordWrap(false)
            end
            if frame.CenterText then
                local s = isMiniFrame and donorSettings or GetSettingsForUnit(unit)
                local cts = s.centerTextSize or s.textSize or 12
                SetMiniFont(frame.CenterText, cts)
                frame.CenterText:SetWordWrap(false)
            end

            -- Apply text tags and positions for mini frames
            if isMiniFrame and frame._applyTextTags then
                frame._applyTextTags(settings.leftTextContent or "name", settings.rightTextContent or "none", settings.centerTextContent or "none")
            end
            if isMiniFrame and frame._applyTextPositions then
                frame._applyTextPositions(settings)
            end

            if frame.Castbar then
                local s = isMiniFrame and donorSettings or settings
                if frame.Castbar.Text then
                    local snSz = s.castSpellNameSize or 11
                    SetMiniFont(frame.Castbar.Text, snSz)
                end
                if frame.Castbar.Time then
                    local dtSz = s.castDurationSize or 10
                    SetMiniFont(frame.Castbar.Time, dtSz)
                end
                -- Boss frames get their full cast text refresh in the boss branch above
                -- (colors/show/sides/bg). Two gaps remain: the donor-font line just above
                -- set boss cast text to the DONOR size, and that branch re-runs layout from
                -- CACHED offsets. Re-apply the size from boss settings (keeping the donor
                -- typeface) and sync X/Y offsets + side layout so live boss frames update
                -- on every cast-text option change.
                if unit:match("^boss") then
                    local cb = frame.Castbar
                    if cb.Text then SetMiniFont(cb.Text, settings.castSpellNameSize or 11) end
                    if cb.Time then SetMiniFont(cb.Time, settings.castDurationSize or 10) end
                    if cb.Target then SetMiniFont(cb.Target, settings.castSpellTargetSize or 11) end
                    if cb._syncOffsetsAndLayout then cb:_syncOffsetsAndLayout(settings) end
                end
            end
            end -- else (enabled frame processing)
        end
    end

    -- Refresh combat indicator on player + target frames after settings change
    for _, ciu in ipairs({ "player", "target" }) do
        local cif = frames[ciu]
        if cif and cif._applyCombatTexture then
            cif._applyCombatTexture()
            local ciDefStyle = (ciu == "player") and "standard" or "none"
            if (db.profile[ciu].combatIndicatorStyle or ciDefStyle) ~= "none" and UnitAffectingCombat(ciu) then
                cif._combatIndicator:Show()
            else
                cif._combatIndicator:Hide()
            end
        end
    end

    -- Refresh leader indicator on player frame after settings change
    if frames.player and frames.player._applyLeaderIndicator then
        frames.player._applyLeaderIndicator()
    end
    if frames.target and frames.target._applyLeaderIndicator then
        frames.target._applyLeaderIndicator()
    end

    -- Refresh elite/rare indicator on the target frame after settings change
    if frames.target and frames.target._applyEliteIndicator then
        frames.target._applyEliteIndicator()
    end
    -- Portrait Dragon on the player, target and focus frames, after every
    -- portrait above has its final size, shape and clip.
    ns.UF_ApplyPortraitDragons()

    -- Refresh faction indicator on the player and target frames after settings change
    if frames.player and frames.player._applyFactionIndicator then
        frames.player._applyFactionIndicator()
    end
    if frames.target and frames.target._applyFactionIndicator then
        frames.target._applyFactionIndicator()
    end
    -- Pet happiness icon (WoW Forever): enable, size, side and offsets.
    ns.UF_ApplyPetHappiness()

    ---------------------------------------------------------------------------
    --  Live-update raid target marker icon (size / alignment / X / Y / enabled)
    --  for player, target, focus, and boss frames.  Uses oUF's EnableElement /
    --  DisableElement so the RAID_TARGET_UPDATE event is properly toggled.
    ---------------------------------------------------------------------------
    local RAID_MARKER_UNITS = { "player", "target", "focus", "boss1", "boss2", "boss3", "boss4", "boss5" }
    for _, rmUnit in ipairs(RAID_MARKER_UNITS) do
        local rmFrame = frames[rmUnit]
        local icon = rmFrame and rmFrame._raidMarkerIcon
        if rmFrame and icon then
            local rmS = GetSettingsForUnit(rmUnit)
            local rmSize   = (rmS and rmS.raidMarkerSize)  or 28
            local rmAlign  = (rmS and rmS.raidMarkerAlign) or "right"
            local rmX      = (rmS and rmS.raidMarkerX)     or 0
            local rmY      = (rmS and rmS.raidMarkerY)     or 0
            local rmEnabled = rmS and rmS.raidMarkerEnabled
            local isBoss = rmUnit:match("^boss%d$")
            icon:SetSize(rmSize, rmSize)
            icon:ClearAllPoints()
            if isBoss then
                if rmAlign == "left" then
                    icon:SetPoint("RIGHT", rmFrame, "LEFT", rmX, rmY)
                elseif rmAlign == "center" then
                    icon:SetPoint("CENTER", rmFrame, "CENTER", rmX, rmY)
                else
                    icon:SetPoint("LEFT", rmFrame, "RIGHT", rmX, rmY)
                end
            else
                local rmAnchor = (rmAlign == "left") and "TOPLEFT"
                    or (rmAlign == "center") and "TOP"
                    or "TOPRIGHT"
                icon:SetPoint("CENTER", rmFrame, rmAnchor, rmX, rmY)
            end
            if rmEnabled then
                rmFrame.RaidTargetIndicator = icon
                rmFrame:EnableElement("RaidTargetIndicator")
                if icon.ForceUpdate then icon:ForceUpdate() end
            else
                rmFrame:DisableElement("RaidTargetIndicator")
                rmFrame.RaidTargetIndicator = nil
                icon:Hide()
            end
        end
    end

    -- Portrait settings (3D zoom, class style) used to live-apply through the ungated
    -- ambient repaints; the gated Override skips same-unit repaints, so settings
    -- changes now force one explicit portrait update per frame instead.
    for _, frame in pairs(frames) do
        if type(frame) == "table" and frame.Portrait and frame.Portrait.ForceUpdate then
            frame.Portrait:ForceUpdate()
        end
    end

    -- Blizzard Style: one final geometry/art pass over every frame, after all
    -- the per-unit re-anchors above (idempotent; nothing while the style is off).
    if ns.UF_Blizz() then
        for _, frame in pairs(frames) do
            if type(frame) == "table" and frame.Health and frame._euiBaseUnit then
                ns.UF_ApplyBlizzardLayout(frame, frame._euiBaseUnit)
            end
        end
    end
    -- WoW Forever: the combo point arc round its host frame's portrait, placed
    -- on the geometry the sweep just settled (returns at once everywhere else).
    ns.UF_ApplyForeverComboArc()

    -- Rounded corners (EllesmereUI_RoundedCorners.lua), on the settled
    -- geometry. The radius rides with the border source, like the border; a
    -- detached power bar rounds on its own with the same radius. An attached
    -- portrait joins with its own art only: the dragons on it reach past the
    -- frame and stay whole.
    for unit, frame in pairs(frames) do
        if type(unit) == "string" and type(frame) == "table" and frame.unifiedBorder then
            local isMini = (unit == "pet" or unit == "targettarget" or unit == "focustarget")
            local isBoss = unit:match("^boss%d$") and true or false
            local src = isBoss and ns.UF_BossBorderSettings()
                or (isMini and GetMiniDonorSettings(unit)) or GetSettingsForUnit(unit)
            local us = GetSettingsForUnit(unit)
            local radius = (not frame._blizzArtFrame and src and src.cornerRadius) or 0
            local corners = src and src.cornerMask
            local power = frame.Power
            local pp = us and us.powerPosition or "below"
            local det = pp == "detached_top" or pp == "detached_bottom"
            -- Join Power Bar: a detached bar right above or below the frame
            -- shares its outline (the frame keeps the far corners).
            local pCorners = corners
            if det and us.cornerJoinPower then
                local upper, lower = EllesmereUI.RoundedJoinCorners(corners)
                if pp == "detached_bottom" then corners, pCorners = upper, lower
                else corners, pCorners = lower, upper end
            end
            if radius > 0 then
                local ps = us and us.portraitStyle or profile.portraitStyle or "attached"
                local attached = ps == "attached" or ((isMini or isBoss) and ps == "detached")
                local bd = frame.Portrait and frame.Portrait.backdrop
                if not (attached and bd and bd:IsShown()) then bd = nil end
                local btb = frame.BottomTextBar
                EllesmereUI.RoundCorners(frame, radius, {
                    roots = { frame._barClip, btb and not btb._isDetached and btb or nil },
                    textures = { bd and bd._bg, bd and bd._2d, bd and bd._class },
                    border = frame.unifiedBorder,
                    clip = frame._barClip,
                    style = src.borderTexture or "solid",
                    corners = corners,
                })
            else
                EllesmereUI.RoundCorners(frame, 0)
            end
            if power then
                if det and radius > 0 then
                    EllesmereUI.RoundCorners(power, radius, {
                        border = power._pbBorder, style = us.powerBorderStyle or "solid",
                        corners = pCorners,
                    })
                else
                    EllesmereUI.RoundCorners(power, 0)
                end
            end
        end
    end

    -- Player Aura Bars resolve font path and outline flag at style-build time; every
    -- settings path landing here (fonts, profiles, options) forces one explicit
    -- re-skin of the default and custom bars, both change-guarded no-ops when nothing changed.
    if ns.PAB_Restyle then ns.PAB_Restyle() end
    -- Profile-grade resync: enable/useBlizzard modes, native frames, default
    -- movers, and a late build when a swap lands on an enabled profile from
    -- a disabled-at-login session. Cheap no-op when nothing changed.
    if ns.PAB_ProfileResync then ns.PAB_ProfileResync() end
    -- Reload-all also SWEEPS stale bar ids (a previous profile's bars must
    -- park on swap -- field report).
    if ns.PAB_ReloadAllCustomBars then ns.PAB_ReloadAllCustomBars() end
    -- Size matching: the unified borders were just applied, so report each
    -- frame's border pad; only a pad that really changed re-pushes its matches.
    if EllesmereUI.MatchPadChanged then
        local padKeys = ns.UF_PAD_KEYS
        for i = 1, #padKeys do EllesmereUI.MatchPadChanged(padKeys[i]) end
    end
end

-- The unit frames whose unified border can reach outside the frame (the
-- class resource bar has none, the boss stack is never size matched), and
-- the three cast bars (a Custom Border Style border, the Classic frame; the
-- cast bar pass runs inside the same reload sweep).
ns.UF_PAD_KEYS = { "player", "target", "focus", "pet", "targettarget", "focustarget",
    "playerCastbar", "targetCastbar", "focusCastbar" }

-- Size matching: the width and height the unit frame's textured border draws
-- OUTSIDE the frame, from exactly what the reload sweep's unified border apply
-- passes (the paint that lands last: the minis take the donor's border, and a
-- per-frame Border Size override drops the donor's exact size). The border
-- wraps the frame getSize measures. nil for a solid border, under the stock
-- looks (no EllesmereUI border), for the class resource bar and the boss
-- stack. Reads settings only. Change together with the sweep.
function ns.UF_FrameBorderPad(k)
    if k == "classPower" or k == "boss" or ns.UF_Blizz() then return nil end
    local settings = GetSettingsForUnit(k)
    if not settings then return nil end
    local isMini = (k == "pet" or k == "targettarget" or k == "focustarget")
    local d = isMini and GetMiniDonorSettings(k) or settings
    local btex = d.borderTexture or "solid"
    if btex == "solid" then return nil end
    local bs = settings.borderSizeOverride or d.borderSize or 1
    local bpx = nil
    if not settings.borderSizeOverride then
        bpx = EllesmereUI.BorderPx(d.borderSizePx, bs, btex)
    end
    return EllesmereUI.BorderMatchPad(bs, btex, d.borderTextureOffset, d.borderTextureOffsetY,
        d.borderTextureShiftX, d.borderTextureShiftY, "unitframes", bs, bpx, nil, d.borderAlpha or 1)
end

I.ReloadFrames = ReloadFrames
