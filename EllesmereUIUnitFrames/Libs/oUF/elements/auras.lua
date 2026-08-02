--[[
# Element: Auras

Handles creation and updating of aura icons.

## Widget

Auras   - A Frame to hold `Button`s representing both buffs and debuffs.
Buffs   - A Frame to hold `Button`s representing buffs.
Debuffs - A Frame to hold `Button`s representing debuffs.

## Notes

At least one of the above widgets must be present for the element to work.

## Options

.disableMouse       - Disables mouse events (boolean)
.disableCooldown    - Disables the cooldown spiral (boolean)
.size               - Aura icon size. Defaults to 16 (number)
.onlyShowPlayer     - Shows only auras created by player/vehicle (boolean)
.showStealableBuffs - Displays the stealable texture on buffs that can be stolen (boolean)
.spacing            - Spacing between each icon. Defaults to 0 (number)
.['spacing-x']      - Horizontal spacing between each icon. Takes priority over `spacing` (number)
.['spacing-y']      - Vertical spacing between each icon. Takes priority over `spacing` (number)
.['growth-x']       - Horizontal growth direction. Defaults to 'RIGHT' (string)
.['growth-y']       - Vertical growth direction. Defaults to 'UP' (string)
.initialAnchor      - Anchor point for the icons. Defaults to 'BOTTOMLEFT' (string)
.filter             - Custom filter list for auras to display. Defaults to 'HELPFUL' for buffs and 'HARMFUL' for
                      debuffs (string)
.tooltipAnchor      - Anchor point for the tooltip. Defaults to 'ANCHOR_BOTTOMRIGHT', however, if a frame has anchoring
                      restrictions it will be set to 'ANCHOR_CURSOR' (string)

## Options Auras

.numBuffs     - The maximum number of buffs to display. Defaults to 32 (number)
.numDebuffs   - The maximum number of debuffs to display. Defaults to 40 (number)
.numTotal     - The maximum number of auras to display. Prioritizes buffs over debuffs. Defaults to the sum of
                .numBuffs and .numDebuffs (number)
.gap          - Controls the creation of an invisible icon between buffs and debuffs. Defaults to false (boolean)
.buffFilter   - Custom filter list for buffs to display. Takes priority over `filter` (string)
.debuffFilter - Custom filter list for debuffs to display. Takes priority over `filter` (string)

## Options Buffs

.num - Number of buffs to display. Defaults to 32 (number)

## Options Debuffs

.num - Number of debuffs to display. Defaults to 40 (number)

## Attributes

button.caster   - the unit who cast the aura (string)
button.filter   - the filter list used to determine the visibility of the aura (string)
button.isDebuff - indicates if the button holds a debuff (boolean)
button.isPlayer - indicates if the aura caster is the player or their vehicle (boolean)

## Examples

    -- Position and size
    local Buffs = CreateFrame('Frame', nil, self)
    Buffs:SetPoint('RIGHT', self, 'LEFT')
    Buffs:SetSize(16 * 2, 16 * 16)

    -- Register with oUF
    self.Buffs = Buffs
--]]

local _, ns = ...
local oUF = ns.oUF

local VISIBLE = 1
local HIDDEN = 0

-- ElvUI changed block
local CREATED = 2
local pcall = pcall
local tinsert = tinsert
local CreateFrame = CreateFrame
local GetSpellInfo = GetSpellInfo
local UnitAura = UnitAura
local UnitIsUnit = UnitIsUnit
local floor, min = math.floor, math.min
-- GLOBALS: GameTooltip
-- end block

local function UpdateTooltip(self)
	GameTooltip:SetUnitAura(self:GetParent().__owner.unit, self:GetID(), self.filter)
end

local function onEnter(self)
	if(not self:IsVisible()) then return end

	GameTooltip:SetOwner(self, self:GetParent().tooltipAnchor)
	self:UpdateTooltip()
end

local function onLeave()
	GameTooltip:Hide()
end

local function createAuraIcon(element, index)
	local button = CreateFrame('Button', '$parentButton' .. index, element)
	button:RegisterForClicks('RightButtonUp')

	local cd = CreateFrame('Cooldown', '$parentCooldown', button, 'CooldownFrameTemplate')
	cd:SetFrameLevel(button:GetFrameLevel() + 1)
	cd:SetAllPoints()

	local icon = button:CreateTexture(nil, 'BORDER')
	icon:SetAllPoints()

	local countFrame = CreateFrame('Frame', '$parentCount', button)
	countFrame:SetAllPoints(button)
	countFrame:SetFrameLevel(cd:GetFrameLevel() + 1)

	local count = countFrame:CreateFontString(nil, 'OVERLAY', 'NumberFontNormal')
	count:SetPoint('BOTTOMRIGHT', countFrame, 'BOTTOMRIGHT', -1, 0)

	local overlay = button:CreateTexture(nil, 'OVERLAY')
	overlay:SetTexture([[Interface\Buttons\UI-Debuff-Overlays]])
	overlay:SetAllPoints()
	overlay:SetTexCoord(.296875, .5703125, 0, .515625)
	button.overlay = overlay

	local stealable = button:CreateTexture(nil, 'OVERLAY')
	stealable:SetTexture([[Interface\TargetingFrame\UI-TargetingFrame-Stealable]])
	stealable:SetPoint('TOPLEFT', -3, 3)
	stealable:SetPoint('BOTTOMRIGHT', 3, -3)
	stealable:SetBlendMode('ADD')
	button.stealable = stealable

	button.UpdateTooltip = UpdateTooltip
	button:SetScript('OnEnter', onEnter)
	button:SetScript('OnLeave', onLeave)

	button.icon = icon
	button.count = count
	button.cd = cd
	-- Modern oUF uses capitalized sub-widget names. Keep both spellings so old
	-- Wrath layouts and current layouts can share button styling.
	button.Icon = icon
	button.Count = count
	button.Cooldown = cd
	button.Overlay = overlay
	button.Stealable = stealable

	--[[ Callback: Auras:PostCreateButton(button)
	Called after a new aura button has been created.

	* self   - the widget holding the aura buttons
	* button - the newly created aura button (Button)
	--]]
	if(element.PostCreateButton) then
		element:PostCreateButton(button)
	elseif(element.PostCreateIcon) then
		element:PostCreateIcon(button)
	end

	return button
end

local function customFilter(element, unit, button, name)
	if((element.onlyShowPlayer and button.isPlayer) or (not element.onlyShowPlayer and name)) then
		return true
	end
end

local function updateIcon(element, unit, index, offset, filter, isDebuff, visible)
	local name, rank, texture, count, debuffType, duration, expiration, caster, isStealable, shouldConsolidate, spellID = UnitAura(unit, index, filter)

	-- count may be nil sometimes
	count = count or 0

	-- ElvUI block
	if element.forceShow or element.forceCreate then
		spellID = 47540
		name, rank, texture = GetSpellInfo(spellID)
		if element.forceShow then
			count, debuffType, duration, expiration, caster, isStealable, shouldConsolidate = 5, 'Magic', 0, 60, 'player', nil, nil
		end
	end
	-- end Block

	if(name) then
		local data = {
			name = name,
			icon = texture,
			applications = count,
			dispelName = debuffType,
			duration = duration,
			expirationTime = expiration,
			sourceUnit = caster,
			isStealable = isStealable,
			spellId = spellID,
			index = index,
			auraInstanceID = index,
			isHelpful = not isDebuff,
			isHarmful = not not isDebuff,
			isHarmfulAura = not not isDebuff,
			isPlayerAura = caster == 'player' or caster == 'vehicle',
		}
		if(element.PostProcessAuraData) then
			data = element:PostProcessAuraData(unit, data, filter)
			if(not data) then return HIDDEN end
		end

		name = data.name
		texture = data.icon
		count = data.applications or 0
		debuffType = data.dispelName
		duration = data.duration
		expiration = data.expirationTime
		caster = data.sourceUnit
		isStealable = data.isStealable
		spellID = data.spellId

		local position = visible + offset + 1
		local button = element[position]
		if(not button) then
			--[[ Override: Auras:CreateButton(position)
			Used to create the aura button at a given position.

			* self     - the widget holding the aura buttons
			* position - the position at which the aura button is to be created (number)

			## Returns

			* button - the button used to represent the aura (Button)
			--]]
			button = (element.CreateButton or element.CreateIcon or createAuraIcon) (element, position)

			tinsert(element, button)
			element.createdIcons = element.createdIcons + 1
			element.createdButtons = element.createdIcons
		end

		button.caster = caster
		button.filter = filter
		button.isDebuff = isDebuff
		button.isPlayer = caster == 'player' or caster == 'vehicle'
		button.auraInstanceID = data.auraInstanceID

		--[[ Override: Auras:CustomFilter(unit, button, ...)
		Defines a custom filter that controls if the aura button should be shown.

		* self   - the widget holding the aura buttons
		* unit   - the unit on which the aura is cast (string)
		* button - the button displaying the aura (Button)
		* ...    - the return values from [UnitAura](http://wowprogramming.com/docs/api/UnitAura.html)

		## Returns

		* show - indicates whether the aura button should be shown (boolean)
		--]]

		-- ElvUI changed block
		local show = not element.forceCreate
		if not (element.forceShow or element.forceCreate) then
			if(element.FilterAura) then
				show = element:FilterAura(unit, data, filter)
			else
				show = (element.CustomFilter or customFilter) (element, unit, button, name, rank, texture, count, debuffType, duration, expiration, caster, isStealable, shouldConsolidate, spellID)
			end
		end
		-- end block

		if(show) then
			-- We might want to consider delaying the creation of an actual cooldown
			-- object to this point, but I think that will just make things needlessly
			-- complicated.
			local cooldown = button.Cooldown or button.cd
			if(cooldown and not element.disableCooldown) then
				if(duration and duration > 0) then
					cooldown:SetCooldown(expiration - duration, duration)
					cooldown:Show()
				else
					cooldown:Hide()
				end
			end

			local overlay = button.Overlay or button.overlay
			if(overlay) then
				if((isDebuff and element.showDebuffType) or (not isDebuff and element.showBuffType) or element.showType) then
					local color = element.__owner.colors.debuff[debuffType] or element.__owner.colors.debuff.none

					overlay:SetVertexColor(color[1], color[2], color[3])
					overlay:Show()
				else
					overlay:Hide()
				end
			end

			local stealable = button.Stealable or button.stealable
			if(stealable) then
				if(not isDebuff and isStealable and element.showStealableBuffs and not UnitIsUnit('player', unit)) then
					stealable:Show()
				else
					stealable:Hide()
				end
			end

			local icon = button.Icon or button.icon
			local countText = button.Count or button.count
			if(icon) then icon:SetTexture(texture) end
			if(countText) then countText:SetText(count > 1 and count) end

			local width = element.width or element.size or 16
			local height = element.height or element.size or 16
			button:SetSize(width, height)

			button:EnableMouse(not element.disableMouse)
			button:SetID(index)
			button:Show()

			--[[ Callback: Auras:PostUpdateIcon(unit, button, index, position)
			Called after the aura button has been updated.

			* self        - the widget holding the aura buttons
			* unit        - the unit on which the aura is cast (string)
			* button      - the updated aura button (Button)
			* index       - the index of the aura (number)
			* position    - the actual position of the aura button (number)
			* duration    - the aura duration in seconds (number?)
			* expiration  - the point in time when the aura will expire. Comparable to GetTime() (number)
			* debuffType  - the debuff type of the aura (string?)['Curse', 'Disease', 'Magic', 'Poison']
			* isStealable - whether the aura can be stolen or purged (boolean)
			--]]
			if(element.PostUpdateIcon) then
				element:PostUpdateIcon(unit, button, index, position, duration, expiration, debuffType, isStealable)
			end
			if(element.PostUpdateButton) then
				element:PostUpdateButton(button, unit, data, position)
			end

			return VISIBLE
		-- ElvUI changed block
		elseif element.forceCreate then
			local size = element.size or 16
			button:SetSize(size, size)
			button:Hide()

			if element.PostUpdateIcon then
				element:PostUpdateIcon(unit, button, index, position, duration, expiration, debuffType, isStealable)
			end

			return CREATED
		-- end block
		else
			return HIDDEN
		end
	end
end

local function SetPosition(element, from, to)
	local width = element.width or element.size or 16
	local height = element.height or element.size or 16
	local sizex = width + (element.spacingX or element['spacing-x'] or element.spacing or 0)
	local sizey = height + (element.spacingY or element['spacing-y'] or element.spacing or 0)
	local anchor = element.initialAnchor or 'BOTTOMLEFT'
	local growthx = ((element.growthX or element['growth-x']) == 'LEFT' and -1) or 1
	local growthy = ((element.growthY or element['growth-y']) == 'DOWN' and -1) or 1
	local cols = element.maxCols or floor(element:GetWidth() / sizex + 0.5)

	for i = from, to do
		local button = element[i]

		-- Bail out if the to range is out of scope.
		if(not button) then break end
		local col = (i - 1) % cols
		local row = floor((i - 1) / cols)

		button:ClearAllPoints()
		button:SetPoint(anchor, element, anchor, col * sizex * growthx, row * sizey * growthy)
	end
end

local function filterIcons(element, unit, filter, limit, isDebuff, offset, dontHide)
	if(not offset) then offset = 0 end
	local index = 1
	local visible = 0
	local hidden = 0
	-- ElvUI changed block
	local created = 0
	-- end block
	while(visible < limit) do
		local result = updateIcon(element, unit, index, offset, filter, isDebuff, visible)
		if(not result) then
			break
		elseif(result == VISIBLE) then
			visible = visible + 1
		elseif(result == HIDDEN) then
			hidden = hidden + 1
		-- ElvUI changed block
		elseif result == CREATED then
			visible = visible + 1
			created = created + 1
		-- end block
		end

		index = index + 1
	end

	-- ElvUI changed block
	visible = visible - created
	-- end block

	if(not dontHide) then
		for i = visible + offset + 1, #element do
			element[i]:Hide()
		end
	end

	return visible, hidden
end

local function UpdateAuras(self, event, unit)
	if(self.unit ~= unit) then return end

	local auras = self.Auras
	if(auras) then
		--[[ Callback: Auras:PreUpdate(unit)
		Called before the element has been updated.

		* self - the widget holding the aura buttons
		* unit - the unit for which the update has been triggered (string)
		--]]
			if(auras.PreUpdate) then auras:PreUpdate(unit, true) end

		local numBuffs = auras.numBuffs or 32
		local numDebuffs = auras.numDebuffs or 40
		local max = auras.numTotal or numBuffs + numDebuffs

		local visibleBuffs = filterIcons(auras, unit, auras.buffFilter or auras.filter or 'HELPFUL', min(numBuffs, max), nil, 0, true)

		local hasGap
		if(visibleBuffs ~= 0 and auras.gap) then
			hasGap = true
			visibleBuffs = visibleBuffs + 1

			local button = auras[visibleBuffs]
			if(not button) then
					button = (auras.CreateButton or auras.CreateIcon or createAuraIcon) (auras, visibleBuffs)
					tinsert(auras, button)
					auras.createdIcons = auras.createdIcons + 1
					auras.createdButtons = auras.createdIcons
				end

				-- Prevent the button from displaying anything.
				local cooldown = button.Cooldown or button.cd
				local icon = button.Icon or button.icon
				local overlay = button.Overlay or button.overlay
				local stealable = button.Stealable or button.stealable
				local countText = button.Count or button.count
				if(cooldown) then cooldown:Hide() end
				if(icon) then icon:SetTexture() end
				if(overlay) then overlay:Hide() end
				if(stealable) then stealable:Hide() end
				if(countText) then countText:SetText() end

			button:EnableMouse(false)
			button:Show()

			--[[ Callback: Auras:PostUpdateGapIcon(unit, gapButton, visibleBuffs)
			Called after an invisible aura button has been created. Only used by Auras when the `gap` option is enabled.

			* self         - the widget holding the aura buttons
			* unit         - the unit that has the invisible aura button (string)
			* gapButton    - the invisible aura button (Button)
			* visibleBuffs - the number of currently visible aura buttons (number)
			--]]
				if(auras.PostUpdateGapIcon) then
					auras:PostUpdateGapIcon(unit, button, visibleBuffs)
				end
				if(auras.PostUpdateGapButton) then
					auras:PostUpdateGapButton(unit, button, visibleBuffs)
				end
		end

		local visibleDebuffs = filterIcons(auras, unit, auras.debuffFilter or auras.filter or 'HARMFUL', min(numDebuffs, max - visibleBuffs), true, visibleBuffs)
		auras.visibleDebuffs = visibleDebuffs

		if(hasGap and visibleDebuffs == 0) then
			auras[visibleBuffs]:Hide()
			visibleBuffs = visibleBuffs - 1
		end

		auras.visibleBuffs = visibleBuffs
		auras.visibleAuras = auras.visibleBuffs + auras.visibleDebuffs

		local fromRange, toRange
		--[[ Callback: Auras:PreSetPosition(max)
		Called before the aura buttons have been (re-)anchored.

		* self - the widget holding the aura buttons
		* max  - the maximum possible number of aura buttons (number)

		## Returns

		* from - the offset of the first aura button to be (re-)anchored (number)
		* to   - the offset of the last aura button to be (re-)anchored (number)
		--]]
		if(auras.PreSetPosition) then
			fromRange, toRange = auras:PreSetPosition(max)
		end

		if(fromRange or auras.createdIcons > auras.anchoredIcons) then
			--[[ Override: Auras:SetPosition(from, to)
			Used to (re-)anchor the aura buttons.
			Called when new aura buttons have been created or if :PreSetPosition is defined.

			* self - the widget that holds the aura buttons
			* from - the offset of the first aura button to be (re-)anchored (number)
			* to   - the offset of the last aura button to be (re-)anchored (number)
			--]]
			(auras.SetPosition or SetPosition) (auras, fromRange or auras.anchoredIcons + 1, toRange or auras.createdIcons)
			auras.anchoredIcons = auras.createdIcons
		end

		--[[ Callback: Auras:PostUpdate(unit)
		Called after the element has been updated.

		* self - the widget holding the aura buttons
		* unit - the unit for which the update has been triggered (string)
		--]]
			if(auras.PostUpdate) then auras:PostUpdate(unit) end
			if(auras.PostUpdateInfo) then auras:PostUpdateInfo(unit, true, true) end
	end

	local buffs = self.Buffs
	if(buffs) then
		if(buffs.PreUpdate) then buffs:PreUpdate(unit) end

		local numBuffs = buffs.num or 32
		local visibleBuffs = filterIcons(buffs, unit, buffs.filter or 'HELPFUL', numBuffs)
		buffs.visibleBuffs = visibleBuffs

		local fromRange, toRange
		if(buffs.PreSetPosition) then
			fromRange, toRange = buffs:PreSetPosition(numBuffs)
		end

		if(fromRange or buffs.createdIcons > buffs.anchoredIcons) then
			(buffs.SetPosition or SetPosition) (buffs, fromRange or buffs.anchoredIcons + 1, toRange or buffs.createdIcons)
			buffs.anchoredIcons = buffs.createdIcons
		end

		if(buffs.PostUpdate) then buffs:PostUpdate(unit) end
	end

	local debuffs = self.Debuffs
	if(debuffs) then
		if(debuffs.PreUpdate) then debuffs:PreUpdate(unit) end

		local numDebuffs = debuffs.num or 40
		local visibleDebuffs = filterIcons(debuffs, unit, debuffs.filter or 'HARMFUL', numDebuffs, true)
		debuffs.visibleDebuffs = visibleDebuffs

		local fromRange, toRange
		if(debuffs.PreSetPosition) then
			fromRange, toRange = debuffs:PreSetPosition(numDebuffs)
		end

		if(fromRange or debuffs.createdIcons > debuffs.anchoredIcons) then
			(debuffs.SetPosition or SetPosition) (debuffs, fromRange or debuffs.anchoredIcons + 1, toRange or debuffs.createdIcons)
			debuffs.anchoredIcons = debuffs.createdIcons
		end

		if(debuffs.PostUpdate) then debuffs:PostUpdate(unit) end
	end
end

local function Update(self, event, unit)
	if(self.unit ~= unit) then return end

	UpdateAuras(self, event, unit)

	-- Assume no event means someone wants to re-anchor things. This is usually
	-- done by UpdateAllElements and :ForceUpdate.
	if(event == 'ForceUpdate' or not event) then
		local buffs = self.Buffs
		if(buffs) then
			(buffs.SetPosition or SetPosition) (buffs, 1, buffs.createdIcons)
		end

		local debuffs = self.Debuffs
		if(debuffs) then
			(debuffs.SetPosition or SetPosition) (debuffs, 1, debuffs.createdIcons)
		end

		local auras = self.Auras
		if(auras) then
			(auras.SetPosition or SetPosition) (auras, 1, auras.createdIcons)
		end
	end
end

local function ForceUpdate(element)
	return Update(element.__owner, 'ForceUpdate', element.__owner.unit)
end

local function Enable(self)
	if(self.Buffs or self.Debuffs or self.Auras) then
		self:RegisterEvent('UNIT_AURA', UpdateAuras)

		local buffs = self.Buffs
		if(buffs) then
			buffs.__owner = self
			buffs.ForceUpdate = ForceUpdate

			buffs.createdIcons = buffs.createdIcons or 0
			buffs.createdButtons = buffs.createdIcons
			buffs.anchoredIcons = 0
			buffs.anchoredButtons = 0

			-- Avoid parenting GameTooltip to frames with anchoring restrictions,
			-- otherwise it'll inherit said restrictions which will cause issues
			-- with its further positioning, clamping, etc
			if(not pcall(self.GetCenter, self)) then
				buffs.tooltipAnchor = 'ANCHOR_CURSOR'
			else
				buffs.tooltipAnchor = buffs.tooltipAnchor or 'ANCHOR_BOTTOMRIGHT'
			end

			buffs:Show()
		end

		local debuffs = self.Debuffs
		if(debuffs) then
			debuffs.__owner = self
			debuffs.ForceUpdate = ForceUpdate

			debuffs.createdIcons = debuffs.createdIcons or 0
			debuffs.createdButtons = debuffs.createdIcons
			debuffs.anchoredIcons = 0
			debuffs.anchoredButtons = 0

			-- Avoid parenting GameTooltip to frames with anchoring restrictions,
			-- otherwise it'll inherit said restrictions which will cause issues
			-- with its further positioning, clamping, etc
			if(not pcall(self.GetCenter, self)) then
				debuffs.tooltipAnchor = 'ANCHOR_CURSOR'
			else
				debuffs.tooltipAnchor = debuffs.tooltipAnchor or 'ANCHOR_BOTTOMRIGHT'
			end

			debuffs:Show()
		end

		local auras = self.Auras
		if(auras) then
			auras.__owner = self
			auras.ForceUpdate = ForceUpdate

			auras.createdIcons = auras.createdIcons or 0
			auras.createdButtons = auras.createdIcons
			auras.anchoredIcons = 0
			auras.anchoredButtons = 0

			-- Avoid parenting GameTooltip to frames with anchoring restrictions,
			-- otherwise it'll inherit said restrictions which will cause issues
			-- with its further positioning, clamping, etc
			if(not pcall(self.GetCenter, self)) then
				auras.tooltipAnchor = 'ANCHOR_CURSOR'
			else
				auras.tooltipAnchor = auras.tooltipAnchor or 'ANCHOR_BOTTOMRIGHT'
			end

			auras:Show()
		end

		return true
	end
end

local function Disable(self)
	if(self.Buffs or self.Debuffs or self.Auras) then
		self:UnregisterEvent('UNIT_AURA', UpdateAuras)

		if(self.Buffs) then self.Buffs:Hide() end
		if(self.Debuffs) then self.Debuffs:Hide() end
		if(self.Auras) then self.Auras:Hide() end
	end
end

oUF:AddElement('Auras', Update, Enable, Disable)
