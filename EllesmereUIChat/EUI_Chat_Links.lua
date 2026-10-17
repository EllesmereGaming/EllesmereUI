if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Chat_Links.lua
--
--  Reading the chat text, the copy popup, URL detection with its popup and
--  the hyperlink tooltip.
--  Reads the earlier Chat files through ns and ns._internals.
-------------------------------------------------------------------------------
local addonName, ns = ...
local I = ns._internals
-- EllesmereUIChat.lua or an earlier EUI_Chat_*.lua file failed to load.
if not I or I.broken then return end
I.broken = true

local EUI = _G.EllesmereUI
local ECHAT = ns.ECHAT
local PP = EUI.PP
local min, max = min, max

local GetFont = I.GetFont

-------------------------------------------------------------------------------
--  Chat text helpers
-------------------------------------------------------------------------------
local function StripUIEscapes(text)
    if not text then return "" end
    text = text:gsub("|H.-|h(.-)|h", "%1")   -- hyperlinks -> display text
    text = text:gsub("|T.-|t", "")            -- textures
    text = text:gsub("|A.-|a", "")            -- atlas
    text = text:gsub("|K.-|k", "")            -- secret value placeholders
    text = text:gsub("|n", "\n")              -- newlines
    text = text:gsub("||", "|")               -- escaped pipes
    -- Keep |cXXXXXXXX and |r color codes so the copy popup preserves colors
    return text
end

-- Read all messages from the active window on demand. The primary source is
-- OUR message frame for the selected window; the hosted combat log (still
-- Blizzard-rendered) and any window the engine has not integrated fall back
-- to the Blizzard buffer read. Secret lines are skipped either way.
local function ReadActiveChatText()
    local selected = GENERAL_CHAT_DOCK and FCFDock_GetSelectedWindow
        and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
    local cf = selected or ChatFrame1
    if not cf then return "" end
    local raw = {}
    local usedEngine = false
    if ECHAT.EngineGetMessageLines and ns._chatWins and ns._chatWins[cf]
        and not (ns._clHosted and cf == _G.ChatFrame2) then
        ECHAT.EngineGetMessageLines(cf, raw)
        usedEngine = true
    end
    if not usedEngine then
        if not cf.GetNumMessages then return "" end
        local n = cf:GetNumMessages()
        for i = 1, n do
            local ok, text = pcall(cf.GetMessageInfo, cf, i)
            if ok then raw[#raw + 1] = text end
        end
    end
    if #raw == 0 then return "(No chat history)" end
    local lines = {}
    for i = 1, #raw do
        local text = raw[i]
        if text and not (issecretvalue and issecretvalue(text)) then
            local sok, stripped = pcall(StripUIEscapes, text)
            if sok and stripped then
                lines[#lines + 1] = stripped
            end
        end
    end
    return table.concat(lines, "\n")
end



-------------------------------------------------------------------------------
--  Copy popup (used by sidebar copy-chat button)
-------------------------------------------------------------------------------

local copyDimmer

local function ShowCopyPopup(text)
    if not copyDimmer then
        local POPUP_W, POPUP_H = 520, 340

        local dimmer = CreateFrame("Frame", nil, UIParent)
        dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
        dimmer:SetAllPoints(UIParent)
        dimmer:EnableMouse(true)
        dimmer:EnableMouseWheel(true)
        dimmer:SetScript("OnMouseWheel", function() end)
        dimmer:Hide()
        local dimTex = EUI.SolidTex(dimmer, "BACKGROUND", 0, 0, 0, 0.25)
        dimTex:SetAllPoints()

        local popup = CreateFrame("Frame", nil, dimmer)
        popup:SetSize(POPUP_W, POPUP_H)
        popup:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
        popup:EnableMouse(true)

        local bg = EUI.SolidTex(popup, "BACKGROUND", 0.077, 0.068, 0.058, 0.95)
        bg:SetAllPoints()
        EUI.MakeBorder(popup, 1, 1, 1, 0.15, EUI.PanelPP)

        -- Blizzard template: scrolling + selection built in
        local textBox = CreateFrame("Frame", nil, popup, "ScrollingEditBoxTemplate")
        textBox:SetPoint("TOPLEFT", popup, "TOPLEFT", 20, -20)
        textBox:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -20, 60)

        local editBox = textBox:GetEditBox()
        editBox:SetFont(GetFont(), 12, EUI.GetFontOutlineFlag("chat") or "")
        editBox:SetTextColor(1, 1, 1, 0.75)
        editBox:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            dimmer:Hide()
        end)
        editBox:SetScript("OnChar", function(self)
            if self._readOnlyText then
                self:SetText(self._readOnlyText)
                self:HighlightText()
            end
        end)

        -- Thin interactive scrollbar reading from the template's ScrollBox
        local scrollBox = textBox:GetScrollBox()
        local track = CreateFrame("Button", nil, popup)
        track:SetWidth(8)
        track:SetPoint("TOPRIGHT", textBox, "TOPRIGHT", 2, -2)
        track:SetPoint("BOTTOMRIGHT", textBox, "BOTTOMRIGHT", 2, 2)
        track:SetFrameLevel(popup:GetFrameLevel() + 5)
        track:EnableMouse(true)
        track:RegisterForClicks("AnyUp")

        local thumb = track:CreateTexture(nil, "ARTWORK")
        thumb:SetColorTexture(1, 1, 1, 0.27)
        thumb:SetWidth(4)
        thumb:SetHeight(40)
        thumb:SetPoint("TOP", track, "TOP", 0, 0)

        local _sbDragging = false
        local _sbDragOffsetY = 0

        local function UpdateThumb()
            if not scrollBox then thumb:Hide(); return end
            local ext = scrollBox:GetVisibleExtentPercentage()
            if not ext or ext >= 1 then thumb:Hide(); return end
            thumb:Show()
            local trackH = track:GetHeight()
            local thumbH = max(20, trackH * ext)
            thumb:SetHeight(thumbH)
            local pct = scrollBox:GetScrollPercentage() or 0
            thumb:ClearAllPoints()
            thumb:SetPoint("TOP", track, "TOP", 0, -(pct * (trackH - thumbH)))
        end

        local function SetScrollFromY(cursorY)
            local trackH = track:GetHeight()
            local ext = scrollBox:GetVisibleExtentPercentage() or 1
            local thumbH = max(20, trackH * ext)
            local maxTravel = trackH - thumbH
            if maxTravel <= 0 then return end
            local trackTop = track:GetTop()
            if not trackTop then return end
            local scale = track:GetEffectiveScale()
            local localY = trackTop - (cursorY / scale) - _sbDragOffsetY
            local pct = max(0, min(1, localY / maxTravel))
            scrollBox:SetScrollPercentage(pct)
        end

        track:SetScript("OnMouseDown", function(self, button)
            if button ~= "LeftButton" then return end
            local _, cursorY = GetCursorPosition()
            local scale = self:GetEffectiveScale()
            local trackTop = self:GetTop()
            if not trackTop then return end
            local thumbTop = thumb:GetTop()
            local thumbBot = thumb:GetBottom()
            if thumbTop and thumbBot then
                local localCursor = cursorY / scale
                if localCursor <= thumbTop and localCursor >= thumbBot then
                    _sbDragOffsetY = thumbTop - localCursor
                    _sbDragging = true
                    return
                end
            end
            -- Not on the thumb: jump to the clicked position
            _sbDragOffsetY = (thumb:GetHeight() or 20) / 2
            _sbDragging = true
            SetScrollFromY(cursorY)
        end)
        track:SetScript("OnMouseUp", function() _sbDragging = false end)

        -- Polls only while the popup is open (hidden frame otherwise)
        local pollFrame = CreateFrame("Frame")
        pollFrame:Hide()
        local _lastPct, _lastExt = -1, -1
        pollFrame:SetScript("OnUpdate", function()
            if _sbDragging then
                local _, cursorY = GetCursorPosition()
                SetScrollFromY(cursorY)
            end
            local ext = scrollBox:GetVisibleExtentPercentage() or 1
            local pct = scrollBox:GetScrollPercentage() or 0
            if ext == _lastExt and pct == _lastPct then return end
            _lastExt, _lastPct = ext, pct
            UpdateThumb()
        end)
        dimmer:HookScript("OnShow", function() _lastPct, _lastExt = -1, -1; pollFrame:Show() end)
        dimmer:HookScript("OnHide", function() _sbDragging = false; pollFrame:Hide() end)

        popup._textBox = textBox
        popup._editBox = editBox

        local closeBtn = CreateFrame("Button", nil, popup)
        closeBtn:SetSize(90, 24)
        closeBtn:SetPoint("BOTTOM", popup, "BOTTOM", 0, 14)
        closeBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
        EUI.MakeStyledButton(closeBtn, "Close", 10,
            EUI.RB_COLOURS, function() dimmer:Hide() end)

        dimmer:SetScript("OnMouseDown", function()
            if not popup:IsMouseOver() then dimmer:Hide() end
        end)

        -- SetPropagateKeyboardInput is protected in combat: always pcall it.
        popup:EnableKeyboard(true)
        popup:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                pcall(self.SetPropagateKeyboardInput, self, false)
                dimmer:Hide()
            else
                pcall(self.SetPropagateKeyboardInput, self, true)
            end
        end)

        popup._dimmer = dimmer
        copyDimmer = dimmer
        copyDimmer._popup = popup
    end

    local popup = copyDimmer._popup
    popup._textBox:SetText(text)
    popup._editBox._readOnlyText = text
    ECHAT.HostPopup(copyDimmer)
    copyDimmer:Show()
    C_Timer.After(0.05, function()
        popup._editBox:SetFocus()
        -- Open at the newest lines: cursor to the end, then pin the scroll there
        popup._editBox:SetCursorPosition(#text)
        popup._editBox:HighlightText()
        popup._textBox:GetScrollBox():ScrollToEnd(true)
    end)
end

-------------------------------------------------------------------------------
--  URL detection + inline copy popup
-------------------------------------------------------------------------------
local URL_PATTERNS = {
    "%f[%S](%a[%w+.-]+://%S+)",
    "^(%a[%w+.-]+://%S+)",
    "%f[%S](www%.[-%w_%%]+%.%a%a+/%S+)",
    "^(www%.[-%w_%%]+%.%a%a+/%S+)",
    "%f[%S](www%.[-%w_%%]+%.%a%a+)",
    "^(www%.[-%w_%%]+%.%a%a+)",
}

-- Literal pre-check so the regex pass is skipped entirely for messages with no
-- URL-like substring (the overwhelming majority).
local function ContainsURL(text)
    if not text then return false end
    return text:find("://", 1, true) or text:find("www.", 1, true)
end

-- Substitution string built once (the color hex is constant)
local _urlSubstitution
local function _GetUrlSubstitution()
    if not _urlSubstitution then
        local eg = EUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.61 }
        local hex = EllesmereUI.HexColor(eg.r, eg.g, eg.b)
        _urlSubstitution = hex .. "|H" .. addonName .. "url:%1|h[%1]|h|r"
    end
    return _urlSubstitution
end

local function WrapURLs(text)
    if not text then return text end
    local sub = _GetUrlSubstitution()
    for _, p in ipairs(URL_PATTERNS) do
        text = text:gsub(p, sub)
    end
    return text
end

local urlBackdrop, urlPopup

local function HideUrlPopup()
    if urlPopup then urlPopup:Hide() end
    if urlBackdrop then urlBackdrop:Hide() end
end

local function ShowUrlPopup(url)
    if not urlPopup then
        urlBackdrop = CreateFrame("Button", nil, UIParent)
        urlBackdrop:SetFrameStrata("DIALOG")
        urlBackdrop:SetFrameLevel(499)
        urlBackdrop:SetAllPoints(UIParent)
        local bdTex = urlBackdrop:CreateTexture(nil, "BACKGROUND")
        bdTex:SetAllPoints()
        bdTex:SetColorTexture(0, 0, 0, 0.10)
        local fadeIn = urlBackdrop:CreateAnimationGroup()
        fadeIn:SetToFinalAlpha(true)
        local a = fadeIn:CreateAnimation("Alpha")
        a:SetFromAlpha(0); a:SetToAlpha(1); a:SetDuration(0.2)
        urlBackdrop._fadeIn = fadeIn
        urlBackdrop:RegisterForClicks("AnyUp")
        urlBackdrop:SetScript("OnClick", HideUrlPopup)
        urlBackdrop:Hide()

        urlPopup = CreateFrame("Frame", nil, UIParent)
        urlPopup:SetFrameStrata("DIALOG")
        urlPopup:SetFrameLevel(500)
        urlPopup:SetSize(340, 52)
        urlPopup:EnableMouse(true)
        local popFade = urlPopup:CreateAnimationGroup()
        popFade:SetToFinalAlpha(true)
        local pa = popFade:CreateAnimation("Alpha")
        pa:SetFromAlpha(0); pa:SetToAlpha(1); pa:SetDuration(0.2)
        urlPopup._fadeIn = popFade

        local bg = urlPopup:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.077, 0.068, 0.058, 0.97)
        if PP and PP.CreateBorder then
            PP.CreateBorder(urlPopup, 1, 1, 1, 0.15, 1, "OVERLAY", 7)
        end

        local hint = urlPopup:CreateFontString(nil, "OVERLAY")
        hint:SetFont(GetFont(), 8, "")
        hint:SetTextColor(1, 1, 1, 0.5)
        hint:SetPoint("TOP", urlPopup, "TOP", 0, -6)
        hint:SetText("Ctrl+C to copy, Escape to close")

        local eb = CreateFrame("EditBox", nil, urlPopup)
        eb:SetSize(300, 16)
        eb:SetPoint("TOP", hint, "BOTTOM", 0, -4)
        eb:SetFont(GetFont(), 11, "")
        eb:SetAutoFocus(false)
        eb:SetJustifyH("CENTER")
        local ebBg = eb:CreateTexture(nil, "BACKGROUND")
        ebBg:SetColorTexture(0.112, 0.105, 0.098, 1)
        ebBg:SetPoint("TOPLEFT", -6, 4); ebBg:SetPoint("BOTTOMRIGHT", 6, -4)
        if PP and PP.CreateBorder then
            PP.CreateBorder(eb, 1, 1, 1, 0.02, 1, "OVERLAY", 7)
        end
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); HideUrlPopup() end)
        eb:SetScript("OnKeyDown", function(self, key)
            if key == "C" and IsControlKeyDown() then
                C_Timer.After(0.05, HideUrlPopup)
            end
        end)
        eb:SetScript("OnMouseUp", function(self) self:HighlightText() end)
        urlPopup:SetScript("OnMouseDown", function() urlPopup._eb:SetFocus(); urlPopup._eb:HighlightText() end)
        urlPopup._eb = eb
    end
    urlPopup._eb:SetText(url)
    urlPopup:ClearAllPoints()
    local cx, cy = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    urlPopup:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", cx / scale, cy / scale + 10)
    ECHAT.HostPopup(urlBackdrop)
    ECHAT.HostPopup(urlPopup)
    urlBackdrop:SetAlpha(0); urlBackdrop:Show(); urlBackdrop._fadeIn:Play()
    urlPopup:SetAlpha(0); urlPopup:Show(); urlPopup._fadeIn:Play()
    urlPopup._eb:SetFocus(); urlPopup._eb:HighlightText()
end

-------------------------------------------------------------------------------
--  Hyperlink tooltip on hover + click-to-toggle item detail popup
-------------------------------------------------------------------------------
local TOOLTIP_LINK_TYPES = {
    achievement = true, apower = true, currency = true, enchant = true,
    glyph = true, instancelock = true, item = true, keystone = true,
    quest = true, spell = true, talent = true, unit = true,
}

local _hyperlinkEntered = nil

local function OnHyperlinkEnter(self, hyperlink)
    -- Secret link (lockdown line): match would error; no tooltip either way.
    if _G.issecretvalue and _G.issecretvalue(hyperlink) then return end
    local cfg = ECHAT.DB()
    if cfg.hideTooltipOnHover then return end
    local linkType = hyperlink:match("^([^:]+)")
    if TOOLTIP_LINK_TYPES[linkType] then
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink(hyperlink)
        GameTooltip:Show()
        _hyperlinkEntered = self
    end
end

local function OnHyperlinkLeave(self)
    if _hyperlinkEntered then
        _hyperlinkEntered = nil
        GameTooltip:Hide()
    end
end

-- Open the copy popup when a wrapped URL link is clicked. Also the mirror
-- for the censored-message links ("[Show Message]" and its send/rewrite
-- siblings): their handlers rewrite or remove the stored line IN PLACE on
-- every chat frame (TransformMessages / RemoveMessagesByPredicate -- no
-- AddMessage, no event), so the engine window would keep showing the
-- placeholder; this post-hook runs after the handler and queues the same
-- deferred rebuild the CAUTIONARY_CHAT_MESSAGE mirror uses.
hooksecurefunc("SetItemRef", function(link)
    if not link then return end
    if _G.issecretvalue and _G.issecretvalue(link) then return end
    if link:find("^censoredmessage") then
        if ECHAT.EngineQueueRebuildAll then ECHAT.EngineQueueRebuildAll() end
        return
    end
    local url = link:match("^" .. addonName .. "url:(.+)$")
    if url then
        ShowUrlPopup(url)
    end
end)

I.ContainsURL, I.OnHyperlinkEnter = ContainsURL, OnHyperlinkEnter
I.OnHyperlinkLeave, I.ReadActiveChatText = OnHyperlinkLeave, ReadActiveChatText
I.ShowCopyPopup, I.WrapURLs = ShowCopyPopup, WrapURLs
I.broken = false
