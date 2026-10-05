if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Nameplates_Name.lua
--
--  NameplateFrame: name, classification, faction, raid icon, target and hover
--  extras.
--  Reads the earlier nameplate files through ns and ns._npInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._npInternals
-- EllesmereUINameplates.lua or an earlier nameplate file failed to load.
if not I or I.broken then return end
I.broken = true

local ipairs, type = ipairs, type
local PP = EllesmereUI.PP
local UnitName = UnitName
local UnitIsUnit = UnitIsUnit
local UnitClassification = UnitClassification
local GetRaidTargetIndex, SetRaidTargetIconTexture = GetRaidTargetIndex, SetRaidTargetIconTexture

local defaults, GetNPOutline, HP_BAR_SLOTS = I.defaults, I.GetNPOutline, I.HP_BAR_SLOTS
local SetFSFont, EstimateHealthTextWidth = I.SetFSFont, I.EstimateHealthTextWidth
local GetAuraSlotOffsets, GetClassificationSlot = I.GetAuraSlotOffsets, I.GetClassificationSlot
local GetDebuffYOffset, GetHealthBarWidth = I.GetDebuffYOffset, I.GetHealthBarWidth
local GetHideEnemyNameWhileCasting = I.GetHideEnemyNameWhileCasting
local GetNameYOffset, GetRaidMarkerPos = I.GetNameYOffset, I.GetRaidMarkerPos
local GetRaidMarkerSize, GetRareEliteIconSize = I.GetRaidMarkerSize, I.GetRareEliteIconSize
local GetShowCastIcon, GetShowClassPower = I.GetShowCastIcon, I.GetShowClassPower
local GetSideAuraXOffset, GetSlotOffsets = I.GetSideAuraXOffset, I.GetSlotOffsets
local GetTextSlot, GetTextSlotOffsets = I.GetTextSlot, I.GetTextSlotOffsets
local GetTextSlotSize, IsBorderEnabled = I.GetTextSlotSize, I.IsBorderEnabled
local PositionArrowsOutsideAuras, EnsureArrows = I.PositionArrowsOutsideAuras, I.EnsureArrows
local EnsureGlow, EnsureTargetHighlight = I.EnsureGlow, I.EnsureTargetHighlight
local EnsureClassPowerPips = I.EnsureClassPowerPips
local GetClassPowerTopPush = I.GetClassPowerTopPush
local HideClassPowerOnPlate = I.HideClassPowerOnPlate
local UpdateClassPowerOnPlate, NameplateFrame = I.UpdateClassPowerOnPlate, I.NameplateFrame

local classPowerType
I.classPowerTypeSetters[#I.classPowerTypeSetters + 1] = function(v) classPowerType = v end
local p
I.profileSetters[#I.profileSetters + 1] = function(v) p = v end

function NameplateFrame:UpdateName()
    local unit = self.unit
    if not unit then return end
    if self.nameplate then
        local actualUnit = self.nameplate.namePlateUnitToken
        if actualUnit and actualUnit ~= unit then
            self.unit = actualUnit
            unit = actualUnit
            -- Occupant changed: nil the absorb lean-gate flag so the next health
            -- paint takes the full absorb path for the new unit; the cached max
            -- belongs to the old unit, drop it too.
            self._absorbHidden = nil
            -- Repaint target/hover styling for the new occupant so the old one's
            -- paint cannot stick; mirrors the UpdateHealthValues swap.
            -- ApplyTarget re-owns the shared target-plate cache as a side effect.
            ns.ClearHoverExtras(self)
            self:ApplyTarget()
            self._maxHPValid = nil
            if ns._npToTSlot or self._totEv then self:SyncToT(actualUnit) end
        end
    end
    -- Standalone level renders on its own FontString and can share the plate with a
    -- name-family slot. Refreshed here (plate acquire/unit swap) so pooled reuse never stales.
    -- Plain text: its colour is the slot's Text Coloring mode (font string colour).
    if self.levelText and self.levelText:IsShown() then
        self.levelText:SetText(ns.GetUnitLevelText(unit))
    end
    -- Classic WoW UI: the level in the vanilla border's plate.
    if self._classicLevel then ns.NP_UpdateClassicLevel(self) end
    -- WoW Forever: the level in the box right of the bar.
    if self._fvLevelBox then ns.NP_UpdateForeverLevel(self) end
    -- The slotted name-family variant decides what renders: name or a level+name
    -- combo (in the slot's materialized part colours). A nil slot keeps the plain-name
    -- write (RefreshNamePosition hides it).
    local slot = ns.FindNameSlot()
    local el = slot and GetTextSlot(slot) or "enemyName"
    local name = EllesmereUI.WithSurname(UnitName(unit))
    if type(name) == "string" then
        -- WoW Forever: the slot's Name Format (nil function off Forever).
        if ns.NP_FormatName then name = ns.NP_FormatName(name, slot) end
        ns.SetNameElementText(self.name, el, name, unit, slot)
        if p and p.nameRaidMarkerEnabled == true then self:RefreshNamePosition(true) end
    end
end
function NameplateFrame:UpdateClassification()
    if not self.unit then return end
    local slot = GetClassificationSlot()
    local _, iType = GetInstanceInfo()
    local inInstance = (iType == "party" or iType == "raid" or iType == "pvp" or iType == "arena")
    if inInstance then
        -- "Show In Instances" (Rare/Quest Indicator slot cog) lifts the
        -- open-world-only gate.
        local show = p and p.classificationShowInInstances
        if show == nil then show = defaults.classificationShowInInstances end
        if show then inInstance = false end
    end
    if slot == "none" or inInstance then
        self.classFrame:Hide()
        self:UpdateNameWidth()
        return
    end
    -- Quest mob indicator takes priority over elite/rare. With "Replace Quest Icon with
    -- Objective" on and a clean remaining count cached, draw that number instead of the icon.
    -- Quest Indicator off: no quest scan, a quest mob shows its elite/rare mark instead.
    if not (p and p.classificationHideQuest) and ns.IsQuestMob and ns.IsQuestMob(self.unit) then
        local objText = (p and p.replaceQuestIconWithObjective == true)
            and ns.GetQuestObjectiveText and ns.GetQuestObjectiveText(self.unit) or nil
        if objText then
            -- classFrame and classText are our own frames, custom keys are safe.
            self.class:Hide()
            if not self.classText then
                self.classText = self.classFrame:CreateFontString(nil, "OVERLAY")
                self.classText:SetPoint("CENTER", self.classFrame, "CENTER", 0, 0)
                self.classText:SetJustifyH("CENTER")
                self.classText:SetJustifyV("MIDDLE")
            end
            local fsz = (p and p.questObjectiveTextSize) or defaults.questObjectiveTextSize
            SetFSFont(self.classText, fsz, GetNPOutline())
            -- SetFormattedText("%s", ...) is the secret-safe text path; the value
            -- was already verified clean (issecretvalue + ^%d+/%d+$) before caching.
            self.classText:SetFormattedText("%s", objText)
            self.classText:Show()
        else
            -- No clean count (quest-giver / percent / secret value) -> icon.
            if self.classText then self.classText:Hide() end
            self.class:Show()
            self.class:SetAtlas("Crosshair_Quest_64")
        end
    else
        if self.classText then self.classText:Hide() end
        -- WoW Forever shows no elite or rare mark on its plates (the quest
        -- marks above stay).
        if ns._npForever then
            self.classFrame:Hide()
            self:UpdateNameWidth()
            return
        end
        -- Rare Indicator off: no elite or rare marks.
        if p and p.classificationHideRare then
            self.classFrame:Hide()
            self:UpdateNameWidth()
            return
        end
        self.class:Show()
        local c = UnitClassification(self.unit)
        -- Classic WoW UI carries elite rank in the plate's own art, so the
        -- indicator marks RARITY alone there: a plain elite shows nothing,
        -- and a rare elite takes the rare mark rather than the elite one.
        if ns.NP_Classic() then
            if c == "rare" or c == "rareelite" then
                self.class:SetAtlas("nameplates-icon-rareelite")
            else
                self.classFrame:Hide()
                self:UpdateNameWidth()
                return
            end
        elseif c == "elite" or c == "worldboss" then
            self.class:SetAtlas("nameplates-icon-elite-gold")
        elseif c == "rareelite" then
            self.class:SetAtlas("nameplates-icon-elite-silver")
        elseif c == "rare" then
            self.class:SetAtlas("nameplates-icon-rareelite")
        else
            self.classFrame:Hide()
            self:UpdateNameWidth()
            return
        end
    end
    local cpPush = GetClassPowerTopPush(self)
    local cxOff, cyOff = GetAuraSlotOffsets("classification")
    local reSize = GetRareEliteIconSize()
    PP.Size(self.classFrame, reSize, reSize)
    self.classFrame:ClearAllPoints()
    if slot == "top" then
        local debuffY = GetDebuffYOffset()
        PP.Point(self.classFrame, "BOTTOM", self.health, "TOP",
            cxOff, debuffY + cpPush + cyOff)
    elseif slot == "left" then
        local sideOff = GetSideAuraXOffset()
        local iconRes, iconSide = ns.GetCastIconReserve(self)
        local classicL = ns.NP_ClassicBarReserve()
        local iconPush = ((iconSide == "left") and iconRes or 0) + classicL
        PP.Point(self.classFrame, "RIGHT", self.health, "LEFT",
            -sideOff - iconPush + cxOff, cyOff)
    elseif slot == "right" then
        local sideOff = GetSideAuraXOffset()
        local iconRes, iconSide = ns.GetCastIconReserve(self)
        local _, classicR = ns.NP_ClassicBarReserve()
        local iconPush = ((iconSide == "right") and iconRes or 0) + classicR
        PP.Point(self.classFrame, "LEFT", self.health, "RIGHT",
            sideOff + iconPush + cxOff, cyOff)
    elseif slot == "topleft" then
        PP.Point(self.classFrame, "BOTTOMLEFT", self.health, "TOPLEFT", cxOff, 2 + cpPush + cyOff)
    elseif slot == "topright" then
        PP.Point(self.classFrame, "BOTTOMRIGHT", self.health, "TOPRIGHT", cxOff, 2 + cpPush + cyOff)
    elseif slot == "bottom" then
        PP.Point(self.classFrame, "TOP", self.cast, "BOTTOM", cxOff, -2 + cyOff)
    end
    self.classFrame:Show()
    self:UpdateNameWidth()
end
-- "Rare/Quest + Faction": the faction badge's step-aside depends on whether the
-- classification icon shows, and some passes (quest objective refreshes) redraw only
-- the classification, so re-place the badge after every classification pass.
NameplateFrame._UpdateClassificationBase = NameplateFrame.UpdateClassification
function NameplateFrame:UpdateClassification()
    self:_UpdateClassificationBase()
    if p and p.classificationIncludeFaction then self:UpdateFaction() end
end
-- Faction badge (Horde/Alliance): a Core Positions slot element, placed exactly like
-- the Rare/Quest indicator above. Which badge (if any) comes from ns.NP_FactionBadge,
-- shared with the friendly plates.
-- artOnly (the plate's own UNIT_FACTION): a badge already up in this slot only
-- needs its art checked; every layout input moves through a layout caller.
function NameplateFrame:UpdateFaction(artOnly)
    local slot = ns.NP_GetFactionSlot()
    local unit = self.unit
    -- Zero cost while the slot is None: no badge frame, no events.
    if unit and slot ~= "none" then
        -- Faction and PvP flag changes both arrive as UNIT_FACTION (the one event
        -- Blizzard's own unit frames repaint their PvP badge on).
        if self._factionEv ~= unit then
            self:RegisterUnitEvent("UNIT_FACTION", unit)
            self._factionEv = unit
        end
        if not self.factionFrame then
            -- Same indicator tier as the classification icon, one level below it, so
            -- a stacked Rare/Quest + Faction pair draws Rare/Quest on top.
            local f = CreateFrame("Frame", nil, self)
            f:SetFrameStrata(ns.GetSlotRaiseStrata(slot) and "HIGH" or "MEDIUM")
            f:SetFrameLevel(self.health:GetFrameLevel() + 2)
            f:Hide()
            self.faction = f:CreateTexture(nil, "ARTWORK")
            self.faction:SetAllPoints()
            self.factionFrame = f
        end
    elseif self._factionEv then
        self:UnregisterEvent("UNIT_FACTION")
        self._factionEv = nil
    end
    local atlas, dim
    if unit and slot ~= "none" then atlas, dim = ns.NP_FactionBadge(unit) end
    if not atlas then
        if self.factionFrame and self.factionFrame:IsShown() then
            self.factionFrame:Hide()
            self:UpdateNameWidth()
            -- A side-slot badge had pushed the target arrows out: pull them back in.
            if self._facSlot == "left" or self._facSlot == "right" then
                PositionArrowsOutsideAuras(self)
                if ns.NPC_ReanchorArrows then ns.NPC_ReanchorArrows(self) end
            end
        end
        return
    end
    -- Repaint only when the art or the dim changes (inputs: faction, Icon Style, dim).
    -- The texture keeps its art across pool recycles, so the memo never goes stale.
    local style = ns.NP_GetFactionStyle()
    if self._facArt ~= atlas or self._facStyle ~= style then
        EllesmereUI.SetFactionArt(self.faction, style, atlas)
        self._facArt, self._facStyle = atlas, style
    end
    if self._facDim ~= dim then
        self.faction:SetDesaturated(dim)
        self.faction:SetAlpha(dim and 0.6 or 1)
        self._facDim = dim
    end
    if artOnly and self._facSlot == slot and self.factionFrame:IsShown() then return end
    local cpPush = GetClassPowerTopPush(self)
    local fxOff, fyOff = GetSlotOffsets(slot)
    -- "Rare/Quest + Faction" with the classification icon showing too: the faction
    -- badge stacks behind it, overlapping by 40% (classification is a frame level
    -- above, so it draws on top); up, or down in the Bottom slot so it clears the cast bar.
    if p and p.classificationIncludeFaction and self.classFrame:IsShown() then
        local step = math.floor(GetRareEliteIconSize() * 0.6 + 0.5)
        fyOff = fyOff + ((slot == "bottom") and -step or step)
    end
    local sz = ns.NP_GetFactionIconSize()
    PP.Size(self.factionFrame, sz, sz)
    self.factionFrame:ClearAllPoints()
    if slot == "top" then
        PP.Point(self.factionFrame, "BOTTOM", self.health, "TOP",
            fxOff, GetDebuffYOffset() + cpPush + fyOff)
    elseif slot == "left" then
        local iconRes, iconSide = ns.GetCastIconReserve(self)
        local classicL = ns.NP_ClassicBarReserve()
        local iconPush = ((iconSide == "left") and iconRes or 0) + classicL
        PP.Point(self.factionFrame, "RIGHT", self.health, "LEFT",
            -GetSideAuraXOffset() - iconPush + fxOff, fyOff)
    elseif slot == "right" then
        local iconRes, iconSide = ns.GetCastIconReserve(self)
        local _, classicR = ns.NP_ClassicBarReserve()
        local iconPush = ((iconSide == "right") and iconRes or 0) + classicR
        PP.Point(self.factionFrame, "LEFT", self.health, "RIGHT",
            GetSideAuraXOffset() + iconPush + fxOff, fyOff)
    elseif slot == "topleft" then
        PP.Point(self.factionFrame, "BOTTOMLEFT", self.health, "TOPLEFT", fxOff, 2 + cpPush + fyOff)
    elseif slot == "topright" then
        PP.Point(self.factionFrame, "BOTTOMRIGHT", self.health, "TOPRIGHT", fxOff, 2 + cpPush + fyOff)
    elseif slot == "bottom" then
        PP.Point(self.factionFrame, "TOP", self.cast, "BOTTOM", fxOff, -2 + fyOff)
    end
    local wasShown = self.factionFrame:IsShown()
    local lastSlot = self._facSlot
    self._facSlot = slot
    self.factionFrame:Show()
    if not wasShown then self:UpdateNameWidth() end
    -- A side-slot badge pushes the target arrows out, like the classification icon:
    -- re-flank them when it appears or moves into or out of a side slot.
    if (not wasShown or lastSlot ~= slot)
        and (slot == "left" or slot == "right" or lastSlot == "left" or lastSlot == "right") then
        PositionArrowsOutsideAuras(self)
        if ns.NPC_ReanchorArrows then ns.NPC_ReanchorArrows(self) end
    end
end
function NameplateFrame:UpdateNameWidth()
    local barW = GetHealthBarWidth()
    -- Width % scales the computed (bar-derived) width; 100 = historical behaviour.
    local pct = (p and p.enemyNameWidthPct) or defaults.enemyNameWidthPct
    local nameSlot = ns.FindNameSlot()
    local nameMarkerReserve = self._nameRaidMarkerShown == true
        and (((p and p.nameRaidMarkerSize) or defaults.nameRaidMarkerSize or 14) + 3) or 0
    if nameSlot == "textSlotTop" then
        -- Above the bar: reserve a fixed slot for the inline raid marker.
        local nameW = barW - nameMarkerReserve
        local rmPos = GetRaidMarkerPos()
        if rmPos ~= "none" and self.raidFrame:IsShown() then
            nameW = nameW - 2 * (GetRaidMarkerSize() - 2) - 7
        end
        local clSlot = GetClassificationSlot()
        if clSlot ~= "none" and self.classFrame:IsShown() then
            nameW = nameW - (GetRareEliteIconSize() + 4)
        end
        -- Stacked with the classification icon ("Rare/Quest + Faction") it takes
        -- no extra width; alone it reserves its own.
        local stacked = p and p.classificationIncludeFaction and self.classFrame:IsShown()
        if self.factionFrame and self.factionFrame:IsShown() and not stacked then
            nameW = nameW - (ns.NP_GetFactionIconSize() + 4)
        end
        PP.Width(self.name, math.max(nameW * pct / 100, 20))
    elseif nameSlot == "textSlotBottomLeft" or nameSlot == "textSlotBottomRight" then
        -- Under the bar the name never truncates: no width box (auto-sized).
        self.name:SetWidth(0)
    elseif nameSlot then
        -- Inside the bar: estimate how much space health text occupies in
        -- opposing slots, then give the name everything that remains.
        local usedWidth = 0
        for _, key in ipairs(ns._npBarTextKeys) do
            if key ~= nameSlot then
                local el = GetTextSlot(key)
                if el ~= "none" and not ns.IsNameElement(el) then
                    usedWidth = usedWidth + EstimateHealthTextWidth(el)
                end
            end
        end
        local nameW = barW - usedWidth - nameMarkerReserve
        PP.Width(self.name, math.max(nameW * pct / 100, 20))
    else
        -- Name not in any slot, use minimal width
        PP.Width(self.name, math.max(barW * pct / 100, 20))
    end
end
function NameplateFrame:ApplyNameVisibility()
    -- Zero cost when off: the name's shown state is owned by RefreshNamePosition;
    -- only override it (hide while the cast bar is up) when the feature is on.
    if not GetHideEnemyNameWhileCasting() then return end
    local hasNameSlot = ns.FindNameSlot() ~= nil
    local shown = hasNameSlot and not self.cast:IsShown()
    self.name:SetShown(shown)
    if self.nameRaidFrame then self.nameRaidFrame:SetShown(shown and self._nameRaidMarkerShown == true) end
end
-- The full-size cast icon (a cast-bar child) occupies its side-slot space only while a cast is
-- up, so its reserve is gated on the cast bar being shown (see GetCastIconReserve). On every
-- cast show/hide, re-anchor the side elements that reserve it (target arrow, classification
-- icon, raid marker) so they track the icon instead of sitting shoved out by a phantom gap.
-- Zero cost unless the full-size icon is enabled.
function NameplateFrame:RefreshCastIconSideReserve()
    if not (GetShowCastIcon() and ns.GetCastIconFullSize()) then return end
    self:UpdateClassification()
    if not (p and p.classificationIncludeFaction) then self:UpdateFaction() end
    self:UpdateRaidIcon()
    PositionArrowsOutsideAuras(self)
    -- Without this, a cast bar showing/hiding shoves an already container-hugging
    -- arrow back out to the coarse fallback position (same gap as the target-swap
    -- path -- see NameplateFrame's isTarget branch).
    if ns.NPC_ReanchorArrows then ns.NPC_ReanchorArrows(self) end
end

function NameplateFrame:RefreshNamePosition(localOnly)
    local nameSlot = ns.FindNameSlot()
    local nameYOff = GetNameYOffset()
    local nameMarkerShown
    local nameMarkerSize = (p and p.nameRaidMarkerSize) or defaults.nameRaidMarkerSize or 14
    if self.nameRaidFrame then
        local idx
        if p and p.nameRaidMarkerEnabled == true and nameSlot and self.unit then
            idx = GetRaidTargetIndex and GetRaidTargetIndex(self.unit)
        end
        if type(idx) == "nil" then
            self._nameRaidMarkerShown = nil
            self.nameRaidFrame:Hide()
        else
            SetRaidTargetIconTexture(self.nameRaid, idx)
            PP.Size(self.nameRaidFrame, nameMarkerSize, nameMarkerSize)
            self._nameRaidMarkerShown = true
            self.nameRaidFrame:Show()
            nameMarkerShown = true
        end
    end
    local nameMarkerReserve = nameMarkerShown and (nameMarkerSize + 3) or 0
    local nameStrata = (p and nameSlot and p[nameSlot .. "Strata"]) or "MEDIUM"
    self:UpdateNameWidth()
    self.name:ClearAllPoints()
    if nameSlot == "textSlotLeft" then
        local txOff, tyOff = GetTextSlotOffsets("textSlotLeft")
        SetFSFont(self.name, GetTextSlotSize("textSlotLeft"), GetNPOutline())
        self.name:SetParent(ns.SlotTextHost(self, nameSlot, nameStrata))
        PP.Point(self.name, "LEFT", self.health, "LEFT", 4 + txOff + nameMarkerReserve, tyOff)
        self.name:SetJustifyH("LEFT")
        self.name:Show()
    elseif nameSlot == "textSlotCenter" then
        local txOff, tyOff = GetTextSlotOffsets("textSlotCenter")
        SetFSFont(self.name, GetTextSlotSize("textSlotCenter"), GetNPOutline())
        self.name:SetParent(ns.SlotTextHost(self, nameSlot, nameStrata))
        self.name:SetPoint("CENTER", self.health, "CENTER", txOff + (nameMarkerReserve * 0.5), tyOff)
        self.name:SetJustifyH("CENTER")
        self.name:Show()
    elseif nameSlot == "textSlotRight" then
        local txOff, tyOff = GetTextSlotOffsets("textSlotRight")
        SetFSFont(self.name, GetTextSlotSize("textSlotRight"), GetNPOutline())
        self.name:SetParent(ns.SlotTextHost(self, nameSlot, nameStrata))
        PP.Point(self.name, "RIGHT", self.health, "RIGHT", -2 + txOff, tyOff)
        self.name:SetJustifyH("RIGHT")
        self.name:Show()
    elseif nameSlot == "textSlotBottomLeft" or nameSlot == "textSlotBottomRight" then
        local txOff, tyOff = GetTextSlotOffsets(nameSlot)
        local slot = HP_BAR_SLOTS[(nameSlot == "textSlotBottomLeft") and 4 or 5]
        SetFSFont(self.name, GetTextSlotSize(nameSlot), GetNPOutline())
        self.name:SetParent(ns.SlotTextHost(self, nameSlot, nameStrata))
        self:PlaceSlotText(self.name, slot, txOff + ((slot.justify == "LEFT") and nameMarkerReserve or 0), tyOff)
        self.name:SetJustifyH(slot.justify)
        self.name:Show()
    elseif nameSlot == "textSlotTop" then
        local txOff, tyOff = GetTextSlotOffsets("textSlotTop")
        SetFSFont(self.name, GetTextSlotSize("textSlotTop"), GetNPOutline())
        self.name:SetParent(ns.SlotTextHost(self, "textSlotTop", nameStrata))
        local cpPush = GetClassPowerTopPush(self)
        PP.Point(self.name, "BOTTOM", self.health, "TOP", txOff + (nameMarkerReserve * 0.5), 4 + nameYOff + cpPush + tyOff)
        self.name:SetJustifyH("CENTER")
        self.name:Show()
    else
        -- Name not assigned to any slot
        self.name:Hide()
    end
    -- Apply name wrap here (not only at creation) so the cog toggle takes effect on the next
    -- settings refresh. Off = single line + ellipsis, on = up to two lines; reflow re-lays out.
    local nameWrap = defaults.enemyNameWrap
    if p and p.enemyNameWrap ~= nil then nameWrap = p.enemyNameWrap end
    if nameSlot == "textSlotBottomLeft" or nameSlot == "textSlotBottomRight" then nameWrap = false end
    self.name:SetWordWrap(nameWrap)
    self.name:SetNonSpaceWrap(false)
    self.name:SetMaxLines(nameWrap and 2 or 1)
    ns.ReflowFontString(self.name)
    self:ApplyNameVisibility()
    local nameRaid = self.nameRaidFrame
    if nameRaid and self._nameRaidMarkerShown and self.name:IsShown() then
        PP.Size(nameRaid, nameMarkerSize, nameMarkerSize)
        -- Follows the name's host so the marker rides the slot's strata; the
        -- host's own SetFrameStrata (SlotTextHost) resets child frames, so
        -- re-assert AFTER parenting.
        nameRaid:SetParent(ns.SlotTextHost(self, nameSlot, nameStrata))
        nameRaid:SetFrameStrata(nameStrata)
        nameRaid:SetFrameLevel(901)
        nameRaid:ClearAllPoints()
        nameRaid:SetPoint("RIGHT", self.name, "LEFT", -3, 0)
        nameRaid:Show()
    elseif nameRaid then
        nameRaid:Hide()
    end
    if localOnly then return end
    self:UpdateClassification()
    if not (p and p.classificationIncludeFaction) then self:UpdateFaction() end
end
function NameplateFrame:UpdateRaidIcon()
    if not self.unit then return end
    local pos = GetRaidMarkerPos()
    if pos == "none" then
        self.raidFrame:Hide()
        self:UpdateNameWidth()
        return
    end
    -- type() is taint-safe: returns "nil"/"number" without reading the secret value
    local idx = GetRaidTargetIndex and GetRaidTargetIndex(self.unit)
    if type(idx) == "nil" then
        self.raidFrame:Hide()
        self:UpdateNameWidth()
        return
    end
    SetRaidTargetIconTexture(self.raid, idx)
    local sz = GetRaidMarkerSize()
    PP.Size(self.raidFrame, sz, sz)
    local cpPush = GetClassPowerTopPush(self)
    local rxOff, ryOff = GetAuraSlotOffsets("raidMarker")
    self.raidFrame:ClearAllPoints()
    if pos == "top" then
        local debuffY = GetDebuffYOffset()
        PP.Point(self.raidFrame, "BOTTOM", self.health, "TOP",
            rxOff, debuffY + cpPush + ryOff)
    elseif pos == "left" then
        local sideOff = GetSideAuraXOffset()
        local iconRes, iconSide = ns.GetCastIconReserve(self)
        local classicL = ns.NP_ClassicBarReserve()
        local iconPush = ((iconSide == "left") and iconRes or 0) + classicL
        PP.Point(self.raidFrame, "RIGHT", self.health, "LEFT",
            -sideOff - iconPush + rxOff, ryOff)
    elseif pos == "right" then
        local sideOff = GetSideAuraXOffset()
        local iconRes, iconSide = ns.GetCastIconReserve(self)
        local _, classicR = ns.NP_ClassicBarReserve()
        local iconPush = ((iconSide == "right") and iconRes or 0) + classicR
        PP.Point(self.raidFrame, "LEFT", self.health, "RIGHT",
            sideOff + iconPush + rxOff, ryOff)
    elseif pos == "topleft" then
        PP.Point(self.raidFrame, "BOTTOMLEFT", self.health, "TOPLEFT", rxOff, cpPush + ryOff)
    elseif pos == "topright" then
        PP.Point(self.raidFrame, "BOTTOMRIGHT", self.health, "TOPRIGHT", rxOff, cpPush + ryOff)
    elseif pos == "bottom" then
        -- Below the cast bar, centered (matches PositionAuraSlot "bottom" convention).
        PP.Point(self.raidFrame, "TOP", self.cast, "BOTTOM", rxOff, -2 + ryOff)
    end
    self.raidFrame:Show()
    self:UpdateNameWidth()
end
function NameplateFrame:ApplyTarget()
    if not self.unit then return end
    local isTarget = UnitIsUnit(self.unit, "target")
    local flip = (self._isTarget == true) ~= (isTarget == true)
    -- The hash line is painted by the health pass from this cached flag, so a
    -- flip queues one coalesced repaint (only while the line is enabled).
    if flip and p and p.hashLineEnabled then
        self:MarkHealthDirty()
    end
    self._isTarget = isTarget  -- cached for hot-path hash line check
    -- The Threat Gap shows on the target's plate only: a flip repaints its text.
    if flip and ns._npTgapOn then ns.NP_UpdateThreatPct(self, self.unit) end
    -- Cache ownership lives here so EVERY painter keeps it coherent:
    -- SetUnit's deferred setup (pending-watcher promotion), the UpdateHealthValues
    -- token swap and PLAYER_TARGET_CHANGED all funnel through this method. Gaining
    -- target claims the slot; a recycled plate that lost target frees it, so a
    -- stale entry can never skip the un-paint on the next target change.
    if isTarget then
        ns._cachedTargetPlate = self
    elseif ns._cachedTargetPlate == self then
        ns._cachedTargetPlate = nil
    end
    -- EllesmereUI: background glow around the plate, tinted + faded with the
    -- target Glow Color/Opacity (re-applied on show so live edits update).
    if isTarget and ns.GetTargetGlowEllesmereUI() then
        EnsureGlow(self)
        if self.glowTextures then
            local gc = ns.GetTargetGlowColor()
            local ga = ns.GetTargetGlowAlpha()
            for _, t in ipairs(self.glowTextures) do t:SetVertexColor(gc.r, gc.g, gc.b, ga) end
        end
        self.glow:Show()
    elseif self.glow then
        self.glow:Hide()
    end
    -- Border Size: resize the health border while targeted. tbsz stays nil unless the effect is
    -- on AND a size was snapshotted. Runs BEFORE Border Color so a rebuilt custom border gets
    -- its target tint right after. Restore is one-shot via self._targetBorderSized.
    local tbsz
    if isTarget and ns.GetTargetGlowBorderSize() then tbsz = ns.GetTargetBorderSizeValue() end
    if tbsz then
        if ns.IsCustomBorderEnabled() then
            ns.ApplyCustomBorderStyle(self, tbsz)
        elseif PP and IsBorderEnabled() then
            PP.SetBorderSize(self.health, tbsz)
        end
        self._targetBorderSized = true
    elseif self._targetBorderSized then
        self._targetBorderSized = nil
        self:ApplyBorder()
    end
    -- Border Color: recolor the health bar border with the custom target color
    if isTarget and ns.GetTargetGlowBorderColor() then
        if PP then
            local bc = ns.GetTargetBorderColor()
            if ns.IsCustomBorderEnabled() then
                -- Custom border replaces the simple one; recolor with the target color,
                -- lazy-creating it if this plate is targeted before its first ApplyBorder ran.
                if not self._customBorder then ns.ApplyCustomBorderStyle(self) end
                if self._customBorder and EllesmereUI.SetBorderStyleColor then
                    EllesmereUI.SetBorderStyleColor(self._customBorder, bc.r, bc.g, bc.b, 1)
                end
            else
                PP.SetBorderColor(self.health, bc.r, bc.g, bc.b, 1)
            end
            self._hbThreatTint = nil
        end
        -- Use Target Border Color on the custom spell icon border (the else branch's
        -- ApplyBorderColor restores it). One field read while off.
        if p and p.castIconCustomBorder then ns.ApplyCastIconBorder(self) end
    else
        self:ApplyBorderColor()
    end
    -- If this plate is wrapping its border around the cast bar, the colour just set landed on
    -- the HIDDEN health border: re-sync the visible unified border. One field read unless live.
    -- (Custom wrap: re-syncs the lower piece and seam to the size and colour just set.)
    if self._wrapActive or self._cbWrapActive then self:UpdateBorderWrap() end
    -- Blizzard Style: stock selection ring / deselected overlay. The classic
    -- plate marks its target through the EUI effects above alone.
    if ns.NP_Style() == "blizzard" then ns.NP_ApplyBlizzSelection(self, isTarget) end
    -- Highlight: translucent wash across the health bar (color + opacity are
    -- configurable; re-applied on show so live edits and pooled textures update)
    if isTarget and ns.GetTargetGlowHighlight() then
        EnsureTargetHighlight(self)
        local c = ns.GetTargetHighlightColor()
        self.targetHighlight:SetColorTexture(c.r, c.g, c.b, ns.GetTargetHighlightAlpha())
        self.targetHighlight:Show()
    elseif self.targetHighlight then
        self.targetHighlight:Hide()
    end
    if p and p.showTargetArrows then
        if isTarget then
            EnsureArrows(self)
            local sc = p.targetArrowScale or 1.0
            local st = ns.ResolveTargetArrowStyle(p)
            self.leftArrow:SetTexture(ns.TARGET_ARROW_DIR .. st.l .. ".png")
            self.rightArrow:SetTexture(ns.TARGET_ARROW_DIR .. st.r .. ".png")
            local acr, acg, acb = ns.GetTargetArrowColor(p)
            self.leftArrow:SetVertexColor(acr, acg, acb)
            self.rightArrow:SetVertexColor(acr, acg, acb)
            local aw, ah = math.floor(st.w * sc + 0.5), math.floor(16 * sc + 0.5)
            PP.Size(self.leftArrow,  aw, ah)
            PP.Size(self.rightArrow, aw, ah)
            self.leftArrow:Show()
            self.rightArrow:Show()
            PositionArrowsOutsideAuras(self)
            -- The coarse pass above only flanks health/name; a plate that already
            -- has a live aura container needs the hugging override too, or a
            -- fresh target selection leaves the arrows stuck at the wide fallback
            -- until an unrelated RAID_TARGET_UPDATE happens to fire afterward.
            if ns.NPC_ReanchorArrows then ns.NPC_ReanchorArrows(self) end
        elseif self.leftArrow then
            self.leftArrow:Hide()
            self.rightArrow:Hide()
        end
    elseif self.leftArrow then
        self.leftArrow:Hide()
        self.rightArrow:Hide()
    end
    -- Class power pips: show on target, hide on others
    if GetShowClassPower() and classPowerType then
        if isTarget then
            EnsureClassPowerPips(self)
            UpdateClassPowerOnPlate(self)
        else
            HideClassPowerOnPlate(self)
        end
    end
    self:ApplyScale()
end
function NameplateFrame:ApplyMouseover()
    if not self.unit then return end
    if UnitExists("mouseover") and UnitIsUnit(self.unit, "mouseover") then
        ns.ShowHoverEffect(self)
        ns.ApplyHoverExtras(self)
        ns._currentMouseoverPlate = self
        if ns._EnsureMouseoverTicker then ns._EnsureMouseoverTicker() end
    else
        ns.HideHoverEffect(self)
        ns.ClearHoverExtras(self)
    end
end

-- Hover Effect extra channels (EUI Glow / Border Color / Border Size --
-- mirrors ApplyTarget's branches; the Highlight channel lives inside
-- ShowHoverEffect). TARGET PRECEDENCE per shared visual: while this plate is
-- the target and the TARGET effect drives the same channel, hover leaves it
-- alone -- and ApplyTarget runs after every target change, so the target
-- state always reasserts over a stale hover write.
function ns.ApplyHoverExtras(plate)
    if not plate or not plate.unit or not plate.health then return end
    local isTarget = plate._isTarget
    local any = false
    local wrapSync = false  -- one cast bar wrap re-sync at the end, after size and colour
    -- EUI Glow (shared self.glow visual).
    if ns.GetHoverGlowEllesmereUI() and not (isTarget and ns.GetTargetGlowEllesmereUI()) then
        EnsureGlow(plate)
        if plate.glowTextures then
            local gc = ns.GetHoverGlowColor()
            local ga = ns.GetHoverGlowAlpha()
            for _, t in ipairs(plate.glowTextures) do t:SetVertexColor(gc.r, gc.g, gc.b, ga) end
        end
        plate.glow:Show()
        any = true
    end
    -- Border Size (a target-sized border wins; restore is ClearHoverExtras').
    if ns.GetHoverGlowBorderSize() and not plate._targetBorderSized then
        local hbsz = ns.GetHoverBorderSizeValue()
        if hbsz then
            if ns.IsCustomBorderEnabled() then
                ns.ApplyCustomBorderStyle(plate, hbsz)
            elseif PP and IsBorderEnabled() then
                PP.SetBorderSize(plate.health, hbsz)
            end
            -- The resize drew the base colour (custom rebuild) or the last clean one
            -- (re-snap) over a Threat Colors tint: put it back unless a hover or target
            -- border colour paints this border instead.
            if plate._threatBdOn and not ns.GetHoverGlowBorderColor()
                and not (isTarget and ns.GetTargetGlowBorderColor()) then
                plate:ApplyBorderColor()
            end
            plate._hoverBorderSized = true
            any = true
            -- The custom wrap copies the size its border is drawn at. Not the Basic
            -- wrap: it re-applies the base size and would undo the hover size.
            if plate._cbWrapActive then wrapSync = true end
        end
    end
    -- Border Color (the target color wins).
    if ns.GetHoverGlowBorderColor() and not (isTarget and ns.GetTargetGlowBorderColor()) then
        if PP then
            local bc = ns.GetHoverBorderColor()
            if ns.IsCustomBorderEnabled() then
                if not plate._customBorder then ns.ApplyCustomBorderStyle(plate) end
                if plate._customBorder and EllesmereUI.SetBorderStyleColor then
                    EllesmereUI.SetBorderStyleColor(plate._customBorder, bc.r, bc.g, bc.b, 1)
                end
            else
                PP.SetBorderColor(plate.health, bc.r, bc.g, bc.b, 1)
            end
            plate._hbThreatTint = nil
            any = true
            -- A friendly plate's ApplyTarget has no border colour of its own to fall back
            -- on: this flag tells it to repaint the base colour on the way out.
            plate._fxBorderTinted = true
        end
        if plate._wrapActive or plate._cbWrapActive then wrapSync = true end
    end
    if wrapSync then plate:UpdateBorderWrap() end
    if any then plate._hoverFxOn = true end
end

-- One-shot restore of every shared channel to the target/base state: the
-- hover-sized border resets explicitly (ApplyTarget only restores its OWN
-- sizing flag), then ApplyTarget's else-branches reset glow/border color.
-- Early-out keeps the no-extras case (the shipped default) zero-cost.
function ns.ClearHoverExtras(plate)
    if not plate or not plate._hoverFxOn then return end
    plate._hoverFxOn = nil
    if plate._hoverBorderSized then
        plate._hoverBorderSized = nil
        plate:ApplyBorder()
    end
    plate:ApplyTarget()
end

I.broken = false
