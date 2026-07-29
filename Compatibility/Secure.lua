-- Secure.lua

EUI = EUI or {}
EUI.API = EUI.API or {}

function EUI.API.FixSecureSnippet(s)
    if type(s) ~= "string" then return s end
    if not (s:find(":RunAttribute") or s:find(":ChildUpdate") or s:find(":SetAttribute") or s:find(":GetAttribute") or s:find("self:CallMethod")) then
        return s
    end
    s = s:gsub('([%w_]+):RunAttribute(%b())', function(frameVar, parens)
        local args = parens:sub(2, -2)
        local firstArg, rest = args:match('^%s*([^,]+)(.*)$')
        if firstArg then
            if frameVar == "control" then
                return string.format('control:Run(control:GetAttribute(%s)%s)', firstArg, rest or '')
            else
                return string.format('control:RunFor(%s, %s:GetAttribute(%s)%s)', frameVar, frameVar, firstArg, rest or '')
            end
        end
        return string.format('%s:RunAttribute(%s)', frameVar, args)
    end)
    s = s:gsub('([%w_]+):ChildUpdate(%b())', function(frameVar, parens)
        local args = parens:sub(2, -2)
        return string.format([[
            local _c = newtable()
            %s:GetChildList(_c)
            for _, _f in ipairs(_c) do
                local _s = _f:GetAttribute("_onchildupdate")
                if _s then control:RunFor(_f, _s, %s) end
            end
        ]], frameVar, args)
    end)
    s = s:gsub('([%w_]+):SetAttribute(%b())', function(frameVar, parens)
        if frameVar == "self" then return string.format('%s:SetAttribute%s', frameVar, parens) end
        local args = parens:sub(2, -2)
        if frameVar == "control" then
            return string.format('control:Run("local k,v=...; self:SetAttribute(k,v)", %s)', args)
        else
            return string.format('control:RunFor(%s, "local k,v=...; self:SetAttribute(k,v)", %s)', frameVar, args)
        end
    end)
    s = s:gsub('([%w_]+):GetAttribute(%b())', function(frameVar, parens)
        if frameVar == "self" then return string.format('%s:GetAttribute%s', frameVar, parens) end
        local args = parens:sub(2, -2)
        if frameVar == "control" then
            return string.format('control:Run("return self:GetAttribute(...)", %s)', args)
        else
            return string.format('control:RunFor(%s, "return self:GetAttribute(...)", %s)', frameVar, args)
        end
    end)
    s = s:gsub('self:CallMethod(%b())', function(parens)
        return string.format('control:CallMethod%s', parens)
    end)
    return s
end
