CONFIG = { chatEmbedEnabled=false, chatEmbedAutoDungeon=false, chatEmbedAutoRaid=false,
    chatEmbedReturnOnExit=false }
DM.EDM = { DB=function() return CONFIG end }
EllesmereUI.L = function(s) return s end
EllesmereUI.ShowWidgetTooltip = function() end
EllesmereUI.HideWidgetTooltip = function() end
EllesmereUI.ShowModule = function(_, name) OPENED_MODULE = name end
EllesmereUI.EvalVisibility = function() return not HIDE_METERS end
EllesmereUI.RequestVisibilityUpdate = function() VISIBILITY_GENERATION=(VISIBILITY_GENERATION or 0)+1 end
EllesmereUI.MakeUnlockElement = function(t) return t end
EllesmereUI._unlockRegisteredElements = {}
EllesmereUI.RegisterUnlockElements = function(_, elements)
    for _, e in ipairs(elements) do EllesmereUI._unlockRegisteredElements[e.key] = e end
end
EllesmereUI.UnregisterUnlockElement = function(_, key)
    assert(key ~= "EDM_Win1" and key ~= "EDM_Win2", "Must not delete embedded saved links")
    EllesmereUI._unlockRegisteredElements[key] = nil
end
CHAT.ECHAT.ResolveSidebarIconOrder = function() return {"showPortals","showSettings"} end
CHAT.ECHAT.ApplyIconFreeMove = function() end
CHAT.ECHAT.ResetIdleTimer = function() IDLE_RESETS = (IDLE_RESETS or 0) + 1 end
CHAT.ECHAT.SetMetersView = function() error("Production engine must replace this stub") end
-- A host must never schedule a polling loop, delayed gate, or install method hooks.
C_Timer = setmetatable({}, {__index=function() error("Unexpected timer in chat host") end})
hooksecurefunc = function() error("Unexpected hook in chat host") end

local F = getmetatable(PANEL).__index
function F:UnregisterEvent(name) self.events[name] = nil end
function F:UnregisterAllEvents() self.events = {} end
function F:GetNumMessages() return 0 end
function F:GetSize() return self:GetWidth(), self:GetHeight() end
function F:GetWidth()
    if self.allPoints then return self.allPoints:GetWidth() end
    local a, b = self.points[1], self.points[2]
    if a and b and a[1]=="TOPLEFT" and b[1]=="BOTTOMRIGHT" then
        return a[2]:GetWidth() + (b[4] or 0) - (a[4] or 0)
    end
    return self.w
end
function F:GetHeight()
    if self.allPoints then return self.allPoints:GetHeight() end
    local a, b = self.points[1], self.points[2]
    if a and b and a[1]=="TOPLEFT" and b[1]=="BOTTOMRIGHT" then
        return a[2]:GetHeight() + (a[5] or 0) - (b[5] or 0)
    end
    return self.h
end
local function Resolve(f)
    local width, height = f:GetWidth(), f:GetHeight()
    if width ~= f.resolvedWidth or height ~= f.resolvedHeight then
        f.resolvedWidth, f.resolvedHeight = width, height
        if f.scripts.OnSizeChanged then f.scripts.OnSizeChanged(f, width, height) end
        for _, child in ipairs(FRAMES) do
            if child.parent == f then Resolve(child) end
        end
    end
end
local setSize, setPoint = F.SetSize, F.SetPoint
function F:SetSize(w,h) setSize(self,w,h); Resolve(self) end
function F:SetPoint(...) setPoint(self,...); Resolve(self) end
function F:SetAllPoints(f) self.allPoints=f; Resolve(self) end
function F:ClearAllPoints() assert(not self.native); self.points={}; self.allPoints=nil end
