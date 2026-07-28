-- Global CreateFrame hook to map modern templates to legacy 3.3.5a equivalents
-- Safely mapped CreateFrame hook to map modern templates to legacy 3.3.5a equivalents
local OriginalCreateFrame = CreateFrame
function CreateFrame(frameType, name, parent, template, id)
    if template then
        if template == "MainMenuFrameButtonTemplate" then
            template = "GameMenuButtonTemplate"
        elseif type(template) == "string" and template:find("MainMenuFrameButtonTemplate") then
            template = template:gsub("MainMenuFrameButtonTemplate", "GameMenuButtonTemplate")
        end
    end
    return OriginalCreateFrame(frameType, name, parent, template, id)
end

if not GetPhysicalScreenSize then
    function GetPhysicalScreenSize()
        local resIndex = GetCurrentResolution()
        local resString = resIndex and select(resIndex, GetScreenResolutions())
        if resString then
            local w, h = string.match(resString, "(%d+)x(%d+)")
            if w and h then
                return tonumber(w), tonumber(h)
            end
        end
        local w = UIParent:GetWidth() or 1920
        local h = UIParent:GetHeight() or 1080
        return w, h
    end
end


-- 5. Frame Metatable Extensions safely supporting modern methods
local EUI_AtlasMap = {
    ["uitools-icon-close"] = "Interface\\Buttons\\UI-Panel-MinimizeButton-Up",
    ["Azerite-PointingArrow"] = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up",
    ["shop-card-wide-frame-default"] = "Interface\\DialogFrame\\UI-DialogBox-Background",
    ["shop-card-wide-frame-hover"] = "Interface\\DialogFrame\\UI-DialogBox-Background",
    ["lootroll-animreveal-a"] = "Interface\\TargetingFrame\\UI-StatusBar",
    ["UI-Journeys-Delve-Companion-Ring"] = "Interface\\Minimap\\MiniMap-TrackingBorder",
    ["Ui-Dialog-New-Background"] = "Interface\\DialogFrame\\UI-DialogBox-Background",
    ["UI-QuestTrackerButton-Secondary-Collapse"] = "Interface\\Buttons\\UI-MinusButton-Up",
    ["UI-QuestTrackerButton-Secondary-Expand"] = "Interface\\Buttons\\UI-PlusButton-Up",
    ["QuestLog-main-background"] = "Interface\\QuestFrame\\UI-QuestLog-Background",
    ["UI-RefreshButton"] = "Interface\\Buttons\\UI-RotationLeft-Button-Up",
    ["characterupdate_background"] = "Interface\\DialogFrame\\UI-DialogBox-Background",
    ["VAS-icon-checkmark-glw"] = "Interface\\RAIDFRAME\\ReadyCheck-Ready",
    ["charactercreate-icon-dice"] = "Interface\\Buttons\\UI-GroupLoot-Dice-Up",
    ["bag-main"] = "Interface\\Buttons\\Button-Backpack-Up",
    ["Crosshair_Quest_64"] = "Interface\\Icons\\INV_Misc_QuestionMark",
    ["UI-HUD-RotationHelper-Inactive-2x"] = "Interface\\Buttons\\UI-Quickslot-Depress",
    ["UI-HUD-ActionBar-IconFrame-Slot"] = "Interface\\Buttons\\UI-EmptySlot",
    ["UI-HUD-ActionBar-IconFrame-Down"] = "Interface\\Buttons\\UI-Quickslot-Depress",
}

local cooldownFrame = CreateFrame("Cooldown", nil, WorldFrame)
local cooldownMeta = getmetatable(cooldownFrame).__index

local function SafeGetMeta(widgetType)
    local ok, obj = pcall(CreateFrame, widgetType)
    if not ok or not obj then return nil end
    local meta = getmetatable(obj)
    return meta and meta.__index
end

local frameMetas = {
    getmetatable(CreateFrame("Frame")).__index,
    getmetatable(CreateFrame("Frame"):CreateTexture()).__index,
    getmetatable(CreateFrame("Frame"):CreateFontString()).__index,
    cooldownMeta,
    SafeGetMeta("Button"),
    SafeGetMeta("CheckButton"),
    SafeGetMeta("ScrollFrame"),
    SafeGetMeta("EditBox"),
    SafeGetMeta("Slider"),
    SafeGetMeta("StatusBar"),
    SafeGetMeta("MessageFrame"),
    SafeGetMeta("SimpleHTML"),
    SafeGetMeta("ScrollingMessageFrame"),
    SafeGetMeta("ColorSelect"),
    SafeGetMeta("Model"),
    SafeGetMeta("PlayerModel"),
    SafeGetMeta("DressUpModel"),
}

if Minimap then
    local mmMeta = getmetatable(Minimap)
    if mmMeta and mmMeta.__index then
        table.insert(frameMetas, mmMeta.__index)
    end
end
if GameTooltip then
    local gtMeta = getmetatable(GameTooltip)
    if gtMeta and gtMeta.__index then
        table.insert(frameMetas, gtMeta.__index)
    end
end

for _, meta in ipairs(frameMetas) do
    if meta then
        if not meta.SetShown then
            meta.SetShown = function(self, show)
                if show then self:Show() else self:Hide() end
            end
        end
        if not meta.SetSnapToPixelGrid then
            meta.SetSnapToPixelGrid = function(self, snap) end
        end
        if not meta.SetPixelSnapDisabled then
            meta.SetPixelSnapDisabled = function(self, disable) end
        end
        if not meta.IsForbidden then
            meta.IsForbidden = function(self) return false end
        end
        if not meta.SetTexelSnappingBias then
            meta.SetTexelSnappingBias = function(self, bias) end
        end
        if not meta.PixelSnap then
            meta.PixelSnap = function(self, val) return val end
        end
        if not meta.SetAtlas then
            meta.SetAtlas = function(self, atlas, useAtlasSize)
                if not atlas or atlas == "" then
                    self:SetTexture(nil)
                    return
                end
                local path = EUI_AtlasMap[atlas]
                if not path then
                    path = "Interface\\Icons\\INV_Misc_QuestionMark"
                    -- Cache unknown atlas lookups dynamically instead of repeatedly falling back
                    EUI_AtlasMap[atlas] = path
                end
                self:SetTexture(path)
            end
        end
        if not meta.SetColorTexture then
            meta.SetColorTexture = function(self, r, g, b, a)
                if self.SetTexture then
                    self:SetTexture(r, g, b, a or 1)
                end
            end
        end
        if not meta.SetClipsChildren then
            meta.SetClipsChildren = function(self, clip) end
        end
        if not meta.SetMaxLines then
            meta.SetMaxLines = function(self, limit) end
        end
        if not meta.SetAlphaFromBoolean then
            meta.SetAlphaFromBoolean = function(self, value, trueAlpha, falseAlpha)
                if trueAlpha == nil then trueAlpha = 1 end
                if falseAlpha == nil then falseAlpha = 0 end
                if value then
                    self:SetAlpha(trueAlpha)
                else
                    self:SetAlpha(falseAlpha)
                end
            end
        end

        -- Additional missing frame methods required by Retail UI scripts
        if not meta.SetIgnoreParentAlpha then
            meta.SetIgnoreParentAlpha = function(self, ignore) end
        end
        if not meta.SetMouseClickEnabled then
            meta.SetMouseClickEnabled = function(self, enabled)
                if self.EnableMouse then self:EnableMouse(enabled) end
            end
        end
        if not meta.SetMouseMotionEnabled then
            meta.SetMouseMotionEnabled = function(self, enabled)
                if self.EnableMouse then self:EnableMouse(enabled) end
            end
        end
        if not meta.SetScaleToFit then meta.SetScaleToFit = function(self) end end
        if not meta.GetScaledRect then meta.GetScaledRect = function(self) return self:GetRect() end end
        if not meta.SetIgnoreParentScale then meta.SetIgnoreParentScale = function(self, ignore) end end
        if not meta.GetLayoutChildren then meta.GetLayoutChildren = function(self) return {self:GetChildren()} end end
        if not meta.MarkDirty then meta.MarkDirty = function(self) end end
        if not meta.SetPadding then meta.SetPadding = function(self, padding) end end
        if not meta.SetSpacing then meta.SetSpacing = function(self, spacing) end end
        if not meta.GetLayoutIndex then meta.GetLayoutIndex = function(self) return self.layoutIndex or 1 end end
        if not meta.SetFrameStrataFromParent then meta.SetFrameStrataFromParent = function(self) end end
        if not meta.SetFixedFrameStrata then meta.SetFixedFrameStrata = function(self, fixed) end end
    end
end

if cooldownMeta then
    if not cooldownMeta.SetCooldownFromDurationObject then
        cooldownMeta.SetCooldownFromDurationObject = function(self, durObj)
            if not durObj then
                self:SetCooldown(0, 0)
                return
            end
            local start = durObj.startTime
            local duration = durObj.duration
            if (not start or start == 0) and durObj.expirationTime and durObj.expirationTime > 0 then
                start = durObj.expirationTime - duration
            end
            self:SetCooldown(start or 0, duration or 0)
        end
    end
end

local okAnim, animFrame = pcall(CreateFrame, "Frame")
if okAnim and animFrame and animFrame.CreateAnimationGroup then
    local okGrp, animGroup = pcall(animFrame.CreateAnimationGroup, animFrame)
    if okGrp and animGroup and animGroup.CreateAnimation then
        local okAlpha, alphaAnim = pcall(animGroup.CreateAnimation, animGroup, "Alpha")
        if okAlpha and alphaAnim then
            local animMeta = getmetatable(alphaAnim)
            if animMeta and animMeta.__index then
                local meta = animMeta.__index
                if not meta.SetFromAlpha then
                    meta.SetFromAlpha = function(self, alpha)
                        self._fromAlpha = alpha
                    end
                end
                if not meta.SetToAlpha then
                    meta.SetToAlpha = function(self, alpha)
                        self._toAlpha = alpha
                        if self.SetChange then
                            local from = self._fromAlpha or 0
                            self:SetChange(alpha - from)
                        end
                    end
                end
            end
        end
    end
end
