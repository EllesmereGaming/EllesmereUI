-- ColorMixin & CreateColor
if not ColorMixin then
    ColorMixin = {}
    ColorMixin.__index = ColorMixin

    function ColorMixin:SetRGBA(r, g, b, a)
        self.r = r
        self.g = g
        self.b = b
        self.a = a or 1
    end

    function ColorMixin:GetRGB()
        return self.r, self.g, self.b
    end

    function ColorMixin:GetRGBA()
        return self.r, self.g, self.b, self.a
    end

    function ColorMixin:GenerateHexColor()
        local r = math.floor(self.r * 255 + 0.5)
        local g = math.floor(self.g * 255 + 0.5)
        local b = math.floor(self.b * 255 + 0.5)
        local a = math.floor((self.a or 1) * 255 + 0.5)
        return string.format("%.2x%.2x%.2x%.2x", a, r, g, b)
    end

    function ColorMixin:GenerateHexColorMarkup()
        return "|c" .. self:GenerateHexColor()
    end

    function ColorMixin:WrapTextInColorCode(text)
        return self:GenerateHexColorMarkup() .. text .. "|r"
    end

    function ColorMixin:IsEqualTo(other)
        if not other then return false end
        return self.r == other.r and self.g == other.g and self.b == other.b and self.a == other.a
    end

    function ColorMixin:Clone()
        return CreateColor(self.r, self.g, self.b, self.a)
    end
end

if not CreateColor then
    function CreateColor(r, g, b, a)
        local color = setmetatable({}, ColorMixin)
        color:SetRGBA(r or 1, g or 1, b or 1, a or 1)
        return color
    end
end
