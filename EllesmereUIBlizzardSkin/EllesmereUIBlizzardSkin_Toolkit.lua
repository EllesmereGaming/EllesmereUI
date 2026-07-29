local WSkin = {}
_G.EllesmereUIBlizzardSkin = WSkin

local _G = _G
local unpack, type, select, getmetatable = unpack, type, select, getmetatable
local CreateFrame = CreateFrame

-- Texture references
local blankTex = "Interface\\Buttons\\WHITE8X8"
local closeTex = "Interface\\Buttons\\UI-Panel-MinimizeButton-Up"

local backdropr, backdropg, backdropb, backdropa, borderr, borderg, borderb = 0, 0, 0, 1, 0, 0, 0
local mult = 1

local function Scale(x) return x end

local function Size(frame, width, height)
	frame:SetSize(Scale(width), Scale(height or width))
end

local function Width(frame, width)
	frame:SetWidth(Scale(width))
end

local function Height(frame, height)
	frame:SetHeight(Scale(height))
end

local function Point(obj, arg1, arg2, arg3, arg4, arg5)
	if type(arg5) == "number" then
		arg5 = Scale(arg5)
		arg4 = Scale(arg4)
	elseif type(arg4) == "number" then
		arg4 = Scale(arg4)
		arg3 = Scale(arg3)
	elseif type(arg3) == "number" then
		arg3 = Scale(arg3)
		arg2 = Scale(arg2)
	end
	obj:SetPoint(arg1, arg2 or obj:GetParent(), arg3, arg4, arg5)
end

local function SetOutside(obj, anchor, xOffset, yOffset, anchor2)
	xOffset = xOffset or 1
	yOffset = yOffset or 1
	anchor = anchor or obj:GetParent()

	if obj:GetPoint() then obj:ClearAllPoints() end
	Point(obj, "TOPLEFT", anchor, "TOPLEFT", -xOffset, yOffset)
	Point(obj, "BOTTOMRIGHT", anchor2 or anchor, "BOTTOMRIGHT", xOffset, -yOffset)
end

local function SetInside(obj, anchor, xOffset, yOffset, anchor2)
	xOffset = xOffset or 1
	yOffset = yOffset or 1
	anchor = anchor or obj:GetParent()

	if obj:GetPoint() then obj:ClearAllPoints() end
	Point(obj, "TOPLEFT", anchor, "TOPLEFT", xOffset, -yOffset)
	Point(obj, "BOTTOMRIGHT", anchor2 or anchor, "BOTTOMRIGHT", -xOffset, yOffset)
end

local function SetTemplate(frame, template, glossTex, ignoreUpdates, forcePixelMode, isUnitFrameElement)
	borderr, borderg, borderb = 0.2, 0.2, 0.2
	if template == "Transparent" then
		backdropr, backdropg, backdropb, backdropa = 0, 0, 0, 0.8
	else
		backdropr, backdropg, backdropb, backdropa = 0.1, 0.1, 0.1, 1
	end

	frame:SetBackdrop({
		bgFile = blankTex,
		edgeFile = blankTex,
		tile = false, tileSize = 0, edgeSize = mult,
		insets = {left = 0, right = 0, top = 0, bottom = 0}
	})
	frame:SetBackdropColor(backdropr, backdropg, backdropb, backdropa)
	frame:SetBackdropBorderColor(borderr, borderg, borderb)
end

local function CreateBackdrop(frame, template, glossTex, ignoreUpdates, forcePixelMode, isUnitFrameElement)
	if not template then template = "Default" end
	local parent = (frame.IsObjectType and frame:IsObjectType("Texture") and frame:GetParent()) or frame
	local backdrop = frame.backdrop or CreateFrame("Frame", nil, parent)
	if not frame.backdrop then frame.backdrop = backdrop end

	SetOutside(backdrop, frame)
	SetTemplate(backdrop, template)

	local frameLevel = parent.GetFrameLevel and parent:GetFrameLevel()
	local frameLevelMinusOne = frameLevel and (frameLevel - 1)
	if frameLevelMinusOne and (frameLevelMinusOne >= 0) then
		backdrop:SetFrameLevel(frameLevelMinusOne)
	else
		backdrop:SetFrameLevel(0)
	end
end

local function Kill(object)
	if object.UnregisterAllEvents then
		object:UnregisterAllEvents()
		object:SetParent(CreateFrame("Frame"))
	else
		object.Show = function() end
	end
	object:Hide()
end

local function StripTextures(object, kill, alpha)
	if object:IsObjectType("Texture") then
		if kill then
			Kill(object)
		elseif alpha then
			object:SetAlpha(0)
		else
			object:SetTexture()
		end
	else
		if object.GetNumRegions then
			for i = 1, object:GetNumRegions() do
				local region = select(i, object:GetRegions())
				if region and region.IsObjectType and region:IsObjectType("Texture") then
					if kill then
						Kill(region)
					elseif alpha then
						region:SetAlpha(0)
					else
						region:SetTexture()
					end
				end
			end
		end
	end
end

local function StyleButton(button, noHover, noPushed, noChecked)
	if button.SetHighlightTexture and not button.hover and not noHover then
		local hover = button:CreateTexture()
		SetInside(hover)
		hover:SetTexture(1, 1, 1, 0.3)
		button:SetHighlightTexture(hover)
		button.hover = hover
	end
	if button.SetPushedTexture and not button.pushed and not noPushed then
		local pushed = button:CreateTexture()
		SetInside(pushed)
		pushed:SetTexture(0.9, 0.8, 0.1, 0.3)
		button:SetPushedTexture(pushed)
		button.pushed = pushed
	end
	if button.SetCheckedTexture and not button.checked and not noChecked then
		local checked = button:CreateTexture()
		SetInside(checked)
		checked:SetTexture(1, 1, 1, 0.3)
		button:SetCheckedTexture(checked)
		button.checked = checked
	end
	local name = button.GetName and button:GetName()
	local cooldown = name and _G[name.."Cooldown"]
	if cooldown then
		cooldown:ClearAllPoints()
		SetInside(cooldown)
	end
end

local CreateCloseButton
do
	local CloseButtonOnClick = function(btn) btn:GetParent():Hide() end
	local CloseButtonOnEnter = function(btn) if btn.Texture then btn.Texture:SetVertexColor(1, 0, 0) end end
	local CloseButtonOnLeave = function(btn) if btn.Texture then btn.Texture:SetVertexColor(1, 1, 1) end end
	CreateCloseButton = function(frame, size, offset, texture, backdrop)
		if frame.CloseButton then return end
		local CloseButton = CreateFrame("Button", nil, frame)
		Size(CloseButton, size or 16)
		Point(CloseButton, "TOPRIGHT", offset or -6, offset or -6)
		if backdrop then CreateBackdrop(CloseButton, nil, true) end
		CloseButton.Texture = CloseButton:CreateTexture(nil, "OVERLAY")
		CloseButton.Texture:SetAllPoints()
		CloseButton.Texture:SetTexture(texture or closeTex)
		CloseButton:SetScript("OnClick", CloseButtonOnClick)
		CloseButton:SetScript("OnEnter", CloseButtonOnEnter)
		CloseButton:SetScript("OnLeave", CloseButtonOnLeave)
		frame.CloseButton = CloseButton
	end
end

-- Expose methods directly on WSkin to accept self (WSkin) as first argument
WSkin.Size = function(self, frame, ...) return Size(frame, ...) end
WSkin.Width = function(self, frame, ...) return Width(frame, ...) end
WSkin.Height = function(self, frame, ...) return Height(frame, ...) end
WSkin.Point = function(self, frame, ...) return Point(frame, ...) end
WSkin.SetOutside = function(self, frame, ...) return SetOutside(frame, ...) end
WSkin.SetInside = function(self, frame, ...) return SetInside(frame, ...) end
WSkin.SetTemplate = function(self, frame, ...) return SetTemplate(frame, ...) end
WSkin.CreateBackdrop = function(self, frame, ...) return CreateBackdrop(frame, ...) end
WSkin.Kill = function(self, frame, ...) return Kill(frame, ...) end
WSkin.StripTextures = function(self, frame, ...) return StripTextures(frame, ...) end
WSkin.StyleButton = function(self, frame, ...) return StyleButton(frame, ...) end
WSkin.CreateCloseButton = function(self, frame, ...) return CreateCloseButton(frame, ...) end

-- Skins
function WSkin:SetModifiedBackdrop()
	if self.backdrop then self = self.backdrop end
	self:SetBackdropBorderColor(1, 0.82, 0)
end

function WSkin:SetOriginalBackdrop()
	if self.backdrop then self = self.backdrop end
	self:SetBackdropBorderColor(0.2, 0.2, 0.2)
end

function WSkin:HandleButton(button, strip, isDeclineButton, useCreateBackdrop, noSetTemplate)
	if button.isSkinned then return end

	if button.Left then button.Left:SetAlpha(0) end
	if button.Middle then button.Middle:SetAlpha(0) end
	if button.Right then button.Right:SetAlpha(0) end

	if button.SetNormalTexture then button:SetNormalTexture("") end
	if button.SetHighlightTexture then button:SetHighlightTexture("") end
	if button.SetPushedTexture then button:SetPushedTexture("") end
	if button.SetDisabledTexture then button:SetDisabledTexture("") end

	if strip then StripTextures(button) end

	if useCreateBackdrop then
		CreateBackdrop(button, nil, true)
	elseif not noSetTemplate then
		SetTemplate(button, nil, true)
	end

	button:HookScript("OnEnter", WSkin.SetModifiedBackdrop)
	button:HookScript("OnLeave", WSkin.SetOriginalBackdrop)

	button.isSkinned = true
end

function WSkin:HandleCloseButton(f, point)
	StripTextures(f)

	if f:GetNormalTexture() then f:SetNormalTexture("") f.SetNormalTexture = function() end end
	if f:GetPushedTexture() then f:SetPushedTexture("") f.SetPushedTexture = function() end end

	if not f.Texture then
		f.Texture = f:CreateTexture(nil, "OVERLAY")
		Point(f.Texture, "CENTER")
		f.Texture:SetTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
		Size(f.Texture, 16, 16)
		f:HookScript("OnEnter", function(btn) if btn.Texture then btn.Texture:SetVertexColor(1, 0, 0) end end)
		f:HookScript("OnLeave", function(btn) if btn.Texture then btn.Texture:SetVertexColor(1, 1, 1) end end)
		f:SetHitRectInsets(7, 6, 7, 6)
	end

	if point then
		Point(f, "TOPRIGHT", point, "TOPRIGHT", 2, 3)
	end
end

function WSkin:HandleCheckBox(frame, noBackdrop, noReplaceTextures)
	if frame.isSkinned then return end
	StripTextures(frame)

	if noBackdrop then
		SetTemplate(frame)
		Size(frame, 16)
	else
		CreateBackdrop(frame)
		SetInside(frame.backdrop, nil, 4, 4)
	end

	if not noReplaceTextures then
		if frame.SetCheckedTexture then
			frame:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
			if noBackdrop then SetInside(frame:GetCheckedTexture(), nil, -4, -4) end
		end
		if frame.SetDisabledCheckedTexture then
			frame:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
			if noBackdrop then SetInside(frame:GetDisabledCheckedTexture(), nil, -4, -4) end
		end
		if frame.SetDisabledTexture then
			frame:SetDisabledTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
			if noBackdrop then SetInside(frame:GetDisabledTexture(), nil, -4, -4) end
		end

		frame:HookScript("OnDisable", function(checkbox)
			if not checkbox.SetDisabledTexture then return end
			if checkbox:GetChecked() then
				checkbox:SetDisabledTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
			else
				checkbox:SetDisabledTexture("")
			end
		end)

		hooksecurefunc(frame, "SetNormalTexture", function(checkbox, texPath)
			if texPath ~= "" then checkbox:SetNormalTexture("") end
		end)
		hooksecurefunc(frame, "SetPushedTexture", function(checkbox, texPath)
			if texPath ~= "" then checkbox:SetPushedTexture("") end
		end)
		hooksecurefunc(frame, "SetHighlightTexture", function(checkbox, texPath)
			if texPath ~= "" then checkbox:SetHighlightTexture("") end
		end)
	end
	frame.isSkinned = true
end

local tabs = {"LeftDisabled","MiddleDisabled","RightDisabled","Left","Middle","Right"}
function WSkin:HandleTab(tab, noBackdrop)
	if (not tab) or (tab.backdrop and not noBackdrop) then return end
	for _, object in ipairs(tabs) do
		local tex = _G[tab:GetName()..object]
		if tex then tex:SetTexture() end
	end
	local highlightTex = tab.GetHighlightTexture and tab:GetHighlightTexture()
	if highlightTex then highlightTex:SetTexture() else StripTextures(tab) end

	if not noBackdrop then
		CreateBackdrop(tab)
		Point(tab.backdrop, "TOPLEFT", 10, -3)
		Point(tab.backdrop, "BOTTOMRIGHT", -10, 3)
		tab:SetHitRectInsets(10, 10, 3, 3)
	end
end

WSkin.ArrowRotation = {
	["up"] = 0,
	["down"] = 3.14,
	["left"] = 1.57,
	["right"] = -1.57,
}

function WSkin:HandleNextPrevButton(btn, arrowDir, color, noBackdrop, stipTexts)
	if btn.isSkinned then return end

	if not arrowDir then
		arrowDir = "down"
		local name = btn:GetName() and string.lower(btn:GetName())
		if name then
			if string.find(name, "left") or string.find(name, "prev") or string.find(name, "decrement") then arrowDir = "left"
			elseif string.find(name, "right") or string.find(name, "next") or string.find(name, "increment") then arrowDir = "right"
			elseif string.find(name, "scrollup") or string.find(name, "upbutton") or string.find(name, "top") or string.find(name, "promote") then arrowDir = "up"
			end
		end
	end

	StripTextures(btn)
	if not noBackdrop then WSkin:HandleButton(btn) end

	if arrowDir == "up" then
		btn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Up")
		btn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Down")
		btn:SetDisabledTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Disabled")
	elseif arrowDir == "down" then
		btn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
		btn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
		btn:SetDisabledTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Disabled")
	else
		btn:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
		btn:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
		btn:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled")
	end

	if noBackdrop then
		Size(btn, 20, 20)
	else
		Size(btn, 18, 18)
	end
	
	local Normal = btn:GetNormalTexture()
	local Pushed = btn:GetPushedTexture()
	local Disabled = btn:GetDisabledTexture()
	if Normal then SetInside(Normal) end
	if Pushed then SetInside(Pushed) end
	if Disabled then SetInside(Disabled) end

	btn.isSkinned = true
end

function WSkin:HandleScrollBar(frame, horizontal)
	if frame.backdrop then return end

	local parent = frame:GetParent()
	local frameName = frame:GetName()

	local scrollUpButton, scrollDownButton
	local thumb = frame.thumbTexture or frame.GetThumbTexture and frame:GetThumbTexture() or _G[string.format("%s%s", frameName, "ThumbTexture")]

	if frameName then
		if not horizontal then
			scrollUpButton = parent.scrollUp or _G[string.format("%s%s", frameName, "ScrollUpButton")] or _G[string.format("%s%s", frameName, "UpButton")] or _G[string.format("%s%s", frameName, "ScrollUp")]
			scrollDownButton = parent.scrollDown or _G[string.format("%s%s", frameName, "ScrollDownButton")] or _G[string.format("%s%s", frameName, "DownButton")] or _G[string.format("%s%s", frameName, "ScrollDown")]
		end
	end

	if not horizontal then Width(frame, 18) else Height(frame, 18) end

	local frameLevel = frame:GetFrameLevel()
	StripTextures(frame)
	CreateBackdrop(frame)
	frame.backdrop:SetAllPoints()
	frame.backdrop:SetFrameLevel(frameLevel)

	if scrollUpButton then
		if not horizontal then
			Point(scrollUpButton, "BOTTOM", frame, "TOP", 0, 1)
			WSkin:HandleNextPrevButton(scrollUpButton, "up")
		end
	end

	if scrollDownButton then
		if not horizontal then
			Point(scrollDownButton, "TOP", frame, "BOTTOM", 0, -1)
			WSkin:HandleNextPrevButton(scrollDownButton, "down")
		end
	end

	if thumb and not thumb.backdrop then
		if not horizontal then Size(thumb, 18, 22) else Size(thumb, 22, 18) end
		thumb:SetTexture()
		CreateBackdrop(thumb, nil, true, true)
		thumb.backdrop:SetFrameLevel(frameLevel + 1)
		thumb.backdrop:SetBackdropColor(0.6, 0.6, 0.6)
		Point(thumb.backdrop, "TOPLEFT", thumb, "TOPLEFT", 2, -2)
		Point(thumb.backdrop, "BOTTOMRIGHT", thumb, "BOTTOMRIGHT", -2, 2)
		if not frame.thumbTexture then frame.thumbTexture = thumb end
	end
end

function WSkin:SetUIPanelWindowInfo(frame, prop, val, offset)
end

function WSkin:SetBackdropHitRect(frame, backdrop)
	if not backdrop then backdrop = frame.backdrop end
	if backdrop then
		frame:SetHitRectInsets(backdrop:GetLeft() - frame:GetLeft(), frame:GetRight() - backdrop:GetRight(), backdrop:GetTop() - frame:GetTop(), frame:GetBottom() - backdrop:GetBottom())
	end
end

function WSkin:HandleDropDownBox(frame, width, direction)
	if frame.backdrop then return end

	local FrameName = frame.GetName and frame:GetName()
	local button = FrameName and _G[FrameName.."Button"]
	local text = FrameName and _G[FrameName.."Text"]

	StripTextures(frame)
	CreateBackdrop(frame)
	frame.backdrop:SetFrameLevel(frame:GetFrameLevel())
	Point(frame.backdrop, "TOPLEFT", 20, -3)
	Point(frame.backdrop, "BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2)

	if not width then width = 155 end
	Width(frame, width)

	if text then
		text:ClearAllPoints()
		Point(text, "RIGHT", button, "LEFT", -2, 0)
	end

	if button then
		WSkin:HandleNextPrevButton(button, direction or "down")
		button:ClearAllPoints()
		Point(button, "RIGHT", frame, "RIGHT", -10, 3)
		Size(button, 16, 16)
	end
end

function WSkin:HandleRotateButton(btn)
	if btn.isSkinned then return end

	SetTemplate(btn)
	Size(btn, btn:GetWidth() - 14, btn:GetHeight() - 14)

	local normTex = btn:GetNormalTexture()
	local pushTex = btn:GetPushedTexture()
	local highlightTex = btn:GetHighlightTexture()

	if normTex then
		SetInside(normTex)
		normTex:SetTexCoord(0.3, 0.29, 0.3, 0.65, 0.69, 0.29, 0.69, 0.65)
	end

	if pushTex then
		pushTex:SetAllPoints(normTex)
		pushTex:SetTexCoord(0.3, 0.29, 0.3, 0.65, 0.69, 0.29, 0.69, 0.65)
	end

	if highlightTex then
		highlightTex:SetAllPoints(normTex)
		highlightTex:SetTexture(1, 1, 1, 0.3)
	end

	btn.isSkinned = true
end

function WSkin:HandleCollapseExpandButton(button, defaultState, useFontString, xOffset, yOffset)
	if button.isSkinned then return end

	button:SetNormalTexture("")
	button:SetPushedTexture("")
	button:SetHighlightTexture("")
	button:SetDisabledTexture("")

	button.SetPushedTexture = function() end
	button.SetHighlightTexture = function() end
	button.SetDisabledTexture = function() end

	if useFontString then
		button.collapseText = button:CreateFontString(nil, "OVERLAY")
		button.collapseText:SetFontObject("GameFontNormal")
		Point(button.collapseText, "LEFT", xOffset or 5, yOffset or 0)
		button.collapseText:SetText(defaultState or "")
		button.SetNormalTexture = function(self, tex)
			if type(tex) == "string" and tex ~= "" then
				if tex:find("MinusButton") or tex:find("ZoomOutButton") then
					self.collapseText:SetText("-")
				else
					self.collapseText:SetText("+")
				end
			end
		end
	else
		local normalTexture = button:GetNormalTexture()
		if normalTexture then
			Size(normalTexture, 16)
			normalTexture:ClearAllPoints()
			Point(normalTexture, "LEFT", xOffset or 3, yOffset or 0)
			normalTexture.SetPoint = function() end
		end

		local pushedTexture = button:GetPushedTexture()
		if pushedTexture then
			Size(pushedTexture, 16)
			pushedTexture:ClearAllPoints()
			Point(pushedTexture, "LEFT", xOffset or 3, yOffset or 0)
			pushedTexture.SetPoint = function() end
		end

		local disabledTexture = button:GetDisabledTexture()
		if disabledTexture then
			Size(disabledTexture, 16)
			disabledTexture:ClearAllPoints()
			Point(disabledTexture, "LEFT", xOffset or 3, yOffset or 0)
			disabledTexture.SetPoint = function() end
			disabledTexture:SetVertexColor(0.6, 0.6, 0.6)
		end
	end
	button.isSkinned = true
end

function WSkin:HandleEditBox(frame)
	if frame.backdrop then return end

	CreateBackdrop(frame)
	frame.backdrop:SetFrameLevel(frame:GetFrameLevel())

	local EditBoxName = frame.GetName and frame:GetName()
	if EditBoxName then
		if _G[EditBoxName.."Left"] then _G[EditBoxName.."Left"]:SetAlpha(0) end
		if _G[EditBoxName.."Middle"] then _G[EditBoxName.."Middle"]:SetAlpha(0) end
		if _G[EditBoxName.."Right"] then _G[EditBoxName.."Right"]:SetAlpha(0) end
		if _G[EditBoxName.."Mid"] then _G[EditBoxName.."Mid"]:SetAlpha(0) end
	end
end
