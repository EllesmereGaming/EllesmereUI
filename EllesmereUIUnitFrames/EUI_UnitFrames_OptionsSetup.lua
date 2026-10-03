if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_UnitFrames_OptionsSetup.lua
--
--  SetupOptionsPanel, run one frame after the frames build: publishes the ns
--  fields the options pages read (ns.db, ns.frames, ns.ReloadFrames, ...) and
--  builds the boss frame preview. Reads the main file through ns and
--  ns._internals; db is set through I.dbSetters.
-------------------------------------------------------------------------------
local _, ns = ...

local PP = EllesmereUI.PP

local I = ns._internals
local frames, ApplyFramePosition, GetFrameDimensions = I.frames, I.ApplyFramePosition, I.GetFrameDimensions
local ReloadFrames, ResolveFontPath, ApplyDarkTheme = I.ReloadFrames, I.ResolveFontPath, I.ApplyDarkTheme
local ApplyBlizzCastbarState, ApplyUnitFrameCastColor = I.ApplyBlizzCastbarState, I.ApplyUnitFrameCastColor
local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end

function SetupOptionsPanel()
    ns.db = db
    ns.frames = frames

    -- Live Enable Boss Frames for the EUI source. The boss frames spawn at login
    -- only, so the enable toggle used to be a silent no-op in the ON->OFF
    -- direction: PromptReloadIfUnspawned only prompts when frames are MISSING,
    -- and nothing hid the live frames -- they kept showing on every boss for the
    -- rest of the session (field report 2026-08-13; Blizzard source toggled live,
    -- hence "only works on Blizzard default"). The unit watch is the show/hide
    -- authority (RegisterUnitWatch at spawn), so toggling it IS the live enable/
    -- disable; frames never spawned this session still fall through to the
    -- reload prompt in the options setter. Watch/Hide writes on these secure
    -- frames are lockdown-blocked: in combat, park a one-shot that re-applies
    -- the CURRENT setting at regen (reads the profile at fire time, so the last
    -- click wins and stacked toggles collapse to one apply).
    function ns.UF_SetBossFramesActive(on)
        if InCombatLockdown() then
            ns.CombatQueue.Defer("BossFramesActive", function()
                ns.UF_SetBossFramesActive(db.profile.enabledFrames.boss ~= false)
            end)
            return
        end
        for i = 1, 5 do
            local f = frames["boss" .. i]
            if f then
                if on then
                    RegisterUnitWatch(f)
                else
                    UnregisterUnitWatch(f)
                    f:Hide()
                end
            end
        end
    end
    ns.ApplyFramePosition = ApplyFramePosition
    ns.GetFrameDimensions = GetFrameDimensions
    local reloadPending = false
    local reloadThrottle = CreateFrame("Frame")
    reloadThrottle:Hide()
    -- Realise a classPowerStyle that changed through a path which never calls
    -- _toggleClassPower (a Spec Override applying at login, a profile switch, an
    -- import). Gated on an actual change because the toggle is a full teardown
    -- and rebuild; running it every reload would thrash the bar.
    local RealiseClassPowerStyle
    RealiseClassPowerStyle = function()
        if not frames._toggleClassPower then return end
        local wantCP = db.profile.player.classPowerStyle or "none"
        -- WoW Forever: compare the style that builds, not the saved one (the
        -- toggle keeps the saved style and builds its effective style).
        local builtCP = wantCP
        if ns.UF_ForeverCPStyle then builtCP = ns.UF_ForeverCPStyle(wantCP) end
        if builtCP == frames._classPowerBuiltStyle then return end
        -- The toggle reparents Blizzard's class power frame and re-anchors the
        -- health bar. The throttle body keeps running after ReloadFrames()'s
        -- lockdown return (same shape as the UpdateFrameVisibility note in InitializeFrames),
        -- so this needs its own guard plus a regen re-run to re-arm the pass.
        if InCombatLockdown() then
            ns.CombatQueue.Defer("RealiseClassPowerStyle", RealiseClassPowerStyle)
            return
        end
        frames._toggleClassPower(wantCP)
    end
    reloadThrottle:SetScript("OnUpdate", function(self)
        self:Hide()
        reloadPending = false
        ReloadFrames()
        ApplyBlizzCastbarState()
        -- Hide While Using Gamepad: a profile switch or spec override changes
        -- the saved toggles without calling the options setter.
        ns.UF_ApplyGamepadCastbar()
        -- A reload restyles the boss frames and re-colors their health to the
        -- player's class color (preview rides on unit="player") + re-tags the name.
        -- Re-assert the preview (red color + fake name) so a settings change doesn't
        -- revert it. Secret-safe: no health values are read.
        if ns._bossPreviewActive and ns.SetBossPreview then ns.SetBossPreview(true) end
        -- ReloadFrames rebuilds frames but never touches the top-level wrapper/3D-
        -- portrait alpha, so recompute the out-of-combat fade here. Without this, a
        -- profile/spec swap (or first switch to a 3D portrait, whose PlayerModel is
        -- created at alpha 1) leaves player/target/focus stuck at the old opacity
        -- until the next combat/target/zone event. Safe from the throttle:
        -- UpdateFrameVisibility guards its restricted Show/Hide behind
        -- InCombatLockdown, and SetAlpha is unrestricted.
        if ns.UpdateFrameVisibility then ns.UpdateFrameVisibility() end
        -- 12.1 aura containers reload with every real pass (direct call --
        -- ns.ReloadFrames is just the throttle-arming stub, so wrapping it
        -- from the container file is timing-unreliable).
        if ns.UF_ReloadAllAuraContainers then ns.UF_ReloadAllAuraContainers() end
        -- Class power: _toggleClassPower is the only thing that honours a
        -- classPowerStyle change, and options + the spec watcher are its only
        -- other callers -- styles changed by overrides, profile switch, or
        -- import land here.
        RealiseClassPowerStyle()
        -- Threat watchers: a profile switch or spec override changes the
        -- saved toggles without calling their setters.
        ns.SyncPlayerThreat()
        if ns.SyncThreatPct then ns.SyncThreatPct() end
    end)
    ns.ReloadFrames = function()
        if not reloadPending then
            reloadPending = true
            reloadThrottle:Show()
        end
    end
    _G._EUF_ReloadFrames = ns.ReloadFrames

    -- Fake debuff icons for the boss preview. Three square icons anchored where the
    -- real Debuffs frame would live, sized to match the Simple Debuff Display layout
    -- (frame bar height, growing right-to-left off the frame's left edge). Created on
    -- demand and torn down on preview disable.
    local FAKE_DEBUFF_SPELLS = { 122, 172, 1714 }  -- Frost Nova, Corruption, Curse of Tongues
    local FAKE_DEBUFF_STACKS = { [2] = 3 }          -- one fake stack (icon 2 only)
    local FAKE_DEBUFF_FRACS  = { 0.35, 0.62, 0.88 } -- static fake swipe fraction remaining
    local FAKE_DEBUFF_SECS   = { 8, 15, 23 }         -- static fake duration-text seconds
    -- Preview-only: a fake aura icon wears the boss aura border settings (the ring
    -- the live buttons' style builds, drawn through the same eight-slice path;
    -- the owned border frame doubles as its texture cache). Blizzard Style keeps
    -- the plain 1 px ring the preview always drew. On ns: this function sits at
    -- the Lua 5.1 local ceiling.
    ns.BossPreviewAuraBorder = function(border, settings)
        if ns.UF_Blizz and ns.UF_Blizz() then
            if PP and PP.CreateBorder then PP.CreateBorder(border, 0, 0, 0, 1) end
            return
        end
        local size = settings.auraBorderSize or 1
        local tex = settings.auraBorderTexture or "solid"
        if ns.UF_BossAuraBorderAboveEffects(settings) then
            border:SetFrameLevel(border:GetParent():GetFrameLevel() + 20)
        end
        EllesmereUI.ApplySecretSafeBorderStyle(border, border, size,
            settings.auraBorderR or 0, settings.auraBorderG or 0, settings.auraBorderB or 0, settings.auraBorderA or 1,
            tex, settings.auraBorderTextureOffset, settings.auraBorderTextureOffsetY,
            settings.auraBorderTextureShiftX, settings.auraBorderTextureShiftY,
            "unitframes", size, nil, EllesmereUI.BorderPx(settings.auraBorderSizePx, size, tex))
    end
    local function AttachFakeDebuffs(frame)
        -- Tear down any prior holder so size/anchor refresh on every call.
        if frame._previewDebuffs then
            frame._previewDebuffs:Hide()
            frame._previewDebuffs:SetParent(nil)
            frame._previewDebuffs = nil
        end
        -- Suppress the real (player-unit) debuffs while the fake overlay is up so
        -- the preview shows exactly the fake set. Restored by ReloadFrames when
        -- the preview is disabled.
        if ns.UF_HideAuraContainers then ns.UF_HideAuraContainers(frame) end
        local settings = db.profile.boss or {}
        local simpleMode = ns.GetBossSimpleDebuffMode(settings)
        local simple = simpleMode ~= "none"
        -- No debuffs shown at all (Simple Debuff Display None + Debuffs Location
        -- None): the prior holder was already torn down above, so bail without
        -- drawing any fake debuffs (mirrors AttachFakeBuffs' none guard).
        if not simple and (settings.debuffAnchor or "bottomleft") == "none" then return end
        local dOffX = settings.debuffOffsetX or 0
        local dOffY = settings.debuffOffsetY or 0
        -- Simple mode uses its own X/Y offsets (falling back to the regular
        -- debuff offsets for existing users) so the preview matches live.
        if simple then dOffX, dOffY = ns.GetBossSimpleDebuffOffset(settings) end
        local powerPos = settings.powerPosition or "below"
        local powerIsAtt = (powerPos == "below" or powerPos == "above")
        local powerH = powerIsAtt and (settings.powerHeight or 0) or 0
        local iconSize
        if simple then
            -- Pixel-snap so the preview icon matches the frame's snapped height
            -- exactly (== frame:GetHeight()), same as the live boss debuffs.
            iconSize = PP.Scale((settings.healthHeight or 34) + powerH)
        else
            iconSize = settings.debuffSize or 22
        end
        local count = #FAKE_DEBUFF_SPELLS
        local gap = 1
        -- Inter-icon spacing from the configured slider (physical pixels). `gap`
        -- stays at 1 for the holder-to-frame edge offset (matches the runtime).
        local iconGap = PP.FromPixels(ns.GetBossDebuffSpacing(settings, simple))
        local holder = CreateFrame("Frame", nil, frame)
        holder:SetSize(iconSize * count + iconGap * (count - 1), iconSize)
        -- Above the unified border so it sits BEHIND the preview debuffs, matching
        -- the live boss aura layering. The border FRAME is frame+10 but its solid
        -- PP border textures live on a sub-container at frame+11, so clear that
        -- (frame+13 also clears the class-icon holder at frame+12).
        holder:SetFrameLevel(frame:GetFrameLevel() + 13)
        holder:ClearAllPoints()
        -- The boss cast bar lives as a sibling parented to the frame but
        -- anchored BELOW frame bottom, so frame:GetHeight() excludes it.
        -- Mirror the live runtime behavior where bottom-anchored debuffs
        -- push down by the cast bar height to avoid overlap.
        local castBg = frame.Castbar and frame.Castbar:GetParent()
        local castbarH = (settings.showCastbar ~= false and castBg)
                         and castBg:GetHeight() or 0
        if simple then
            -- Simple mode: align debuff stack with the health bar top so
            -- they never encroach on the cast bar area. Left grows off the
            -- frame's left edge; Right grows off the right edge.
            if simpleMode == "right" then
                holder:SetPoint("TOPLEFT", frame, "TOPRIGHT", 1 + dOffX, dOffY)
            else
                holder:SetPoint("TOPRIGHT", frame, "TOPLEFT", -1 + dOffX, dOffY)
            end
        else
            local dAnc = settings.debuffAnchor or "bottomleft"
            if dAnc == "topleft" then
                holder:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0 + dOffX, gap + dOffY)
            elseif dAnc == "topright" then
                holder:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0 + dOffX, gap + dOffY)
            elseif dAnc == "bottomleft" then
                holder:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0 + dOffX, -gap - castbarH + dOffY)
            elseif dAnc == "bottomright" then
                holder:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0 + dOffX, -gap - castbarH + dOffY)
            elseif dAnc == "right" then
                holder:SetPoint("LEFT", frame, "RIGHT", gap + dOffX, 0 + dOffY)
            else  -- "left" or fallback
                holder:SetPoint("RIGHT", frame, "LEFT", -gap + dOffX, 0 + dOffY)
            end
        end
        -- Cooldown-text + stack settings, mode-aware so the preview mirrors the
        -- live boss aura buttons (simple keys in Simple Debuff Display, regular
        -- debuff keys otherwise).
        local showCD, cdSize, cdOffX, cdOffY
        if simple then
            showCD = settings.simpleDebuffShowCooldownText
            cdSize = settings.simpleDebuffCooldownTextSize or 14
            cdOffX = settings.simpleDebuffCooldownTextOffsetX or 0
            cdOffY = settings.simpleDebuffCooldownTextOffsetY or 0
        else
            showCD = settings.debuffShowCooldownText
            cdSize = settings.debuffCooldownTextSize or 10
            cdOffX = settings.debuffCooldownTextOffsetX or 0
            cdOffY = settings.debuffCooldownTextOffsetY or 0
        end
        local stackSize = settings.debuffStackTextSize or 14
        local stackOffX = settings.debuffStackTextOffsetX or 0
        local stackOffY = settings.debuffStackTextOffsetY or 0
        local stackPos = settings.debuffStackTextPosition
        local cdTextColor = settings.debuffCooldownTextColor or {r=1, g=1, b=1}
        local stackTextColor = settings.debuffStackTextColor or {r=1, g=1, b=1}
        local fontPath = (EllesmereUI.GetFontPath("unitFrames")) or "Fonts\\FRIZQT__.TTF"
        local now = GetTime()
        for idx, spellID in ipairs(FAKE_DEBUFF_SPELLS) do
            local iconFrame = CreateFrame("Frame", nil, holder)
            iconFrame:SetSize(iconSize, iconSize)
            if simpleMode == "right" then
                iconFrame:SetPoint("LEFT", holder, "LEFT", (idx - 1) * (iconSize + iconGap), 0)
            else
                iconFrame:SetPoint("RIGHT", holder, "RIGHT", -(idx - 1) * (iconSize + iconGap), 0)
            end
            iconFrame:SetFrameLevel(holder:GetFrameLevel())
            local icon = iconFrame:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints()
            local tex = GetSpellTexture and GetSpellTexture(spellID)
                     or (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID))
            if tex then icon:SetTexture(tex) end
            local z = settings.debuffIconZoom or 0.07
            icon:SetTexCoord(z, 1 - z, z, 1 - z)
            -- Static fake cooldown swipe: a huge duration parked at a fixed fraction so
            -- the wedge never visibly moves. Native countdown numbers stay hidden; the
            -- duration text below is a manual static FontString instead.
            local cd = CreateFrame("Cooldown", nil, iconFrame, "CooldownFrameTemplate")
            cd:SetAllPoints(iconFrame)
            -- Swipe sits above the border (border at +1, PP container at +2) so
            -- the layering matches the live boss aura buttons.
            cd:SetFrameLevel(iconFrame:GetFrameLevel() + 3)
            cd:SetDrawEdge(false)
            cd:SetDrawBling(false)
            cd:SetReverse(false)
            cd:SetDrawSwipe(true)
            cd:SetSwipeColor(0, 0, 0, 0.6)
            cd:SetHideCountdownNumbers(true)
            local frac = FAKE_DEBUFF_FRACS[idx] or 0.6
            cd:SetCooldown(now - 3600 * (1 - frac), 3600)
            -- Text host above the swipe AND the border container so the
            -- duration/stack text renders over the icon border, not under it.
            local textHost = CreateFrame("Frame", nil, iconFrame)
            textHost:SetAllPoints(iconFrame)
            textHost:SetFrameLevel(iconFrame:GetFrameLevel() + (ns.UF_BossAuraBorderAboveEffects(settings) and 25 or 4))
            local durText = textHost:CreateFontString(nil, "OVERLAY")
            durText:SetDrawLayer("OVERLAY", 7)
            EllesmereUI.ApplyIconTextFont(durText, fontPath, cdSize, "unitFrames")
            durText:SetPoint("CENTER", iconFrame, "CENTER", cdOffX, cdOffY)
            durText:SetTextColor(cdTextColor.r, cdTextColor.g, cdTextColor.b)
            durText:SetText(FAKE_DEBUFF_SECS[idx] or 10)
            if not showCD then durText:Hide() end
            -- Stack text on a single icon only (looks natural; most debuffs are
            -- unstacked). Driven by the Stack Size / Stack X / Stack Y controls.
            if FAKE_DEBUFF_STACKS[idx] then
                local stack = textHost:CreateFontString(nil, "OVERLAY")
                stack:SetDrawLayer("OVERLAY", 7)
                EllesmereUI.ApplyIconTextFont(stack, fontPath, stackSize, "unitFrames")
                ns.ApplyStackAnchor(stack, iconFrame, stackPos, stackOffX, stackOffY)
                stack:SetTextColor(stackTextColor.r, stackTextColor.g, stackTextColor.b)
                stack:SetText(FAKE_DEBUFF_STACKS[idx])
            end
            -- Border just above the icon; its PP container renders at border+1
            -- (iconFrame+2), below the swipe and text host so both stay on top.
            local border = CreateFrame("Frame", nil, iconFrame)
            border:SetAllPoints(icon)
            border:SetFrameLevel(iconFrame:GetFrameLevel() + 1)
            ns.BossPreviewAuraBorder(border, settings)
        end
        frame._previewDebuffs = holder
    end
    local function DetachFakeDebuffs(frame)
        if frame._previewDebuffs then frame._previewDebuffs:Hide() end
    end

    -- Fake buff icons for the boss preview. Two square icons anchored where the
    -- real Buffs frame would live, sized to the buff size. Created on demand and
    -- torn down on preview disable. Capped at 2 regardless of Max Count.
    local FAKE_BUFF_SPELLS = { 21562, 1459 }  -- Power Word: Fortitude, Arcane Intellect
    local function AttachFakeBuffs(frame)
        if frame._previewBuffs then
            frame._previewBuffs:Hide()
            frame._previewBuffs:SetParent(nil)
            frame._previewBuffs = nil
        end
        -- Suppress the real (player-unit) buffs while preview is up. Restored by
        -- ReloadFrames when the preview is disabled.
        if ns.UF_HideAuraContainers then ns.UF_HideAuraContainers(frame) end
        local settings = db.profile.boss or {}
        local simpleMode = ns.GetBossSimpleBuffMode(settings)
        local simple = simpleMode ~= "none"
        -- Simple Buff Display overrides Buffs Location, so only bail on the
        -- location/visibility guards when simple mode is off.
        if not simple and (settings.showBuffs == false or (settings.buffAnchor or "topleft") == "none") then return end
        local anchor = settings.buffAnchor or "topleft"
        local bOffX = settings.buffOffsetX or 0
        local bOffY = settings.buffOffsetY or 0
        -- Simple mode uses its own X/Y offsets (falling back to the regular buff
        -- offsets for existing users) so the preview matches live.
        if simple then bOffX, bOffY = ns.GetBossSimpleBuffOffset(settings) end
        local powerPos = settings.powerPosition or "below"
        local powerIsAtt = (powerPos == "below" or powerPos == "above")
        local powerH = powerIsAtt and (settings.powerHeight or 0) or 0
        local iconSize
        if simple then
            -- Pixel-snap so the preview icon matches the frame's snapped height
            -- exactly (== frame:GetHeight()), same as the live boss buffs.
            iconSize = PP.Scale((settings.healthHeight or 34) + powerH)
        else
            iconSize = settings.buffSize or 22
        end
        local count = #FAKE_BUFF_SPELLS
        local gap = 1
        -- Inter-icon spacing from the configured slider (physical pixels). `gap`
        -- stays at 1 for the holder-to-frame edge offset (matches the runtime).
        local iconGap = PP.FromPixels(ns.GetBossBuffSpacing(settings, simple))
        local holder = CreateFrame("Frame", nil, frame)
        holder:SetSize(iconSize * count + iconGap * (count - 1), iconSize)
        -- Above the unified border so it sits BEHIND the preview buffs, matching
        -- the live boss aura layering. The border FRAME is frame+10 but its solid
        -- PP border textures live on a sub-container at frame+11, so clear that
        -- (frame+13 also clears the class-icon holder at frame+12).
        holder:SetFrameLevel(frame:GetFrameLevel() + 13)
        holder:ClearAllPoints()
        local castBg = frame.Castbar and frame.Castbar:GetParent()
        local castbarH = (settings.showCastbar ~= false and castBg)
                         and castBg:GetHeight() or 0
        if simple then
            -- Align the column with the health bar top, side-based (matches the
            -- live runtime + Simple Debuff Display).
            if simpleMode == "right" then
                holder:SetPoint("TOPLEFT", frame, "TOPRIGHT", 1 + bOffX, bOffY)
            else
                holder:SetPoint("TOPRIGHT", frame, "TOPLEFT", -1 + bOffX, bOffY)
            end
        elseif anchor == "topleft" then
            holder:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0 + bOffX, gap + bOffY)
        elseif anchor == "topright" then
            holder:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0 + bOffX, gap + bOffY)
        elseif anchor == "bottomleft" then
            holder:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0 + bOffX, -gap - castbarH + bOffY)
        elseif anchor == "bottomright" then
            holder:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0 + bOffX, -gap - castbarH + bOffY)
        elseif anchor == "right" then
            holder:SetPoint("LEFT", frame, "RIGHT", gap + bOffX, 0 + bOffY)
        else  -- "left" or fallback
            holder:SetPoint("RIGHT", frame, "LEFT", -gap + bOffX, 0 + bOffY)
        end
        for idx, spellID in ipairs(FAKE_BUFF_SPELLS) do
            local iconFrame = CreateFrame("Frame", nil, holder)
            iconFrame:SetSize(iconSize, iconSize)
            if simple and simpleMode == "left" then
                -- Left mode grows leftward from the right edge of the holder.
                iconFrame:SetPoint("RIGHT", holder, "RIGHT", -(idx - 1) * (iconSize + iconGap), 0)
            else
                iconFrame:SetPoint("LEFT", holder, "LEFT", (idx - 1) * (iconSize + iconGap), 0)
            end
            iconFrame:SetFrameLevel(holder:GetFrameLevel())
            local icon = iconFrame:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints()
            local tex = GetSpellTexture and GetSpellTexture(spellID)
                     or (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID))
            if tex then icon:SetTexture(tex) end
            local z = settings.buffIconZoom or 0.07
            icon:SetTexCoord(z, 1 - z, z, 1 - z)
            local border = CreateFrame("Frame", nil, iconFrame)
            border:SetAllPoints(icon)
            border:SetFrameLevel(iconFrame:GetFrameLevel() + 1)
            ns.BossPreviewAuraBorder(border, settings)
        end
        frame._previewBuffs = holder
    end
    local function DetachFakeBuffs(frame)
        if frame._previewBuffs then frame._previewBuffs:Hide() end
    end

    -- Fake static cast bar for the boss preview (boss2 only). This drives the
    -- REAL cast bar so it is 100% identical to a live cast: it disables the oUF
    -- Castbar element (so oUF never resets our frozen state), then shows the bar
    -- with a fixed mid-cast fill + spell name / timer / icon and the active-cast
    -- tint -- the same state OnCastbarCastActive produces during a real cast.
    local FAKE_CAST_SPELL_NAME = "Shadow Bolt"
    local FAKE_CAST_SPELL_ICON = 136197
    local function DetachFakeCastBar(frame)
        if not frame._fakeCastActive then return end
        frame._fakeCastActive = nil
        local castbar = frame.Castbar
        local castbarBg = castbar and castbar:GetParent()
        if castbar then
            if castbar.castTintLayer then
                castbar.castTintLayer:SetAlpha(0)
                castbar._castTintOn = nil
            end
            castbar:Hide()
        end
        if castbarBg then castbarBg:Hide() end
        -- The real Castbar element is re-enabled by ReloadFrames when the preview
        -- is turned off, so no manual re-enable is needed here.
    end
    local function AttachFakeCastBar(frame)
        local castbar = frame.Castbar
        local castbarBg = castbar and castbar:GetParent()
        if not castbar or not castbarBg then return end
        local settings = db.profile.boss or {}
        if settings.showCastbar == false then
            castbarBg:Hide()
            return
        end
        -- Suppress the real Castbar element so oUF can't reset the frozen cast.
        if frame:IsElementEnabled("Castbar") then frame:DisableElement("Castbar") end
        castbar._eufSettings = settings
        -- Frozen mid-cast fill (respects the configured reverse-fill direction).
        castbar:SetMinMaxValues(0, 1)
        castbar:SetValue(0.65)
        if castbar.Text then castbar.Text:SetText(FAKE_CAST_SPELL_NAME) end
        if castbar.Time then
            if settings.showCastDuration == false then
                castbar.Time:SetText(""); castbar.Time:Hide()
            else
                castbar.Time:Show(); castbar.Time:SetText("1.8")
            end
        end
        if castbar.Icon then
            castbar.Icon:SetTexture(FAKE_CAST_SPELL_ICON)
            -- SetTexture resets the crop; re-apply the cast icon's fixed zoom.
            castbar.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        -- Active-cast tint -- same path a real cast uses.
        if castbar.castTintLayer then
            castbar.castTintLayer:SetAlpha(castbar._fillOp or 1)
            castbar._castTintOn = true
            ApplyUnitFrameCastColor(castbar)
        end
        castbarBg:Show()
        castbar:Show()
        if castbar._iconFrame then
            if settings.showCastIcon == false then castbar._iconFrame:Hide()
            else castbar._iconFrame:Show() end
        end
        if castbar._layoutTextZones then castbar:_layoutTextZones() end
        frame._fakeCastActive = true
    end

    -- Refresh the in-game boss preview's fake auras when boss settings that affect them
    -- (simpleDebuffs, debuffAnchor, debuffSize, buffAnchor, etc.) change.
    ns.RefreshBossPreviewDebuffs = function()
        if not ns._bossPreviewActive then return end
        for i = 1, 3 do
            local f = frames["boss" .. i]
            if f then
                AttachFakeDebuffs(f); AttachFakeBuffs(f)
                -- Only the 2nd boss frame shows a sample cast bar.
                if i == 2 then AttachFakeCastBar(f) end
            end
        end
    end

    -- Apply / clear a hostile-red health bar override on a boss frame while
    -- preview is active. Real boss frames never class-color (no player class),
    -- so piggybacking on unit="player" would otherwise paint the bar in the
    -- user's class color -- wrong for a preview.
    local PREVIEW_HEALTH_RED_R, PREVIEW_HEALTH_RED_G, PREVIEW_HEALTH_RED_B = 0.8, 0.2, 0.2

    -- Fake boss names for the preview. Generated once per activation (stable
    -- across reloads), regenerated on a fresh activation. Health is intentionally
    -- NOT faked: the health max is a secret value in Midnight and cannot be read
    -- or compared, so the bar keeps the player's real (filled) health.
    local PREVIEW_BOSS_NAMES = {
        "The Lich King", "Ragnaros", "Kel'Thuzad", "Archimonde", "Kil'jaeden",
        "Deathwing", "Yogg-Saron", "C'Thun", "Cenarius", "Varimathras",
    }
    local function GenBossPreviewNames()
        local pool = {}
        for i = 1, #PREVIEW_BOSS_NAMES do pool[i] = PREVIEW_BOSS_NAMES[i] end
        for i = #pool, 2, -1 do
            local j = math.random(i)
            pool[i], pool[j] = pool[j], pool[i]
        end
        return { pool[1], pool[2], pool[3] }
    end

    -- Override the name fontstring with a fake boss name. Its text zone is
    -- parked so the engine's text painter stops overwriting it; SetText with a
    -- literal string is secret-safe. Restored on clear.
    local function BossPreviewNameFS(f)
        local s = db.profile.boss
        local lc = (s and s.leftTextContent) or "name"
        local rc = (s and s.rightTextContent) or "perhp"
        local cc = (s and s.centerTextContent) or "none"
        if lc == "name" then return f.LeftText end
        if rc == "name" then return f.RightText end
        if cc == "name" then return f.CenterText end
        return nil
    end
    local function ApplyBossPreviewName(f, name)
        local fs = BossPreviewNameFS(f)
        if not fs then return end
        f._previewNameFS = fs
        local zones = f._euiTextZones
        if zones and not fs._previewSavedZone then
            for i = #zones, 1, -1 do
                if zones[i].fs == fs then
                    fs._previewSavedZone = table.remove(zones, i)
                    break
                end
            end
        end
        fs:SetText(name)
    end
    local function ClearBossPreviewName(f)
        local fs = f._previewNameFS
        if not fs then return end
        if fs._previewSavedZone then
            local zones = f._euiTextZones
            if not zones then zones = {}; f._euiTextZones = zones end
            zones[#zones + 1] = fs._previewSavedZone
            fs._previewSavedZone = nil
        end
        f._previewNameFS = nil
        if ns.UF_PaintText then ns.UF_PaintText(f, f._euiUnit) end
    end

    local function ApplyBossPreviewColor(f)
        local h = f.Health
        if not h then return end
        f._previewColorSaved = f._previewColorSaved or {
            colorClass       = h.colorClass,
            colorReaction    = h.colorReaction,
            colorTapped      = h.colorTapped,
            colorDisconnected= h.colorDisconnected,
        }
        -- Color the fake boss frames exactly as a real boss frame would: Dark Mode
        -- dark fill/bg, or a Custom Colored Fill, via ApplyDarkTheme (both leave
        -- colorClass off). The ONE exception: where a real frame would show the live
        -- unit's class/reaction color (ApplyDarkTheme leaves colorClass ON), our fake
        -- unit is the player with no boss classification -- substitute the red
        -- preview color instead of the player's class color.
        ApplyDarkTheme(h)
        if h.colorClass then
            h.colorClass = false
            h.colorReaction = false
            h.colorTapped = false
            h.colorDisconnected = false
            h:SetStatusBarColor(PREVIEW_HEALTH_RED_R, PREVIEW_HEALTH_RED_G, PREVIEW_HEALTH_RED_B)
            -- oUF's own update may re-color on the next tick; this PostUpdate keeps
            -- the override sticky for the duration of the preview.
            h.PostUpdateColor = function(self) self:SetStatusBarColor(PREVIEW_HEALTH_RED_R, PREVIEW_HEALTH_RED_G, PREVIEW_HEALTH_RED_B) end
        end
    end
    local function ClearBossPreviewColor(f)
        local h = f.Health
        if not h then return end
        local s = f._previewColorSaved
        if s then
            h.colorClass = s.colorClass
            h.colorReaction = s.colorReaction
            h.colorTapped = s.colorTapped
            h.colorDisconnected = s.colorDisconnected
            f._previewColorSaved = nil
        end
        h.PostUpdateColor = nil
    end

    -- Re-apply the boss preview colors after a Dark Mode change: the dark refresher
    -- repaints every frame via ApplyDarkTheme, which would drop our red class-color
    -- substitute. Called from the dark-mode refresher while the preview is active.
    ns._ReapplyBossPreviewColor = function()
        for i = 1, 3 do
            local f = frames["boss" .. i]
            if f then ApplyBossPreviewColor(f) end
        end
    end

    -- Boss preview: force boss1/2/3 to render with the player's unit data so
    -- the user can see the boss frame styling live in-game without a real
    -- encounter. Gated out of combat to avoid taint; caller is responsible
    -- for auto-clearing on EUI options window close.
    ns.SetBossPreview = function(enabled)
        if InCombatLockdown() then return false end
        ns._bossPreviewActive = enabled and true or false
        if enabled and not ns._bossPreviewNames then
            ns._bossPreviewNames = GenBossPreviewNames()
        end
        for i = 1, 3 do
            local f = frames["boss" .. i]
            if f then
                if enabled then
                    f:SetAttribute("unit", "player")
                    f:Show()
                    ApplyBossPreviewColor(f)
                    if f.UpdateAllElements then f:UpdateAllElements("BossPreview") end
                    -- After UpdateAllElements re-tags the name, override it with a fake boss name.
                    ApplyBossPreviewName(f, (ns._bossPreviewNames and ns._bossPreviewNames[i]) or PREVIEW_BOSS_NAMES[i] or "Boss")
                    AttachFakeDebuffs(f)
                    AttachFakeBuffs(f)
                    -- Only the 2nd boss frame shows a sample cast bar.
                    if i == 2 then AttachFakeCastBar(f) end
                else
                    ClearBossPreviewColor(f)
                    ClearBossPreviewName(f)
                    f:SetAttribute("unit", "boss" .. i)
                    if not UnitExists("boss" .. i) then f:Hide() end
                    if f.UpdateAllElements then f:UpdateAllElements("BossPreview") end
                    DetachFakeDebuffs(f)
                    DetachFakeBuffs(f)
                    DetachFakeCastBar(f)
                end
            end
        end
        if not enabled then
            ns._bossPreviewNames = nil
            -- Restore the real Buffs/Debuffs elements (and their anchors/counts)
            -- that the fake overlay disabled while preview was active.
            if ns.ReloadFrames then ns.ReloadFrames() end
        end
        return true
    end
    ns.ResolveFontPath = ResolveFontPath

    -- Trigger the EllesmereUI options module registration now that ns.db is ready
    if ns._InitEUIModule then
        ns._InitEUIModule()
    end

    -- Player Aura Bars build here, the first point ns.db is known to exist,
    -- in a tick of their own: the container build is insecure work whose
    -- cost scales with the bar count, so it keeps its own watchdog budget
    -- instead of riding this execution (login budget split rule).
    if ns.PAB_CreateBars then C_Timer.After(0, ns.PAB_CreateBars) end
end
