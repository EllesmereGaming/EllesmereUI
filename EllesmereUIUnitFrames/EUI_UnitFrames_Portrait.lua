if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_UnitFrames_Portrait.lua
--
--  Class icons, the portrait and raid icon painters, masks and art, detached
--  shapes, CreatePortrait and SwapPortraitMode. Publishes through I; loads
--  before Layout and Builders, which re-import. db is set via I.dbSetters.
-------------------------------------------------------------------------------
local _, ns = ...

local math_max = math.max
local issecretvalue = issecretvalue
local PP = EllesmereUI.PP

local I = ns._internals
local frames, UnsnapTex = I.frames, I.UnsnapTex
local GetSettingsForUnit, UnitToSettingsKey = I.GetSettingsForUnit, I.UnitToSettingsKey
local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end

local UF_ICONS_PATH = "Interface\\AddOns\\EllesmereUI\\media\\icons\\"
local CLASS_FULL_SPRITE_BASE = UF_ICONS_PATH .. "class-full\\"
local CLASS_FULL_COORDS = EllesmereUI.CLASS_ICON_SPRITE_COORDS

-- Apply a class icon from the sprite sheet. mirror = true swaps the cell's
-- left/right coords (Mirror Portrait); the coords are written on every paint.
local function ApplyClassIconTexture(tex, classToken, style, mirror)
    local coords = CLASS_FULL_COORDS[classToken]
    if not coords then return false end
    tex:SetTexture(CLASS_FULL_SPRITE_BASE .. style .. ".tga")
    if mirror then
        tex:SetTexCoord(coords[2], coords[1], coords[3], coords[4])
    else
        tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    end
    return true
end

-- Class art for a player unit. A readable token paints the pack's sprite cell.
-- A secret one (identity-restricted players, e.g. enemies in instanced PvP)
-- cannot key the sprite table, so the stock class atlas carries it: a secret
-- string concatenates to a secret string and SetAtlas takes secrets from addon
-- code, so the class is never read in Lua. SetAtlas keeps the texture's
-- coords (a sprite cell or the question-mark crop from an earlier paint) and
-- applies them inside the atlas, so they reset first; the next readable paint
-- re-asserts file and coords. Returns false when there is no class to paint.
-- mirror = true (Mirror Portrait) flips both lanes: the reset before SetAtlas
-- is the flipped one, and the sprite cell's left/right coords swap.
function ns.UF_PaintClassIcon(tex, unit, style, mirror)
    local _, ct = UnitClass(unit)
    if issecretvalue(ct) then
        if mirror then
            tex:SetTexCoord(1, 0, 0, 1)
        else
            tex:SetTexCoord(0, 1, 0, 1)
        end
        tex:SetAtlas("classicon-" .. ct)
        return true
    end
    if not ct then return false end
    return ApplyClassIconTexture(tex, ct, style, mirror)
end


-- What a non-player shows on a Class art frame: "2d", "none" or "3d". s = the
-- frame's own settings (its base unit's table). "2d" unless the frame opted in
-- (portraitNonPlayerOn), and under a stock style (it owns the portrait). "3d"
-- (a real mode swap, SwapPortraitMode) also falls back to "2d" while the
-- portrait is hidden (no model built), has a masked Detached shape (a model
-- cannot be masked) or sits on a mini frame (its fade never reaches a model).
function ns.UF_ClassFallback(s)
    if not (s and s.portraitNonPlayerOn) or ns.UF_Blizz() then return "2d" end
    local v = s.portraitNonPlayer or "2d"
    if v == "3d" then
        local style = s.portraitStyle
        local p = db.profile
        if s.showPortrait == false or style == "none"
            or (style == "detached" and (s.detachedPortraitShape or "portrait") ~= "none")
            or s == p.targettarget or s == p.focustarget or s == p.pet then
            return "2d"
        end
    end
    return v
end

-- Class art frames only (the class object, or a model shown as the fallback):
-- true when the live unit needs the other object, plus the resolved fallback
-- for a non-player. A model on a frame not set to Class is a genuine 3D
-- portrait. No unit, no swap.
function ns.UF_ClassFallbackNeedsSwap(frame, unit)
    local p = frame.Portrait
    if not (unit and p and (p.isClass or p.is2D == false)) then return false end
    local uKey = UnitToSettingsKey(frame._euiBaseUnit or unit)
    local s = uKey and db.profile[uKey]
    if p.isClass then
        -- Not opted in: the fallback is "2d" and the class object stays.
        if not (s and s.portraitNonPlayerOn) then return false, "2d" end
    elseif ((s and s.portraitMode) or db.profile.portraitMode or "2d") ~= "class" then
        return false
    end
    if not UnitExists(unit) then return false end
    local fb = not UnitIsPlayer(unit) and ns.UF_ClassFallback(s) or nil
    if p.isClass then return fb == "3d", fb end
    return fb ~= "3d", fb
end

-- Mirror angles (degrees) for playable-race models, whether used by a player or NPC.
-- Non-playable NPC models are excluded.
-- Unlisted/missing/restricted IDs stay normal; never infer facing from unit type.
do
    local mirrorAngles -- Built only when portrait mirroring first needs a model ID.
    local function GetMirrorAngle(id)
        if issecretvalue(id) or type(id) ~= "number" or id <= 0 then return end
        if not mirrorAngles then
            mirrorAngles = {
                -- Playable-race model IDs.
                [118355] = 291, [118135] = 291, [1838560] = 291, [1838562] = 291, [878772] = 291,
                [950080] = 291, [116921] = 291, [1100258] = 291, [1839709] = 291, [117170] = 291,
                [1100087] = 291, [1853408] = 291, [1890763] = 291, [1892825] = 291, [1890765] = 291,
                [1892543] = 291, [117437] = 291, [1022598] = 291, [1822372] = 291, [117721] = 291,
                [1005887] = 291, [1839253] = 291, [119063] = 291, [940356] = 291, [1838564] = 291,
                [119159] = 291, [900914] = 291, [1838566] = 291, [119369] = 291, [1838568] = 291,
                [119376] = 291, [1838570] = 291, [1630402] = 291, [1859379] = 291, [1630218] = 291,
                [1858265] = 291, [119563] = 291, [1000764] = 291, [1838572] = 291, [1842700] = 291,
                [119940] = 291, [1011653] = 291, [1838385] = 291, [1886724] = 291, [1721003] = 291,
                [1593999] = 291, [1825438] = 291, [1620605] = 291, [1839042] = 291, [2564806] = 291,
                [2622502] = 291, [1810676] = 291, [1858099] = 291, [1814471] = 291, [1857801] = 291,
                [120590] = 291, [921844] = 291, [1838574] = 291, [120791] = 291, [974343] = 291,
                [1838576] = 291, [121087] = 291, [949470] = 291, [1838580] = 291, [121287] = 291,
                [917116] = 291, [1838578] = 291, [1968587] = 291, [1968838] = 291, [1087591] = 291,
                [1088030] = 291, [589715] = 291, [1853610] = 291, [535052] = 291, [1853956] = 291,
                [121608] = 291, [997378] = 291, [1838582] = 291, [121768] = 291, [959310] = 291,
                [1838584] = 291, [121961] = 291, [986648] = 291, [1839008] = 291, [122055] = 291,
                [968705] = 291, [1838586] = 291, [122414] = 291, [1018060] = 291, [1838588] = 291,
                [122560] = 291, [1022938] = 291, [1838590] = 291, [1733758] = 291, [1859345] = 291,
                [1734034] = 291, [1858367] = 291, [1890759] = 291, [1890761] = 291, [307453] = 291,
                [1838201] = 291, [307454] = 291, [1838592] = 291, [1662187] = 291, [1894572] = 291,
                [1630447] = 291, [1900779] = 291, [4395382] = 291, [4207724] = 291, [4220448] = 291,
                [7478494] = 291, [7478487] = 291,
            }
        end
        return mirrorAngles[id]
    end

    -- 2D textures have no model ID: the portrait's hidden, lazy 3D frame loads
    -- the unit once per GUID and the answer is cached (ns.UF_ForgetPortraitMirror
    -- drops it on UNIT_MODEL_CHANGED, so forms and transforms check again). A
    -- model whose file is not resolved yet stays loaded until OnModelLoaded, then
    -- onReady(guid) lets the portrait repaint its flip. Secret GUIDs are not
    -- cached. The model is our own frame, so its fields are ours to use.
    local verdict, verdictCount = {}, 0
    local function Release(model)
        model._mirPending, model._mirReady = nil, nil
        -- Shown = a 3D portrait now owns the model: leave it loaded.
        if not model:IsShown() then model:ClearModel() end
        model:SetKeepModelOnHide(false)
    end
    local function Store(key, v)
        if verdict[key] == nil then
            if verdictCount >= 500 then wipe(verdict); verdictCount = 0 end
            verdictCount = verdictCount + 1
        end
        verdict[key] = v
    end
    local function Resolve(model, key)
        local v = GetMirrorAngle(model:GetModelFileID()) ~= nil
        local ready = model._mirReady
        Release(model)
        Store(key, v)
        if ready then ready(key) end
        return v
    end
    local function OnModelLoaded(model)
        local key = model._mirPending
        if not key then return end
        if model:IsShown() then Release(model); return end
        Resolve(model, key)
    end
    function ns.UF_CanMirrorPortrait2D(model, unit, onReady)
        -- IDs may be secret: only type() and issecretvalue() ever test them.
        local guid = UnitGUID(unit)
        local key = (not issecretvalue(guid)) and guid or nil
        if key then
            local v = verdict[key]
            if v ~= nil then return v end
            -- This unit's load is still in flight: take the answer if it is in.
            if model._mirPending == key then
                if type(model:GetModelFileID()) == "nil" then return false end
                model._mirReady = nil
                return Resolve(model, key)
            end
        end
        if model._mirPending then Release(model) end
        model:SetKeepModelOnHide(true)
        model:ClearModel()
        model:SetUnit(unit)
        local id = model:GetModelFileID()
        if type(id) == "nil" and key and onReady then
            model._mirPending, model._mirReady = key, onReady
            if not model._mirHooked then
                model._mirHooked = true
                model:HookScript("OnModelLoaded", OnModelLoaded)
            end
            return false
        end
        local v = GetMirrorAngle(id) ~= nil
        Release(model)
        if key and type(id) ~= "nil" then Store(key, v) end
        return v
    end
    function ns.UF_ForgetPortraitMirror(unit)
        local guid = UnitGUID(unit)
        if not issecretvalue(guid) and guid and verdict[guid] ~= nil then
            verdict[guid] = nil
            verdictCount = verdictCount - 1
        end
    end

    function ns.UF_ApplyPortraitRotation(model, mirror)
        local angle = mirror and GetMirrorAngle(model:GetModelFileID())
        if not angle then
            -- Clear the previous target's transform when switching to a creature,
            -- losing the model ID, showing a question mark, or disabling mirroring.
            if model._portraitMirrored then
                model:SetViewTranslation(0, 0)
                model:SetRotation(0, false)
                model._portraitMirrored = nil
            end
            return
        end
        -- Reapply after every model reload, even when the angle has not changed.
        model:SetViewTranslation(15, 0)
        model:SetRotation(math.rad(angle), false)
        model._portraitMirrored = true
    end
end

-- Shared portrait element Override (2D texture and 3D model objects; class texture
-- keeps its own). The vendored oUF Update only guid-gates the eventless OnUpdate poll,
-- so every other trigger (onShow, target-changed sweeps, any unit event) repaints
-- unconditionally, re-running SetPortraitTexture + the re-anchor PostUpdate for the
-- SAME unit in heavy combat. This Override repaints only when identity/availability
-- changed, on real appearance events (same-guid model/portrait-file changes), or on an
-- explicit ForceUpdate (mode swaps). Secret guids (instanced-PvP identities) can't be
-- compared, so they fail open to repainting. No unitIsUnit head-check (secret booleans
-- on eventless frames; the gate keeps repaint-on-any-event dispatch cheap). PostUpdate
-- runs only after a real repaint: 2D heals what SetPortraitTexture resets, 3D
-- re-applies zoom after SetUnit -- nothing to heal without a repaint.
-- fallback: the class lane's resolved non-player fallback, when the painter has it.
local PortraitOverride  -- forward declaration; painter registrations below the definition
local SwapPortraitMode  -- forward declaration; the portrait painter swaps through it
function PortraitOverride(self, event, evtUnit, fallback)
    local element = self.Portrait
    if not element then return end
    local u = self._euiUnit
    if not u then return end
    if element.PreUpdate then element:PreUpdate(u) end
    local isAvailable = UnitIsConnected(u) and UnitIsVisible(u)
    local guid = UnitGUID(u)
    local changed
    if issecretvalue(guid) or issecretvalue(element.guid) then
        changed = true
    else
        changed = element.guid ~= guid
    end
    local isModel = element:IsObjectType("PlayerModel")
    local hasStateChanged = changed
        or element.state ~= isAvailable
        or event == "UNIT_PORTRAIT_UPDATE"
        -- 3D portraits must reload on model changes. The opted-in 2D mirror
        -- eligibility check below also uses this event; ordinary 2D art uses
        -- UNIT_PORTRAIT_UPDATE / PORTRAITS_UPDATED.
        or (event == "UNIT_MODEL_CHANGED" and isModel)
        or event == "ForceUpdate"
        -- Unit swaps (vehicle enter/exit) always repaint: the swap moment can
        -- paint before the new unit's art/model streams in, and nothing with
        -- a changed guid follows.
        or event == "UnitChanged"
        -- World transitions can reset PlayerModel widget state at the same guid;
        -- repaint once per zone so 3D portraits never come back blank.
        or event == "PLAYER_ENTERING_WORLD"
        -- The repaint above runs mid-loading-screen, where SetPortraitTexture
        -- has no portrait art to hand back yet and paints a blank one. The
        -- client fires PORTRAITS_UPDATED once that art is ready, and it is the
        -- only trigger that follows: the guid and the availability state both
        -- come back unchanged, so without this the blank is what the gate
        -- caches until the next reload. Blizzard's own player portrait (the
        -- character micro button) re-runs SetPortraitTexture on the same event
        -- for the same reason. 2D only: the event says portrait ART is ready,
        -- which the model path does not read, and repainting it would mean a
        -- ClearModel + SetUnit reload every time the client streams a batch.
        or (event == "PORTRAITS_UPDATED" and not isModel)
        -- Frame re-show: PlayerModel widgets DROP their model while hidden
        -- (loading screens hide the unit frames; the PEW fan-out skips hidden
        -- frames, so the re-show is the one trigger that reliably follows --
        -- with guid and availability both reading unchanged, field-traced).
        -- Models only: 2D textures survive Hide/Show.
        or (event == "Show" and isModel)
    -- A changed model can also change 2D mirror eligibility, including class
    -- mode's NPC fallback: drop the cached answer and repaint, only when opted in.
    if event == "UNIT_MODEL_CHANGED" and not isModel then
        local uk = UnitToSettingsKey(self._euiBaseUnit or u)
        local us = uk and db.profile[uk]
        if us and us.portraitMirror and not ns.UF_Blizz() then
            ns.UF_ForgetPortraitMirror(u)
            hasStateChanged = true
        end
    end
    -- Blank-model recovery is only needed when no other change requires a paint.
    -- Show can run before assets stream in; PORTRAITS_UPDATED retries a still-
    -- blank model without reloading one that is already populated.
    if not hasStateChanged and event == "PORTRAITS_UPDATED" and isModel and element.GetModelFileID then
        local modelFileID = element:GetModelFileID()
        hasStateChanged = not issecretvalue(modelFileID) and modelFileID == nil
    end
    if hasStateChanged then
        if isModel then
            if not isAvailable then
                element:SetCamDistanceScale(0.25)
                element:SetPortraitZoom(0)
                element:SetPosition(0, 0, 0.25)
                element:ClearModel()
                element:SetModel([[Interface\Buttons\TalkToMeQuestionMark.m2]])
            else
                local uKey3d = UnitToSettingsKey(self._euiBaseUnit or u)
                local uS3d = uKey3d and db.profile[uKey3d]
                local camScale = ((uS3d and uS3d.portrait3dZoom) or 100) / 100
                element:ClearModel()
                element:SetUnit(u)
                element:SetPortraitZoom(1)
                element:SetPosition(0, 0, 0)
                element:SetCamDistanceScale(camScale)
            end
        elseif element.isClass then
            -- Class sprite lane: the engine painter is the single portrait
            -- dispatch, so class mode paints here too. SetPortraitTexture on
            -- this element would stamp portrait art through the sprite
            -- cell's texcoords (the field-reported weird-colored square);
            -- ApplyClassIconTexture instead re-asserts file + coords, and
            -- re-reading the style here lets art-style changes ride any
            -- repaint. Unit swaps (target changes) land through the same
            -- guid gate as every other portrait mode.
            -- Only players take class art (UnitClass reports most NPCs as
            -- warriors); anyone else shows its 2D portrait on the backdrop's
            -- 2D texture, as Blizzard's own class portraits do. UnitIsPlayer
            -- is never secret. The frame's fallback (ns.UF_ClassFallback) can
            -- be nothing at all, available or not ("3d" swaps before the paint).
            local npcTex = element.backdrop and element.backdrop._2d
            local fb
            if npcTex and not UnitIsPlayer(u) then
                fb = fallback
                if not fb then
                    local uKeyF = UnitToSettingsKey(self._euiBaseUnit or u)
                    fb = ns.UF_ClassFallback(uKeyF and db.profile[uKeyF])
                end
            end
            if fb and (isAvailable or fb == "none") then
                element:Hide()
                if fb == "none" then
                    -- Hidden here: a previous unit's 2D art would stay visible.
                    npcTex:Hide()
                else
                    SetPortraitTexture(npcTex, u, npcTex._blizzNoMask)
                    if npcTex.PostUpdate then npcTex:PostUpdate(u) end
                    npcTex:Show()
                end
            else
                if npcTex then npcTex:Hide() end
                element:Show()
                local uKeyC = UnitToSettingsKey(self._euiBaseUnit or u)
                local uSC = uKeyC and db.profile[uKeyC]
                -- Mirror Portrait flips the class art (never under a stock
                -- style); the question-mark fallback always reads unflipped.
                if not (isAvailable and ns.UF_PaintClassIcon(element, u,
                        (uSC and uSC.classThemeStyle) or "modern",
                        uSC and uSC.portraitMirror and not ns.UF_Blizz())) then
                    element:SetTexCoord(0.15, 0.85, 0.15, 0.85)
                    element:SetTexture([[Interface\Icons\INV_Misc_QuestionMark]])
                end
            end
        else
            if isAvailable then
                -- Third argument: skip the client's own round crop (nil off
                -- the Blizzard Style; set by the style's portrait pass on the
                -- player frame, whose stock mask is not a circle).
                SetPortraitTexture(element, u, element._blizzNoMask)
            else
                element:SetTexture([[Interface\Icons\INV_Misc_QuestionMark]])
            end
        end
        -- Recovery-preserving stamp: an UNAVAILABLE paint (fallback art --
        -- transition windows, streaming models) must not cache its guid, or
        -- the gate skips every later same-guid trigger and the fallback is
        -- what sticks (vehicle swaps lost the portrait this way). Leaving
        -- the guid unstamped makes the next trigger a guid-change repaint.
        element.guid = isAvailable and guid or nil
        element.state = isAvailable
    end
    if hasStateChanged and element.PostUpdate then
        return element:PostUpdate(u, hasStateChanged)
    end
end

-- Portraits: PortraitOverride was already the complete painter (GUID/state
-- gated 2D/3D handling); the engine becomes its event source. Raid target
-- icon: index lookup straight onto the icon texture.
ns.Engine.SetPainter("portrait", function(frame, unit, event)
    if frame.Portrait and ns.Engine.ElementOn(frame, "Portrait") then
        -- Class art frames: a 3D non-player fallback is a real mode swap, made
        -- before the paint so both read the same unit (no 2D flash between).
        local swap, fb = ns.UF_ClassFallbackNeedsSwap(frame, unit)
        if swap then SwapPortraitMode(frame, true) end
        PortraitOverride(frame, event or "ForceUpdate", unit, fb)
    end
end)
-- Element ForceUpdate stamp: the settings code refreshes portraits through
-- frame.Portrait:ForceUpdate(), and mode swaps replace the Portrait object,
-- so the stamp is re-applied wherever the field is reassigned.
function ns.UF_StampPortraitForceUpdate(frame)
    local p = frame.Portrait
    if not p or p.ForceUpdate then return end
    p.ForceUpdate = function()
        if ns.Engine.ElementOn(frame, "Portrait") then
            PortraitOverride(frame, "ForceUpdate", frame._euiUnit)
        end
    end
end

-- Mirror-only edits reuse loaded models; 2D/class art keeps its normal repaint.
function ns.UF_RefreshPortraitMirror(unitKey)
    for _, frame in pairs(frames) do
        if type(frame) == "table" and frame.Portrait
            and UnitToSettingsKey(frame._euiBaseUnit or frame._euiUnit) == unitKey
            and ns.Engine.ElementOn(frame, "Portrait") then
            local p = frame.Portrait
            if p:IsObjectType("PlayerModel") then
                ns.UF_ApplyPortraitRotation(p, p.state and db.profile[unitKey].portraitMirror and not ns.UF_Blizz())
            elseif p.ForceUpdate then
                p:ForceUpdate()
            end
        end
    end
end
ns.Engine.SetPainter("raidicon", function(frame, unit)
    if not ns.Engine.ElementOn(frame, "RaidTargetIndicator") then return end
    local element = frame.RaidTargetIndicator
    if not element then return end
    -- The styles create the icon as a bare texture; the marker SHEET must be
    -- assigned before SetRaidTargetIconTexture's texcoords can render (the
    -- old element wiring auto-assigned it on enable -- same file the
    -- nameplate markers use).
    if not element:GetTexture() then
        element:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    end
    local index = UnitExists(unit) and GetRaidTargetIndex(unit) or nil
    if index then
        SetRaidTargetIconTexture(element, index)
        element:Show()
    else
        element:Hide()
    end
end)

-- One-stop engine wiring for a freshly spawned frame: the shared colors
-- table, the castbar owner backref, the channel set derived from the widgets
-- the style actually built, the matching Blizzard-frame suppression, and the
-- first full paint.
function ns.UF_AttachEngineFrame(frame, unit, polled)
    frame.colors = ns.Colors
    -- Smoothing defaults the old element wiring seeded on enable: painters
    -- pass element.smoothing into every SetValue/SetTimerDuration, and the
    -- old build guaranteed Immediate until settings stamped otherwise
    -- (ReloadFrames overrides Health's; Power and Castbar keep this).
    local IMMEDIATE = Enum and Enum.StatusBarInterpolation
        and Enum.StatusBarInterpolation.Immediate
    if frame.Health and not frame.Health.smoothing then
        frame.Health.smoothing = IMMEDIATE
    end
    if frame.Power and not frame.Power.smoothing then
        frame.Power.smoothing = IMMEDIATE
    end
    if frame.Castbar and not frame.Castbar.smoothing then
        frame.Castbar.smoothing = IMMEDIATE
    end
    local channels = {}
    if frame.Health then channels[#channels + 1] = "health" end
    if frame.Power then channels[#channels + 1] = "power" end
    channels[#channels + 1] = "text"
    if frame.HealthPrediction then channels[#channels + 1] = "absorb" end
    if frame.Portrait then
        channels[#channels + 1] = "portrait"
        ns.UF_StampPortraitForceUpdate(frame)
    end
    if frame.Castbar then
        frame.Castbar.__owner = frame
        channels[#channels + 1] = "castbar"
    end
    if frame.RaidTargetIndicator then channels[#channels + 1] = "raidicon" end
    if polled then
        ns.Engine.AttachPolled(frame, unit, channels)
    else
        ns.Engine.Attach(frame, unit, channels)
    end
    -- Opt-in heal prediction joins its channel here when the unit has it on.
    if frame.HealthPrediction and ns.UF_HEAL_PRED_UNITS[unit] then
        ns.UF_HealPredApply(frame, unit, GetSettingsForUnit(unit))
    end
    -- Opt-in Blizzard Glow Line: built and joined only when on.
    if frame.HealthPrediction then ns.UF_AbsorbGlowApply(frame, unit) end
    -- The player's power value channel: joined while the frame is visible and
    -- shows the value, so it also follows the frame's show and hide.
    if unit == "player" and frame.Power then
        frame:HookScript("OnShow", ns.UF_PowerValSync)
        frame:HookScript("OnHide", ns.UF_PowerValSync)
        ns.UF_PowerValSync(frame)
    end
    ns.Engine.HideBlizzardUnitFrame(unit)
    ns.Engine.RepaintAll(frame, "Spawn")
end

-- Mask and border paths for detached portrait shapes.
local PORTRAIT_MASKS = EllesmereUI.SHAPE_MASKS
local PORTRAIT_BORDERS = EllesmereUI.SHAPE_BORDERS

-- Top pixel inset for each mask shape (px from edge to visible portrait area in 128px mask)
local MASK_INSETS = EllesmereUI.SHAPE_INSETS

-- Shared with EllesmereUIUnitFrames_PlayerAuraBars.lua (same addon/ns), which reuses
-- this shape media set for Player Aura Bars' iconShape feature.
ns.PORTRAIT_MASKS   = PORTRAIT_MASKS
ns.PORTRAIT_BORDERS = PORTRAIT_BORDERS
ns.MASK_INSETS      = MASK_INSETS

-- Detached portrait shapes whose ring art draws OUTSIDE the mask (never
-- clipped by it), with the ring's inset from the backdrop edge in px. Kept
-- here, not in the shared catalogue, so no other module's shape path changes.
ns.UF_UNMASKED_RING = { pixelsCircle = 4 }
-- Round shapes: the only ones that take the Outer Ring and the Inner Shadow.
ns.UF_ROUND_SHAPES = { circle = true, pixelsCircle = true }
ns.UF_PORTRAIT_INNER_SHADOW = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\pixels_inner_shadow.tga"
ns.UF_THIN_BORDER_RING = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\pixels_ring_thin_border.tga"

-- Stock target-frame dragon art, placed as on the stock 58px portrait (top-right corner 15px right, 11px up).
ns.UF_WINGLESS_GOLD   = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold"
ns.UF_WINGLESS_SILVER = "ui-hud-unitframe-target-portraiton-boss-rare-silver"
-- The Elite Enemy Dragon's art per unit classification (none for the rest).
ns.UF_WINGLESS_ATLAS = {
    elite = ns.UF_WINGLESS_GOLD, worldboss = ns.UF_WINGLESS_GOLD,
    rare = ns.UF_WINGLESS_SILVER, rareelite = ns.UF_WINGLESS_SILVER,
}
-- Atlas info per name, read once (false: not in this client).
ns.UF_WinglessInfoCache = {}
function ns.UF_WinglessInfo(atlas)
    local info = ns.UF_WinglessInfoCache[atlas]
    if info == nil then
        info = C_Texture.GetAtlasInfo(atlas) or false
        ns.UF_WinglessInfoCache[atlas] = info
    end
    return info or nil
end

-- Paints the dragon art unless the texture already shows this atlas and
-- mirror (the memo; UF_PlaceWinglessDragon clears it). False when missing.
function ns.UF_WinglessArt(tex, atlas, mirrored)
    if tex._wAtlas == atlas and tex._wFlip == mirrored then return true end
    local info = ns.UF_WinglessInfo(atlas)
    if not info then return false end
    -- The atlas's file with its coordinates, not SetAtlas: after SetAtlas,
    -- SetTexCoord crops within the atlas region instead of the file.
    tex:SetTexture(info.file or info.filename)
    local l, r = info.leftTexCoord, info.rightTexCoord
    if mirrored then l, r = r, l end
    tex:SetTexCoord(l, r, info.topTexCoord, info.bottomTexCoord)
    tex._wAtlas, tex._wFlip = atlas, mirrored
    return true
end

-- Lays the dragon out on host (size from its height, scale percent around its
-- centre, x/y shift, class tint) and repaints its art; the caller shows it.
-- False, hidden, when the atlas is missing.
function ns.UF_PlaceWinglessDragon(tex, host, atlas, mirrored, classColor, scale, x, y)
    tex._wAtlas = nil
    if not ns.UF_WinglessArt(tex, atlas, mirrored) then tex:Hide(); return false end
    local info = ns.UF_WinglessInfo(atlas)
    local h = host:GetHeight()
    if not PP.IsNum(h) or h < 1 then h = 46 end
    local k = h / 58
    local w, th = info.width * k, info.height * k
    local cx, cy = 44 * k - w / 2, 40 * k - th / 2
    if mirrored then cx = -cx end
    local s = (PP.IsNum(scale) and scale or 100) / 100
    tex:SetSize(w * s, th * s)
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", host, "CENTER", cx * s + (x or 0), cy * s + (y or 0))
    local cc
    if classColor then
        local _, tok = UnitClass("player")
        cc = tok and EllesmereUI.GetClassColor(tok)
    end
    tex:SetDesaturated(cc and true or false)
    if cc then tex:SetVertexColor(cc.r, cc.g, cc.b) else tex:SetVertexColor(1, 1, 1) end
    return true
end

-- Raises a dragon holder over its portrait backdrop: strata nil, false or
-- "inherit" follows the backdrop; level is added to the backdrop's, at least 1.
function ns.UF_LiftDragonHolder(holder, host, strata, level)
    holder:SetFrameStrata((not strata or strata == "inherit") and host:GetFrameStrata() or strata)
    holder:SetFrameLevel(host:GetFrameLevel() + math_max(1, level or 1))
end

-- Portrait Dragon: the boss dragon curled round the player, target and focus
-- portraits (Player Frame Dragon, Elite Enemy Dragon), attached or detached,
-- any shape. One key set per unit (detachedPortraitWinglessDragon and its
-- suffixed keys). A target table whose Elite/Rare Indicator style is
-- "wingless" is read as a view: its dragon comes from that style's keys and
-- the indicator itself reads as off, with nothing rewritten until an options
-- setter calls ns.UF_PinLegacyDragon.
function ns.UF_DragonLegacy(s)
    return s ~= nil and s.eliteIndicatorStyle == "wingless"
end

-- The effective dragon settings of unitKey's settings table s: on, scale, x,
-- y, flip, classColor, strata, level, instances. The table is kept per unit
-- and rewritten by every call, so callers read it at once.
ns._ufDragonEff = {}
function ns.UF_DragonSettings(unitKey, s)
    local e = ns._ufDragonEff[unitKey]
    if not e then
        e = {}
        ns._ufDragonEff[unitKey] = e
    end
    if not s then
        e.on = false
    elseif ns.UF_DragonLegacy(s) then
        e.on = s.eliteIndicatorEnabled == true
        e.scale = s.eliteIndicatorWinglessScale or 100
        e.x, e.y = s.eliteIndicatorX or 0, s.eliteIndicatorY or 0
        e.flip = s.eliteIndicatorWinglessFlip == true
        e.classColor = s.eliteIndicatorWinglessClassColor == true
        e.strata = s.eliteIndicatorWinglessStrata or "inherit"
        e.level = s.eliteIndicatorWinglessLevel or 1
        e.instances = s.eliteIndicatorShowInInstances == true
    else
        e.on = s.detachedPortraitWinglessDragon == true
        e.scale = s.detachedPortraitWinglessDragonScale or 100
        e.x, e.y = s.detachedPortraitWinglessDragonX or 0, s.detachedPortraitWinglessDragonY or 0
        e.flip = s.detachedPortraitWinglessDragonFlip == true
        e.classColor = s.detachedPortraitWinglessDragonClassColor == true
        e.strata = s.detachedPortraitWinglessDragonStrata or "inherit"
        e.level = s.detachedPortraitWinglessDragonLevel or 2
        e.instances = s.detachedPortraitWinglessDragonInstances == true
    end
    return e
end

-- Writes a legacy view's effective dragon values into the dragon's own keys
-- and retires the old style (Elite/Rare Indicator off, Badge style), so the
-- frame looks the same. Every options setter of the dragon row and of the
-- Elite/Rare Indicator calls it first; nothing calls it at load.
function ns.UF_PinLegacyDragon(s)
    if not ns.UF_DragonLegacy(s) then return end
    local e = ns.UF_DragonSettings("target", s)
    s.detachedPortraitWinglessDragon = e.on
    s.detachedPortraitWinglessDragonScale = e.scale
    s.detachedPortraitWinglessDragonX = e.x
    s.detachedPortraitWinglessDragonY = e.y
    s.detachedPortraitWinglessDragonFlip = e.flip
    s.detachedPortraitWinglessDragonClassColor = e.classColor
    s.detachedPortraitWinglessDragonStrata = e.strata
    s.detachedPortraitWinglessDragonLevel = e.level
    s.detachedPortraitWinglessDragonInstances = e.instances
    s.eliteIndicatorEnabled = false
    s.eliteIndicatorStyle = "badge"
end

-- Lays the dragon out on host (a portrait backdrop, or the options preview
-- frame) from effective settings e, facing mirrored, over the gold art (gold
-- and silver share one box); nil e hides it. Its holder frame and texture
-- exist from the first draw. The dragon reaches past the host, so any clip
-- on a live backdrop lifts while it shows (an Inside portrait is a 3D
-- model, which ignores the clip anyway). Returns the texture for the
-- caller to paint and show, or nil (hidden, or no art).
function ns.UF_PortraitDragon(host, e, mirrored)
    local holder = host._winglessHolder
    if not e then
        if holder then
            holder:Hide()
            if holder._unclipped then
                holder._unclipped = nil
                if host._isInside then host:SetClipsChildren(true) end
            end
        end
        return nil
    end
    if not holder then
        holder = CreateFrame("Frame", nil, host)
        holder:SetAllPoints(host)
        host._winglessHolder = holder
        host._winglessDragon = holder:CreateTexture(nil, "OVERLAY")
    end
    -- The options preview sits in a DIALOG window, so a lower strata would hide it.
    ns.UF_LiftDragonHolder(holder, host, not host._isPreview and e.strata, e.level)
    holder:Show()
    local tex = host._winglessDragon
    if not ns.UF_PlaceWinglessDragon(tex, host, ns.UF_WINGLESS_GOLD, mirrored,
        e.classColor, e.scale, e.x, e.y) then
        return nil
    end
    -- Lift the clip on every live show: Inside clips on purpose, and a
    -- backdrop that left Inside this session keeps that clip (the reload
    -- pass resets it only for attached portraits).
    if not host._isPreview then
        host:SetClipsChildren(false)
        holder._unclipped = true
    end
    return tex
end

-- The dragon's art on a live frame: gold on the player (as laid out), and on
-- target or focus the unit's classification art (gold for elite and boss,
-- silver for rare and rare elite, none for the rest, players included), nor
-- in instances unless Show in Instances is on.
function ns.UF_PaintPortraitDragon(holder)
    local tex = holder._tex
    if not holder._enemy then
        tex:Show()
        return
    end
    local atlas
    if holder._inst or not IsInInstance() then
        -- Secrecy check before any use of the classification.
        local c = UnitClassification(holder._unitKey)
        atlas = not issecretvalue(c) and ns.UF_WINGLESS_ATLAS[c]
    end
    if atlas and ns.UF_WinglessArt(tex, atlas, holder._mirrored) then
        tex:Show()
    else
        tex:Hide()
    end
end

-- One live frame's dragon (uf = the player, target or focus frame, unitKey
-- its settings key): drawn while it is on, the portrait shows and no stock
-- style draws the frame, hidden otherwise; nothing is built before the first
-- enable. The holder keeps what the paint and the strata pass read. Player
-- faces mirrored unless flipped, target and focus the art's own way.
function ns.UF_ApplyPortraitDragon(uf, unitKey)
    local bd = uf and uf.Portrait and uf.Portrait.backdrop
    if not bd then return end
    local e = ns.UF_DragonSettings(unitKey, db.profile[unitKey])
    local mirrored = (unitKey == "player") ~= e.flip
    local tex = e.on and bd:IsShown() and not ns.UF_Blizz()
        and ns.UF_PortraitDragon(bd, e, mirrored)
    local holder = bd._winglessHolder
    if not tex then
        if holder then
            holder._on = false
            ns.UF_PortraitDragon(bd, nil)
        end
        return
    end
    if not holder._unitKey then
        holder._unitKey, holder._uf, holder._tex = unitKey, uf, tex
        -- A portrait resized outside a settings pass (class power, UI
        -- scale) lays its dragon out again.
        holder:SetScript("OnSizeChanged", ns.UF_PortraitDragonResized)
    end
    holder._on = true
    holder._enemy = unitKey ~= "player"
    holder._mirrored = mirrored
    holder._inst = e.instances
    holder._strata, holder._level = e.strata, e.level
    ns.UF_PaintPortraitDragon(holder)
end

function ns.UF_PortraitDragonResized(holder)
    if holder._on then ns.UF_ApplyPortraitDragon(holder._uf, holder._unitKey) end
end

-- Repaints unitKey's dragon when it is up (classification events).
function ns.UF_PaintPortraitDragonFor(unitKey)
    local uf = frames[unitKey]
    local bd = uf and uf.Portrait and uf.Portrait.backdrop
    local holder = bd and bd._winglessHolder
    if holder and holder._on then ns.UF_PaintPortraitDragon(holder) end
end

function ns.UF_PortraitDragonEvent(_, event, unit)
    if event == "PLAYER_TARGET_CHANGED" then
        ns.UF_PaintPortraitDragonFor("target")
    elseif event == "PLAYER_FOCUS_CHANGED" then
        ns.UF_PaintPortraitDragonFor("focus")
    elseif event == "UNIT_CLASSIFICATION_CHANGED" then
        ns.UF_PaintPortraitDragonFor(unit)
    else
        ns.UF_PaintPortraitDragonFor("target")
        ns.UF_PaintPortraitDragonFor("focus")
    end
end

-- The Elite Enemy Dragons' events (unit changes, classification changes,
-- zoning for the instance check): registered only for the frames whose
-- dragon is up, none at all while neither is (zero cost off).
function ns.UF_ArmPortraitDragonEvents()
    local tf, ff = frames.target, frames.focus
    local tb = tf and tf.Portrait and tf.Portrait.backdrop
    local fb = ff and ff.Portrait and ff.Portrait.backdrop
    local t = tb and tb._winglessHolder and tb._winglessHolder._on
    local f = fb and fb._winglessHolder and fb._winglessHolder._on
    local ev = ns._ufDragonEvents
    if ev then ev:UnregisterAllEvents() end
    if not (t or f) then return end
    if not ev then
        ev = CreateFrame("Frame")
        ev:SetScript("OnEvent", ns.UF_PortraitDragonEvent)
        ns._ufDragonEvents = ev
    end
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    if t then ev:RegisterEvent("PLAYER_TARGET_CHANGED") end
    if f then ev:RegisterEvent("PLAYER_FOCUS_CHANGED") end
    if t and f then
        ev:RegisterUnitEvent("UNIT_CLASSIFICATION_CHANGED", "target", "focus")
    else
        ev:RegisterUnitEvent("UNIT_CLASSIFICATION_CHANGED", t and "target" or "focus")
    end
end

-- Every frame's dragon, then the events: each settings pass and login.
function ns.UF_ApplyPortraitDragons()
    ns.UF_ApplyPortraitDragon(frames.player, "player")
    ns.UF_ApplyPortraitDragon(frames.target, "target")
    ns.UF_ApplyPortraitDragon(frames.focus, "focus")
    ns.UF_ArmPortraitDragonEvents()
end

-- Outer Ring art for a detachedPortraitOuterRing value, or nil (nothing to
-- draw). "border" follows the frame's Border Style (frameTex): its ring
-- companion, nil for a style without one.
function ns.UF_OuterRingPath(ringKey, frameTex)
    local GBC = EllesmereUI.GetBorderCompanion
    if ringKey == "border" then return GBC(frameTex, "ring") end
    if ringKey == "pixels" or ringKey == "pixels-textured" then return GBC(ringKey, "ring") end
    if ringKey == "pixels-shadow" then return GBC("pixels", "ringShadow") end
    if ringKey == "pixels-textured-shadow" then return GBC("pixels-textured", "ringShadow") end
    if ringKey == "thin-border" then return ns.UF_THIN_BORDER_RING end
    return nil
end

-- Outer Ring and Inner Shadow on a round detached portrait. host = the
-- portrait backdrop (or the options preview frame, same field names), s = the
-- unit's settings, shape = its resolved shape; s == nil hides both. Nothing
-- exists until a first non-default value. The ring is laid out from the host
-- size (Outer Ring Size percent, minus a 4px inset, edges snapped by PP.Point)
-- and tinted with the frame border colour, which the hover path recolours in
-- place. The ring's geometry is memoized on the texture (ring key, frame
-- Border Style, ring size, host width and height, pixel grid) and its tint on
-- the colour (border r, g, b, alpha), so the per-target class-colour re-run
-- only compares. The Portrait Dragon is its own pass (ns.UF_PortraitDragon).
function ns.UF_PortraitExtras(host, s, shape)
    local round = s and ns.UF_ROUND_SHAPES[shape]
    local ringKey = (round and s.detachedPortraitOuterRing) or "none"
    local ring = host._outerRing
    if ringKey ~= "none" then
        local texKey = s.borderTexture or "solid"
        local scale = s.detachedPortraitOuterRingScale or 118
        local w, h = host:GetWidth(), host:GetHeight()
        if w < 1 then w = 46 end
        if h < 1 then h = 46 end
        local mult = PP.mult
        if not ring then
            ring = host:CreateTexture(nil, "OVERLAY", nil, 1)
            host._outerRing = ring
        end
        if ring._key ~= ringKey or ring._tex ~= texKey or ring._scale ~= scale
            or ring._w ~= w or ring._h ~= h or ring._mult ~= mult then
            ring._key, ring._tex, ring._scale = ringKey, texKey, scale
            ring._w, ring._h, ring._mult = w, h, mult
            local path = ns.UF_OuterRingPath(ringKey, texKey)
            ring._path = path
            if path then
                ring:SetTexture(path)
                local ext = (scale - 100) / 200
                local ox, oy = w * ext - 4, h * ext - 4
                ring:ClearAllPoints()
                PP.Point(ring, "TOPLEFT", host, "TOPLEFT", -ox, oy)
                PP.Point(ring, "BOTTOMRIGHT", host, "BOTTOMRIGHT", ox, -oy)
            end
        end
        if ring._path then
            local bc = s.borderColor
            local r, g, b = 0, 0, 0
            if bc then r, g, b = bc.r, bc.g, bc.b end
            local a = s.borderAlpha or 1
            if ring._r ~= r or ring._g ~= g or ring._b ~= b or ring._a ~= a then
                ring._r, ring._g, ring._b, ring._a = r, g, b, a
                ring:SetVertexColor(r, g, b, a)
            end
            ring:Show()
        else
            ring:Hide()
        end
    elseif ring then
        ring:Hide()
    end

    local shadow = host._innerShadow
    if round and s.detachedPortraitInnerShadow then
        if not shadow then
            -- Over the masked portrait art (ARTWORK), under the shape ring.
            shadow = host:CreateTexture(nil, "ARTWORK", nil, 7)
            shadow:SetTexture(ns.UF_PORTRAIT_INNER_SHADOW)
            shadow:SetAllPoints(host)
            host._innerShadow = shadow
        end
        local mask = host._shapeMask
        if mask and shadow._mask ~= mask then
            shadow:AddMaskTexture(mask)
            shadow._mask = mask
        end
        shadow:Show()
    elseif shadow then
        shadow:Hide()
    end
end

-- Scale class art around its center, retaining the existing inset and mask fill
-- at 100%. Shared with the preview; sprite coordinates and borders stay intact.
function ns.UF_SetClassPortraitPoints(tex, host, zoom, insetX, insetY)
    local clip = false
    if zoom and zoom ~= 100 and not ns.UF_Blizz() then
        local scale = zoom / 100
        local w, h = host:GetWidth(), host:GetHeight()
        if w < 1 then w = 46 end
        if h < 1 then h = 46 end
        local halfW, halfH = w * 0.5, h * 0.5
        insetX = halfW - (halfW - insetX) * scale
        insetY = halfH - (halfH - insetY) * scale
        clip = zoom > 100
    end
    -- Clip only the enlarged class texture, never the portrait's decorations.
    -- Nothing is created for the default zoom or for zooming out.
    local mask = tex._classZoomMask
    if clip then
        if not mask then
            mask = host:CreateMaskTexture()
            mask:SetAllPoints(host)
            -- NEAREST: a bilinear 8x8 mask fades the outer 1/16 into a dark band.
            mask:SetTexture("Interface\\Buttons\\WHITE8X8", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST")
            tex._classZoomMask = mask
        end
        if not tex._classZoomMasked then
            tex:AddMaskTexture(mask)
            mask:Show()
            tex._classZoomMasked = true
        end
    elseif tex._classZoomMasked then
        tex:RemoveMaskTexture(mask)
        mask:Hide()
        tex._classZoomMasked = nil
    end
    tex:ClearAllPoints()
    PP.Point(tex, "TOPLEFT", host, "TOPLEFT", insetX, -insetY)
    PP.Point(tex, "BOTTOMRIGHT", host, "BOTTOMRIGHT", -insetX, insetY)
end

-- Apply a detached portrait shape (mask + border overlay) to a portrait backdrop;
-- creates the mask/border textures on first call, then updates them.
--   backdrop  : the portrait backdrop frame
--   uSettings : per-unit DB table
--   unitToken : the unit this portrait belongs to ("player", "target", ...)
local function ApplyDetachedPortraitShape(backdrop, uSettings, unitToken)
    -- Mini frames never use detached portraits.
    local isMini = unitToken and (unitToken == "pet" or unitToken == "targettarget" or unitToken == "focustarget" or unitToken:match("^boss%d$"))
    local isDetached = not isMini and ((uSettings and uSettings.portraitStyle) or db.profile.portraitStyle or "attached") == "detached"
    -- Blizzard Style: the portrait sits in the stock art's ring, never detached.
    if isDetached and ns.UF_Blizz() then isDetached = false end
    local shape = (uSettings and uSettings.detachedPortraitShape) or "portrait"
    local showBorder = true
    local borderOpacity = ((uSettings and uSettings.detachedPortraitBorderOpacity) or 100) / 100
    local borderColor = (uSettings and uSettings.detachedPortraitBorderColor) or { r = 0, g = 0, b = 0 }
    local useClassColor = (uSettings and uSettings.detachedPortraitClassColor) or false
    local rawBorderSize = (uSettings and uSettings.detachedPortraitBorderSize) or 7
    -- Border art is natively 7px. Scale UP by (7 - rawBorderSize) so the mask
    -- clips the inner portion, leaving rawBorderSize px visible.
    local bExp = 7 - rawBorderSize

    -- Border color; class color overrides the manual color.
    local bR, bG, bB = borderColor.r, borderColor.g, borderColor.b
    if useClassColor then
        -- Unit Color in Dark Mode keeps the unit path below under Dark Mode.
        local isDark = db and db.profile and db.profile.darkTheme
            and not (uSettings and uSettings.detachedPortraitUnitColorDark)
        if isDark then
            -- Dark mode: always the player's own class color.
            local _, classToken = UnitClass("player")
            if classToken then
                local c = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classToken]
                if c then bR, bG, bB = c.r, c.g, c.b end
            end
        elseif unitToken and UnitExists(unitToken) then
            -- Non-dark: the unit's health bar color (class for players, reaction
            -- for NPCs, tapped grey).
            local _, classToken = UnitClass(unitToken)
            if UnitIsPlayer(unitToken) and not issecretvalue(classToken) and classToken then
                local c = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classToken]
                if c then bR, bG, bB = c.r, c.g, c.b end
            elseif UnitIsTapDenied and UnitIsTapDenied(unitToken) then
                bR, bG, bB = 0.6, 0.6, 0.6
            else
                local reaction = UnitReaction(unitToken, "player")
                if reaction then
                    -- Prefer oUF's reaction table (carries the custom Enemy Colors
                    -- override) so the border matches the health bar.
                    local c = (ns.Colors and ns.Colors.reaction and ns.Colors.reaction[reaction])
                        or FACTION_BAR_COLORS[reaction]
                    if c then bR, bG, bB = c.r, c.g, c.b end
                end
            end
        else
            -- Fallback: player class color.
            local _, classToken = UnitClass("player")
            if classToken then
                local c = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classToken]
                if c then bR, bG, bB = c.r, c.g, c.b end
            end
        end
    end

    -- Not detached: drop the mask and reset texture positions.
    if not isDetached then
        if backdrop._shapeMask then
            if backdrop._2d then backdrop._2d:RemoveMaskTexture(backdrop._shapeMask) end
            if backdrop._class then backdrop._class:RemoveMaskTexture(backdrop._shapeMask) end
            if backdrop._bg then backdrop._bg:RemoveMaskTexture(backdrop._shapeMask) end
            backdrop._shapeMask:Hide()
        end
        if backdrop._shapeBorderTex then backdrop._shapeBorderTex:Hide() end
        if backdrop._sqBorderTexs then
            for _, t in ipairs(backdrop._sqBorderTexs) do t:Hide() end
        end
        -- Detached mode expands these for mask fill; reset to default.
        if backdrop._2d then
            backdrop._2d:ClearAllPoints()
            PP.Point(backdrop._2d, "TOPLEFT", backdrop, "TOPLEFT", 0, 0)
            PP.Point(backdrop._2d, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", 0, 0)
        end
        if backdrop._class then
            local bh2 = backdrop:GetHeight()
            if bh2 < 1 then bh2 = 46 end
            local classInset = math.floor(bh2 * 0.08)
            ns.UF_SetClassPortraitPoints(backdrop._class, backdrop,
                uSettings and uSettings.portraitClassZoom, classInset, classInset)
        end
        if backdrop._3d then
            backdrop._3d:ClearAllPoints()
            PP.Point(backdrop._3d, "TOPLEFT", backdrop, "TOPLEFT", 0, 0)
            PP.Point(backdrop._3d, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", 0, 0)
        end
        if backdrop._outerRing or backdrop._innerShadow then ns.UF_PortraitExtras(backdrop, nil) end
        return
    end

    -- === MASK ===
    local maskPath = shape ~= "none" and PORTRAIT_MASKS[shape] or nil
    if shape == "none" then
        -- Drop mask, border and background.
        if backdrop._bg then backdrop._bg:Hide() end
        if backdrop._shapeMask then
            if backdrop._2d then pcall(backdrop._2d.RemoveMaskTexture, backdrop._2d, backdrop._shapeMask) end
            if backdrop._class then pcall(backdrop._class.RemoveMaskTexture, backdrop._class, backdrop._shapeMask) end
            if backdrop._bg then pcall(backdrop._bg.RemoveMaskTexture, backdrop._bg, backdrop._shapeMask) end
            backdrop._shapeMask:Hide()
        end
        if backdrop._shapeBorderTex then backdrop._shapeBorderTex:Hide() end
        if backdrop._sqBorderTexs then
            for _, t in ipairs(backdrop._sqBorderTexs) do t:Hide() end
        end
        -- Reset content to fill the backdrop.
        if backdrop._2d then
            backdrop._2d:ClearAllPoints()
            PP.Point(backdrop._2d, "TOPLEFT", backdrop, "TOPLEFT", 0, 0)
            PP.Point(backdrop._2d, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", 0, 0)
        end
        if backdrop._class then
            local bh2 = backdrop:GetHeight()
            if bh2 < 1 then bh2 = 46 end
            local classInset = math.floor(bh2 * 0.08)
            ns.UF_SetClassPortraitPoints(backdrop._class, backdrop,
                uSettings and uSettings.portraitClassZoom, classInset, classInset)
        end
        if backdrop._3d then
            backdrop._3d:ClearAllPoints()
            PP.Point(backdrop._3d, "TOPLEFT", backdrop, "TOPLEFT", 0, 0)
            PP.Point(backdrop._3d, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", 0, 0)
        end
        if backdrop._outerRing or backdrop._innerShadow then ns.UF_PortraitExtras(backdrop, nil) end
        return
    end
    if backdrop._bg then backdrop._bg:Show() end
    if maskPath then
        if not backdrop._shapeMask then
            backdrop._shapeMask = backdrop:CreateMaskTexture()
        end
        -- Inset the mask 1px when the border is visible so scaling cannot make
        -- the mask edge poke out from behind the border art.
        backdrop._shapeMask:ClearAllPoints()
        if rawBorderSize >= 1 then
            PP.Point(backdrop._shapeMask, "TOPLEFT", backdrop, "TOPLEFT", 1, -1)
            PP.Point(backdrop._shapeMask, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", -1, 1)
        else
            backdrop._shapeMask:SetAllPoints(backdrop)
        end
        backdrop._shapeMask:SetTexture(maskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        backdrop._shapeMask:Show()
        if backdrop._2d then backdrop._2d:AddMaskTexture(backdrop._shapeMask) end
        if backdrop._class then backdrop._class:AddMaskTexture(backdrop._shapeMask) end
        if backdrop._bg then backdrop._bg:AddMaskTexture(backdrop._shapeMask) end
    end

    -- Hide legacy square border textures if this frame has them.
    if backdrop._sqBorderTexs then
        for _, t in ipairs(backdrop._sqBorderTexs) do t:Hide() end
    end

    -- === TGA BORDER OVERLAY ===
    -- Geometry (anchors, mask attach, art) re-applies only when one of its
    -- inputs changes -- shape, border size step, pixel grid, mask object -- so
    -- the per-target class-colour re-run only recolours. A shape listed in
    -- ns.UF_UNMASKED_RING (Pixels Circle) keeps its ring art outside the mask,
    -- inset from the backdrop by that many px at Size 7; each step below 7
    -- moves it 1px outward, as the size step expands every other shape's art.
    local sbt = backdrop._shapeBorderTex
    if not sbt then
        sbt = backdrop:CreateTexture(nil, "OVERLAY")
        backdrop._shapeBorderTex = sbt
    end
    local sbtMask, sbtMult = backdrop._shapeMask, PP.mult
    if sbt._gShape ~= shape or sbt._gExp ~= bExp or sbt._gMult ~= sbtMult or sbt._gMask ~= sbtMask then
        sbt._gShape, sbt._gExp, sbt._gMult, sbt._gMask = shape, bExp, sbtMult, sbtMask
        local ringInset = ns.UF_UNMASKED_RING[shape]
        local off = bExp - (ringInset or 0)
        sbt:ClearAllPoints()
        PP.Point(sbt, "TOPLEFT", backdrop, "TOPLEFT", -off, off)
        PP.Point(sbt, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", off, -off)
        if sbtMask then
            pcall(sbt.RemoveMaskTexture, sbt, sbtMask)
            -- Mask the border too so its inner edge is clipped.
            if not ringInset then sbt:AddMaskTexture(sbtMask) end
        end
        local borderPath = PORTRAIT_BORDERS[shape]
        if borderPath then sbt:SetTexture(borderPath) end
    end
    if showBorder and PORTRAIT_BORDERS[shape] then
        sbt:SetVertexColor(bR, bG, bB, borderOpacity)
        sbt:Show()
    else
        sbt:Hide()
    end

    -- === Content positioning within mask ===
    -- Scale the portrait so its visible area fills the mask opening.
    -- MASK_INSETS[shape] = px from mask edge to visible area in the 128px mask.
    -- Content expands to fill the mask; border size does not affect content.
    local insetPx = MASK_INSETS[shape] or 17
    local bw = backdrop:GetWidth()
    local bh2 = backdrop:GetHeight()
    if bw < 1 then bw = 46 end
    if bh2 < 1 then bh2 = 46 end
    local visRatio = (128 - 2 * insetPx) / 128
    local cScale = 1 / visRatio
    -- User art scale, stored as a percentage (100 = default).
    local artScale = ((uSettings and uSettings.portraitArtScale) or 100) / 100
    cScale = cScale * artScale
    local expand = (cScale - 1) * 0.5
    local oL = -(expand * bw)
    local oR =  (expand * bw)
    local oT =  (expand * bh2)
    local oB = -(expand * bh2)
    if backdrop._2d then
        backdrop._2d:ClearAllPoints()
        PP.Point(backdrop._2d, "TOPLEFT", backdrop, "TOPLEFT", oL, oT)
        PP.Point(backdrop._2d, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", oR, oB)
    end
    if backdrop._class then
        local classInset = math.floor(bh2 * 0.08)
        ns.UF_SetClassPortraitPoints(backdrop._class, backdrop,
            uSettings and uSettings.portraitClassZoom, classInset + oL, classInset - oT)
    end
    if backdrop._3d then
        -- 3D models ignore SetClipsChildren, so keep them inside the backdrop
        -- bounds. Art scale is not applied to 3D (camera zoom is fixed).
        backdrop._3d:ClearAllPoints()
        PP.Point(backdrop._3d, "TOPLEFT", backdrop, "TOPLEFT", 0, 0)
        PP.Point(backdrop._3d, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", 0, 0)
    end

    -- Outer Ring / Inner Shadow (round shapes); nothing built while off.
    ns.UF_PortraitExtras(backdrop, uSettings, shape)
end
local function CreatePortrait(frame, side, frameHeight, unit)
    local portraitHeight = frameHeight or 46
    local uKey = UnitToSettingsKey(unit)
    local uSettings = uKey and db.profile[uKey]
    local portraitStyle = (uSettings and uSettings.portraitStyle) or db.profile.portraitStyle or "attached"
    -- Mini frames never use detached portraits.
    local isMiniP = unit and (unit == "pet" or unit == "targettarget" or unit == "focustarget" or unit:match("^boss%d$"))
    if isMiniP and portraitStyle == "detached" then portraitStyle = "attached" end
    -- Blizzard Style: the portrait sits in the stock art's ring, never detached
    -- and never off (the stock frames always carry one).
    if (portraitStyle == "detached" or portraitStyle == "none") and ns.UF_Blizz() then portraitStyle = "attached" end
    local isAttached = (portraitStyle == "attached")

    -- Per-unit size/offset adjustments.
    local pSizeAdj = (uSettings and uSettings.portraitSize) or 0
    local pXOff = (uSettings and uSettings.portraitX) or 0
    local pYOff = (uSettings and uSettings.portraitY) or 0
    local baseHeight = portraitHeight
    if not isAttached and not isInside and portraitStyle ~= "none" then pSizeAdj = pSizeAdj + 10; pYOff = pYOff + 5 end
    local adjustedHeight = baseHeight + pSizeAdj
    if adjustedHeight < 8 then adjustedHeight = 8 end

    -- Attached: "top" and "inside*" fall back to the default side.
    local effectiveSide = side
    local isInside = (side == "insideleft" or side == "insideright" or side == "insidecenter")
    if isAttached and (side == "top" or isInside) then
        effectiveSide = (unit == "player") and "left" or "right"
        isInside = false
    end

    local backdrop = CreateFrame("Frame", nil, frame)
    backdrop:SetFrameStrata(frame:GetFrameStrata())
    backdrop:SetFrameLevel(frame:GetFrameLevel() + 1)
    if isInside then
        -- Inside: portrait fills frame height, width = adjusted portrait size.
        PP.Size(backdrop, adjustedHeight, portraitHeight)
    else
        PP.Size(backdrop, adjustedHeight, adjustedHeight)
    end
    backdrop:SetClipsChildren(false)

    local bgTex = backdrop:CreateTexture(nil, "BACKGROUND")
    PP.Point(bgTex, "TOPLEFT", backdrop, "TOPLEFT", 0, 0)
    PP.Point(bgTex, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", 0, 0)
    bgTex:SetColorTexture(0.1, 0.1, 0.1, 1)
    if isInside then bgTex:Hide() end
    backdrop._bg = bgTex

    if portraitStyle == "none" then
        -- Disabled: anchor the (hidden) backdrop to the frame corner, avoiding any
        -- dependency on frame.Health which may not exist yet.
        PP.Point(backdrop, "TOPLEFT", frame, "TOPLEFT", 0, 0)
    elseif isInside then
        -- Inside: overlays the health bar. Anchored to the frame initially;
        -- ReloadFrames re-anchors to frame.Health once layout resolves.
        backdrop._isInside = true
        backdrop:SetFrameLevel(frame:GetFrameLevel() + 3)
        PP.Point(backdrop, "TOPLEFT", frame, "TOPLEFT", pXOff, pYOff)
    elseif isAttached then
        if effectiveSide == "left" then
            PP.Point(backdrop, "TOPLEFT", frame, "TOPLEFT", 0, 0)
        else
            PP.Point(backdrop, "TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        end
    else
        -- Detached: float outside the health bar edge.
        if effectiveSide == "top" then
            backdrop:SetPoint("BOTTOM", frame.Health or frame, "TOP", pXOff, 15 + pYOff)
        elseif effectiveSide == "left" then
            backdrop:SetPoint("TOPRIGHT", frame.Health or frame, "TOPLEFT", -15 + pXOff, pYOff)
        else
            backdrop:SetPoint("TOPLEFT", frame.Health or frame, "TOPRIGHT", 15 + pXOff, pYOff)
        end
        -- Raise a detached portrait above border/text/power.
        backdrop:SetFrameLevel(frame:GetFrameLevel() + 15)
    end

    -- 2D and class theme textures are eager; the 3D PlayerModel is deferred until
    -- 3D display or an enabled 2D mirror lookup needs it.
    local model3D = nil

    local function EnsureModel3D()
        if model3D then return model3D end
        model3D = CreateFrame("PlayerModel", nil, backdrop)
        PP.Point(model3D, "TOPLEFT", backdrop, "TOPLEFT", 0, 0)
        PP.Point(model3D, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", 0, 0)
        model3D:SetCamera(0)
        local camScale = ((uSettings and uSettings.portrait3dZoom) or 100) / 100
        model3D:SetCamDistanceScale(camScale)
        -- Re-apply zoom and orientation after SetUnit resets the camera.
        model3D.PostUpdate = function(self)
            -- The frame engine does not assign an __owner to portraits.
            local u = frame._euiBaseUnit or frame._euiUnit
            if not u then return end
            local uk = UnitToSettingsKey(u)
            local us = uk and db.profile[uk]
            local cs = ((us and us.portrait3dZoom) or 100) / 100
            self:SetCamDistanceScale(cs)
            ns.UF_ApplyPortraitRotation(self, self.state and us and us.portraitMirror and not ns.UF_Blizz())
        end
        model3D:Hide()
        backdrop._3d = model3D
        return model3D
    end
    backdrop._ensureModel3D = EnsureModel3D

    local tex2D = backdrop:CreateTexture(nil, "ARTWORK")
    PP.Point(tex2D, "TOPLEFT", backdrop, "TOPLEFT", 0, 0)
    PP.Point(tex2D, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", 0, 0)
    tex2D:SetTexCoord(0.15, 0.85, 0.15, 0.85)
    tex2D:Hide()
    -- A 2D mirror lookup that finished loading after the paint: repaint the flip
    -- when the frame still shows that unit.
    local function MirrorReady(guid)
        local u = frame._euiUnit
        if not (u and UnitIsConnected(u) and UnitIsVisible(u)) then return end
        local g = UnitGUID(u)
        if issecretvalue(g) or g ~= guid then return end
        tex2D:PostUpdate(u)
    end

    -- Class theme icon: painted by the engine portrait painter's class lane
    -- (element.isClass); this creation-time paint only seeds art before the
    -- first dispatch.
    local texClass = backdrop:CreateTexture(nil, "ARTWORK")
    local classInset = math.floor(portraitHeight * 0.08)
    ns.UF_SetClassPortraitPoints(texClass, backdrop,
        uSettings and uSettings.portraitClassZoom, classInset, classInset)
    texClass:SetAlpha(0.8)
    if unit and UnitIsPlayer(unit) then
        ns.UF_PaintClassIcon(texClass, unit, (uSettings and uSettings.classThemeStyle) or "modern",
            uSettings and uSettings.portraitMirror and not ns.UF_Blizz())
    end
    texClass:Hide()

    backdrop._3d = model3D
    backdrop._2d = tex2D
    backdrop._class = texClass

    local mode
    do
        mode = (uSettings and uSettings.portraitMode) or db.profile.portraitMode or "2d"
        -- Blizzard Style masks the 2D art: a 3D model cannot be masked, and
        -- the portrait is never off.
        if (mode == "3d" or mode == "none") and ns.UF_Blizz() then mode = "2d" end
    end
    -- portraitStyle/portraitMode "none" hides the backdrop but keeps the structure
    -- alive so ReloadFrames can show it again without a /reload.
    if portraitStyle == "none" or mode == "none" then
        backdrop:Hide()
        -- tex2D is a minimal placeholder so frame.Portrait is non-nil and carries a
        -- backdrop reference; it stays hidden with the backdrop.
        tex2D.backdrop = backdrop
        tex2D.is2D = true
        return tex2D
    end
    local active
    if mode == "class" then
        texClass:Show()
        tex2D:Hide()
        active = texClass
        active.isClass = true
    elseif mode == "2d" then
        tex2D:Show()
        active = tex2D
        active.is2D = true
    else
        local m3d = EnsureModel3D()
        m3d:Show()
        active = m3d
        active.is2D = false
    end
    active.backdrop = backdrop

    -- SetPortraitTexture resets snapping and anchor points, so re-disable pixel
    -- snap and re-anchor after every portrait repaint (PortraitOverride). hasStateChanged
    -- is set only by the 2D lane's call (the class lane's NPC paint passes none).
    tex2D.PostUpdate = function(self, u, hasStateChanged)
        UnsnapTex(self)
        self:ClearAllPoints()
        -- When detached, ApplyDetachedPortraitShape uses expanded offsets for mask
        -- fill; re-apply those instead of resetting to default.
        local uKey2 = UnitToSettingsKey(frame._euiBaseUnit or u)
        local uS2 = uKey2 and db.profile[uKey2]
        local isDetNow = ((uS2 and uS2.portraitStyle) or db.profile.portraitStyle or "attached") == "detached"
        if isDetNow and backdrop then
            local shape2 = (uS2 and uS2.detachedPortraitShape) or "portrait"
            local insetPx2 = MASK_INSETS[shape2] or 17
            local bw2 = backdrop:GetWidth()
            local bh3 = backdrop:GetHeight()
            if bw2 < 1 then bw2 = 46 end
            if bh3 < 1 then bh3 = 46 end
            local visR2 = (128 - 2 * insetPx2) / 128
            local cS2 = 1 / visR2
            local artS2 = ((uS2 and uS2.portraitArtScale) or 100) / 100
            cS2 = cS2 * artS2
            local exp2 = (cS2 - 1) * 0.5
            PP.Point(self, "TOPLEFT", backdrop, "TOPLEFT", -(exp2 * bw2), exp2 * bh3)
            PP.Point(self, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", exp2 * bw2, -(exp2 * bh3))
        else
            PP.Point(self, "TOPLEFT", backdrop, "TOPLEFT", 0, 0)
            PP.Point(self, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", 0, 0)
        end
        -- Mirror Portrait: the crop survives repaints, so it is written only
        -- when the flip state changes (the first on-to-off pass restores the
        -- creation crop). Never under a stock style (its full-art coords
        -- stand), and the unavailable question mark always reads unflipped.
        local mir = (uS2 and uS2.portraitMirror and not ns.UF_Blizz()
            and not (hasStateChanged and self.state == false)
            and ns.UF_CanMirrorPortrait2D(EnsureModel3D(), u, MirrorReady)) and true or false
        if mir ~= (self._mirrored or false) then
            self._mirrored = mir
            if mir then
                self:SetTexCoord(0.85, 0.15, 0.15, 0.85)
            else
                self:SetTexCoord(0.15, 0.85, 0.15, 0.85)
            end
        end
    end

    ApplyDetachedPortraitShape(backdrop, uSettings, unit)

    return active
end

-- Swap portrait mode (3D/2D/class theme) without recreating frames: 2D and class
-- textures already exist on the backdrop, 3D PlayerModel is lazy-created on first use;
-- this just shows/hides and reassigns frame.Portrait. painting = the portrait
-- painter is the caller and paints the new object itself.
function SwapPortraitMode(frame, painting)
    local portrait = frame.Portrait
    if not portrait or not portrait.backdrop then return end
    local bd = portrait.backdrop
    if not bd._2d then return end

    local wantMode
    do
        local unit = frame._euiUnit or frame:GetAttribute("unit")
        -- The frame's own settings: a vehicle's live token has none.
        local uKey = UnitToSettingsKey(frame._euiBaseUnit or unit)
        local s = uKey and db.profile[uKey]
        wantMode = (s and s.portraitMode) or db.profile.portraitMode or "2d"
        -- A non-player on Class art takes the model when its fallback is 3D
        -- ("none" stays on the class object: the class lane draws nothing).
        if wantMode == "class" and unit and UnitExists(unit) and not UnitIsPlayer(unit)
            and ns.UF_ClassFallback(s) == "3d" then
            wantMode = "3d"
        end
        -- Blizzard Style masks the 2D art: a 3D model cannot be masked, and
        -- the portrait is never off.
        if (wantMode == "3d" or wantMode == "none") and ns.UF_Blizz() then wantMode = "2d" end
    end

    local curMode
    if portrait.isClass then curMode = "class"
    elseif portrait.is2D then curMode = "2d"
    else curMode = "3d" end

    if wantMode == curMode then return end

    -- (No event surgery needed on a mode swap: the engine's portrait painter
    -- targets whatever frame.Portrait currently is.)

    -- Hide all
    if bd._3d then bd._3d:ClearModel(); bd._3d:Hide() end
    bd._2d:Hide()
    if bd._class then bd._class:Hide() end

    if wantMode == "class" and bd._class then
        -- The art comes from the engine painter's class lane on the
        -- repaint below (players: class art, anyone else: the frame's
        -- non-player fallback).
        bd._class:Show()
        bd._2d:Hide()
        bd._class.backdrop = bd
        bd._class.isClass = true
        frame.Portrait = bd._class
    elseif wantMode == "3d" then
        -- Lazily create the PlayerModel on first switch to 3D
        if bd._ensureModel3D then bd._ensureModel3D() end
        if not bd._3d then return end
        -- A model ignores parent alpha: take the body's current fade until
        -- the visibility pass mirrors it.
        bd._3d:SetAlpha((frame._visWrap or frame):GetAlpha())
        bd._3d:Show()
        bd._3d.backdrop = bd
        bd._3d.is2D = false
        bd._3d.isClass = nil
        frame.Portrait = bd._3d
    else
        bd._2d:Show()
        bd._2d.backdrop = bd
        bd._2d.is2D = true
        bd._2d.isClass = nil
        frame.Portrait = bd._2d
    end
    -- The new object's guid memo dates from its last paint (a model was also
    -- cleared above): drop it so the next paint repaints even the same unit.
    frame.Portrait.guid = nil

    -- Repaint through the new object immediately.
    if not painting and frame.EnableElement then frame:EnableElement("Portrait") end
    ns.UF_StampPortraitForceUpdate(frame)
end

I.ApplyClassIconTexture, I.ApplyDetachedPortraitShape = ApplyClassIconTexture, ApplyDetachedPortraitShape
I.CreatePortrait, I.SwapPortraitMode = CreatePortrait, SwapPortraitMode
