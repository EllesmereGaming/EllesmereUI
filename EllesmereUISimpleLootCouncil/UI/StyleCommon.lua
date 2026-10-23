if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end if (select(2, ...)).slcInert then return end



SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local S = addon.Style or {}
addon.Style = S
local P = addon.Pixel or {}
addon.Pixel = P







local function Secret(v)
    return issecretvalue ~= nil and issecretvalue(v) and true or false
end
P.IsSecret = Secret


local function EffectiveScale(frame)
    if not frame or not frame.GetEffectiveScale then return nil end

    local ok, scale = pcall(frame.GetEffectiveScale, frame)
    if not ok or Secret(scale) then return nil end
    if type(scale) ~= "number" or scale <= 0 then return nil end
    return scale
end
P.EffectiveScale = EffectiveScale



P.WINDOW_BIAS = 1 / 64


function P.GridPixel(pixels)
    return math.floor(pixels - P.WINDOW_BIAS + 0.5) + P.WINDOW_BIAS
end


function P.AlignFrame(frame)
    local point, relativeTo, relativePoint, x, y = frame:GetPoint()
    if Secret(point) or Secret(relativeTo) or Secret(relativePoint) then return end
    if not point or (relativeTo and relativeTo ~= UIParent) then return end
    if type(x) ~= "number" or type(y) ~= "number" or Secret(x) or Secret(y) then return end

    local physW, physH = GetPhysicalScreenSize()
    if type(physW) ~= "number" or type(physH) ~= "number"
        or Secret(physW) or Secret(physH) or physW <= 0 or physH <= 0 then return end

    local width, height = frame:GetWidth(), frame:GetHeight()
    if type(width) ~= "number" or type(height) ~= "number"
        or Secret(width) or Secret(height) or width <= 0 or height <= 0 then return end

    local step = P.OnePixel(frame)
    local function position(part, extent)
        if part:find("LEFT", 1, true) or part:find("BOTTOM", 1, true) then return 0 end
        if part:find("RIGHT", 1, true) or part:find("TOP", 1, true) then return extent end
        return extent * 0.5
    end
    local relative = relativePoint or point
    local left = position(relative:match("LEFT") or relative:match("RIGHT") or "CENTER", physW)
        + x / step - position(point:match("LEFT") or point:match("RIGHT") or "CENTER", width / step)
    local bottom = position(relative:match("BOTTOM") or relative:match("TOP") or "CENTER", physH)
        + y / step - position(point:match("BOTTOM") or point:match("TOP") or "CENTER", height / step)
    local dx = (P.GridPixel(left) - left) * step
    local dy = (P.GridPixel(bottom) - bottom) * step
    if math.abs(dx) > step * 0.0001 or math.abs(dy) > step * 0.0001 then
        frame:SetPoint(point, relativeTo or UIParent, relative, x + dx, y + dy)
    end
end


function P.Reanchor(frame)
    local point, relativeTo, relativePoint, x, y = frame:GetPoint()
    if Secret(point) or Secret(relativeTo) or Secret(relativePoint)
        or Secret(x) or Secret(y) then return end
    if not point or (relativeTo and relativeTo ~= UIParent) then return end
    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, relativePoint or point, x or 0, y or 0)
    P.AlignFrame(frame)
end



local queue, queued = {}, false

local function Flush()
    queued = false

    local pending = queue
    queue = {}
    for i = 1, #pending do
        local fn = pending[i]


        if fn then pcall(fn) end
    end
end



local settleQueue, settleFrame, settleTicks = {}, nil, 0

local function SettleTick(self)
    settleTicks = settleTicks + 1
    for i = 1, #settleQueue do
        local fn = settleQueue[i]
        if fn then pcall(fn) end
    end
    if settleTicks >= 2 then
        self:SetScript("OnUpdate", nil)
        for i = #settleQueue, 1, -1 do settleQueue[i] = nil end
    end
end

function P.Settle(fn)
    settleQueue[#settleQueue + 1] = fn
    settleTicks = 0
    if not settleFrame then settleFrame = CreateFrame("Frame") end
    settleFrame:SetScript("OnUpdate", SettleTick)
end

function P.AfterLayout(fn)
    queue[#queue + 1] = fn
    if not queued then
        queued = true
        C_Timer.After(0, Flush)
    end
end




local buildQueue, buildFrame = {}, CreateFrame("Frame")
buildFrame:Hide()
buildFrame:SetScript("OnUpdate", function(self)
    self:Hide()
    local pending = buildQueue
    buildQueue = {}
    for i = 1, #pending do
        local ok, err = pcall(pending[i])
        if not ok then addon.Log:Bug("UI", "window build failed: " .. tostring(err)) end
    end
end)

function S.BuildOnDriver(fn)
    buildQueue[#buildQueue + 1] = fn
    buildFrame:Show()
end





local function Unpack(c, alpha)
    return c[1], c[2], c[3], alpha or c[4] or 1
end
S.Unpack = Unpack

function S.ColorStart(color)
    return ("|cff%02x%02x%02x"):format(
        math.floor(color[1] * 255 + 0.5),
        math.floor(color[2] * 255 + 0.5),
        math.floor(color[3] * 255 + 0.5))
end

function S.Colorize(color, text)
    return S.ColorStart(color) .. text .. "|r"
end




function S.Flatten(color, over)
    local a = color[4]
    if not a or a >= 1 then return color end
    over = over or S.color.canvas
    return {
        color[1] * a + over[1] * (1 - a),
        color[2] * a + over[2] * (1 - a),
        color[3] * a + over[3] * (1 - a),
        1,
    }
end




local RAINBOW = {
    { 0.976, 0.020, 0.008 },
    { 0.984, 0.463, 0.000 },
    { 1.000, 0.800, 0.000 },
    { 0.502, 0.714, 0.071 },
    { 0.059, 0.561, 0.373 },
    { 0.408, 0.463, 0.800 },
    { 0.698, 0.333, 0.788 },
}




function S.Rainbow(text)
    if not text or text == "" then return text end
    if text:find("|", 1, true) then return text end

    local visible = 0
    for i = 1, #text do
        local ch = text:sub(i, i)
        if ch ~= " " and ch ~= "\n" then visible = visible + 1 end
    end
    if visible == 0 then return text end

    local span = #RAINBOW - 1
    local out, seen = {}, 0
    for i = 1, #text do
        local ch = text:sub(i, i)
        if ch == " " or ch == "\n" then
            out[#out + 1] = ch
        else
            local t = visible > 1 and (seen / (visible - 1)) or 0
            local pos = t * span
            local index = math.min(math.floor(pos), span - 1)
            local f = pos - index
            local a, b = RAINBOW[index + 1], RAINBOW[index + 2]


            out[#out + 1] = ("|cff%02x%02x%02x%s|r"):format(
                math.floor((a[1] * (1 - f) + b[1] * f) * 255 + 0.5),
                math.floor((a[2] * (1 - f) + b[2] * f) * 255 + 0.5),
                math.floor((a[3] * (1 - f) + b[3] * f) * 255 + 0.5),
                ch)
            seen = seen + 1
        end
    end
    return table.concat(out)
end







function S.Label(parent, fontObject, justify, lines)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(fontObject or S.fontBody)
    fs:SetJustifyH(justify or "LEFT")
    if lines == "wrap" then
        fs:SetWordWrap(true)
    else
        lines = lines or 1
        fs:SetWordWrap(lines > 1)
        fs:SetMaxLines(lines)
    end
    return fs
end


function S.RequiresSentence(message, ...)
    if type(message) ~= "string" or message == "" then return nil end
    return addon.Locale.Format(message, ...)
end









function S.IsItemLink(link)
    return type(link) == "string"
        and (link:find("|H", 1, true) ~= nil or link:find("^%a+:%-?%d") ~= nil)
end




local compareOwner
local compareWatch

local function RebuildOnModifier()
    local owner = compareOwner
    if not owner or GameTooltip:GetOwner() ~= owner or not GameTooltip:IsShown() then
        compareOwner = nil
        compareWatch:UnregisterEvent("MODIFIER_STATE_CHANGED")
        return
    end
    if not owner:IsVisible() or not owner:IsMouseOver() then return end
    local onEnter = owner:GetScript("OnEnter")
    if onEnter then onEnter(owner) end
end


function S.WatchTooltipModifiers(owner)
    compareOwner = owner
    if not compareWatch then
        compareWatch = CreateFrame("Frame")
        compareWatch:SetScript("OnEvent", RebuildOnModifier)
    end
    compareWatch:RegisterEvent("MODIFIER_STATE_CHANGED")
end

function S.SetTooltipItem(link, name)
    if not S.IsItemLink(link) then
        GameTooltip:ClearLines()
        local title = name or link
        if title and title ~= "" then GameTooltip:AddLine(title, 1, 1, 1) end
        return false
    end
    GameTooltip_SuppressAutomaticCompareItem(GameTooltip)
    GameTooltip:SetHyperlink(link)
    S.WatchTooltipModifiers(GameTooltip:GetOwner())
    return true
end



local gamepadSeen
function S.GamepadUI()
    if not addon.IsForever then return false end
    local style, types = C_InputInterfaceStyle, Enum and Enum.InputDeviceInterfaceType
    local current = style and types and style.GetCurrentStyle()
    local on = current ~= nil and current == types.Gamepad
    if on ~= gamepadSeen then
        gamepadSeen = on
        addon.Log:D("UI", "gamepad interface style", tostring(current), on and "on" or "off")
    end
    return on
end


function S.ItemModifiedClick(link)
    if not S.IsItemLink(link) then return false end
    if IsShiftKeyDown() then
        ChatFrameUtil.InsertLink(link)
        return true
    end
    if IsControlKeyDown() and DressUpLink and not S.GamepadUI() then
        DressUpLink(link)
        return true
    end
    return false
end


function S.WindowOf(frame)
    local parent = frame:GetParent()
    while parent and parent ~= UIParent do frame, parent = parent, parent:GetParent() end
    return frame
end



function S.SideTooltip(owner, edge, bottom)
    edge = edge or S.WindowOf(owner)
    local tip = GameTooltip
    local ownerRight, edgeRight = owner:GetRight(), edge:GetRight()
    if type(ownerRight) ~= "number" or type(edgeRight) ~= "number" then
        tip:SetOwner(owner, "ANCHOR_RIGHT")
        return
    end
    tip:SetOwner(owner, "ANCHOR_NONE")
    tip:ClearAllPoints()

    local dx = (edgeRight * edge:GetEffectiveScale() - ownerRight * owner:GetEffectiveScale())
        / tip:GetEffectiveScale()
    tip:SetPoint("BOTTOMLEFT", owner, bottom and "BOTTOMRIGHT" or "TOPRIGHT",
        dx + 2 * addon.Pixel.Hairline(tip), 0)
end


function S.AboveTooltip(owner)
    local tip = GameTooltip
    tip:SetOwner(owner, "ANCHOR_NONE")
    tip:ClearAllPoints()
    tip:SetPoint("BOTTOM", owner, "TOP", 0, 2 * addon.Pixel.Hairline(tip))
end








local tooltipRules = setmetatable({}, { __mode = "k" })

local function HideTooltipRules(tooltip)
    local pool = tooltipRules[tooltip]
    if not pool then return end
    for i = 1, pool.used do pool[i]:Hide() end
    pool.used = 0
end

function S.TooltipRule(tooltip)
    tooltip:AddLine(" ", 0, 0, 0, true)

    if S.GamepadUI() then return end
    local line = tooltip:GetLeftLine(tooltip:NumLines())
    if not line then return end

    local pool = tooltipRules[tooltip]
    if not pool then
        pool = { used = 0 }
        tooltipRules[tooltip] = pool

        tooltip:HookScript("OnTooltipCleared", HideTooltipRules)
        tooltip:HookScript("OnHide", HideTooltipRules)
    end

    local Pixel = addon.Pixel
    pool.used = pool.used + 1
    local rule = pool[pool.used]
    if not rule then
        rule = Pixel.Crisp(tooltip:CreateTexture(nil, "ARTWORK"))
        pool[pool.used] = rule
    end
    rule:SetColorTexture(Unpack(S.color.accent))
    rule:ClearAllPoints()
    rule:SetPoint("LEFT", line, "LEFT", 0, 0)
    rule:SetPoint("RIGHT", line, "RIGHT", 0, 0)
    rule:SetHeight(Pixel.Hairline(tooltip))
    rule:Show()
end


function S.TooltipSection(tooltip, title)
    if tooltip:NumLines() > 0 then S.TooltipRule(tooltip) end
    title = addon.Locale.SectionTitle(title)
    local c = S.color.accent

    tooltip:AddLine(title, c[1], c[2], c[3])
end






function S.ScrollWheel(bar, step)
    return function(_, delta)
        local _, maximum = bar:GetMinMaxValues()
        if maximum <= 0 then return end
        bar:SetValue(math.max(0, math.min(maximum,
            bar:GetValue() - delta * step * 2)))
    end
end






S.logoWindows = {}


S.titleWindows = {}


function S.PrideActive()
    local db = addon.db
    return db and db.pride and S.logoPride.loaded and true or false
end


function S.RefreshLogos()
    for _, f in ipairs(S.logoWindows) do
        if f.ApplyLogo then f:ApplyLogo() end
    end
    for _, f in ipairs(S.titleWindows) do f.RefreshTitle() end
end






local PRIDE_TITLED = {
    voter = true, ml = true, queue = true, tradeQueue = true, history = true,
    raidteam = true, raidteamranks = true, attendance = true,
    versions = true, sendConfig = true, configOffer = true, raidPrompt = true,
    colorPicker = true,
}



function S.InstallWindowTitle(f, key, titleText, mark, badge, tag, squareTag, text)
    local size = S.size
    function f:SetTag(text, color)
        if not text or text == "" then
            tag:Hide()
        else
            if squareTag then
                tag:SetLabel(text)
            else
                tag:SetChipColor(color or S.color.textMuted)
                tag:SetText(text)
            end
            tag:Show()
        end

        if f.ClampTitle then P.AfterLayout(f.ClampTitle) end
    end


    local rawSetText, rawTitle = titleText.SetText, ""
    local function ShowTitle()
        local text = rawTitle
        if text ~= "" and S.PrideActive() and PRIDE_TITLED[key] then
            text = key == "sendConfig" and T["Send Gay config"]
                or (key == "raidPrompt" or text == T["Simple Loot Council"]) and T["Gay Loot Council"]
                or addon.Locale.Format(T["Gay %s"], (text:gsub("^%l", string.upper)))
        end
        rawSetText(titleText, text)
    end
    function titleText:SetText(text) rawTitle = text or ""; ShowTitle() end
    f.RefreshTitle = function() ShowTitle(); if f.ClampTitle then P.AfterLayout(f.ClampTitle) end end
    S.titleWindows[#S.titleWindows + 1] = f

    titleText:SetText(text)



    local function ClampTitle()
        local markRight, badgeLeft = mark:GetRight(), badge:GetLeft()
        if not markRight or not badgeLeft then return end

        local reserved = tag:IsShown() and (tag:GetWidth() + size.TAG_GAP) or 0
        local available = badgeLeft - markRight - size.TITLE_GAP - reserved - size.GAP
        if available <= 0 then return end

        titleText:SetWidth(0)
        if titleText:GetStringWidth() > available then
            titleText:SetWidth(available)
        end
    end
    P.AfterLayout(ClampTitle)
    P.OnRescale(ClampTitle)
    f.ClampTitle = ClampTitle
end



local drag = {}
local dragFrame = CreateFrame("Frame")
dragFrame:Hide()

local function DragTo(frame)
    local es = EffectiveScale(frame)
    if not es then return end
    local cx, cy = GetCursorPosition()
    local x = drag.left + (cx - drag.cx) / es
    local y = drag.bottom + (cy - drag.cy) / es

    local ratio = (EffectiveScale(UIParent) or es) / es
    local step = P.OnePixel(frame)

    local function Place(v, max)
        v = P.GridPixel(math.max(0, math.min(max, v)) / step)
        if v * step > max then v = v - 1 end
        if v < 0 then v = v + 1 end
        return v * step
    end
    x = Place(x, UIParent:GetWidth() * ratio - frame:GetWidth())
    y = Place(y, UIParent:GetHeight() * ratio - frame:GetHeight())
    if x == drag.x and y == drag.y then return end

    drag.x, drag.y = x, y
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
end

dragFrame:SetScript("OnUpdate", function()
    local frame = drag.frame
    if not frame or not frame:IsShown() then
        drag.frame = nil
        dragFrame:Hide()
        return
    end
    DragTo(frame)
end)

function P.StartDrag(frame)
    local left, bottom = frame:GetLeft(), frame:GetBottom()
    local cx, cy = GetCursorPosition()
    if type(left) ~= "number" or type(bottom) ~= "number" or Secret(left) or Secret(bottom)
        or Secret(cx) or Secret(cy) or not EffectiveScale(frame) then

        drag.native = frame
        frame:StartMoving()
        return
    end
    drag.frame, drag.left, drag.bottom, drag.cx, drag.cy = frame, left, bottom, cx, cy
    drag.x, drag.y = nil, nil
    dragFrame:Show()
end

function P.StopDrag(frame)
    if drag.native == frame then
        drag.native = nil
        frame:StopMovingOrSizing()
    elseif drag.frame == frame then
        DragTo(frame)
        drag.frame = nil
        dragFrame:Hide()
    end
    P.AlignFrame(frame)
end



function S.InstallWindowGeometry(f, key, header, close)


    local grip = CreateFrame("Frame", nil, header)
    grip:SetPoint("TOPLEFT")
    grip:SetPoint("BOTTOMRIGHT", close, "BOTTOMLEFT")
    grip:EnableMouse(true)
    grip:RegisterForDrag("LeftButton")
    grip:SetScript("OnDragStart", function() P.StartDrag(f) end)
    grip:SetScript("OnDragStop", function()
        P.StopDrag(f)
        f:SavePosition()
    end)


    function f:SavePosition()
        local point, _, relPoint, x, y = f:GetPoint()
        addon.db.windows[key] = { point = point, relPoint = relPoint, x = x, y = y }
    end




    function f:SetHeightFromTop(height)
        height = P.Snap(height)
        local was = f:GetHeight()
        local point, relTo, relPoint, x, y = f:GetPoint()

        if point and was and was > 0 and height ~= was and f:IsShown() then
            local above = point:find("TOP") and 0
                or (point:find("BOTTOM") and 1 or 0.5)
            if above > 0 then
                f:SetPoint(point, relTo, relPoint, x,
                    y - (height - was) * above)
            end
        end
        f:SetHeight(height)
        P.AlignFrame(f)
    end



    function f:SetSizeFromBottomRight(width, height)
        width, height = P.Snap(width), P.Snap(height)
        local wasW, wasH = f:GetWidth(), f:GetHeight()
        local point, relTo, relPoint, x, y = f:GetPoint()
        if point and wasW and wasH and wasW > 0 and wasH > 0 and f:IsShown()
            and (width ~= wasW or height ~= wasH) then
            local left = point:find("RIGHT") and 0 or (point:find("LEFT") and 1 or 0.5)
            local up = point:find("BOTTOM") and 0 or (point:find("TOP") and 1 or 0.5)
            f:SetPoint(point, relTo, relPoint, x - (width - wasW) * left,
                y + (height - wasH) * up)
            f:SetSize(width, height)
            P.AlignFrame(f)
            f:SavePosition()
            return
        end
        f:SetSize(width, height)
        P.AlignFrame(f)
    end


    function f:SetSizeFromTopLeft(width, height)
        width, height = P.Snap(width), P.Snap(height)
        local wasW, wasH = f:GetWidth(), f:GetHeight()
        local point, relTo, relPoint, x, y = f:GetPoint()
        if point and wasW and wasH and wasW > 0 and wasH > 0 and f:IsShown()
            and (width ~= wasW or height ~= wasH) then
            local right = point:find("RIGHT") and 1 or (point:find("LEFT") and 0 or 0.5)
            local down = point:find("BOTTOM") and 1 or (point:find("TOP") and 0 or 0.5)
            f:SetPoint(point, relTo, relPoint, x + (width - wasW) * right,
                y - (height - wasH) * down)
            f:SetSize(width, height)
            P.AlignFrame(f)
            f:SavePosition()
            return
        end
        f:SetSize(width, height)
        P.AlignFrame(f)
    end



    function f:PlaceAtCursor()
        local scale = UIParent:GetEffectiveScale()
        local x, y = GetCursorPosition()
        local w, h = f:GetWidth(), f:GetHeight()
        x = math.max(w / 2, math.min(UIParent:GetWidth() - w / 2, x / scale))
        y = math.max(h / 2, math.min(UIParent:GetHeight() - h / 2, y / scale))
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
        P.AlignFrame(f)
    end

    function f:RestorePosition()
        local pos = addon.db.windows[key]
        f:ClearAllPoints()
        if pos and pos.point then
            f:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
        else
            f:SetPoint("CENTER")
        end
        P.AlignFrame(f)
    end



    f:HookScript("OnSizeChanged", function() P.AfterLayout(function() P.Reanchor(f) end) end)
    P.OnRescale(function() P.AlignFrame(f) end)

    S.FollowWindowAlpha(f)
end






S.windows = S.windows or {}
S.WINDOW_ALPHA_MIN = 0.3

function S.WindowAlpha()
    local alpha = tonumber(addon.db and addon.db.windowAlpha) or 1
    return math.max(S.WINDOW_ALPHA_MIN, math.min(1, alpha))
end


function S.FollowWindowAlpha(f)
    S.windows[#S.windows + 1] = f
    f:SetAlpha(S.WindowAlpha())
end

function S.SetWindowAlpha(alpha)
    addon.db.windowAlpha = math.max(S.WINDOW_ALPHA_MIN, math.min(1, tonumber(alpha) or 1))
    for _, f in ipairs(S.windows) do f:SetAlpha(addon.db.windowAlpha) end
end
