if EllesmereUI and EllesmereUI.ADDON_ROSTER then
	local found = false
	for _, info in ipairs(EllesmereUI.ADDON_ROSTER) do
		if info.folder == 'EllesmereUIDamageMeter' then found = true; break end
	end
	if not found then
		local insertIdx = #EllesmereUI.ADDON_ROSTER + 1
		for i, info in ipairs(EllesmereUI.ADDON_ROSTER) do
			if info.folder == 'EllesmereUIPartyMode' or info.comingSoon then
				insertIdx = i; break
			end
		end
		table.insert(EllesmereUI.ADDON_ROSTER, insertIdx, {
			folder      = 'EllesmereUIDamageMeter',
			display     = 'Damage Meter',
			search_name = 'EllesmereUI Damage Meter',
			icon_on     = 'Interface\\Icons\\INV_Misc_Map_01',
			icon_off    = 'Interface\\Icons\\INV_Misc_Map_01',
		})
	end
end

local function InitOptions()
	if not EllesmereUI or not EllesmereUI.RegisterModule then return end
	local addon = EllesmereUIDamageMeter
	if not addon or not addon.db then return end

	local function DB() return addon.db.profile end

	local S = addon.S
	local CLASS_FULL_SPRITE_BASE = S.CLASS_FULL_BASE
	local CLASS_FULL_COORDS = S.CLASS_FULL_COORDS
	local FLAT_TEX = S.FLAT_TEX
	local texTextures = S.texTextures
	local texDropdownValues = S.texDropdownValues
	local texDropdownOrder = S.texDropdownOrder

	local classIconValues = {
		['fabled'] = 'Fabled (TUI)',
		['modern'] = 'Modern', ['arcade'] = 'Arcade', ['glyph'] = 'Glyph',
		['legend'] = 'Legend', ['midnight'] = 'Midnight', ['pixel'] = 'Pixel', ['runic'] = 'Runic',
		['none'] = 'None',
	}
	local classIconOrder = { 'fabled', 'modern', 'arcade', 'glyph', 'legend', 'midnight', 'pixel', 'runic', 'none' }

	local previewData = {
		{ name = 'Trenchy',    class = 'DEATHKNIGHT', pct = 0.85 },
		{ name = 'Healbro',    class = 'PRIEST',      pct = 0.62 },
		{ name = 'Stabsworth', class = 'ROGUE',       pct = 0.45 },
	}

	local previewFrame

	local function UpdatePreview()
		if not previewFrame or not previewFrame.Update then return end
		previewFrame:Update()
	end

	local function Refresh()
		if addon.UpdateMeterLayout then addon:UpdateMeterLayout() end
		if addon.RefreshMeter then addon:RefreshMeter() end
		UpdatePreview()
	end

	local function BuildPreview(parent, yOffset)
		local pf = CreateFrame('Frame', nil, parent)
		local previewW = 240
		local previewH = 120
		pf:SetSize(previewW, previewH)
		pf:SetPoint('TOP', parent, 'TOP', 0, yOffset - 6)

		local previewScale = UIParent:GetEffectiveScale() / parent:GetEffectiveScale()
		pf:SetScale(previewScale)

		-- Background
		local bg = pf:CreateTexture(nil, 'BACKGROUND')
		bg:SetAllPoints()
		bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)

		-- Header
		local header = CreateFrame('Frame', nil, pf)
		header:SetPoint('TOPLEFT', pf, 'TOPLEFT', 0, 0)
		header:SetPoint('TOPRIGHT', pf, 'TOPRIGHT', 0, 0)
		header:SetHeight(22)
		local headerBg = header:CreateTexture(nil, 'BACKGROUND')
		headerBg:SetAllPoints()
		headerBg:SetColorTexture(0.15, 0.15, 0.15, 0.8)
		local headerText = header:CreateFontString(nil, 'OVERLAY')
		headerText:SetPoint('LEFT', 4, 0)
		headerText:SetFont(EllesmereUI.EXPRESSWAY or 'Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
		headerText:SetText('Damage')
		headerText:SetShadowOffset(1, -1)

		local bars = {}
		local LSM = LibStub('LibSharedMedia-3.0')
		for i, data in ipairs(previewData) do
			local bar = CreateFrame('Frame', nil, pf, 'BackdropTemplate')
			bar.statusbar = CreateFrame('StatusBar', nil, bar)
			bar.statusbar:SetAllPoints()
			bar.statusbar:SetMinMaxValues(0, 1)
			bar.statusbar:SetValue(data.pct)
			bar.bg = bar:CreateTexture(nil, 'BACKGROUND')
			bar.bg:SetAllPoints()
			bar.icon = bar.statusbar:CreateTexture(nil, 'OVERLAY')
			bar.icon:SetPoint('LEFT', 1, 0)
			bar.leftText = bar.statusbar:CreateFontString(nil, 'OVERLAY')
			bar.leftText:SetJustifyH('LEFT')
			bar.leftText:SetShadowOffset(1, -1)
			bar.rightText = bar.statusbar:CreateFontString(nil, 'OVERLAY')
			bar.rightText:SetPoint('RIGHT', -4, 0)
			bar.rightText:SetJustifyH('RIGHT')
			bar.rightText:SetShadowOffset(1, -1)
			bar.data = data
			bars[i] = bar
		end
		pf._bars = bars
		pf._header = header
		pf._headerBg = headerBg
		pf._headerText = headerText
		pf._bg = bg

		function pf:Update()
			local db = DB()
			if not db then return end

			local barH = db.barHeight or 18
			local spacing = db.barSpacing or 1
			local fFont = EllesmereUI.EXPRESSWAY or 'Fonts\\FRIZQT__.TTF'
			if db.barFont then
				local fetched = LSM:Fetch('font', db.barFont)
				if fetched then fFont = fetched end
			end
			local fSize = db.barFontSize or 11
			local fFlags = (db.barFontOutline and db.barFontOutline ~= 'NONE') and db.barFontOutline or ''

			local resolveTex = EllesmereUI.ResolveTexturePath
			local fgTex = resolveTex and resolveTex(texTextures, db.barTexture, FLAT_TEX) or FLAT_TEX
			local bgTex = resolveTex and resolveTex(texTextures, db.barBGTexture, FLAT_TEX) or FLAT_TEX

			if db.showHeaderBackdrop then
				local hc = db.headerBGColor
				self._headerBg:SetColorTexture(hc.r, hc.g, hc.b, hc.a)
				self._headerBg:Show()
			else
				self._headerBg:Hide()
			end

			if db.showBackdrop then
				local bc = db.backdropColor
				self._bg:SetColorTexture(bc.r, bc.g, bc.b, bc.a)
				self._bg:Show()
			else
				self._bg:Hide()
			end

			local iconStyle = db.classIconStyle or 'fabled'
			local iconSize = math.max(8, barH - 2)
			local showIcons = db.showClassIcon

			for i, bar in ipairs(self._bars) do
				local data = bar.data
				bar:SetHeight(barH)
				bar:ClearAllPoints()
				if i == 1 then
					bar:SetPoint('TOPLEFT', self._header, 'BOTTOMLEFT', 0, 0)
					bar:SetPoint('TOPRIGHT', self._header, 'BOTTOMRIGHT', 0, 0)
				else
					bar:SetPoint('TOPLEFT', self._bars[i-1], 'BOTTOMLEFT', 0, -spacing)
					bar:SetPoint('TOPRIGHT', self._bars[i-1], 'BOTTOMRIGHT', 0, -spacing)
				end
				bar:Show()

				bar.statusbar:SetStatusBarTexture(fgTex)
				bar.statusbar:SetValue(data.pct)
				bar.bg:SetTexture(bgTex)

				local cc = EllesmereUI.GetClassColor(data.class)
				if db.barClassColor and cc then
					bar.statusbar:SetStatusBarColor(cc.r, cc.g, cc.b)
				else
					local c = db.barColor
					bar.statusbar:SetStatusBarColor(c.r, c.g, c.b, c.a)
				end

				if db.barBGClassColor and cc then
					bar.bg:SetVertexColor(cc.r, cc.g, cc.b, db.barBGColor.a)
				else
					local c = db.barBGColor
					bar.bg:SetVertexColor(c.r, c.g, c.b, c.a)
				end

				bar.icon:SetSize(iconSize, iconSize)
				if showIcons and iconStyle ~= 'none' then
					if iconStyle == 'fabled' then
						local S = addon.S
						bar.icon:SetTexture(S and S.CLASS_ICONS or '')
						local coords = S and S.CLASS_ICON_COORDS and S.CLASS_ICON_COORDS[data.class]
						if coords then
							bar.icon:SetTexCoord(unpack(coords))
						end
					else
						bar.icon:SetTexture(CLASS_FULL_SPRITE_BASE .. iconStyle .. '.tga')
						local coords = CLASS_FULL_COORDS[data.class]
						if coords then
							bar.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
						end
					end
					bar.icon:Show()
				else
					bar.icon:Hide()
				end

				bar.leftText:SetFont(fFont, fSize, fFlags)
				bar.rightText:SetFont(fFont, fSize, fFlags)
				bar.leftText:ClearAllPoints()
				if showIcons and iconStyle ~= 'none' then
					bar.leftText:SetPoint('LEFT', bar.icon, 'RIGHT', 2, 0)
				else
					bar.leftText:SetPoint('LEFT', 4, 0)
				end
				bar.leftText:SetPoint('RIGHT', bar.rightText, 'LEFT', -4, 0)

				bar.leftText:SetText(data.name)
				bar.rightText:SetText(math.floor(data.pct * 100000))

				if db.textClassColor and cc then
					bar.leftText:SetTextColor(cc.r, cc.g, cc.b)
				else
					local c = db.textColor
					bar.leftText:SetTextColor(c.r, c.g, c.b)
				end
				if db.valueClassColor and cc then
					bar.rightText:SetTextColor(cc.r, cc.g, cc.b)
				else
					local c = db.valueColor
					bar.rightText:SetTextColor(c.r, c.g, c.b)
				end
			end

			local totalH = 22 + (#self._bars * barH) + ((#self._bars - 1) * spacing)
			self:SetHeight(totalH)
		end

		previewFrame = pf
		pf:Update()

		return (previewH + 16) / previewScale
	end

	local function BuildGeneralPage(_, parent, yOffset)
		local W = EllesmereUI.Widgets
		local wrapper = CreateFrame('Frame', nil, parent)
		wrapper:SetAllPoints()

		local h = 0

		local previewH = BuildPreview(wrapper, yOffset - h)
		h = h + previewH + 10

		local _, rh
		_, rh = W:SectionHeader(wrapper, 'General', yOffset - h); h = h + rh

		_, rh = W:DualRow(wrapper, yOffset - h,
			{ type = 'toggle', text = 'Enable',
				getValue = function() return DB().enabled end,
				setValue = function(v) DB().enabled = v; Refresh() end },
			{ type = 'toggle', text = 'Test Mode',
				getValue = function() return addon._meterTestMode end,
				setValue = function(v) addon:SetMeterTestMode(v) end }
		); h = h + rh

		_, rh = W:DualRow(wrapper, yOffset - h,
			{ type = 'toggle', text = 'Show Timer',
				getValue = function() return DB().showTimer end,
				setValue = function(v) DB().showTimer = v; Refresh() end },
			{ type = 'toggle', text = 'Show Rank',
				getValue = function() return DB().showRank end,
				setValue = function(v) DB().showRank = v; Refresh() end }
		); h = h + rh

		_, rh = W:DualRow(wrapper, yOffset - h,
			{ type = 'toggle', text = 'Show Class Icon',
				getValue = function() return DB().showClassIcon end,
				setValue = function(v) DB().showClassIcon = v; Refresh() end },
			{ type = 'dropdown', text = 'Icon Style', values = classIconValues, order = classIconOrder,
				getValue = function() return DB().classIconStyle or 'fabled' end,
				setValue = function(v) DB().classIconStyle = v; Refresh() end,
				disabled = function() return not DB().showClassIcon end }
		); h = h + rh

		_, rh = W:DualRow(wrapper, yOffset - h,
			{ type = 'toggle', text = 'Show Backdrop',
				getValue = function() return DB().showBackdrop end,
				setValue = function(v) DB().showBackdrop = v; Refresh() end },
			{ type = 'toggle', text = 'Bar Border',
				getValue = function() return DB().barBorderEnabled end,
				setValue = function(v) DB().barBorderEnabled = v; Refresh() end }
		); h = h + rh

		_, rh = W:DualRow(wrapper, yOffset - h,
			{ type = 'toggle', text = 'Header Backdrop',
				getValue = function() return DB().showHeaderBackdrop end,
				setValue = function(v) DB().showHeaderBackdrop = v; Refresh() end },
			{ type = 'toggle', text = 'Header Border',
				getValue = function() return DB().showHeaderBorder end,
				setValue = function(v) DB().showHeaderBorder = v; Refresh() end }
		); h = h + rh

		_, rh = W:DualRow(wrapper, yOffset - h,
			{ type = 'toggle', text = 'Header Mouseover',
				getValue = function() return DB().headerMouseover end,
				setValue = function(v) DB().headerMouseover = v; Refresh() end },
			{ type = 'toggle', text = 'Hide in Flight',
				getValue = function() return DB().hideInFlight end,
				setValue = function(v) DB().hideInFlight = v; if addon.UpdateFlightTicker then addon:UpdateFlightTicker() end end }
		); h = h + rh

		_, rh = W:DualRow(wrapper, yOffset - h,
			{ type = 'toggle', text = 'Hide in Pet Battle',
				getValue = function() return DB().hideInPetBattle end,
				setValue = function(v) DB().hideInPetBattle = v end },
			{ type = 'toggle', text = 'Auto-Reset on Instance',
				getValue = function() return DB().autoResetOnComplete end,
				setValue = function(v) DB().autoResetOnComplete = v end }
		); h = h + rh

		_, rh = W:SectionHeader(wrapper, 'Size', yOffset - h); h = h + rh

		_, rh = W:DualRow(wrapper, yOffset - h,
			{ type = 'slider', text = 'Width', min = 120, max = 500, step = 1,
				getValue = function() return DB().standaloneWidth end,
				setValue = function(v) DB().standaloneWidth = v; if addon.ResizeMeterWindow then addon:ResizeMeterWindow(1) end; Refresh() end },
			{ type = 'slider', text = 'Height', min = 80, max = 500, step = 1,
				getValue = function() return DB().standaloneHeight end,
				setValue = function(v) DB().standaloneHeight = v; if addon.ResizeMeterWindow then addon:ResizeMeterWindow(1) end; Refresh() end }
		); h = h + rh

		_, rh = W:DualRow(wrapper, yOffset - h,
			{ type = 'slider', text = 'Bar Height', min = 8, max = 40, step = 1,
				getValue = function() return DB().barHeight end,
				setValue = function(v) DB().barHeight = v; Refresh() end },
			{ type = 'slider', text = 'Bar Spacing', min = 0, max = 10, step = 1,
				getValue = function() return DB().barSpacing end,
				setValue = function(v) DB().barSpacing = v; Refresh() end }
		); h = h + rh

		_, rh = W:SectionHeader(wrapper, 'Textures', yOffset - h); h = h + rh

		_, rh = W:DualRow(wrapper, yOffset - h,
			{ type = 'dropdown', text = 'Bar Texture', values = texDropdownValues, order = texDropdownOrder,
				getValue = function() return DB().barTexture or 'none' end,
				setValue = function(v) DB().barTexture = v; Refresh() end },
			{ type = 'dropdown', text = 'Bar BG Texture', values = texDropdownValues, order = texDropdownOrder,
				getValue = function() return DB().barBGTexture or 'none' end,
				setValue = function(v) DB().barBGTexture = v; Refresh() end }
		); h = h + rh

		_, rh = W:SectionHeader(wrapper, 'Font', yOffset - h); h = h + rh

		_, rh = W:DualRow(wrapper, yOffset - h,
			{ type = 'slider', text = 'Bar Font Size', min = 6, max = 24, step = 1,
				getValue = function() return DB().barFontSize end,
				setValue = function(v) DB().barFontSize = v; Refresh() end },
			{ type = 'slider', text = 'Header Font Size', min = 6, max = 24, step = 1,
				getValue = function() return DB().headerFontSize end,
				setValue = function(v) DB().headerFontSize = v; Refresh() end }
		); h = h + rh

		_, rh = W:SectionHeader(wrapper, 'Colors', yOffset - h); h = h + rh

		_, rh = W:DualRow(wrapper, yOffset - h,
			{ type = 'toggle', text = 'Class Color Bars',
				getValue = function() return DB().barClassColor end,
				setValue = function(v) DB().barClassColor = v; Refresh() end },
			{ type = 'multiSwatch', text = 'Bar Color', swatches = {
				{ tooltip = 'Bar Color',
					getValue = function() local c = DB().barColor; return c.r, c.g, c.b, c.a end,
					setValue = function(r, g, b, a) local c = DB().barColor; c.r, c.g, c.b, c.a = r, g, b, a; Refresh() end,
					hasAlpha = true },
			}, disabled = function() return DB().barClassColor end }
		); h = h + rh

		_, rh = W:DualRow(wrapper, yOffset - h,
			{ type = 'toggle', text = 'Class Color Text',
				getValue = function() return DB().textClassColor end,
				setValue = function(v) DB().textClassColor = v; Refresh() end },
			{ type = 'multiSwatch', text = 'Text Color', swatches = {
				{ tooltip = 'Text Color',
					getValue = function() local c = DB().textColor; return c.r, c.g, c.b end,
					setValue = function(r, g, b) local c = DB().textColor; c.r, c.g, c.b = r, g, b; Refresh() end },
			}, disabled = function() return DB().textClassColor end }
		); h = h + rh

		_, rh = W:DualRow(wrapper, yOffset - h,
			{ type = 'toggle', text = 'Class Color Values',
				getValue = function() return DB().valueClassColor end,
				setValue = function(v) DB().valueClassColor = v; Refresh() end },
			{ type = 'multiSwatch', text = 'Value Color', swatches = {
				{ tooltip = 'Value Color',
					getValue = function() local c = DB().valueColor; return c.r, c.g, c.b end,
					setValue = function(r, g, b) local c = DB().valueColor; c.r, c.g, c.b = r, g, b; Refresh() end },
			}, disabled = function() return DB().valueClassColor end }
		); h = h + rh

		_, rh = W:DualRow(wrapper, yOffset - h,
			{ type = 'toggle', text = 'Class Color BG',
				getValue = function() return DB().barBGClassColor end,
				setValue = function(v) DB().barBGClassColor = v; Refresh() end },
			{ type = 'multiSwatch', text = 'BG Color', swatches = {
				{ tooltip = 'Background Color',
					getValue = function() local c = DB().barBGColor; return c.r, c.g, c.b, c.a end,
					setValue = function(r, g, b, a) local c = DB().barBGColor; c.r, c.g, c.b, c.a = r, g, b, a; Refresh() end,
					hasAlpha = true },
			}, disabled = function() return DB().barBGClassColor end }
		); h = h + rh

		return h
	end

	EllesmereUI:RegisterModule('EllesmereUIDamageMeter', {
		title       = 'Damage Meter',
		description = 'Damage meter',
		pages       = { 'General' },
		buildPage   = function(pageName, parent, yOffset)
			if pageName == 'General' then
				return BuildGeneralPage(pageName, parent, yOffset)
			end
		end,
		onPageCacheRestore = function()
			UpdatePreview()
		end,
		onReset = function()
			if addon.db and addon.db.ResetProfile then
				addon.db:ResetProfile()
			end
			wipe(S.winDBCache)
			Refresh()
		end,
	})

	EllesmereUI:RegisterOnShow(UpdatePreview)
end

if IsLoggedIn() then
	InitOptions()
else
	local initFrame = CreateFrame('Frame')
	initFrame:RegisterEvent('PLAYER_LOGIN')
	initFrame:SetScript('OnEvent', function(self)
		self:UnregisterEvent('PLAYER_LOGIN')
		InitOptions()
	end)
end
