if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_Widgets_SegmentedControl.lua
--  BuildSegmentedControl, the pill-shaped tab bar of the multi-edit headers.
--  DEFERRED: body runs on first EllesmereUI:EnsureLoaded() call, not at load.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI
EllesmereUI._deferredInits[#EllesmereUI._deferredInits + 1] = function()
local PP = EllesmereUI.PanelPP
local ELLESMERE_GREEN = EllesmereUI.ELLESMERE_GREEN
local MEDIA_PATH = EllesmereUI.MEDIA_PATH
local ShowWidgetTooltip = EllesmereUI.ShowWidgetTooltip
local HideWidgetTooltip = EllesmereUI.HideWidgetTooltip

-------------------------------------------------------------------------------
--  Segmented Control  (pill-shaped tab bar for multi-edit headers)
--  cfg = {
--      parent       = Frame,          -- parent frame to attach to
--      width        = number,         -- total width (used as fallback)
--      autoWidth    = bool,           -- auto-size to fit label content
--      keys         = { "k1", ... },  -- ordered keys
--      labels       = { k1="Lbl" },   -- display labels per key
--      getChecked   = function(key) -> bool,
--      getEyeball   = function() -> key  (optional, the "primary" selected key)
--      onToggle     = function(key),  -- called when a segment is clicked
--      isDisabled   = function(key) -> bool  (optional, grays out segment)
--      disabledTip  = function(key) -> string (optional, tooltip for disabled)
--  }
--  Returns: frame, height, refreshFn
-------------------------------------------------------------------------------
local function BuildSegmentedControl(cfg)
    local ACCENT   = ELLESMERE_GREEN
    local SEG_H    = cfg.height or 28
    local FONT_SZ  = 13
    local SEG_PAD  = 22
    local PILL_BG  = { 0.125, 0.125, 0.137 }  -- #202023
    local PILL_BGA = 0.95
    local INACTIVE_R, INACTIVE_G, INACTIVE_B = 0.467, 0.471, 0.482  -- #77787b
    local INACTIVE_A = 0.5
    local ACTIVE_R,   ACTIVE_G,   ACTIVE_B   = ACCENT.r, ACCENT.g, ACCENT.b
    local BG_HOVER_BOOST = 0.04  -- 4% brightness on hover for background

    local numKeys = #cfg.keys

    local tmpFS = UIParent:CreateFontString(nil, "OVERLAY")
    tmpFS:SetFont(EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", FONT_SZ, "")
    local segWidths = {}
    local pillW = 0
    for _, key in ipairs(cfg.keys) do
        tmpFS:SetText(EllesmereUI.L(cfg.labels[key] or key))
        local w = math.ceil(tmpFS:GetStringWidth()) + SEG_PAD * 2
        segWidths[key] = w
        pillW = pillW + w
    end
    tmpFS:Hide()

    if not cfg.autoWidth then
        pillW = cfg.width
        local baseW = math.floor(pillW / numKeys)
        local remainder = pillW - baseW * numKeys
        for idx, key in ipairs(cfg.keys) do
            segWidths[key] = baseW + (idx <= remainder and 1 or 0)
        end
    end

    -- Square mode option
    local SQUARE = cfg.square and true or false
    local capW = SQUARE and 0 or SEG_H
    if not SQUARE then
        segWidths[cfg.keys[1]] = math.floor(segWidths[cfg.keys[1]] - capW)
        segWidths[cfg.keys[numKeys]] = math.floor(segWidths[cfg.keys[numKeys]] - capW)
    end
    pillW = 0
    for _, key in ipairs(cfg.keys) do pillW = pillW + segWidths[key] end
    -- Account for 1px overlap between adjacent segments
    local overlapTotal = (numKeys - 1) * 1
    local totalW = pillW + capW * 2 - overlapTotal

    local frame = CreateFrame("Frame", nil, cfg.parent)
    frame:SetSize(totalW, SEG_H)

    local pillBody = CreateFrame("Frame", nil, frame)
    pillBody:SetSize(pillW - overlapTotal, SEG_H)
    PP.Point(pillBody, "TOP", frame, "TOP", 0, 0)
    pillBody:SetFrameLevel(frame:GetFrameLevel() + 1)

    local bg = pillBody:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0)  -- transparent; per-segment segBg handles background

    -------------------------------------------------------------------
    -- Pill caps
    -------------------------------------------------------------------
    local CAP_FILL_L_TEX   = MEDIA_PATH .. "pill-fill-l.png"
    local CAP_FILL_R_TEX   = MEDIA_PATH .. "pill-fill-r.png"
    local CAP_BORDER_L_TEX = MEDIA_PATH .. "pill-border-l.png"
    local CAP_BORDER_R_TEX = MEDIA_PATH .. "pill-border-r.png"

    local capLeftFill = pillBody:CreateTexture(nil, "BACKGROUND", nil, 1)
    capLeftFill:SetSize(capW, SEG_H)
    capLeftFill:SetTexture(CAP_FILL_L_TEX)
    capLeftFill:SetVertexColor(PILL_BG[1], PILL_BG[2], PILL_BG[3], PILL_BGA)

    local capLeftBdr = pillBody:CreateTexture(nil, "BACKGROUND", nil, 2)
    capLeftBdr:SetSize(capW, SEG_H)
    capLeftBdr:SetTexture(CAP_BORDER_L_TEX)

    local capRightFill = pillBody:CreateTexture(nil, "BACKGROUND", nil, 1)
    capRightFill:SetSize(capW, SEG_H)
    capRightFill:SetTexture(CAP_FILL_R_TEX)
    capRightFill:SetVertexColor(PILL_BG[1], PILL_BG[2], PILL_BG[3], PILL_BGA)

    local capRightBdr = pillBody:CreateTexture(nil, "BACKGROUND", nil, 2)
    capRightBdr:SetSize(capW, SEG_H)
    capRightBdr:SetTexture(CAP_BORDER_R_TEX)

    -- Cap accent overlays (5% accent tint when checked, using same pill cap PNGs)
    local capLeftAccent = pillBody:CreateTexture(nil, "BACKGROUND", nil, 3)
    capLeftAccent:SetSize(capW, SEG_H)
    capLeftAccent:SetTexture(CAP_FILL_L_TEX)
    capLeftAccent:SetVertexColor(ACCENT.r, ACCENT.g, ACCENT.b, 0.05)
    capLeftAccent:Hide()

    local capRightAccent = pillBody:CreateTexture(nil, "BACKGROUND", nil, 3)
    capRightAccent:SetSize(capW, SEG_H)
    capRightAccent:SetTexture(CAP_FILL_R_TEX)
    capRightAccent:SetVertexColor(ACCENT.r, ACCENT.g, ACCENT.b, 0.05)
    capRightAccent:Hide()

    -- Cap click zones anchored to pillBody for now, re-anchored after segments
    local capLeftBtn = CreateFrame("Button", nil, frame)
    capLeftBtn:SetSize(capW, SEG_H)
    PP.Point(capLeftBtn, "RIGHT", pillBody, "LEFT", 0, 0)
    capLeftBtn:SetFrameLevel(pillBody:GetFrameLevel() + 4)
    capLeftBtn:SetScript("OnClick", function()
        local key = cfg.keys[1]
        if cfg.isDisabled and cfg.isDisabled(key) then return end
        if cfg.onToggle then cfg.onToggle(key) end
    end)
    capLeftBtn:SetScript("OnEnter", function()
        local key = cfg.keys[1]
        if cfg.isDisabled and cfg.isDisabled(key) then
            if cfg.disabledTip then
                local tip = cfg.disabledTip(key)
                if tip then ShowWidgetTooltip(capLeftBtn, tip) end
            end
            return
        end
        frame._hoverIdx = 1
        if frame._refreshAll then frame._refreshAll() end
    end)
    capLeftBtn:SetScript("OnLeave", function()
        HideWidgetTooltip()
        frame._hoverIdx = nil
        if frame._refreshAll then frame._refreshAll() end
    end)

    local capRightBtn = CreateFrame("Button", nil, frame)
    capRightBtn:SetSize(capW, SEG_H)
    PP.Point(capRightBtn, "LEFT", pillBody, "RIGHT", 0, 0)
    capRightBtn:SetFrameLevel(pillBody:GetFrameLevel() + 4)
    capRightBtn:SetScript("OnClick", function()
        local key = cfg.keys[numKeys]
        if cfg.isDisabled and cfg.isDisabled(key) then return end
        if cfg.onToggle then cfg.onToggle(key) end
    end)
    capRightBtn:SetScript("OnEnter", function()
        local key = cfg.keys[numKeys]
        if cfg.isDisabled and cfg.isDisabled(key) then
            if cfg.disabledTip then
                local tip = cfg.disabledTip(key)
                if tip then ShowWidgetTooltip(capRightBtn, tip) end
            end
            return
        end
        frame._hoverIdx = numKeys
        if frame._refreshAll then frame._refreshAll() end
    end)
    capRightBtn:SetScript("OnLeave", function()
        HideWidgetTooltip()
        frame._hoverIdx = nil
        if frame._refreshAll then frame._refreshAll() end
    end)

    -------------------------------------------------------------------
    -- Segments each has full 1px border; adjacent segments overlap by 1px
    -------------------------------------------------------------------
    local segments = {}
    local BASE_LEVEL = pillBody:GetFrameLevel() + 3
    local CHECKED_LEVEL = BASE_LEVEL + 1  -- checked segments draw on top

    for i, key in ipairs(cfg.keys) do
        local thisW = segWidths[key]

        local btn = CreateFrame("Button", nil, pillBody)
        PP.Size(btn, thisW, SEG_H)
        if i == 1 then
            PP.Point(btn, "TOPLEFT", pillBody, "TOPLEFT", 0, 0)
        else
            -- Anchor to previous segment's right edge, shifted 1px left for overlap
            PP.Point(btn, "TOPLEFT", segments[i-1].btn, "TOPRIGHT", -1, 0)
        end
        btn:SetFrameLevel(BASE_LEVEL)

        -- Per-segment hover background overlay
        local segBg = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
        segBg:SetAllPoints()
        segBg:SetColorTexture(PILL_BG[1], PILL_BG[2], PILL_BG[3], PILL_BGA)

        -- Accent tint overlay for checked/active segments (5% opacity)
        local accentBg = btn:CreateTexture(nil, "BACKGROUND", nil, 2)
        accentBg:SetAllPoints()
        accentBg:SetColorTexture(ACCENT.r, ACCENT.g, ACCENT.b, 0.05)
        accentBg:Hide()

        -- Full 1px border on all 4 sides matches MakeBorder's pixel-perfect technique: vertical edges inset by 1px to avoid overlapping corners.
        local segTop = btn:CreateTexture(nil, "ARTWORK", nil, 7)
        segTop:SetColorTexture(INACTIVE_R, INACTIVE_G, INACTIVE_B, INACTIVE_A)
        segTop:SetHeight(1)
        PP.Point(segTop, "TOPLEFT", btn, "TOPLEFT", 0, 0)
        PP.Point(segTop, "TOPRIGHT", btn, "TOPRIGHT", 0, 0)

        local segBot = btn:CreateTexture(nil, "ARTWORK", nil, 7)
        segBot:SetColorTexture(INACTIVE_R, INACTIVE_G, INACTIVE_B, INACTIVE_A)
        segBot:SetHeight(1)
        PP.Point(segBot, "BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
        PP.Point(segBot, "BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)

        -- Vertical edges anchored to horizontal edges (inset 1px) to avoid bright corners
        local segLeft = btn:CreateTexture(nil, "ARTWORK", nil, 7)
        segLeft:SetColorTexture(INACTIVE_R, INACTIVE_G, INACTIVE_B, INACTIVE_A)
        segLeft:SetWidth(1)
        PP.Point(segLeft, "TOPLEFT", segTop, "BOTTOMLEFT", 0, 0)
        PP.Point(segLeft, "BOTTOMLEFT", segBot, "TOPLEFT", 0, 0)

        local segRight = btn:CreateTexture(nil, "ARTWORK", nil, 7)
        segRight:SetColorTexture(INACTIVE_R, INACTIVE_G, INACTIVE_B, INACTIVE_A)
        segRight:SetWidth(1)
        PP.Point(segRight, "TOPRIGHT", segTop, "BOTTOMRIGHT", 0, 0)
        PP.Point(segRight, "BOTTOMRIGHT", segBot, "TOPRIGHT", 0, 0)

        local lbl = btn:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(EllesmereUI.EXPRESSWAY, FONT_SZ, "")
        local lblOfsX = 0
        if i == 1 then lblOfsX = -capW / 2 end
        if i == numKeys then lblOfsX = capW / 2 end
        lbl:SetPoint("CENTER", lblOfsX, 0)
        lbl:SetText(EllesmereUI.L(cfg.labels[key] or key))

        segments[i] = {
            key = key, btn = btn, lbl = lbl, w = thisW, segBg = segBg, accentBg = accentBg,
            segTop = segTop, segBot = segBot, segLeft = segLeft, segRight = segRight,
        }

        btn:SetScript("OnClick", function()
            if cfg.isDisabled and cfg.isDisabled(key) then return end
            if cfg.onToggle then cfg.onToggle(key) end
        end)

        btn:SetScript("OnEnter", function()
            if cfg.isDisabled and cfg.isDisabled(key) then
                if cfg.disabledTip then
                    local tip = cfg.disabledTip(key)
                    if tip then ShowWidgetTooltip(btn, tip) end
                end
                return
            end
            frame._hoverIdx = i
            if frame._refreshAll then frame._refreshAll() end
        end)

        btn:SetScript("OnLeave", function()
            HideWidgetTooltip()
            frame._hoverIdx = nil
            if frame._refreshAll then frame._refreshAll() end
        end)
    end

    -------------------------------------------------------------------
    -- Anchor caps to segment buttons. Raw SetPoint (not PixelUtil) for cap textures to avoid asymmetric pixel rounding that squishes one side.
    -------------------------------------------------------------------
    local firstBtn = segments[1].btn
    local lastBtn  = segments[#segments].btn

    capLeftFill:SetPoint("RIGHT", firstBtn, "LEFT", 0, 0)
    capLeftBdr:SetPoint("RIGHT", firstBtn, "LEFT", 0, 0)
    capLeftAccent:SetPoint("RIGHT", firstBtn, "LEFT", 0, 0)
    capRightFill:SetPoint("LEFT", lastBtn, "RIGHT", 0, 0)
    capRightBdr:SetPoint("LEFT", lastBtn, "RIGHT", 0, 0)
    capRightAccent:SetPoint("LEFT", lastBtn, "RIGHT", 0, 0)
    capLeftBtn:ClearAllPoints()
    capLeftBtn:SetPoint("RIGHT", firstBtn, "LEFT", 0, 0)
    capRightBtn:ClearAllPoints()
    capRightBtn:SetPoint("LEFT", lastBtn, "RIGHT", 0, 0)

    if SQUARE then
        -- No rounded caps: hide the textures and their click zones outright.
        capLeftFill:Hide();  capLeftBdr:Hide();  capLeftAccent:Hide()
        capRightFill:Hide(); capRightBdr:Hide(); capRightAccent:Hide()
        capLeftBtn:Hide();   capRightBtn:Hide()
    end

    -------------------------------------------------------------------
    -- RefreshAll
    -------------------------------------------------------------------
    local function RefreshAll()
        local eyeKey = cfg.getEyeball and cfg.getEyeball()
        local hoverIdx = frame._hoverIdx

        for idx, seg in ipairs(segments) do
            local disabled = cfg.isDisabled and cfg.isDisabled(seg.key)
            local checked  = cfg.getChecked(seg.key)
            local isHover  = (hoverIdx == idx)

            -- Label color
            if disabled then
                seg.lbl:SetTextColor(1, 1, 1, 0.20)
            elseif checked then
                seg.lbl:SetTextColor(ACTIVE_R, ACTIVE_G, ACTIVE_B, 1.0)
            else
                seg.lbl:SetTextColor(1, 1, 1, 0.60)
            end

            -- Checked segments get higher frame level so their border draws on top of the adjacent unchecked segment's border.
            if checked and not disabled then
                seg.btn:SetFrameLevel(CHECKED_LEVEL)
            else
                seg.btn:SetFrameLevel(BASE_LEVEL)
            end

            -- Border color: checked = accent, unchecked = inactive gray, disabled = 25% opacity
            local br, bg2, bb, ba
            if disabled then
                br, bg2, bb, ba = INACTIVE_R, INACTIVE_G, INACTIVE_B, 0.10
            elseif checked then
                br, bg2, bb, ba = ACTIVE_R, ACTIVE_G, ACTIVE_B, 1.0
            else
                br, bg2, bb, ba = INACTIVE_R, INACTIVE_G, INACTIVE_B, INACTIVE_A
            end

            seg.segTop:SetColorTexture(br, bg2, bb, ba)
            seg.segBot:SetColorTexture(br, bg2, bb, ba)
            seg.segLeft:SetColorTexture(br, bg2, bb, ba)
            seg.segRight:SetColorTexture(br, bg2, bb, ba)

            -- All 4 borders visible, except (pill mode only): first segment hides its left, last hides its right -- the rounded caps draw those edges. In square mode those outer edges are the box border, kept.
            seg.segTop:Show()
            seg.segBot:Show()
            local isFirst = (idx == 1)
            local isLast  = (idx == #segments)
            if isFirst and not SQUARE then seg.segLeft:Hide() else seg.segLeft:Show() end
            if isLast  and not SQUARE then seg.segRight:Hide() else seg.segRight:Show() end

            -- Background: disabled = 50% opacity, hover = lighten by 4%, normal = PILL_BGA
            if disabled then
                seg.segBg:SetColorTexture(PILL_BG[1], PILL_BG[2], PILL_BG[3], 0.50)
                seg.accentBg:Hide()
            elseif isHover then
                local hr, hg, hb = PILL_BG[1] + BG_HOVER_BOOST, PILL_BG[2] + BG_HOVER_BOOST, PILL_BG[3] + BG_HOVER_BOOST
                seg.segBg:SetColorTexture(hr, hg, hb, PILL_BGA)
                if checked then
                    seg.accentBg:SetColorTexture(ACCENT.r, ACCENT.g, ACCENT.b, 0.05); seg.accentBg:Show()
                else
                    seg.accentBg:Hide()
                end
            else
                seg.segBg:SetColorTexture(PILL_BG[1], PILL_BG[2], PILL_BG[3], PILL_BGA)
                if checked then
                    seg.accentBg:SetColorTexture(ACCENT.r, ACCENT.g, ACCENT.b, 0.05); seg.accentBg:Show()
                else
                    seg.accentBg:Hide()
                end
            end
        end

        -- Square mode has no caps; the segment borders above are the whole box.
        if SQUARE then return end

        -- Cap borders & fills: match adjacent segment's state (checked/disabled/hover)
        local firstKey = cfg.keys[1]
        local lastKey  = cfg.keys[numKeys]
        local firstDisabled = cfg.isDisabled and cfg.isDisabled(firstKey)
        local lastDisabled  = cfg.isDisabled and cfg.isDisabled(lastKey)
        local firstChecked = cfg.getChecked(firstKey) and not firstDisabled
        local lastChecked  = cfg.getChecked(lastKey) and not lastDisabled
        local firstHover = (hoverIdx == 1) and not firstDisabled
        local lastHover  = (hoverIdx == numKeys) and not lastDisabled

        local lbr, lbg2, lbb, lba = INACTIVE_R, INACTIVE_G, INACTIVE_B, INACTIVE_A
        if firstDisabled then lba = 0.10
        elseif firstChecked then lbr, lbg2, lbb, lba = ACTIVE_R, ACTIVE_G, ACTIVE_B, 1.0 end
        capLeftBdr:SetVertexColor(lbr, lbg2, lbb, lba)

        local rbr, rbg2, rbb, rba = INACTIVE_R, INACTIVE_G, INACTIVE_B, INACTIVE_A
        if lastDisabled then rba = 0.10
        elseif lastChecked then rbr, rbg2, rbb, rba = ACTIVE_R, ACTIVE_G, ACTIVE_B, 1.0 end
        capRightBdr:SetVertexColor(rbr, rbg2, rbb, rba)

        -- Cap fills: disabled = 50% opacity, hover = lighten by 4%, normal = PILL_BGA
        local lfr, lfg, lfb, lfa = PILL_BG[1], PILL_BG[2], PILL_BG[3], PILL_BGA
        if firstDisabled then lfa = 0.50
        elseif firstHover then lfr, lfg, lfb = lfr + BG_HOVER_BOOST, lfg + BG_HOVER_BOOST, lfb + BG_HOVER_BOOST end
        capLeftFill:SetVertexColor(lfr, lfg, lfb, lfa)

        local rfr, rfg, rfb, rfa = PILL_BG[1], PILL_BG[2], PILL_BG[3], PILL_BGA
        if lastDisabled then rfa = 0.50
        elseif lastHover then rfr, rfg, rfb = rfr + BG_HOVER_BOOST, rfg + BG_HOVER_BOOST, rfb + BG_HOVER_BOOST end
        capRightFill:SetVertexColor(rfr, rfg, rfb, rfa)

        -- Cap accent overlays: show 5% accent tint when checked (matches segment accentBg)
        if firstChecked then
            capLeftAccent:SetVertexColor(ACCENT.r, ACCENT.g, ACCENT.b, 0.05)
            capLeftAccent:Show()
        else
            capLeftAccent:Hide()
        end
        if lastChecked then
            capRightAccent:SetVertexColor(ACCENT.r, ACCENT.g, ACCENT.b, 0.05)
            capRightAccent:Show()
        else
            capRightAccent:Hide()
        end
    end

    frame._refreshAll = RefreshAll
    RefreshAll()

    -- Pill sits at 90% opacity permanently
    frame:SetAlpha(0.9)    return frame, SEG_H, RefreshAll
end




EllesmereUI.BuildSegmentedControl = BuildSegmentedControl
end  -- end deferred init
