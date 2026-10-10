if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_UnitFrames_Unlock.lua
--
--  Unit frame movers for Unlock Mode. RegisterUFUnlockElements is published
--  as I.RegisterUFUnlockElements for EUI_UnitFrames_Lifecycle.lua (EnableBody
--  calls it). db is set through I.dbSetters.
-------------------------------------------------------------------------------
local _, ns = ...

local PP = EllesmereUI.PP

local I = ns._internals
local frames, GetSettingsForUnit, GetFrameDimensions = I.frames, I.GetSettingsForUnit, I.GetFrameDimensions
local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end

-------------------------------------------------------------------------------
--  Register unit frame elements with Unlock Mode. Called synchronously from
--  OnEnable (right after InitializeFrames) so registration lands inside the
--  PLAYER_LOGIN pre-lockdown window on a combat reload -- timers never fire
--  during the loading screen, so a deferred registration would land after
--  combat lockdown re-engaged, leaving anchored unit frames unpositionable
--  until combat dropped.
-------------------------------------------------------------------------------
local function RegisterUFUnlockElements()
    if EllesmereUI and EllesmereUI.RegisterUnlockElements then
        local MK = EllesmereUI.MakeUnlockElement
        local UNIT_LABELS = {
            player = "Player", target = "Target", focus = "Focus",
            pet = "Pet", targettarget = "Target of Target",
            focustarget = "Focus Target", boss = "Boss Frames",
            classPower = "Class Resource",
            playerCastbar = "Player Frame Mini Cast Bar",
            targetCastbar = "Target Cast Bar",
            focusCastbar = "Focus Cast Bar",
        }
        local elements = {}
        local orderBase = 100

        local function Rebuild() ns.ReloadFrames() end

        -- Which frame's Visibility governs each mover (the minis follow their
        -- parent, and so does a class resource bar unlocked from the player frame).
        local MOVER_VIS_OF = { pet = "player", targettarget = "target",
                               focustarget = "focus", classPower = "player" }
        local function MakeUFElement(key, order)
            return MK({
                key = key,
                label = UNIT_LABELS[key] or key,
                group = "Unit Frames",
                order = orderBase + order,
                -- Blizzard Style frames are the stock size: no resize handles or
                -- Width/Height fields (Frame Scale in the options instead).
                noResize = (ns.UF_Blizz() and key ~= "classPower" and not key:find("Castbar", 1, true)) or nil,
                -- Only the look fixes the size: size matches to and from the
                -- frame stay stored for the EllesmereUI look (the cast bars keep
                -- following the visible art meanwhile), and spec layouts never
                -- bank the look's size as the frame's own.
                sizeFixedByLook = (ns.UF_Blizz() and key ~= "classPower") or nil,
                -- Visibility "never" keeps the frame built but never on screen, so
                -- there is nothing to drag. Re-read on each unlock-mode open, so
                -- lifting it (a spec override, the dropdown) needs no /reload. The
                -- minis and an unlocked class resource bar have no Visibility of
                -- their own and ride the frame they follow; Always Show Pet opts out.
                isHidden = function()
                    if key == "pet" and db.profile.pet and db.profile.pet.alwaysShow then
                        return false
                    end
                    return ns.VisEffective(db.profile[MOVER_VIS_OF[key] or key]) == "never"
                end,
                getFrame = function(k)
                    if k == "boss" then return frames["boss1"] end
                    if k == "classPower" then return frames._classPowerBar end
                    return frames[k]
                end,
                getSize = function(k)
                    if k == "classPower" then
                        if frames._classPowerBar then
                            local w = frames._classPowerBar:GetWidth()
                            local h = frames._classPowerBar:GetHeight()
                            if w < 10 then w = 120 end
                            if h < 5 then h = 14 end
                            return w, h
                        end
                        return 120, 14
                    end
                    local w, h = GetFrameDimensions((k == "boss") and "boss1" or k)
                    -- Blizzard Style: sizes (and so size matches) are the
                    -- visible art, not the stock box's transparent padding.
                    if ns.UF_Blizz() then
                        local l, r, t, b = ns.UF_BlizzVis((k == "boss") and frames.boss1 or frames[k])
                        if l then return w - l - r, h - t - b end
                    end
                    return w, h
                end,
                -- The size the unit's own settings give (the EllesmereUI look),
                -- for code that must never take the style's stock size for it.
                getSettingSize = function(k)
                    if k == "classPower" then return nil end
                    return GetFrameDimensions((k == "boss") and "boss1" or k, true)
                end,
                -- Blizzard Style: the mover outlines the visible art.
                getInsets = function(k)
                    if not ns.UF_Blizz() then return nil end
                    return ns.UF_BlizzVis((k == "boss") and frames.boss1 or frames[k])
                end,
                -- Size matching: what a textured border draws outside the frame
                -- (nil for a solid border, the stock looks, class resource, boss).
                getMatchPad = ns.UF_FrameBorderPad,
                -- Extra height the unlock overlay should extend BELOW the frame.
                -- Boss frames have a castbar anchored under the frame (not a
                -- separate movable element like the player/target cast bars), so
                -- the overlay grows down to wrap it. Other units return 0.
                getBottomExtra = function(k)
                    if k ~= "boss" then return 0 end
                    local b = db.profile.boss
                    if b and b.showCastbar ~= false then return b.castbarHeight or 14 end
                    return 0
                end,
                -- Blizzard Style: stock frame sizes, so new width/height matches are refused
                -- and unlock resizes never write frameWidth/healthHeight into the EUI-look settings.
                matchUnavailable = function()
                    if ns.UF_Blizz() then
                        return EllesmereUI.L("Size matching is unavailable with Blizzard Style Unit Frames.")
                    end
                end,
                setWidth = function(k, w)
                    if k == "classPower" then return end
                    if ns.UF_Blizz() then return end
                    if not EllesmereUI._unlockActive and not EllesmereUI._propagatingMatch
                       and not EllesmereUI._unlockLayerApplying then Rebuild(); return end
                    local unit = (k == "boss") and "boss1" or k
                    local s = GetSettingsForUnit(unit)
                    if not s then return end
                    local wPStyle = s.portraitStyle or db.profile.portraitStyle or "attached"
                    local showPortrait = wPStyle ~= "none" and s.showPortrait ~= false
                    local isAttached = wPStyle == "attached"
                    if showPortrait and isAttached then
                        local pSizeAdj = s.portraitSize or 0
                        if not isAttached then pSizeAdj = pSizeAdj + 10 end
                        local powerPos = s.powerPosition or "below"
                        local powerIsAtt = (powerPos == "below" or powerPos == "above")
                        local ptH = s.healthHeight + (powerIsAtt and (s.powerHeight or 6) or 0)
                        local adjPH = ptH + pSizeAdj
                        if adjPH < 8 then adjPH = 8 end
                        s.frameWidth = math.max(PP.Snap(w - adjPH), 50)
                    else
                        s.frameWidth = math.max(PP.Snap(w), 50)
                    end
                    Rebuild()
                end,
                setHeight = function(k, h)
                    if k == "classPower" then return end
                    if ns.UF_Blizz() then return end
                    if not EllesmereUI._unlockActive and not EllesmereUI._propagatingMatch
                       and not EllesmereUI._unlockLayerApplying then Rebuild(); return end
                    local unit = (k == "boss") and "boss1" or k
                    local s = GetSettingsForUnit(unit)
                    if not s then return end
                    local powerPos = s.powerPosition or "below"
                    local powerIsAtt = (powerPos == "below" or powerPos == "above")
                    local powerH = powerIsAtt and (s.powerHeight or 6) or 0
                    local btbPos = s.btbPosition or "bottom"
                    local btbIsAtt = (btbPos == "top" or btbPos == "bottom")
                    local btbH = (s.bottomTextBar and btbIsAtt) and (s.bottomTextBarHeight or 16) or 0
                    s.healthHeight = math.max(PP.Snap(h - powerH - btbH), 8)
                    Rebuild()
                end,
                loadPos = function(k)
                    local pos = db.profile.positions[k]
                    if not pos then return nil end
                    return { point = pos.point, relPoint = pos.relPoint or pos.point, x = pos.x, y = pos.y }
                end,
                savePos = function(k, point, relPoint, x, y)
                    db.profile.positions[k] = { point = point, relPoint = relPoint, x = x, y = y }
                    if EllesmereUI._unlockActive then return end
                    if k == "boss" then
                        local spacing = ns.UF_BossSpacing()
                        local bossStackDir = db.profile.boss and db.profile.boss.bossStackDirection or "down"
                        -- boss1 to UIParent; chain 2..5 from the previous boss.
                        if frames.boss1 then
                            frames.boss1:ClearAllPoints()
                            frames.boss1:SetPoint(point, UIParent, relPoint, ns.UF_ScaledOffsets(frames.boss1, x, y))
                        end
                        for i = 2, 5 do
                            local bf = frames["boss" .. i]
                            local prev = frames["boss" .. (i - 1)]
                            if bf and prev then
                                bf:ClearAllPoints()
                                if bossStackDir == "up" then
                                    bf:SetPoint("TOPLEFT", prev, "TOPLEFT", 0, spacing)
                                else
                                    bf:SetPoint("TOPLEFT", prev, "TOPLEFT", 0, -spacing)
                                end
                            end
                        end
                    elseif k == "classPower" then
                        if frames._classPowerBar then
                            frames._classPowerBar:ClearAllPoints()
                            frames._classPowerBar:SetPoint(point, UIParent, relPoint, x, y)
                        end
                    else
                        local fr = frames[k]
                        if fr then
                            fr:ClearAllPoints()
                            fr:SetPoint(point, UIParent, relPoint, ns.UF_ScaledOffsets(fr, x, y))
                        end
                    end
                end,
                clearPos = function(k)
                    db.profile.positions[k] = nil
                end,
                applyPos = function(k)
                    local pos = db.profile.positions[k]
                    if not pos then return end
                    -- Unlock-anchored elements: the anchor system is the position
                    -- authority. Only bootstrap from the saved standalone position
                    -- while the frame has no bounds yet (first placement); otherwise
                    -- leave it alone so the anchor position is never clobbered.
                    local anchored = EllesmereUI.IsUnlockAnchored
                        and EllesmereUI.IsUnlockAnchored(k)
                    local pt = pos.point
                    local rpt = pos.relPoint or pt
                    local px, py = pos.x, pos.y
                    local PPa = EllesmereUI and EllesmereUI.PP
                    -- Helper: snap (x, y) for a frame using SnapCenterForDim for
                    -- CENTER anchors and SnapForES otherwise. CENTER snap needs
                    -- the frame's actual size to handle odd-pixel-dim frames
                    -- correctly (cy must be integer + 0.5 for odd heights).
                    local function SnapForFrame(fr, x, y)
                        if not PPa or not fr or not x or not y then return x, y end
                        local es = fr:GetEffectiveScale()
                        local isCenterAnchor = (pt == "CENTER")
                            and (rpt == "CENTER")
                        if isCenterAnchor and PPa.SnapCenterForDim then
                            return PPa.SnapCenterForDim(x, fr:GetWidth() or 0, es),
                                   PPa.SnapCenterForDim(y, fr:GetHeight() or 0, es)
                        elseif PPa.SnapForES then
                            return PPa.SnapForES(x, es), PPa.SnapForES(y, es)
                        end
                        return x, y
                    end
                    if k == "boss" then
                        local spacing = ns.UF_BossSpacing()
                        local bossStackDir = db.profile.boss and db.profile.boss.bossStackDirection or "down"
                        if frames.boss1 and not (anchored and frames.boss1:GetLeft()) then
                            local bx, by = SnapForFrame(frames.boss1, ns.UF_ScaledOffsets(frames.boss1, pos.x, pos.y))
                            frames.boss1:ClearAllPoints()
                            frames.boss1:SetPoint(pt, UIParent, rpt, bx, by)
                        end
                        for i = 2, 5 do
                            local bf = frames["boss" .. i]
                            local prev = frames["boss" .. (i - 1)]
                            if bf and prev then
                                bf:ClearAllPoints()
                                if bossStackDir == "up" then
                                    bf:SetPoint("TOPLEFT", prev, "TOPLEFT", 0, spacing)
                                else
                                    bf:SetPoint("TOPLEFT", prev, "TOPLEFT", 0, -spacing)
                                end
                            end
                        end
                    elseif k == "classPower" then
                        local cpb = frames._classPowerBar
                        if cpb and not (anchored and cpb:GetLeft()) then
                            px, py = SnapForFrame(cpb, px, py)
                            cpb:ClearAllPoints()
                            cpb:SetPoint(pt, UIParent, rpt, px, py)
                        end
                    else
                        local fr = frames[k]
                        if fr and not (anchored and fr:GetLeft()) then
                            px, py = SnapForFrame(fr, ns.UF_ScaledOffsets(fr, px, py))
                            fr:ClearAllPoints()
                            fr:SetPoint(pt, UIParent, rpt, px, py)
                        end
                    end
                end,
            })
        end

        -- Core unit frames. Only register a mover for units that actually use
        -- the EllesmereUI frame; a unit set to Blizzard-default or Hidden has no
        -- EUI frame to move.
        local function AddUFElement(u, order)
            if ns.GetUnitFrameSource(u) == "eui" then
                elements[#elements + 1] = MakeUFElement(u, order)
            end
        end
        AddUFElement("player", 1)
        AddUFElement("target", 2)
        AddUFElement("focus", 3)
        AddUFElement("pet", 4)
        AddUFElement("targettarget", 5)
        AddUFElement("focustarget", 6)
        if ns.GetUnitFrameSource("boss") == "eui" then
            local bossElem = MakeUFElement("boss", 7)
            -- Boss is a stack of 5 chained frames; resize / match actions don't make
            -- sense on the aggregate element. Boss can still anchor to other elements;
            -- it just can't be used as an anchor target.
            bossElem.noResize       = true   -- removes Width/Height Match + resize handles
            bossElem.noAnchorTarget = true   -- others cannot anchor to boss
            elements[#elements + 1] = bossElem
        end

        -- Conditional elements. WoW Forever: the style that builds
        -- (ns.UF_ForeverCPStyle; a rogue under the EllesmereUI look reads its
        -- own), not the shared showClassPowerBar.
        local cpShown = db.profile.player.showClassPowerBar
        if ns.UF_ForeverCPStyle then
            cpShown = ns.UF_ForeverCPStyle(db.profile.player.classPowerStyle or "none") ~= "none"
        end
        if ns.GetUnitFrameSource("player") == "eui" and cpShown and not db.profile.player.lockClassPowerToFrame then
            elements[#elements + 1] = MakeUFElement("classPower", 9)
        end

        -- Cast bar elements: standalone registration, no special-case branching
        local function MakeCastBarElement(cbKey, unitKey, order)
            local function GetCBFrame()
                local uf = frames[unitKey]
                return uf and uf.Castbar and uf.Castbar:GetParent()
            end
            local function GetCBSettings()
                if unitKey == "player" then return db.profile.player end
                return GetSettingsForUnit(unitKey)
            end
            local function GetWidthKey()
                return unitKey == "player" and "playerCastbarWidth" or "castbarWidth"
            end
            local function GetHeightKey()
                return unitKey == "player" and "playerCastbarHeight" or "castbarHeight"
            end
            return MK({
                key = cbKey,
                label = UNIT_LABELS[cbKey] or cbKey,
                group = "Unit Frames",
                order = orderBase + order,
                getFrame = function() return GetCBFrame() end,
                -- Blizzard Style: the holder carries the layout aspect (see
                -- ns.UF_CastbarAspectTemplate), so the mover cannot anchor to
                -- it and takes the same screen spot by absolute anchor.
                detachedMover = (ns.UF_Blizz() and ns.UF_LayoutAspectOK()) or nil,
                isHidden = function()
                    -- Live show/hide: mirror the per-unit cast bar enable setting
                    -- (player defaults off; target/focus default on). The mover is
                    -- gated on each unlock-mode open, so toggling the setting takes
                    -- effect without a /reload.
                    local s = GetCBSettings()
                    if not s then return true end
                    if ns.VisEffective(s) == "never" then return true end
                    if unitKey == "player" then return not s.showPlayerCastbar end
                    return s.showCastbar == false
                end,
                getSize = function()
                    -- Return stored DB values so cog menu shows what the
                    -- user typed, not the pixel-snapped frame size.
                    local s = GetCBSettings()
                    if s then
                        local w = s[GetWidthKey()] or 181
                        local h = s[GetHeightKey()] or 14
                        return w, h
                    end
                    return 100, 14
                end,
                -- Classic WoW UI: the vanilla frame's rim outside the holder
                -- (icon included, the frame wraps both), so a width or height
                -- match lines up with what is on screen. The EllesmereUI look:
                -- a Custom Border Style cast border's reach (nil while off).
                getMatchPad = function()
                    if ns.UF_Style() ~= "classic" then
                        return ns.UF_CastBorderPad(unitKey, GetCBSettings())
                    end
                    local CF = EllesmereUI.ClassicFrame
                    if not CF then return nil end
                    local s = GetCBSettings()
                    return CF.Pad(CF.ScaleK(s and s[ns.UF_CastClassicKey(unitKey)]), false)
                end,
                setWidth = function(_, w)
                    local s = GetCBSettings()
                    if not s then return end
                    local newW = math.max(PP.Snap(w), 30)
                    s[GetWidthKey()] = newW
                    local f = GetCBFrame()
                    -- Stored height, not the live one: a holder on the Blizzard
                    -- Style aura block reads back a secret rect.
                    if f then PP.Size(f, newW, s[GetHeightKey()] or 14) end
                end,
                setHeight = function(_, h)
                    if not EllesmereUI._unlockActive and not EllesmereUI._unlockLayerApplying then return end
                    local s = GetCBSettings()
                    if not s then return end
                    local newH = math.max(PP.Snap(h), 5)
                    s[GetHeightKey()] = newH
                    local f = GetCBFrame()
                    if f then PP.Size(f, s[GetWidthKey()] or 181, newH) end
                    local uf = frames[unitKey]
                    local cbar = uf and uf.Castbar
                    if cbar and cbar._blizzCast then
                        -- Blizzard Style: the icon spans the bar and its text box.
                        cbar._icoSide = newH
                        ns.UF_BlizzCastIcon(cbar)
                    elseif cbar and cbar._blizzFrame and ns.UF_BLIZZ.cast then
                        -- Classic kit: the vanilla frame's overhangs scale with
                        -- the height, so the whole cast pass re-runs.
                        cbar._icoSide = newH
                        ns.UF_ApplyBlizzCastbar(cbar)
                    elseif cbar and cbar._iconFrame then
                        cbar._iconFrame:SetSize(newH, newH)
                    end
                end,
                loadPos = function()
                    local pos = db.profile.positions[cbKey]
                    if not pos then return nil end
                    return { point = pos.point, relPoint = pos.relPoint or pos.point, x = pos.x, y = pos.y }
                end,
                savePos = function(_, point, relPoint, x, y)
                    db.profile.positions[cbKey] = { point = point, relPoint = relPoint, x = x, y = y }
                    if EllesmereUI._unlockActive then return end
                    local f = GetCBFrame()
                    if f then
                        f:ClearAllPoints()
                        f:SetPoint(point, UIParent, relPoint, x, y)
                    end
                end,
                clearPos = function()
                    db.profile.positions[cbKey] = nil
                end,
                applyPos = function()
                    local pos = db.profile.positions[cbKey]
                    if not pos then return end
                    local f = GetCBFrame()
                    if not f then return end
                    -- Unlock-anchored castbars: the anchor system owns the
                    -- position (castbars are anchored to their unit frame by
                    -- default). Only bootstrap while the frame has no bounds.
                    if EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored(cbKey)
                       and f:GetLeft() then
                        return
                    end
                    local pt, rpt = pos.point, pos.relPoint or pos.point
                    local px, py = pos.x, pos.y
                    local PPa = EllesmereUI and EllesmereUI.PP
                    if PPa and px and py then
                        local es = f:GetEffectiveScale()
                        local isCenterAnchor = (pt == "CENTER") and (rpt == "CENTER")
                        if isCenterAnchor and PPa.SnapCenterForDim then
                            px = PPa.SnapCenterForDim(px, f:GetWidth() or 0, es)
                            py = PPa.SnapCenterForDim(py, f:GetHeight() or 0, es)
                        elseif PPa.SnapForES then
                            px = PPa.SnapForES(px, es)
                            py = PPa.SnapForES(py, es)
                        end
                    end
                    f:ClearAllPoints()
                    f:SetPoint(pt, UIParent, rpt, px or 0, py or 0)
                end,
            })
        end

        -- Always register all three cast bars; visibility is gated live via each
        -- element's isHidden (mirrors the show setting), so toggling a cast bar
        -- on/off takes effect on the next unlock-mode open -- no /reload needed.
        if ns.GetUnitFrameSource("player") == "eui" then
            elements[#elements + 1] = MakeCastBarElement("playerCastbar", "player", 10)
        end
        if ns.GetUnitFrameSource("target") == "eui" then
            elements[#elements + 1] = MakeCastBarElement("targetCastbar", "target", 11)
        end
        if ns.GetUnitFrameSource("focus") == "eui" then
            elements[#elements + 1] = MakeCastBarElement("focusCastbar", "focus", 12)
        end

        EllesmereUI:RegisterUnlockElements(elements, "EllesmereUIUnitFrames")
        -- First sighting of each frame's border pad: the login reload ran before
        -- these elements existed, so without it the first border change after
        -- login would only be recorded, never re-pushed.
        if EllesmereUI.MatchPadChanged then
            local padKeys = ns.UF_PAD_KEYS
            for i = 1, #padKeys do EllesmereUI.MatchPadChanged(padKeys[i]) end
        end

        -- Seed default anchor + width-match for castbars so they start anchored to
        -- their parent frame with matched width out of the box. Only seed if the user
        -- has NEVER configured this castbar in unlock mode (tracked by
        -- _castbarUnlockSeeded); once they have, stop overwriting their choices.
        if EllesmereUIDB then
            if not EllesmereUIDB.unlockAnchors then EllesmereUIDB.unlockAnchors = {} end
            if not EllesmereUIDB.unlockWidthMatch then EllesmereUIDB.unlockWidthMatch = {} end
            if not EllesmereUIDB._castbarUnlockSeeded then EllesmereUIDB._castbarUnlockSeeded = {} end
            local CB_DEFAULTS = {
                { cb = "playerCastbar", parent = "player" },
                { cb = "targetCastbar", parent = "target" },
                { cb = "focusCastbar",  parent = "focus" },
            }
            local cbPositions = db and db.profile and db.profile.positions
            for _, def in ipairs(CB_DEFAULTS) do
                if not EllesmereUIDB._castbarUnlockSeeded[def.cb] then
                    -- Skip seeding if the user already has a saved position
                    -- (they moved the cast bar freely without anchoring)
                    local hasPos = cbPositions and cbPositions[def.cb]
                    if not hasPos then
                        if not EllesmereUIDB.unlockAnchors[def.cb] then
                            EllesmereUIDB.unlockAnchors[def.cb] = { target = def.parent, side = "BOTTOM" }
                        end
                        if not EllesmereUIDB.unlockWidthMatch[def.cb] then
                            EllesmereUIDB.unlockWidthMatch[def.cb] = def.parent
                        end
                    end
                    -- Mark as seeded so we never overwrite user changes
                    EllesmereUIDB._castbarUnlockSeeded[def.cb] = true
                end
            end
        end
    end
end

I.RegisterUFUnlockElements = RegisterUFUnlockElements
