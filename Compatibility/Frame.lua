EUI = EUI or {}
EUI.API = EUI.API or {}

function EUI.API.ApplyFrameCompat(frame)
    if not frame then return frame end

    if not frame.SetShown then
        frame.SetShown = function(self, show)
            if show then self:Show() else self:Hide() end
        end
    end

    if not frame.SetColorTexture then
        frame.SetColorTexture = function(self, r, g, b, a)
            if self.SetTexture then
                self:SetTexture(r, g, b, a or 1)
            else
                self:SetTexture("Interface\\Buttons\\WHITE8X8")
                self:SetVertexColor(r, g, b, a or 1)
            end
        end
    end

    if not frame.SetAtlas then
        frame.SetAtlas = function(self, atlas, useAtlasSize)
            if not atlas or atlas == "" then
                self:SetTexture(nil)
                return
            end
            local path = EUI_AtlasMap and EUI_AtlasMap[atlas]
            if not path then
                path = "Interface\\Icons\\INV_Misc_QuestionMark"
                if EUI_AtlasMap then EUI_AtlasMap[atlas] = path end
            end
            self:SetTexture(path)
        end
    end

    if not frame.SetSnapToPixelGrid then frame.SetSnapToPixelGrid = function(self, snap) end end
    if not frame.SetPixelSnapDisabled then frame.SetPixelSnapDisabled = function(self, disable) end end
    if not frame.IsForbidden then frame.IsForbidden = function(self) return false end end
    if not frame.SetTexelSnappingBias then frame.SetTexelSnappingBias = function(self, bias) end end
    if not frame.PixelSnap then frame.PixelSnap = function(self, val) return val end end
    if not frame.SetClipsChildren then frame.SetClipsChildren = function(self, clip) end end
    if not frame.SetMaxLines then frame.SetMaxLines = function(self, limit) end end

    if not frame.SetAlphaFromBoolean then
        frame.SetAlphaFromBoolean = function(self, value, trueAlpha, falseAlpha)
            if trueAlpha == nil then trueAlpha = 1 end
            if falseAlpha == nil then falseAlpha = 0 end
            if value then
                self:SetAlpha(trueAlpha)
            else
                self:SetAlpha(falseAlpha)
            end
        end
    end

    if not frame.SetIgnoreParentAlpha then frame.SetIgnoreParentAlpha = function(self, ignore) end end
    if not frame.SetMouseClickEnabled then
        frame.SetMouseClickEnabled = function(self, enabled)
            if self.EnableMouse then self:EnableMouse(enabled) end
        end
    end
    if not frame.SetMouseMotionEnabled then
        frame.SetMouseMotionEnabled = function(self, enabled)
            if self.EnableMouse then self:EnableMouse(enabled) end
        end
    end
    if not frame.SetScaleToFit then frame.SetScaleToFit = function(self) end end
    if not frame.GetScaledRect then frame.GetScaledRect = function(self) return self:GetRect() end end
    if not frame.SetIgnoreParentScale then frame.SetIgnoreParentScale = function(self, ignore) end end
    if not frame.GetLayoutChildren then frame.GetLayoutChildren = function(self) return {self:GetChildren()} end end
    if not frame.MarkDirty then frame.MarkDirty = function(self) end end
    if not frame.SetPadding then frame.SetPadding = function(self, padding) end end
    if not frame.SetSpacing then frame.SetSpacing = function(self, spacing) end end
    if not frame.GetLayoutIndex then frame.GetLayoutIndex = function(self) return self.layoutIndex or 1 end end
    if not frame.SetFrameStrataFromParent then frame.SetFrameStrataFromParent = function(self) end end
    if not frame.SetFixedFrameStrata then frame.SetFixedFrameStrata = function(self, fixed) end end

    if frame:GetObjectType() == "Cooldown" and not frame.SetCooldownFromDurationObject then
        frame.SetCooldownFromDurationObject = function(self, durObj)
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

    if frame.CreateAnimationGroup and not frame._animHooked then
        frame._animHooked = true
        local origCreateAnimationGroup = frame.CreateAnimationGroup
        frame.CreateAnimationGroup = function(self, ...)
            local group = origCreateAnimationGroup(self, ...)
            if group then
                local origCreateAnimation = group.CreateAnimation
                group.CreateAnimation = function(g, animType, ...)
                    local anim = origCreateAnimation(g, animType, ...)
                    if anim and animType == "Alpha" then
                        if not anim.SetFromAlpha then
                            anim.SetFromAlpha = function(a, alpha) a._fromAlpha = alpha end
                        end
                        if not anim.SetToAlpha then
                            anim.SetToAlpha = function(a, alpha)
                                a._toAlpha = alpha
                                if a.SetChange then
                                    local from = a._fromAlpha or 0
                                    a:SetChange(alpha - from)
                                end
                            end
                        end
                    end
                    return anim
                end
            end
            return group
        end
    end

    return frame
end

function EllesmereUI.StripRetailTemplates(template)
    if not template then return template end
    if type(template) == "string" then
        template = template:gsub("BackdropTemplate", "")
        template = template:gsub(",%s*,", ",")
        template = template:gsub("^%s*,", "")
        template = template:gsub(",%s*$", "")
        if template == "" then template = nil end

        if template then
            if template == "MainMenuFrameButtonTemplate" then
                template = "GameMenuButtonTemplate"
            elseif template:find("MainMenuFrameButtonTemplate") then
                template = template:gsub("MainMenuFrameButtonTemplate", "GameMenuButtonTemplate")
            end
        end
    end
    return template
end

function EllesmereUI.SafeCreateFrame(frameType, name, parent, template)
    local sanitizedTemplate = EllesmereUI.StripRetailTemplates(template)
    local f = CreateFrame(frameType, name, parent, sanitizedTemplate)

    if f then
        EUI.API.ApplyFrameCompat(f)

        if type(frameType) == "string" and frameType:lower() == "editbox" then
            if f.SetAutoFocus then f:SetAutoFocus(false) end
            if f.ClearFocus then f:ClearFocus() end
        end
    end
    return f
end

if not GetPhysicalScreenSize then
    _G.GetPhysicalScreenSize = function()
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
