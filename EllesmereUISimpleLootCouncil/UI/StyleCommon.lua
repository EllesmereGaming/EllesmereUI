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









function S.PinClockWidth(fs)
    if fs.clockPinned then return end
    fs:SetText("88:88")
    local width = fs:GetUnboundedStringWidth()
    fs:SetText("")
    if type(width) == "number" and width > 0 then
        fs:SetWidth(math.ceil(width))
        fs:SetJustifyH("LEFT")
        fs.clockPinned = true
    end
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


function S.PrideText(text)
    local prefix = T["Gay %s"]
    if prefix:find("^Gay") then text = text:gsub("^%u", string.lower) end
    return addon.Locale.Format(prefix, text)
end


function S.RefreshLogos()
    for _, f in ipairs(S.logoWindows) do
        if f.ApplyLogo then f:ApplyLogo() end
    end
    for _, f in ipairs(S.titleWindows) do f.RefreshTitle() end
end






local PRIDE_TITLED = {
    voter = true, queue = true, tradeQueue = true, history = true,
    raidteam = true, raidteamranks = true, attendance = true,
    versions = true, sendConfig = true, configOffer = true,
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
                tag:SetChipColor(color or S.color.accent)
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
            text = key == "sendConfig" and T["Send gay config"]
                or S.PrideText(text)
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

        if max <= 0 then return 0 end
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



function S.InstallPlacement(f, key, default)
    f.slcPlacementKey = key

    function f:SavePosition()
        local rec, windows = S.PlacementRecord(f), addon.db and addon.db.windows
        if rec and windows then windows[key] = rec end
    end

    function f:RestorePosition()
        local pos = addon.db and addon.db.windows and addon.db.windows[key]
        local scale = S.ScaleNow(f)
        f:ClearAllPoints()
        if pos and pos.point then
            f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, (tonumber(pos.x) or 0) / scale,
                (tonumber(pos.y) or 0) / scale)
            P.AlignFrame(f)


            if not pos.thirds then
                S.ReanchorToThirds(f)
                f:SavePosition()
            end
            return
        elseif default then
            f:SetPoint(default[1], UIParent, default[2], default[3] / scale, default[4] / scale)
        else
            f:SetPoint("CENTER")
        end
        P.AlignFrame(f)
    end
end



function S.StopWindowDrag(f)
    P.StopDrag(f)
    S.ReanchorToThirds(f)
    f:SavePosition()
end



function S.InstallWindowGeometry(f, key, header, close)


    local grip = CreateFrame("Frame", nil, header)
    grip:SetPoint("TOPLEFT")
    grip:SetPoint("BOTTOMRIGHT", close, "BOTTOMLEFT")
    grip:EnableMouse(true)
    grip:RegisterForDrag("LeftButton")
    grip:SetScript("OnDragStart", function() P.StartDrag(f) end)
    grip:SetScript("OnDragStop", function() S.StopWindowDrag(f) end)

    S.InstallPlacement(f, key)




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



    function f:SetSizeFromTopRight(width, height)
        width, height = P.Snap(width), P.Snap(height)
        local wasW, wasH = f:GetWidth(), f:GetHeight()
        local point, relTo, relPoint, x, y = f:GetPoint()
        if point and wasW and wasH and wasW > 0 and wasH > 0 and f:IsShown()
            and (width ~= wasW or height ~= wasH) then
            local left = point:find("RIGHT") and 0 or (point:find("LEFT") and 1 or 0.5)
            local down = point:find("BOTTOM") and 1 or (point:find("TOP") and 0 or 0.5)
            f:SetPoint(point, relTo, relPoint, x - (width - wasW) * left,
                y - (height - wasH) * down)
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
        S.ScaleNow(f)
        local x, y = S.CursorOffset(f)
        f:ClearAllPoints()
        if not x then
            f:SetPoint("CENTER")
            return
        end

        local own = EffectiveScale(f) or 1
        local ratio = (EffectiveScale(UIParent) or own) / own
        local w, h = f:GetWidth(), f:GetHeight()
        x = math.max(w / 2, math.min(UIParent:GetWidth() * ratio - w / 2, x))
        y = math.max(h / 2, math.min(UIParent:GetHeight() * ratio - h / 2, y))
        f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
        P.AlignFrame(f)
    end


    function f:PlaceCentredHigh()
        local scale = S.ScaleNow(f)
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", 0, UIParent:GetHeight() * 0.1 / scale)
        P.AlignFrame(f)
    end




    f:HookScript("OnSizeChanged", function()
        P.AfterLayout(function()
            S.ApplyWindowScale(f)
            P.Reanchor(f)
        end)
    end)
    f:HookScript("OnShow", function() S.ApplyWindowScale(f) end)
    P.OnRescale(function()
        S.ApplyWindowScale(f)
        P.AlignFrame(f)
    end)

    S.FollowWindowAlpha(f)
    S.FollowWindowScale(f)
end






function S.NotificationOn(key)
    local chosen = addon.db and addon.db.soundNotifications
    if type(chosen) ~= "table" then return true end
    return chosen[key] ~= false
end

function S.PlayNotification(key)
    if not S.NotificationOn(key) then return end
    PlaySound(SOUNDKIT.UI_70_ARTIFACT_FORGE_APPEARANCE_COLOR_SELECT, "Master")
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





S.WINDOW_SCALE_MIN_PCT, S.WINDOW_SCALE_MAX_PCT, S.WINDOW_SCALE_STEP_PCT = 70, 200, 5
S.WINDOW_SCALE_FLOOR = 0.5
S.WINDOW_FIT_MARGIN = 16

local function Num(v)
    return type(v) == "number" and not Secret(v) and v == v and v ~= math.huge and v ~= -math.huge
end


function S.ClampWindowScale(v)
    if v == nil or Secret(v) then return 1 end
    v = tonumber(v)
    if not Num(v) then return 1 end
    local step = S.WINDOW_SCALE_STEP_PCT
    local pct = math.floor(v * 100 / step + 0.5) * step
    pct = math.max(S.WINDOW_SCALE_MIN_PCT, math.min(S.WINDOW_SCALE_MAX_PCT, pct))
    return pct / 100
end

function S.WindowScale()
    return S.ClampWindowScale(addon.db and addon.db.windowScale)
end



function S.AppliedScale(width, height, screenW, screenH, setting)
    setting = S.ClampWindowScale(setting)
    local twice = 2 * S.WINDOW_FIT_MARGIN
    local fit = math.huge
    if Num(width) and width > 0 and Num(screenW) and screenW > 0 then
        fit = math.min(fit, (screenW - twice) / width)
    end
    if Num(height) and height > 0 and Num(screenH) and screenH > 0 then
        fit = math.min(fit, (screenH - twice) / height)
    end
    local lowest = setting >= 1 and 1 or S.WINDOW_SCALE_FLOOR
    if fit >= setting then return setting end
    return math.max(lowest, math.floor(fit * 1000) / 1000)
end


local function Fractions(point)
    if type(point) ~= "string" then return nil end
    local fx = point:find("LEFT", 1, true) and 0 or (point:find("RIGHT", 1, true) and 1 or 0.5)
    local fy = point:find("BOTTOM", 1, true) and 0 or (point:find("TOP", 1, true) and 1 or 0.5)
    return fx, fy
end



function S.RectFromAnchor(point, relPoint, x, y, w, h, e, W, H)
    if not (Num(x) and Num(y) and Num(w) and Num(h) and Num(e) and Num(W) and Num(H)) or e <= 0 then
        return nil
    end
    local px, py = Fractions(point)
    local rx, ry = Fractions(relPoint or point)
    if not px or not rx then return nil end
    w, h = w * e, h * e
    return rx * W + x * e - px * w, ry * H + y * e - py * h, w, h
end



function S.ThirdsAnchor(left, bottom, w, h, W, H)
    if not (Num(left) and Num(bottom) and Num(w) and Num(h) and Num(W) and Num(H)) then return nil end
    local cx, cy = left + w / 2, bottom + h / 2
    local horizontal = cx < W / 3 and "LEFT" or (cx > 2 * W / 3 and "RIGHT" or "")
    local vertical = cy < H / 3 and "BOTTOM" or (cy > 2 * H / 3 and "TOP" or "")
    local point = vertical .. horizontal
    if point == "" then point = "CENTER" end
    local x = horizontal == "LEFT" and left or (horizontal == "RIGHT" and left + w - W or cx - W / 2)
    local y = vertical == "BOTTOM" and bottom or (vertical == "TOP" and bottom + h - H or cy - H / 2)
    return point, point, x, y
end


function S.CursorOffset(frame)
    local es = EffectiveScale(frame)
    local cx, cy = GetCursorPosition()
    if not es or not Num(cx) or not Num(cy) then return nil end
    return cx / es, cy / es
end

local function ScreenSize()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    if Num(w) and Num(h) then return w, h end
end


local function OwnScale(f)
    local ok, s = pcall(f.GetScale, f)
    if ok and Num(s) and s > 0 then return s end
end


local function LiveRect(f)
    local point, relTo, relPoint, x, y = f:GetPoint()
    if Secret(point) or Secret(relTo) or Secret(relPoint) or not point
        or (relTo and relTo ~= UIParent) then return nil end
    local W, H = ScreenSize()
    local e = OwnScale(f)
    if not W or not e then return nil end
    return S.RectFromAnchor(point, relPoint, x, y, f:GetWidth(), f:GetHeight(), e, W, H)
end


function S.PlacementRecord(f)
    local left, bottom, w, h = LiveRect(f)
    if not left then return nil end
    local W, H = ScreenSize()
    local point, relPoint, x, y = S.ThirdsAnchor(left, bottom, w, h, W, H)
    if not point then return nil end
    return { point = point, relPoint = relPoint, x = x, y = y, thirds = true }
end


function S.ReanchorToThirds(f)
    local rec = S.PlacementRecord(f)
    local scale = OwnScale(f)
    if not rec or not scale then return end
    f:ClearAllPoints()
    f:SetPoint(rec.point, UIParent, rec.relPoint, rec.x / scale, rec.y / scale)
    P.AlignFrame(f)
end


local scaleWindows, heldWindows = {}, {}
S.scaleWindows = scaleWindows

local function AppliedFor(f)
    local W, H = ScreenSize()
    return S.AppliedScale(f:GetWidth(), f:GetHeight(), W, H, S.WindowScale())
end


function S.RefreshEdgeSnap()
    if not P.AutoEdgeSnap then return end
    local scaled = S.WindowScale() ~= 1
    for i = 1, #scaleWindows do
        local s = OwnScale(scaleWindows[i])
        if s and math.abs(s - 1) > 1e-4 then scaled = true end
    end
    P.AutoEdgeSnap(scaled)
end



local resnapQueued = false
local function RequestResnap()
    if not P.Resnap or resnapQueued then return end
    resnapQueued = true
    P.AfterLayout(function()
        resnapQueued = false
        P.Resnap()
    end)
end



function S.ScaleNow(f)
    local current = OwnScale(f) or 1
    if heldWindows[f] then return current end
    local target = AppliedFor(f)
    if math.abs(target - current) > 1e-4 then
        f:SetScale(target)
        S.RefreshEdgeSnap()
        RequestResnap()
        return target
    end
    return current
end



local function Rescale(f, current, target)
    local point, relTo, relPoint, x, y = f:GetPoint()
    local pinned = point and not Secret(point) and not Secret(relPoint) and Num(x) and Num(y)
        and (not relTo or relTo == UIParent)
    f:SetScale(target)
    if pinned then
        f:ClearAllPoints()
        f:SetPoint(point, UIParent, relPoint or point, x * current / target, y * current / target)
        P.AlignFrame(f)
    end
end



function S.ApplyWindowScale(f)
    if heldWindows[f] then return false end
    local current = OwnScale(f)
    if not current then return false end
    local target = AppliedFor(f)
    if math.abs(target - current) <= 1e-4 then return false end
    Rescale(f, current, target)
    S.RefreshEdgeSnap()
    RequestResnap()
    return true
end


function S.FollowWindowScale(f)
    scaleWindows[#scaleWindows + 1] = f
    S.ScaleNow(f)
end

function S.SetWindowScale(value)
    if not addon.db then return end
    addon.db.windowScale = S.ClampWindowScale(value)
    for i = 1, #scaleWindows do S.ApplyWindowScale(scaleWindows[i]) end
    S.RefreshEdgeSnap()
    RequestResnap()
end



function S.HoldWindowScale(f)
    if f then
        heldWindows[f] = true
    end
end

function S.ReleaseWindowScale()
    local released = {}
    for f in pairs(heldWindows) do released[#released + 1] = f end
    for _, f in ipairs(released) do
        heldWindows[f] = nil
        S.ApplyWindowScale(f)
    end
    if #released > 0 then RequestResnap() end
end



function S.MatchScale(frame, owner)
    local scale
    local kind = type(owner)
    if (kind == "table" or kind == "userdata") and owner.GetParent then
        scale = OwnScale(S.WindowOf(owner))
    end
    scale = scale or S.WindowScale()
    local current = OwnScale(frame)
    if current and math.abs(scale - current) <= 1e-4 then return scale end
    frame:SetScale(scale)
    if P.Resnap then P.Resnap() end
    return scale
end
