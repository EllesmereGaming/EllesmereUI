if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end if (select(2, ...)).slcInert then return end


SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil

local Callbacks = {}
addon.Callbacks = Callbacks

local registry = {}

function Callbacks:Register(event, callback)
    registry[event] = registry[event] or {}
    registry[event][#registry[event] + 1] = callback
end


function Callbacks:Unregister(event, callback)
    local list = registry[event]
    if not list then return end

    for i = #list, 1, -1 do
        if list[i] == callback then table.remove(list, i) end
    end
end




function Callbacks:Fire(event, ...)
    local list = registry[event]
    if not list then return end

    for _, callback in ipairs(list) do
        local ok, err = pcall(callback, ...)
        if not ok then
            addon.Log:Bug("Callbacks", ("%s listener failed: %s"):format(event, tostring(err)))
        end
    end
end






local views, order = {}, {}



local FRAME_BUDGET_MS = 1000 / 60
local stats = { flushes = 0, paints = 0, ms = 0, worst = 0, over = 0, errors = 0 }
local observer




local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function() Callbacks:Flush(GetTime()) end)

local function IsShown(view)
    local ok, shown = pcall(view.shown)
    return ok and shown and true or false
end

local function Record(ms, painted, now)
    stats.flushes = stats.flushes + 1
    stats.paints = stats.paints + painted
    stats.ms = stats.ms + ms
    if ms > stats.worst then stats.worst = ms end
    if ms > FRAME_BUDGET_MS then stats.over = stats.over + 1 end
    if observer then pcall(observer, ms, now) end
end



local function Recycle(view, scope)
    wipe(scope.sessions)
    wipe(scope.candidates)
    wipe(scope.kinds)
    scope.allCandidates, scope.allKinds = nil, nil
    view.spare = scope
end

local function Paint(view, now)
    local held = view.scope
    local scope = not view.all and held or nil
    view.dirty, view.all, view.scope = false, false, nil
    view.lastPaint = now
    view.painting = true
    local ok, err = pcall(view.paint, scope)
    view.painting = false
    if held then Recycle(view, held) end
    view.paints = view.paints + 1
    if not ok then
        stats.errors = stats.errors + 1
        addon.Log:Bug("Callbacks", ("%s paint failed: %s"):format(view.name, tostring(err)))
    end
end

function Callbacks:RegisterView(name, spec)
    if views[name] then return views[name] end
    local frame = spec.frame
    local view = {
        name = name,
        paint = spec.paint,
        shown = spec.shown or function() return frame:IsShown() end,
        interval = spec.interval or 0,
        dirty = false, all = false, scope = nil,
        lastPaint = -math.huge, painting = false, paints = 0,
    }
    views[name] = view
    order[#order + 1] = view


    if frame then
        frame:HookScript("OnShow", function() Callbacks:PaintNow(name) end)
    end
    return view
end



function Callbacks:Invalidate(name, session, kind, candidate)
    local view = views[name]
    if not view then return false end
    if not view.all then
        if session == nil then
            local scope = view.scope
            view.all, view.scope = true, nil
            if scope then Recycle(view, scope) end
        else
            local scope = view.scope
            if not scope then
                scope = view.spare
                if scope then
                    view.spare = nil
                else
                    scope = { sessions = {}, candidates = {}, kinds = {} }
                end
                view.scope = scope
            end
            scope.sessions[session] = true
            if candidate == nil then
                scope.allCandidates = true
            else
                scope.candidates[candidate] = true
            end
            if kind == nil then
                scope.allKinds = true
            else
                scope.kinds[kind] = true
            end
        end
    end
    view.dirty = true
    driver:Show()
    return true
end



function Callbacks:PaintNow(name)
    local view = views[name]
    if not view or not view.dirty or view.painting or not IsShown(view) then
        return false
    end
    local now = GetTime()
    local started = debugprofilestop()
    Paint(view, now)
    Record(debugprofilestop() - started, 1, now)
    return true
end



function Callbacks:Flush(now)
    now = now or GetTime()
    local started, painted = debugprofilestop(), 0
    for _, view in ipairs(order) do
        if view.dirty and not view.painting and IsShown(view)
            and now - view.lastPaint >= view.interval then
            Paint(view, now)
            painted = painted + 1
        end
    end
    if painted > 0 then Record(debugprofilestop() - started, painted, now) end



    for _, view in ipairs(order) do
        if view.dirty and IsShown(view) then return end
    end
    driver:Hide()
end



function Callbacks:PaintPending()
    for _, view in ipairs(order) do
        if view.dirty and IsShown(view) then return true end
    end
    return false
end



function Callbacks.PaintStats()
    return {
        flushes = stats.flushes, paints = stats.paints, ms = stats.ms,
        worst = stats.worst, over = stats.over, errors = stats.errors,
    }
end

function Callbacks.ResetPaintStats()
    stats.flushes, stats.paints, stats.ms = 0, 0, 0
    stats.worst, stats.over, stats.errors = 0, 0, 0
end



function Callbacks.SetPaintObserver(fn)
    observer = fn
end
