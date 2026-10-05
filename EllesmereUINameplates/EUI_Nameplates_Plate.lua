if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Nameplates_Plate.lua
--
--  Blizzard frame hiding, the cast fallback frame, text helpers and the
--  NameplateFrame mixin: cast text, appearance, target of target, SetUnit,
--  ClearUnit.
--  Reads the earlier nameplate files through ns and ns._npInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._npInternals
-- EllesmereUINameplates.lua or an earlier nameplate file failed to load.
if not I or I.broken then return end
I.broken = true

local pairs, type = pairs, type
local PP = EllesmereUI.PP
local UnitName = UnitName
local UnitIsUnit, UnitCanAttack = UnitIsUnit, UnitCanAttack
local UnitIsPlayer = UnitIsPlayer
local UnitClassBase = UnitClassBase
local UnitCastingInfo, UnitChannelInfo = UnitCastingInfo, UnitChannelInfo

local defaults, GetNPOutline, HP_BAR_SLOTS = I.defaults, I.GetNPOutline, I.HP_BAR_SLOTS
local SetFSFont, ApplyHealthBarTexture = I.SetFSFont, I.ApplyHealthBarTexture
local GetAuraSlotOffsets, GetAuraSlots = I.GetAuraSlotOffsets, I.GetAuraSlots
local GetAuraSpacing, GetBuffIconSize = I.GetAuraSpacing, I.GetBuffIconSize
local GetCastBarHeight, GetCCIconSize = I.GetCastBarHeight, I.GetCCIconSize
local GetDebuffIconSize, GetEnemyNameTextSize = I.GetDebuffIconSize, I.GetEnemyNameTextSize
local GetFocusCastHeight, GetHealthBarHeight = I.GetFocusCastHeight, I.GetHealthBarHeight
local GetHealthBarWidth, GetHitboxYShift = I.GetHealthBarWidth, I.GetHitboxYShift
local GetNameplateYOffset, GetNameYOffset = I.GetNameplateYOffset, I.GetNameYOffset
local GetShowCastIcon, GetStackSpacingScale = I.GetShowCastIcon, I.GetStackSpacingScale
local GetTextSlot, GetTextSlotColor = I.GetTextSlot, I.GetTextSlotColor
local GetTextSlotOffsets, GetTextSlotSize = I.GetTextSlotOffsets, I.GetTextSlotSize
local IsComboHealthText, PositionAuraSlot = I.IsComboHealthText, I.PositionAuraSlot
local NotifyCastEnded, GetClassPowerTopPush = I.NotifyCastEnded, I.GetClassPowerTopPush
local HideClassPowerOnPlate = I.HideClassPowerOnPlate

local p
I.profileSetters[#I.profileSetters + 1] = function(v) p = v end

-- Pre-hook SetTexture for pooled aura-slot icons (snap-disabled at creation, so
-- the pixel-snap hook is pure overhead). Upgraded to PP.RawSetTexture in
-- OnEnable; starts as a plain wrapper so it is never nil.
local RawSetTex = function(t, v) t:SetTexture(v) end

local hookedUFs = {}
local hookedHighlights = {}
local hookedSoftTargetIcons = {}
local npOffscreenParent = CreateFrame("Frame")
npOffscreenParent:Hide()
local storedParents = {}
-- Park record per pooled UnitFrame (our table, weak on the frame): the swept children in park
-- order, plus .held while HideBlizzardFrame owns the frame. Wiped and reused by the reclaim.
ns._npParked = setmetatable({}, { __mode = "k" })
local function MoveToOffscreen(element, unit)
    if not element then return end
    -- PERF: skip SetParent if already offscreen (saves ~14 calls per plate respawn)
    if element:GetParent() == npOffscreenParent then return end
    if not storedParents[element] then
        storedParents[element] = element:GetParent()
    end
    element:SetParent(npOffscreenParent)
end
local function HideBlizzardFrame(nameplate, unit)
    if not nameplate then return end
    local uf = nameplate.UnitFrame
    if not uf then return end
    -- Suppress unconditionally: if we are called, an EUI plate is taking over this nameplate.
    -- NEVER gate on UnitCanAttack -- it can return false on the first frame (unit not fully
    -- registered), skipping the whole block and leaving Blizzard's UnitFrame visible as a
    -- giant black box.
    uf:SetAlpha(0)
    local rec = ns._npParked[uf]
    if not rec then rec = {}; ns._npParked[uf] = rec end
    rec.held = true
    -- The AurasFrame rides offscreen with the other children (WidgetContainer is the one child
    -- kept live, below): our containers own plate auras and these lists are taint-locked and
    -- unused. Alpha-0 keep-alive is NOT enough -- its item frames are mouse-enabled Blizzard
    -- templates with tooltip handlers, an invisible tooltip/click trap parked above every plate.
    if uf.AurasFrame then
        MoveToOffscreen(uf.AurasFrame, unit)
    end
    -- Park the UnitFrame's child frames on the hidden holder, discovered generically:
    -- whatever Blizzard parents under the UnitFrame is swept, no per-widget list to maintain.
    -- The UnitFrame ITSELF must stay on the nameplate where Blizzard placed it (alpha 0 above)
    -- -- parking the whole frame under a hidden holder flips every plate's content to
    -- IsVisible()==false and breaks click target selection between overlapping plates in packs.
    -- Exclusions: kept-live frames, plus protected/forbidden children (alpha 0 hides them).
    -- Walk backwards: each SetParent below removes that child from uf's list, and only the
    -- indices already visited shift, so none is skipped. Runs twice per enemy plate add, so
    -- it reads the live list instead of building a table. A child is recorded once: an enemy
    -- re-acquire finds its children already parked, so the record never grows.
    for i = uf:GetNumChildren(), 1, -1 do
        local child = (select(i, uf:GetChildren()))
        if child and child ~= uf.WidgetContainer and child ~= uf.AurasFrame
        and child ~= uf.SoftTargetFrame
           and not child:IsForbidden() and not child:IsProtected() then
            if not storedParents[child] then
                storedParents[child] = uf
                rec[#rec + 1] = child
            end
            child:SetParent(npOffscreenParent)
        end
    end
    -- All visual children are reparented offscreen so layout recalculations cannot shift
    -- bounds.
    -- Kill the CompactUnitFrame's ENTIRE event surface (raid-frames-style
    -- takeover): Blizzard registers ~27 unit events (incl. UNIT_AURA) plus
    -- ~20 globals (incl. UPDATE_MOUSEOVER_UNIT) per plate, and its dirty
    -- flags arm a real OnUpdate on this alpha-0 frame -- none of which our
    -- rendering uses, all of which was running under every plate all combat
    -- long. Partial self-heal: the driver's secure CompactUnitFrame_SetUnit
    -- restores the unit events and OnUnitSet's set when the pooled frame is
    -- next acquired, for any unit; the globals CompactUnitFrame_OnLoad
    -- registers never come back, and UpdateAll on each acquire keeps that
    -- stale window to one plate life. The soft-target trio comes back below:
    -- the kept-alive SoftTargetFrame icon is driven by exactly those events
    -- (the OnEvent script itself stays -- Blizzard set it, and
    -- UnregisterAllEvents clears registrations only).
    uf:UnregisterAllEvents()
    uf:RegisterEvent("PLAYER_TARGET_CHANGED")
    uf:RegisterEvent("PLAYER_SOFT_FRIEND_CHANGED")
    uf:RegisterEvent("PLAYER_SOFT_ENEMY_CHANGED")
    -- The cast bar is its own frame with its own registrations (we render our own). It lives
    -- at CastBarsContainer.castBar; the driver's SetUnit re-registers it on reacquisition.
    local blizzCastBar = uf.castBar or (uf.CastBarsContainer and uf.CastBarsContainer.castBar)
    if blizzCastBar and not blizzCastBar:IsForbidden() then
        blizzCastBar:UnregisterAllEvents()
    end
    -- Keep WidgetContainer functional but reparent to the nameplate itself so its layout
    -- doesn't affect the UnitFrame's bounds.
    if uf.WidgetContainer then
        uf.WidgetContainer:SetParent(nameplate)
    end
    -- Keep the soft-target cursor icon working: reparent it live instead of sweeping it
    -- offscreen or leaving it under uf's forced alpha-0.
    if uf.SoftTargetFrame then
        uf.SoftTargetFrame:SetParent(nameplate)
        uf.SoftTargetFrame:SetAlpha(1)
        -- Same icon is reused for enemy/friend/interact soft-targets; only allow the
        -- interact case through. The hook cannot be uninstalled, so it gates on the
        -- pooled UnitFrame's own current unit (the driver's SetUnit sets it before it
        -- shows the icon), never on where the icon hangs: the first Show of an add
        -- runs before we park or reclaim the frame. Every attackable unit is ours.
        local icon = uf.SoftTargetFrame.Icon
        if icon and not hookedSoftTargetIcons[icon] then
            hookedSoftTargetIcons[icon] = uf
            hooksecurefunc(icon, "Show", function(self)
                local owner = hookedSoftTargetIcons[self]
                local ufUnit = owner and owner.unit
                if not ufUnit then return end
                -- Hide only for attackable enemies. NPCs and non-attackable
                -- objects, even hostile ones, keep the icon.
                local canAttack = UnitCanAttack("player", ufUnit)
                if issecretvalue and issecretvalue(canAttack) then return end
                if canAttack then self:Hide() end
            end)
        end
    end
    if not hookedUFs[uf] then
        hookedUFs[uf] = true
        local locked = false
        hooksecurefunc(uf, "SetAlpha", function(self)
            if locked then return end
            -- Force alpha 0 only while an EUI plate owns this nameplate. On recycle to a
            -- friendly unit the plate is released and ns.plates[unit] is nil, so the hook no-ops.
            local ufUnit = self.unit or (self.GetUnit and self:GetUnit())
            if not ufUnit or not ns.plates[ufUnit] then return end
            locked = true
            self:SetAlpha(0)
            locked = false
        end)
    end
    if uf.selectionHighlight and not hookedHighlights[uf.selectionHighlight] then
        hookedHighlights[uf.selectionHighlight] = true
        hooksecurefunc(uf.selectionHighlight, "Show", function(self)
            local parent = self:GetParent()
            if parent == npOffscreenParent then return end
            if parent then
                local ufUnit = parent.unit or (parent.GetUnit and parent:GetUnit())
                if ufUnit and UnitExists(ufUnit) and UnitCanAttack("player", ufUnit) then
                    self:SetAlpha(0)
                    self:Hide()
                end
            end
        end)
        hooksecurefunc(uf.selectionHighlight, "SetShown", function(self, shown)
            if shown then
                local parent = self:GetParent()
                if parent == npOffscreenParent then return end
                if parent then
                    local ufUnit = parent.unit or (parent.GetUnit and parent:GetUnit())
                    if ufUnit and UnitExists(ufUnit) and UnitCanAttack("player", ufUnit) then
                        self:SetAlpha(0)
                        self:Hide()
                    end
                end
            end
        end)
    end
end
-- Hand a pooled UnitFrame back its parked pieces when the driver acquires it for a unit we do
-- not take over. Not at NAME_PLATE_UNIT_REMOVED: the driver has already released the frame
-- (base.UnitFrame is nil) before any addon sees that event. Enemy re-acquires skip this and
-- re-park in place. Zero cost for a frame no enemy ever held: one lookup.
function ns.NP_ReclaimBlizzardFrame(uf)
    local rec = uf and ns._npParked[uf]
    if not (rec and rec.held) or uf:IsForbidden() then return end
    -- Reverse park order, so the children return to uf in their original order.
    for i = #rec, 1, -1 do
        local child = rec[i]
        if storedParents[child] == uf then
            storedParents[child] = nil
            if child:GetParent() == npOffscreenParent then child:SetParent(uf) end
        end
    end
    wipe(rec)
    uf:SetAlpha(1)
    local auras = uf.AurasFrame
    local auraParent = auras and storedParents[auras]
    if auraParent then
        storedParents[auras] = nil
        if auras:GetParent() == npOffscreenParent then auras:SetParent(auraParent) end
    end
    -- The kept-live frames still sit on the base of the enemy that last held this frame.
    local wc, stf = uf.WidgetContainer, uf.SoftTargetFrame
    if wc and wc:GetParent() ~= uf then wc:SetParent(uf) end
    if stf and stf:GetParent() ~= uf then stf:SetParent(uf) end
end
-- WoW Forever: Blizzard's behind-camera arrow (the rotated offscreen icon under a plate
-- whose unit is behind the camera) stays hidden on every plate, friendly ones included.
-- Alpha only: Blizzard drives nothing but its shown state, so alpha 0 holds for the
-- life of the pooled UnitFrame; once per frame (weak external record, nothing written
-- on Blizzard's frame).
if EllesmereUI.IS_FOREVER then
    local hiddenBehindCam = setmetatable({}, { __mode = "k" })
    function ns.NP_HideBehindCameraIcon(uf)
        if not uf or hiddenBehindCam[uf] or uf:IsForbidden() then return end
        hiddenBehindCam[uf] = true
        local icon = uf.behindCameraIcon
        if icon then icon:SetAlpha(0) end
    end
end
ns.HideBlizzardFrame = HideBlizzardFrame
local castFallbackFrame = CreateFrame("Frame")
I.fallbackCastCount = 0
local _fallbackPlates = {}
castFallbackFrame._textAccum = 0.1
castFallbackFrame:SetScript("OnUpdate", function(self, elapsed)
    -- Bar fill tracks every frame (smoothness); target TEXT refreshes at 10Hz -- names never
    -- change faster and per-frame SetText is wasted, especially on secret strings.
    local textAccum = self._textAccum + elapsed
    local doText = textAccum >= 0.1
    self._textAccum = doText and 0 or textAccum
    for plate in pairs(_fallbackPlates) do
        if plate.isCasting and plate.unit and plate.nameplate then
            local bc = plate.nameplate.UnitFrame and plate.nameplate.UnitFrame.castBar
            if bc and bc:IsShown() then
                plate.cast:SetMinMaxValues(bc:GetMinMaxValues())
                plate.cast:SetValue(bc:GetValue())
                -- Keep spell name + target current in fallback mode.
                if doText and plate.UpdateCastText then
                    local castName = UnitCastingInfo(plate.unit)
                    if type(castName) == "nil" then castName = UnitChannelInfo(plate.unit) end
                    plate:UpdateCastText(castName)
                end
            else
                if not plate._interrupted then
                    plate.cast:Hide()
                end
                plate.isCasting = false
                plate._castFallback = nil
                _fallbackPlates[plate] = nil
                I.fallbackCastCount = I.fallbackCastCount - 1
                if I.fallbackCastCount <= 0 then
                    I.fallbackCastCount = 0
                    castFallbackFrame:Hide()
                end
                NotifyCastEnded(plate)
            end
        end
    end
end)
castFallbackFrame:Hide()

-- Shared cast-bar text anchoring. The text line holds three elements (spell name, spell
-- target, cast timer), each assigned to a side. The timer reserves a fixed width on its side;
-- a non-center element sharing that side shifts inward by that width. Center elements anchor
-- to the bar center and are never pushed.
--   side    : "left" | "right" | "center"
--   pushed  : true when the timer shares this side and this element must move in
--   reserve : timer reserved width (only consumed when pushed)
--   isTimer : the timer uses slightly tighter base insets than text
-- Returns: point (anchor), xOff (base, before the user X offset), justify
function ns.GetCastTextAnchor(side, pushed, reserve, isTimer)
    if side == "center" then
        return "CENTER", 0, "CENTER"
    elseif side == "left" then
        local base = isTimer and 3 or 5
        if pushed then base = base + reserve end
        return "LEFT", base, "LEFT"
    else -- "right"
        local base = -3
        if pushed then base = base - reserve end
        return "RIGHT", base, "RIGHT"
    end
end

-- WoW does not visually re-lay-out a FontString when only SetJustifyH changes (only a fresh
-- build does), so clear then re-set the text to force realignment -- and it MUST be a real
-- change, since re-setting an identical string is deduped and skips the re-layout. GetText may
-- return a secret (enemy name, cast name/target): SetText accepts secrets without inspecting
-- them, but truthiness/equality on a secret errors, so the existence check uses type() rather
-- than `t or ""`.
function ns.ReflowFontString(fs)
    local t = fs:GetText()
    fs:SetText("")
    if type(t) == "nil" then
        fs:SetText("")
    else
        fs:SetText(t)
    end
end

local NameplateFrame = {}

function NameplateFrame:UpdateCastText(spellName)
    local spellTarget, spellTargetClass
    if UnitShouldDisplaySpellTargetName and UnitShouldDisplaySpellTargetName(self.unit) then
        local rawTarget = UnitSpellTargetName and UnitSpellTargetName(self.unit)
        -- Names may be SECRET: type() is safe, and SetText/SetFormattedText accept secret
        -- strings without exposing them to Lua.
        if type(rawTarget) ~= "nil" then
            spellTarget = rawTarget
            spellTargetClass = UnitSpellTargetClass and UnitSpellTargetClass(self.unit)
        end
    end

    local hasTarget = type(spellTarget) ~= "nil"
    local db = p or defaults
    local combine = db.castCombineNameTarget == true
    local useClassColor = defaults.castTargetClassColor
    if db.castTargetClassColor ~= nil then useClassColor = db.castTargetClassColor end

    local targetColor
    if useClassColor then
        if type(spellTargetClass) ~= "nil" and C_ClassColor then
            targetColor = C_ClassColor.GetClassColor(spellTargetClass)
        end
    end

    local nameColor = db.castNameColor or defaults.castNameColor
    -- Combined mode paints the target color onto the cast NAME string (the target rides
    -- in it as a format arg); separate mode paints its own FontString.
    local targetText
    if combine and hasTarget then
        targetText = self.castName
    else
        targetText = self.castTarget
    end
    if useClassColor then
        if targetColor then
            targetText:SetTextColor(targetColor:GetRGB())
        else
            targetText:SetTextColor(1, 1, 1, 1)
        end
    else
        local c = db.castTargetColor or defaults.castTargetColor
        targetText:SetTextColor(c.r, c.g, c.b, 1)
    end
    if not combine or not hasTarget then
        self.castName:SetTextColor(nameColor.r, nameColor.g, nameColor.b, 1)
    end

    if type(spellName) == "nil" then
        self.castName:SetText("")
    elseif combine and hasTarget then
        -- 12.1 class RGB may be SECRET: use it as the FontString's base color,
        -- then override only the spell prefix with a clean profile-color escape.
        local nameHex = string.format("ff%02x%02x%02x",
            math.floor(nameColor.r * 255 + 0.5), math.floor(nameColor.g * 255 + 0.5),
            math.floor(nameColor.b * 255 + 0.5))
        self.castName:SetFormattedText("|c" .. nameHex .. "%s - |r%s", spellName, spellTarget)
    else
        self.castName:SetText(spellName)
    end
    if combine or not hasTarget then
        self.castTarget:SetText("")
    else
        self.castTarget:SetText(spellTarget)
    end

    local castW = self.cast:GetWidth()
    if castW and castW > 0 then
        local nameWidth = combine and 80 or (db.castNameWidthPct or defaults.castNameWidthPct)
        self.castName:SetWidth(castW * nameWidth / 100)
    end
    self.castName:SetShown((db.castNameSide or defaults.castNameSide) ~= "none")
    self.castTarget:SetShown(not combine and hasTarget
        and (db.castTargetSide or defaults.castTargetSide) ~= "none")
end

-- Appearance generation: bumped by RefreshAllSettings so plates re-apply static appearance on
-- next SetUnit. Plates stamp _appearanceGen after applying so cache-hit re-spawns skip the work.
ns._npAppearanceGen = ns._npAppearanceGen or 1

-- Static appearance: anchors, sizes, fonts, colors and aura layout depending only on settings,
-- not the bound unit. Runs once per plate after creation, then only when RefreshAllSettings
-- bumps the generation. Saves ~0.7ms per spawn.
function NameplateFrame:ApplyAppearance()
    self:SetSize(1, 1)
    local castH = GetCastBarHeight()
    self.health:ClearAllPoints()
    self.health:SetPoint("CENTER", self, "CENTER", 0, GetNameplateYOffset())
    self.health:SetSize(GetHealthBarWidth(), GetHealthBarHeight())
    ns.NP_SizeAbsorbBars(self, GetHealthBarWidth(), GetHealthBarHeight())
    -- (Classic WoW UI seats its health border from self:ApplyBorder below,
    -- once the bar carries its new size. A second seat here would repeat the
    -- level's font, anchors and unit reads for nothing.)
    ns.ApplyLowHpGlow(self)
    -- Width may have changed: clear the overlay gates so the next apply re-runs geometry (the
    -- stripe texcoord crop derives from the settings width, which the gates never watch).
    self._ovTgtTex, self._ovFocTex, self._ovHoverTex = nil, nil, nil
    ns.LayoutCastBar(self, ns.GetHealthBarWidth(), castH)
    ns.LayoutCastIcon(self, castH)
    local showIcon = GetShowCastIcon()
    if showIcon then
        self.castIconFrame:Show()
    else
        self.castIconFrame:Hide()
    end
    -- After the icon's own show state: the custom icon border is not its child.
    ns.ApplyCastIconBorder(self)
    self.castLeftBorder:SetWidth(1)
    ns.NP_SetSparkHeight(self, castH)
    -- Show Spark (Cast Color cog): default on; explicit false hides it.
    self.castSpark:SetShown(not (p and p.castBarSparkEnabled == false))
    self.kickMarker:SetSize(GetHealthBarWidth(), castH)
    -- Enemy name color (per-slot; any name-family variant)
    local nameSlotKey = ns.FindNameSlot()
    if nameSlotKey then
        local nr, ng, nb = GetTextSlotColor(nameSlotKey)
        self.name:SetTextColor(nr, ng, nb, 1)
    end
    -- The Threat Colors name memo: the static write above replaces its tint.
    self._nameThR, self._nameThG, self._nameThB = nil, nil, nil
    -- Same for the Text Coloring slot memo: the static slot colours written here and
    -- in ApplyHealthTextAppearance below replace what it last painted.
    if self._scMemo then
        for _, e in pairs(self._scMemo) do e[1] = nil end
    end
    self:RefreshNamePosition()
    -- Cast text sizes, colors, and offsets
    local cns = (p and p.castNameSize) or defaults.castNameSize
    local cts = (p and p.castTargetSize) or defaults.castTargetSize
    local cnc = (p and p.castNameColor) or defaults.castNameColor
    local ctmSz = (p and p.castTimerSize) or defaults.castTimerSize
    local ctmC = (p and p.castTimerColor) or defaults.castTimerColor
    local cnOX = (p and p.castNameOffsetX) or defaults.castNameOffsetX
    local cnOY = (p and p.castNameOffsetY) or defaults.castNameOffsetY
    local ctOX = (p and p.castTargetOffsetX) or defaults.castTargetOffsetX
    local ctOY = (p and p.castTargetOffsetY) or defaults.castTargetOffsetY
    local tmOX = (p and p.castTimerOffsetX) or defaults.castTimerOffsetX
    local tmOY = (p and p.castTimerOffsetY) or defaults.castTimerOffsetY
    SetFSFont(self.castName, cns, GetNPOutline())
    SetFSFont(self.castTarget, cts, GetNPOutline())
    SetFSFont(self.castTimer, ctmSz, GetNPOutline())
    self.castTimer:SetTextColor(ctmC.r, ctmC.g, ctmC.b, 1)
    local showTimer = defaults.showCastTimer
    if p and p.showCastTimer ~= nil then showTimer = p.showCastTimer end
    self._showCastTimer = showTimer
    local nameSide   = (p and p.castNameSide)   or defaults.castNameSide
    local targetSide = (p and p.castTargetSide) or defaults.castTargetSide
    local timerSide  = (p and p.castTimerSide)  or defaults.castTimerSide
    local combineNameTarget = p and p.castCombineNameTarget == true
    local castW = self.cast:GetWidth()
    local timerW = ctmSz * 2.2
    -- Per-element truncation: width as a % of the cast bar, plus a wrap toggle.
    local cnWPct = (p and p.castNameWidthPct) or defaults.castNameWidthPct
    local ctWPct = (p and p.castTargetWidthPct) or defaults.castTargetWidthPct
    local cnWrap = defaults.castNameWrap
    if p and p.castNameWrap ~= nil then cnWrap = p.castNameWrap end
    local ctWrap = defaults.castTargetWrap
    if p and p.castTargetWrap ~= nil then ctWrap = p.castTargetWrap end
    self.castName:SetWordWrap(cnWrap)
    self.castName:SetMaxLines(cnWrap and 2 or 1)
    self.castTarget:SetWordWrap(ctWrap)
    self.castTarget:SetNonSpaceWrap(false)
    self.castTarget:SetMaxLines(ctWrap and 2 or 1)
    if castW and castW > 0 then
        if nameSide ~= "none" then
            local pt, xb, jh = ns.GetCastTextAnchor(nameSide, showTimer and timerSide == nameSide, timerW, false)
            self.castName:SetWidth(castW * (combineNameTarget and 80 or cnWPct) / 100)
            self.castName:SetJustifyH(jh)
            self.castName:ClearAllPoints()
            self.castName:SetPoint(pt, self.cast, pt, xb + cnOX, cnOY)
        end
        if targetSide ~= "none" then
            local pt, xb, jh = ns.GetCastTextAnchor(targetSide, showTimer and timerSide == targetSide, timerW, false)
            self.castTarget:SetWidth(castW * ctWPct / 100)
            self.castTarget:SetJustifyH(jh)
            self.castTarget:ClearAllPoints()
            self.castTarget:SetPoint(pt, self.cast, pt, xb + ctOX, ctOY)
        end
        -- Timer side is only "left"/"right"; visibility stays governed by showTimer.
        local tpt, txb, tjh = ns.GetCastTextAnchor(timerSide, false, timerW, true)
        -- timerW stays the layout reserve (pushes name/target inward above), but the timer
        -- FontString auto-sizes (width 0) so a long value never truncates. Pinned by its outer
        -- edge (RIGHT on the right side, LEFT on the left), so overflow grows inward past the
        -- reserved slot while the pinned edge holds.
        self.castTimer:SetWidth(0)
        self.castTimer:SetJustifyH(tjh)
        self.castTimer:ClearAllPoints()
        self.castTimer:SetPoint(tpt, self.cast, tpt, txb + tmOX, tmOY)
    end
    -- Base visibility by side (UpdateCast refines the target per cast on hasTarget).
    self.castName:SetShown(nameSide ~= "none")
    self.castTarget:SetShown(not combineNameTarget and targetSide ~= "none")
    self.castTimer:SetShown(showTimer)
    -- Force the new justify onto already-rendered text (side changed mid-cast): a fresh cast
    -- re-flows itself via UpdateCast, a live setting change does not.
    ns.ReflowFontString(self.castName)
    ns.ReflowFontString(self.castTarget)
    ns.ReflowFontString(self.castTimer)
    self.castName:SetTextColor(cnc.r, cnc.g, cnc.b, 1)
    local function GetAuraDurationCfg(kind)
        local sizeKey = kind .. "DurationTextSize"
        local xKey = kind .. "DurationTextX"
        local yKey = kind .. "DurationTextY"
        local colorKey = kind .. "DurationTextColor"
        return {
            size = (p and p[sizeKey]) or (p and p.auraDurationTextSize) or defaults.auraDurationTextSize,
            x = (p and p[xKey]) or (p and p.auraDurationTextX) or defaults.auraDurationTextX,
            y = (p and p[yKey]) or (p and p.auraDurationTextY) or defaults.auraDurationTextY,
            color = (p and p[colorKey]) or (p and p.auraDurationTextColor) or defaults.auraDurationTextColor,
        }
    end
    local debuffDur = GetAuraDurationCfg("debuff")
    local buffDur = GetAuraDurationCfg("buff")
    local ccDur = GetAuraDurationCfg("cc")
    local auraStackSize = (p and p.auraStackTextSize) or defaults.auraStackTextSize
    local auraStackColor = (p and p.auraStackTextColor) or defaults.auraStackTextColor
    local auraStackX = (p and p.auraStackTextX) or defaults.auraStackTextX
    local auraStackY = (p and p.auraStackTextY) or defaults.auraStackTextY
    local auraStackPos = (p and p.auraStackTextPosition) or defaults.auraStackTextPosition
    local debuffTPos = (p and p.debuffTimerPosition) or (p and p.auraTextPosition) or defaults.debuffTimerPosition
    local buffTPos   = (p and p.buffTimerPosition)   or (p and p.auraTextPosition) or defaults.buffTimerPosition
    local ccTPos     = (p and p.ccTimerPosition)     or (p and p.auraTextPosition) or defaults.ccTimerPosition
    local function ApplyTimerPosition(durText, auraFrame, pos, cfg)
        local cd = auraFrame.cd
        if pos == "none" then
            if cd and cd.SetHideCountdownNumbers then
                cd:SetHideCountdownNumbers(true)
            end
            return
        end
        if cd and cd.SetHideCountdownNumbers then
            cd:SetHideCountdownNumbers(false)
        end
        SetFSFont(durText, cfg.size, "OUTLINE, SLUG")
        durText:SetTextColor(cfg.color.r, cfg.color.g, cfg.color.b, 1)
        durText:ClearAllPoints()
        if pos == "center" then
            durText:SetPoint("CENTER", auraFrame, "CENTER", cfg.x, cfg.y)
            durText:SetJustifyH("CENTER")
        elseif pos == "topright" then
            PP.Point(durText, "TOPRIGHT", auraFrame, "TOPRIGHT", 3 + cfg.x, 4 + cfg.y)
            durText:SetJustifyH("RIGHT")
        elseif pos == "bottomleft" then
            PP.Point(durText, "BOTTOMLEFT", auraFrame, "BOTTOMLEFT", -3 + cfg.x, -4 + cfg.y)
            durText:SetJustifyH("LEFT")
        elseif pos == "bottomright" then
            PP.Point(durText, "BOTTOMRIGHT", auraFrame, "BOTTOMRIGHT", 3 + cfg.x, -4 + cfg.y)
            durText:SetJustifyH("RIGHT")
        else
            PP.Point(durText, "TOPLEFT", auraFrame, "TOPLEFT", -3 + cfg.x, 4 + cfg.y)
            durText:SetJustifyH("LEFT")
        end
    end
    local function ApplyStackPosition(countText, auraFrame, pos)
        if pos == "none" then
            countText:Hide()
            return
        end
        countText:Show()
        countText:ClearAllPoints()
        if pos == "center" then
            countText:SetPoint("CENTER", auraFrame, "CENTER", auraStackX, auraStackY)
            countText:SetJustifyH("CENTER")
        elseif pos == "topright" then
            PP.Point(countText, "TOPRIGHT", auraFrame, "TOPRIGHT", 3 + auraStackX, 4 + auraStackY)
            countText:SetJustifyH("RIGHT")
        elseif pos == "bottomleft" then
            PP.Point(countText, "BOTTOMLEFT", auraFrame, "BOTTOMLEFT", -3 + auraStackX, -4 + auraStackY)
            countText:SetJustifyH("LEFT")
        elseif pos == "topleft" then
            PP.Point(countText, "TOPLEFT", auraFrame, "TOPLEFT", -3 + auraStackX, 4 + auraStackY)
            countText:SetJustifyH("LEFT")
        else
            PP.Point(countText, "BOTTOMRIGHT", auraFrame, "BOTTOMRIGHT", 3 + auraStackX, -4 + auraStackY)
            countText:SetJustifyH("RIGHT")
        end
    end
    for i = 1, #self.debuffs do
        if self.debuffs[i] and self.debuffs[i].cd and self.debuffs[i].cd.text then
            SetFSFont(self.debuffs[i].cd.text, debuffDur.size, "OUTLINE, SLUG")
            self.debuffs[i].cd.text:SetTextColor(debuffDur.color.r, debuffDur.color.g, debuffDur.color.b, 1)
            ApplyTimerPosition(self.debuffs[i].cd.text, self.debuffs[i], debuffTPos, debuffDur)
        end
        if self.debuffs[i] and self.debuffs[i].count then
            SetFSFont(self.debuffs[i].count, auraStackSize, "OUTLINE, SLUG")
            self.debuffs[i].count:SetTextColor(auraStackColor.r, auraStackColor.g, auraStackColor.b, 1)
            ApplyStackPosition(self.debuffs[i].count, self.debuffs[i], auraStackPos)
        end
    end
    local debuffSz = GetDebuffIconSize()
    local buffSz = GetBuffIconSize()
    local ccSz = GetCCIconSize()
    local debuffCrop = ns.GetAuraCrop("debuffs")
    local buffCrop = ns.GetAuraCrop("buffs")
    local ccCrop = ns.GetAuraCrop("ccs")
    local debuffH = ns.GetAuraCropHeight(debuffCrop, debuffSz)
    local buffH = ns.GetAuraCropHeight(buffCrop, buffSz)
    local ccH = ns.GetAuraCropHeight(ccCrop, ccSz)
    local debuffSlot, buffSlot, ccSlot = GetAuraSlots()
    for i = 1, #self.debuffs do
        ns.ApplyAuraSlotCrop(self.debuffs[i], debuffCrop, debuffSz)
        ns.ApplyFrameIconBorder(self.debuffs[i], ns.GetIconBorderEnabled("debuffs"), true)
    end
    for i = 1, 4 do
        ns.ApplyAuraSlotCrop(self.buffs[i], buffCrop, buffSz)
        ns.ApplyFrameIconBorder(self.buffs[i], ns.GetIconBorderEnabled("buffs"), true)
        if self.buffs[i].cd and self.buffs[i].cd.text then
            SetFSFont(self.buffs[i].cd.text, buffDur.size, "OUTLINE, SLUG")
            self.buffs[i].cd.text:SetTextColor(buffDur.color.r, buffDur.color.g, buffDur.color.b, 1)
            ApplyTimerPosition(self.buffs[i].cd.text, self.buffs[i], buffTPos, buffDur)
        end
        if self.buffs[i].count then
            SetFSFont(self.buffs[i].count, auraStackSize, "OUTLINE, SLUG")
            self.buffs[i].count:SetTextColor(auraStackColor.r, auraStackColor.g, auraStackColor.b, 1)
            ApplyStackPosition(self.buffs[i].count, self.buffs[i], auraStackPos)
        end
    end
    PositionAuraSlot(self.buffs, 4, buffSlot, self, buffSz, buffH, GetAuraSpacing("buffs"), GetAuraSlotOffsets("buffSlot"))
    for i = 1, 2 do
        ns.ApplyAuraSlotCrop(self.cc[i], ccCrop, ccSz)
        ns.ApplyFrameIconBorder(self.cc[i], ns.GetIconBorderEnabled("ccs"), true)
        if self.cc[i].cd and self.cc[i].cd.text then
            SetFSFont(self.cc[i].cd.text, ccDur.size, "OUTLINE, SLUG")
            self.cc[i].cd.text:SetTextColor(ccDur.color.r, ccDur.color.g, ccDur.color.b, 1)
            ApplyTimerPosition(self.cc[i].cd.text, self.cc[i], ccTPos, ccDur)
        end
    end
    PositionAuraSlot(self.cc, 2, ccSlot, self, ccSz, ccH, GetAuraSpacing("ccs"), GetAuraSlotOffsets("ccSlot"))
    ApplyHealthBarTexture(self)
    ns.ApplyCastBarTexture(self)
    ns.ApplyAbsorbStyle(self)
    self:ApplyBorder()
    self:ApplyBorderColor()
    if self.ApplyCastBorder then self:ApplyCastBorder() end
    if self.ApplyCastBorderColor then self:ApplyCastBorderColor() end
    self:ApplyHealthTextAppearance()
    if ns.RefreshCastOverlay then ns.RefreshCastOverlay(self) end
    -- Re-sync the cast-bar wrap LAST, after normal borders and cast-overlay lift are
    -- re-applied: for a wrapped plate this re-hides the borders ApplyBorder/ApplyCastBorder
    -- just re-showed (no double border). Pure no-op unless enabled or wrapped.
    if self.UpdateBorderWrap and (self._wrapActive or self._cbWrapActive or ns.GetWrapBorderCastbar()) then
        self:UpdateBorderWrap()
    end
    ns.ApplySlotStrata(self)
end

-- PERF: health text font/position/color + cached slot assignments. Called from ApplyAppearance
-- (settings change/fresh plate), NEVER per health tick; UpdateHealthValues only rewrites text
-- content via the cache.
-- Anchors one bar-slot font string. A bottom slot hangs under the health bar's
-- corner and drops below the cast bar while one shows (AnchorBottomTexts
-- re-runs this on every cast show / hide).
function NameplateFrame:PlaceSlotText(fs, slot, txOff, tyOff)
    fs:ClearAllPoints()
    if slot.bottom then
        local drop = (self.cast:IsShown() and self._castDrop) or 0
        PP.Point(fs, slot.anchor, self.health, slot.point, slot.xOff + txOff, drop - 2 + tyOff)
    elseif slot.anchor == "CENTER" then
        fs:SetPoint("CENTER", self.health, "CENTER", txOff, tyOff)
    else
        PP.Point(fs, slot.anchor, self.health, slot.point, slot.xOff + txOff, tyOff)
    end
end
-- Cast shown or hidden: re-anchor whatever the bottom slots hold. Runs only
-- while a bottom slot is in use (ns._npBottomUsed).
function NameplateFrame:AnchorBottomTexts()
    local B = ns._npBottomFS
    for si = 4, 5 do
        local slot = HP_BAR_SLOTS[si]
        local key = B[si - 3]
        local fs = key and self[key]
        if fs then
            -- Prebuilt keys: this runs on every cast show / hide.
            local txOff = (p and p[slot.xKey]) or 0
            local tyOff = (p and p[slot.yKey]) or 0
            if key == "name" and si == 4 and self._nameRaidMarkerShown then
                txOff = txOff + ((p and p.nameRaidMarkerSize) or defaults.nameRaidMarkerSize or 14) + 3
            end
            self:PlaceSlotText(fs, slot, txOff, tyOff)
        end
    end
end
-- Target of Target text: its own font string, built the first time a slot
-- shows it.
function NameplateFrame:EnsureToTText()
    local fs = self.totText
    if not fs then
        fs = self.healthTextFrame:CreateFontString(nil, "OVERLAY")
        SetFSFont(fs, 10, GetNPOutline())
        fs:Hide()
        self.totText = fs
    end
    return fs
end
-- The unit's target's name, repainted on UNIT_TARGET (registered only while a
-- slot shows it). Name and class token may be secret: they only reach setters.
-- The slot's Class text mode paints a player target in its class colour; anything
-- else keeps the slot colour.
function NameplateFrame:UpdateToT()
    local fs, unit, slotKey = self.totText, self.unit, ns._npToTSlot
    if not (fs and unit and slotKey) then return end
    local tu = ns._npToTUnits[unit]
    if not tu then tu = unit .. "target"; ns._npToTUnits[unit] = tu end
    -- No target: a space, so the text keeps its line (top auras and the range
    -- text anchor to it).
    if not UnitExists(tu) then fs:SetText(" "); return end
    -- WoW Forever joins the surname and applies the slot's Name Format (retail:
    -- the name as is; NP_FormatName is nil there).
    local name = EllesmereUI.WithSurname(UnitName(tu))
    if ns.NP_FormatName then name = ns.NP_FormatName(name, slotKey) end
    fs:SetText(name)
    if not ns._npToTClass then return end
    local tok
    if UnitIsPlayer(tu) then tok = UnitClassBase(tu) end
    if type(tok) ~= "nil" then
        if issecretvalue(tok) then
            -- Same order as the slot painter: the restricted-unit palette, then Blizzard's.
            local ok, r, g, b = EllesmereUI.GetClassColorForRestrictedUnit(tu, tok)
            if ok then fs:SetTextColor(r, g, b, 1); return end
            local c = C_ClassColor.GetClassColor(tok)
            if c then fs:SetTextColor(c:GetRGB()); return end
        else
            local c = EllesmereUI.GetClassColor(tok)
            if c then fs:SetTextColor(c.r, c.g, c.b, 1); return end
        end
    end
    local c = (p and p[ns._npToTColorKey]) or defaults[ns._npToTColorKey]
    if c then fs:SetTextColor(c.r, c.g, c.b, 1) else fs:SetTextColor(1, 1, 1, 1) end
end
function NameplateFrame:UNIT_TARGET()
    self:UpdateToT()
end
-- Target of Target for the plate's (new) unit: UNIT_TARGET follows the token
-- while a slot shows it, and the text repaints. Plate acquire and both
-- occupant-swap paths come here.
function NameplateFrame:SyncToT(unit)
    if ns._npToTSlot then
        if self._totEv ~= unit then
            self:RegisterUnitEvent("UNIT_TARGET", unit)
            self._totEv = unit
        end
        self:UpdateToT()
    elseif self._totEv then
        self:UnregisterEvent("UNIT_TARGET")
        self._totEv = nil
    end
end

function NameplateFrame:ApplyHealthTextAppearance()
    self.hpText:Hide()
    self.hpNumber:Hide()
    if self.levelText then self.levelText:Hide() end
    if self.totText then self.totText:Hide() end
    -- Slot assignments may change element kinds: drop the value memo so the
    -- next UpdateHealthValues rewrites every slot's content.
    self._hpTxtPct, self._hpTxtCur = nil, nil
    if not self._cachedHealthSlots then
        self._cachedHealthSlots = { _count = 0 }
    end
    local ca = self._cachedHealthSlots
    -- Slot kinds may change: re-derive the lazily-computed number/combo flag.
    ca._anyNum = nil
    local ci = 0

    for si = 1, #HP_BAR_SLOTS do
        local slot = HP_BAR_SLOTS[si]
        local element = GetTextSlot(slot.key)
        local txOff, tyOff = GetTextSlotOffsets(slot.key)
        local slotFontSz = GetTextSlotSize(slot.key)
        local sr, sg, sb = GetTextSlotColor(slot.key)
        local slotStrata = (p and p[slot.key .. "Strata"]) or "MEDIUM"
        if element == "healthPercent" or element == "healthPercentNoSign" then
            local fs = self.hpText
            fs:SetParent(ns.SlotTextHost(self, slot.key, slotStrata))
            SetFSFont(fs, slotFontSz, GetNPOutline())
            self:PlaceSlotText(fs, slot, txOff, tyOff)
            fs:SetJustifyH(slot.justify or slot.anchor)
            fs:SetTextColor(sr, sg, sb, 1)
            fs:Show()
            ci = ci + 1
            if not ca[ci] then ca[ci] = {} end
            ca[ci].element = element
            ca[ci].fs = fs
            ca[ci].slotKey = slot.key
            ca[ci].bottom = slot.bottom or false
        elseif element == "healthNumber" then
            local fs = self.hpNumber
            fs:SetParent(ns.SlotTextHost(self, slot.key, slotStrata))
            SetFSFont(fs, slotFontSz, GetNPOutline())
            self:PlaceSlotText(fs, slot, txOff, tyOff)
            fs:SetJustifyH(slot.justify or slot.anchor)
            fs:SetTextColor(sr, sg, sb, 1)
            fs:Show()
            ci = ci + 1
            if not ca[ci] then ca[ci] = {} end
            ca[ci].element = element
            ca[ci].fs = fs
            ca[ci].slotKey = slot.key
            ca[ci].bottom = slot.bottom or false
        elseif IsComboHealthText(element) then
            local fs = self.hpText
            fs:SetParent(ns.SlotTextHost(self, slot.key, slotStrata))
            SetFSFont(fs, slotFontSz, GetNPOutline())
            self:PlaceSlotText(fs, slot, txOff, tyOff)
            fs:SetJustifyH(slot.justify or slot.anchor)
            fs:SetTextColor(sr, sg, sb, 1)
            fs:Show()
            ci = ci + 1
            if not ca[ci] then ca[ci] = {} end
            ca[ci].element = element
            ca[ci].fs = fs
            ca[ci].slotKey = slot.key
            ca[ci].bottom = slot.bottom or false
        elseif element == "level" or element == "targetOfTarget" then
            -- Standalone level / Target of Target: own FontString, NOT in the health slot
            -- cache (level content is static per unit -- written here and by UpdateName on
            -- acquire; Target of Target rides UNIT_TARGET -- never on health ticks).
            -- Width/wrap applied inline since the cache loop below skips it.
            local isLevel = element == "level"
            local fs = isLevel and self.levelText or self:EnsureToTText()
            fs:SetParent(ns.SlotTextHost(self, slot.key, slotStrata))
            SetFSFont(fs, slotFontSz, GetNPOutline())
            self:PlaceSlotText(fs, slot, txOff, tyOff)
            fs:SetJustifyH(slot.justify or slot.anchor)
            fs:SetTextColor(sr, sg, sb, 1)
            if isLevel and self.unit then fs:SetText(ns.GetUnitLevelText(self.unit)) end
            -- The bottom slots never truncate: no Width % or Wrap there.
            local lwpct = (not slot.bottom and p and p[slot.key .. "WidthPct"]) or 100
            fs:SetWidth(lwpct < 100 and (GetHealthBarWidth() * lwpct / 100) or 0)
            local lwrap = (not slot.bottom and p and p[slot.key .. "Wrap"]) and true or false
            fs:SetWordWrap(lwrap)
            fs:SetMaxLines(lwrap and 2 or 1)
            fs:Show()
        end
    end

    -- Top slot health text
    local topElement = GetTextSlot("textSlotTop")
    if topElement == "healthPercent" or topElement == "healthPercentNoSign" or topElement == "healthNumber"
       or IsComboHealthText(topElement) then
        local nameYOff = GetNameYOffset()
        local cpPush = GetClassPowerTopPush(self)
        local txOff, tyOff = GetTextSlotOffsets("textSlotTop")
        local topFontSz = GetTextSlotSize("textSlotTop")
        local tr, tg, tb = GetTextSlotColor("textSlotTop")
        local fs
        if topElement == "healthNumber" then
            fs = self.hpNumber
        else
            fs = self.hpText
        end
        SetFSFont(fs, topFontSz, GetNPOutline())
        fs:SetParent(ns.SlotTextHost(self, "textSlotTop", (p and p.textSlotTopStrata) or "MEDIUM"))
        fs:ClearAllPoints()
        PP.Point(fs, "BOTTOM", self.health, "TOP", txOff, 4 + nameYOff + cpPush + tyOff)
        fs:SetJustifyH("CENTER")
        fs:SetTextColor(tr, tg, tb, 1)
        fs:Show()
        ci = ci + 1
        if not ca[ci] then ca[ci] = {} end
        ca[ci].element = topElement
        ca[ci].fs = fs
        ca[ci].slotKey = "textSlotTop"
        ca[ci].bottom = false
    elseif topElement == "level" or topElement == "targetOfTarget" then
        -- Standalone level / Target of Target in the top slot: same shape as the
        -- health block above, on its own font string, no cache entry.
        local nameYOff = GetNameYOffset()
        local cpPush = GetClassPowerTopPush(self)
        local txOff, tyOff = GetTextSlotOffsets("textSlotTop")
        local topFontSz = GetTextSlotSize("textSlotTop")
        local tr, tg, tb = GetTextSlotColor("textSlotTop")
        local isLevel = topElement == "level"
        local fs = isLevel and self.levelText or self:EnsureToTText()
        SetFSFont(fs, topFontSz, GetNPOutline())
        fs:SetParent(ns.SlotTextHost(self, "textSlotTop", (p and p.textSlotTopStrata) or "MEDIUM"))
        fs:ClearAllPoints()
        PP.Point(fs, "BOTTOM", self.health, "TOP", txOff, 4 + nameYOff + cpPush + tyOff)
        fs:SetJustifyH("CENTER")
        fs:SetTextColor(tr, tg, tb, 1)
        if isLevel and self.unit then fs:SetText(ns.GetUnitLevelText(self.unit)) end
        local lwpct = (p and p.textSlotTopWidthPct) or 100
        fs:SetWidth(lwpct < 100 and (GetHealthBarWidth() * lwpct / 100) or 0)
        local lwrap = (p and p.textSlotTopWrap) and true or false
        fs:SetWordWrap(lwrap)
        fs:SetMaxLines(lwrap and 2 or 1)
        fs:Show()
    end
    ca._count = ci
    -- Per-slot health % decimal preference, resolved in this rare appearance pass and cached
    -- per entry + an _anyDecimal flag, so the per-tick render in UpdateHealthValues stays lean.
    local barW = GetHealthBarWidth()
    local anyDec = false
    for i = 1, ci do
        local e = ca[i]
        local el = e.element
        if el == "healthPercent" or el == "healthPercentNoSign"
           or IsComboHealthText(el) then
            local dec = (p and e.slotKey and p[e.slotKey .. "PctDecimal"]) and true or false
            e.pctDecimal = dec
            if dec then anyDec = true end
        else
            e.pctDecimal = false
        end
        -- Per-slot Width % of the health bar + Wrap. SetWidth/SetWordWrap re-flow the
        -- FontString themselves (only SetJustifyH needs ReflowFontString), and
        -- UpdateHealthValues re-sets text on the same SetUnit pass, so no reflow here. Default
        -- 100 = unconstrained (SetWidth 0 = auto-size): a width box on a single-point-anchored
        -- FontString ignores SetJustifyH and would re-centre a right/left value, so only box
        -- it when narrowed.
        -- The bottom slots never truncate: no Width % or Wrap there.
        local wpct = (not e.bottom and p and e.slotKey and p[e.slotKey .. "WidthPct"]) or 100
        e.fs:SetWidth(wpct < 100 and (barW * wpct / 100) or 0)
        local wrap = false
        if not e.bottom and p and e.slotKey and p[e.slotKey .. "Wrap"] ~= nil then wrap = p[e.slotKey .. "Wrap"] end
        e.fs:SetWordWrap(wrap)
        e.fs:SetMaxLines(wrap and 2 or 1)
    end
    ca._anyDecimal = anyDec
end

function NameplateFrame:SetUnit(unit, nameplate)
    self.unit = unit
    self.nameplate = nameplate
    self:SetParent(nameplate)
    self:ClearAllPoints()
    self:SetPoint("CENTER", nameplate, "CENTER", 0, GetHitboxYShift())
    self:SetFrameLevel(nameplate:GetFrameLevel() + 1)
    self:Show()
    -- Recycled/fresh plate: forget any prior eased scale so the first ApplyScale snaps instead of growing in from a stale one.
    self._curScale = nil
    ns._scaleAnim[self] = nil
    if ns._hitboxOverlayShown or self.hitboxOverlay then ns._ApplyHitboxOverlay(self) end
    -- Apply static appearance only when stale (settings changed or fresh pool plate).
    if self._appearanceGen ~= ns._npAppearanceGen then
        self:ApplyAppearance()
        self._appearanceGen = ns._npAppearanceGen
    end
    HideBlizzardFrame(nameplate, unit)
    self:RegisterUnitEvent("UNIT_HEALTH", unit)
    self:RegisterUnitEvent("UNIT_MAXHEALTH", unit)
    self:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", unit)
    self:RegisterUnitEvent("UNIT_NAME_UPDATE", unit)
    self:RegisterUnitEvent("UNIT_THREAT_LIST_UPDATE", unit)
    -- Target of Target text: its event only while a slot shows it.
    self:SyncToT(unit)
    -- Attach a pooled aura-container bundle for this unit.
    if ns.NPC_AttachPlate then ns.NPC_AttachPlate(self, unit) end
    if ns.DebuffColors_Attach then ns.DebuffColors_Attach(self, unit) end
    -- Non-Target Opacity (zero cost while off: one numeric compare).
    if ns._ntAlpha < 1 then ns.NT_Apply(self) end
    -- Execute glow is per-spawn state, not appearance: ApplyAppearance is generation-cached
    -- (skipped on recycled plates) and the threshold watcher only reaches plates active at flip
    -- time, so a plate pooled during a no-execute window would return glowless. Re-assert.
    ns.ApplyLowHpGlow(self)
    -- Critical: health bar must display immediately
    self:UpdateHealth()
    -- PERF: defer non-critical work 1 frame. Stacking bounds, name, cast bar, classification,
    -- raid icon, target glow, mouseover -- all imperceptible 1 frame late. Cuts ~40% off spike.
    self._castDirtyFull = true
    if not self._deferredSetupCB then
        self._deferredSetupCB = function()
            if not self.unit then return end
            local np = self.nameplate
            -- Stacking bounds
            if np and np.SetStackingBoundsFrame then
                if not self._stackBounds then
                    self._stackBounds = CreateFrame("Frame", nil, np)
                    -- Load-bearing: SetStackingBoundsFrame reads this frame's rendered bounds
                    -- (union of its regions), NOT its SetSize. Without a full-size region the
                    -- bounds rect is empty and plates stop stacking. Alpha 0 so it never shows.
                    local tex = self._stackBounds:CreateTexture(nil, "BACKGROUND")
                    tex:SetColorTexture(1, 0, 0, 0)
                    tex:SetAllPoints(self._stackBounds)
                end
                self._stackBounds:SetParent(np)
                self._stackBounds:ClearAllPoints()
                local barH = GetHealthBarHeight()
                local castH2 = GetCastBarHeight()
                local nameGap = 4 + GetEnemyNameTextSize()
                local totalH = nameGap + barH + castH2
                local scale = GetStackSpacingScale() / 100
                self._stackBounds:SetPoint("CENTER", np, "CENTER", 0, GetNameplateYOffset())
                self._stackBounds:SetSize(GetHealthBarWidth(), totalH * scale)
                self._stackBounds:Show()
                np:SetStackingBoundsFrame(self._stackBounds)
            end
            -- Focus cast height override
            if UnitIsUnit(self.unit, "focus") then
                local pct = GetFocusCastHeight()
                if pct ~= 100 then
                    local castH = math.floor(GetCastBarHeight() * pct / 100 + 0.5)
                    ns.LayoutCastBar(self, ns.GetHealthBarWidth(), castH)
                    ns.LayoutCastIcon(self, castH)
                    ns.NP_SetSparkHeight(self, castH)
                    self.kickMarker:SetSize(GetHealthBarWidth(), castH)
                end
            end
            -- Cast target color
            local useClassColor = defaults.castTargetClassColor
            if p and p.castTargetClassColor ~= nil then useClassColor = p.castTargetClassColor end
            if useClassColor then
                local appliedCTC = false
                local classToken
                if UnitSpellTargetClass then
                    classToken = UnitSpellTargetClass(self.unit)
                end
                -- classToken may be SECRET: type() is the safe nil check
                if type(classToken) == "nil" then
                    local targetUnit = self.unit .. "target"
                    if UnitIsPlayer(targetUnit) then
                        classToken = UnitClassBase(targetUnit)
                    end
                end
                if type(classToken) ~= "nil" and C_ClassColor then
                    local c = C_ClassColor.GetClassColor(classToken)
                    if c then
                        self.castTarget:SetTextColor(c:GetRGB())
                        appliedCTC = true
                    end
                end
                if not appliedCTC then
                    self.castTarget:SetTextColor(1, 1, 1, 1)
                end
            else
                local ctc = (p and p.castTargetColor) or defaults.castTargetColor
                self.castTarget:SetTextColor(ctc.r, ctc.g, ctc.b, 1)
            end
            self:UpdateName()
            self:UpdateClassification()
            if not (p and p.classificationIncludeFaction) then self:UpdateFaction() end
            self:UpdateRaidIcon()
            if p and p.nameRaidMarkerEnabled == true then self:RefreshNamePosition(true) end
            self:ApplyTarget()
            self:ApplyMouseover()
            self:UpdateCast()
            -- Mirrored class colour only: on a fresh plate Blizzard's own SetUnit may not have
            -- run yet, in which case the same-unit guard refused to mirror and the plate is
            -- wearing the plain fallback. Retry once a frame later so it does not sit there
            -- until the unit's next health event.
            if self._mirrorPending then self:UpdateHealthColor() end
        end
    end
    C_Timer.After(0, self._deferredSetupCB)
end
function NameplateFrame:ClearUnit()
    self:UnregisterAllEvents()
    self._factionEv = nil
    self._totEv = nil

    -- Classic WoW UI: blank the level in the border's plate. Plates are
    -- pooled, so a recycled one would otherwise carry the last unit's level
    -- until its first paint.
    if self._classicLevel then
        self._classicLevel:SetText("")
        if self._classicSkull then self._classicSkull:Hide() end
    end
    -- WoW Forever: the level box waits for the next unit's level.
    if self._fvLevelBox then self._fvLevelBox:Hide() end

    -- Non-Target Opacity: released pool frames always go back at full
    -- alpha (nil _ntCurAlpha = never faded, keeps this a no-op).
    if self._ntCurAlpha and self._ntCurAlpha < 1 then
        self:SetAlpha(1)
    end
    self._ntCurAlpha = nil
    self._oorCurAlpha = nil

    if self.isCasting then
        self.isCasting = false
        if self._castFallback then
            self._castFallback = nil
            _fallbackPlates[self] = nil
            I.fallbackCastCount = I.fallbackCastCount - 1
            if I.fallbackCastCount <= 0 then I.fallbackCastCount = 0; castFallbackFrame:Hide() end
        end
        NotifyCastEnded(self)
    end

    self.name:SetText("")
    for i = 1, 2 do
        local slot = self.cc[i]
        if slot.cd then
            if slot.cd.SetDrawSwipe then slot.cd:SetDrawSwipe(false) end
            if slot.cd.Clear then slot.cd:Clear() else slot.cd:SetCooldown(0, 0) end
            slot.cd:Hide()
        end
        RawSetTex(slot.icon, nil)
        slot:Hide()
        slot._auraId = nil
    end
    for i = 1, #self.debuffs do
        local dSlot = self.debuffs[i]
        if dSlot.cd then
            if dSlot.cd.SetDrawSwipe then dSlot.cd:SetDrawSwipe(false) end
            if dSlot.cd.Clear then dSlot.cd:Clear() else dSlot.cd:SetCooldown(0, 0) end
            dSlot.cd:Hide()
        end
        RawSetTex(dSlot.icon, nil)
        dSlot:Hide()
        dSlot._durationObj = nil
        dSlot._auraId = nil
    end
    for i = 1, 4 do
        local bSlot = self.buffs[i]
        if bSlot.cd then
            if bSlot.cd.SetDrawSwipe then bSlot.cd:SetDrawSwipe(false) end
            if bSlot.cd.Clear then bSlot.cd:Clear() else bSlot.cd:SetCooldown(0, 0) end
            bSlot.cd:Hide()
        end
        RawSetTex(bSlot.icon, nil)
        bSlot:Hide()
        if bSlot.dispelGlow and bSlot.dispelGlow.active then
            ns.StopDispelGlow(bSlot)
        end
        bSlot._auraId = nil
    end
    -- Release this plate's aura-container bundle back to the pool.
    if ns.NPC_DetachPlate then ns.NPC_DetachPlate(self) end
    if ns.DebuffColors_Detach then ns.DebuffColors_Detach(self) end
    self.unit = nil
    self.nameplate = nil
    self._absorbHidden = nil
    self._maxHPValid = nil
    self._lastHCr, self._lastHCg, self._lastHCb = nil, nil, nil
    self._mirrorPending = nil
    -- Threat Colors border/text channels: drop the skip-if-unchanged caches so a recycled
    -- plate always repaints for its new unit. _threatBdOn / _threatNameOn are deliberately
    -- LEFT set -- they record that the border and name still carry a threat tint, and the
    -- next UpdateHealthColor uses that to hand them back if the new unit has no signal.
    self._threatBdKr, self._threatBdKg, self._threatBdKb = nil, nil, nil
    self._nameThR, self._nameThG, self._nameThB = nil, nil, nil
    -- Hostility / Class slot colours: the next occupant's class token is read afresh.
    self._scUnit = nil
    -- Health-text value memo (UpdateHealthValues): a recycled plate must
    -- always write its first values, never skip against the old unit's.
    self._hpTxtPct, self._hpTxtCur = nil, nil
    self._ovFocShown, self._ovTgtShown = nil, nil
    self._focusLetterShown = nil
    if self._tptShown then self.threatPctText:Hide() end
    self._tptShown = nil
    self._kickIsChannel = nil
    self._castIsChannel = nil
    self._kickIsEmpowered = nil
    self._kickGeoDirty = nil
    self._castTex = nil
    self._castLockout = nil
    self._nameRaidMarkerShown = nil
    -- A recycled frame's first health paint must not treat the new occupant as
    -- the old target (the hash line reads this flag).
    self._isTarget = nil
    self.cast:Hide()
    self.castShieldFrame:Hide()
    self.castShieldFrame:SetAlpha(1)
    self.castBarOverlay:SetAlpha(0)
    self.isCasting = false
    self._castFallback = nil
    _fallbackPlates[self] = nil
    self._kickProtected = nil
    self._castImportant = false
    self:HideKickTick()
    if self._interruptTimer then
        self._interruptTimer:Cancel()
        self._interruptTimer = nil
    end
    self._interrupted = nil
    if self.glow then self.glow:Hide() end
    if self.targetHighlight then self.targetHighlight:Hide() end
    ns.HideHoverEffect(self)
    if self.nameRaidFrame then self.nameRaidFrame:Hide() end
    self.raidFrame:Hide()
    self.classFrame:Hide()
    if self.factionFrame then self.factionFrame:Hide() end
    if self.classText then self.classText:Hide() end
    if self.focusLetter then self.focusLetter:Hide() end
    if self.leftArrow then self.leftArrow:Hide() end
    if self.rightArrow then self.rightArrow:Hide() end
    HideClassPowerOnPlate(self)
    self._absCurClip:Hide()
    self._absMissClip:Hide()
    self:Hide()
    self:SetScale(1)
    self._curScale = nil
    ns._scaleAnim[self] = nil
    self:SetParent(UIParent)
    self:ClearAllPoints()
    -- Detach stacking bounds from the old nameplate so it doesn't
    -- confuse the stacking engine when the nameplate is recycled.
    if self._stackBounds then
        self._stackBounds:ClearAllPoints()
        self._stackBounds:SetParent(self)
        self._stackBounds:Hide()
    end
end

I._fallbackPlates, I.castFallbackFrame = _fallbackPlates, castFallbackFrame
I.NameplateFrame = NameplateFrame
I.SetRawSetTex = function(f) RawSetTex = f end
I.broken = false
