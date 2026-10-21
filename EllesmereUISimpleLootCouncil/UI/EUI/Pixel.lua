if EUI_CLIENT_BLOCKED then return end 


SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil

local P = addon.Pixel
local PP = EllesmereUI.PP

local EffectiveScale = P.EffectiveScale


function P.OnePixel(frame)
    local scale = EffectiveScale(frame)
    if not scale then return PP.mult end
    return PP.perfect / scale
end

function P.Hairline(frame)
    local px = frame and P.OnePixel(frame) or PP.mult
    return px > 0 and px or 1
end



function P.Snap(x, frame)
    if type(x) ~= "number" or x == 0 then return x end
    local scale = frame and EffectiveScale(frame)
    if scale then return PP.SnapForES(x, scale) end
    return PP.Snap(x)
end

local Snap = P.Snap

function P.Size(frame, w, h)
    if w and h then
        frame:SetSize(Snap(w), Snap(h))
    elseif w then
        frame:SetWidth(Snap(w))
    elseif h then
        frame:SetHeight(Snap(h))
    end
    return frame
end

local function SnapArg(v)
    if type(v) == "number" then return Snap(v) end
    return v
end



function P.Point(obj, ...)
    local n = select("#", ...)
    if n == 0 then return obj end
    local a, b, c, d, e = ...
    if n == 1 then
        obj:SetPoint(a)
    elseif n == 2 then
        obj:SetPoint(a, SnapArg(b))
    elseif n == 3 then
        obj:SetPoint(a, SnapArg(b), SnapArg(c))
    elseif n == 4 then
        obj:SetPoint(a, SnapArg(b), SnapArg(c), SnapArg(d))
    else
        obj:SetPoint(a, SnapArg(b), SnapArg(c), SnapArg(d), SnapArg(e))
    end
    return obj
end

function P.Crisp(tex)
    PP.DisablePixelSnap(tex)
    return tex
end



local resnap = {}

function P.OnRescale(fn)
    resnap[#resnap + 1] = fn
    return fn
end

local function Rescale()
    for i = 1, #resnap do
        local fn = resnap[i]
        if fn then pcall(fn) end
    end
end

function P:Init()
    EllesmereUI.RegisterPxReapply(P, Rescale)
end
