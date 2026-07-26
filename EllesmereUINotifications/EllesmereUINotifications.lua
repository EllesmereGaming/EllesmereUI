-------------------------------------------------------------------------------
-- EllesmereUINotifications.lua - event-driven reward notification feed
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EN = EllesmereUI.Lite.NewAddon(ADDON_NAME)

local floor, max = math.floor, math.max
local format = string.format
local DB_DEFAULTS = { profile = {
    enabled = true, duration = 5, fadeDuration = 0.6, maxVisible = 6,
    enterAnimation = "SLIDE_TOP", exitAnimation = "FADE",
    enterDuration = 0.2, exitDuration = 1.2,
    width = 310, spacing = 5, alignment = "RIGHT",
    fontSize = 14, valueFontSize = 12, iconSize = 28, backgroundAlpha = 0.72,
    growUp = true, showIcons = true, showItemQuality = true,
    showItemValue = false, showTooltip = true,
    displayStyle = "BAR", borderTexture = "solid", borderSize = 1,
    borderR = 0, borderG = 0, borderB = 0, borderA = 1,
    borderOffsetX = 0, borderOffsetY = 0, borderBehind = false,
    fontName = "__global", fontStyle = "OUTLINE_SHADOW",
    barTexture = "__solid", barR = 0.035, barG = 0.035, barB = 0.035,
    iconPartOfBar = true, iconOffsetX = 5, showIconDivider = false,
    alertsEnabled = false, alertEpicBoE = true, alertEpicWarbound = true,
    alertItemIDs = "", alertItemVariants = {}, alertItemReagentQualities = {},
    alertGlow = true, alertBarHighlight = false, alertGlowStyle = 6,
    alertSoundKey = "NONE",
    tsmEnabled = false, tsmPriceSource = "DBMarket", tsmReplaceVendor = false,
    externalPriceSource = "NONE",
    tsmAlertThreshold = 10000000, tsmThresholdDefaultApplied = false,
    alertR = 1, alertG = .65, alertB = .1,
    showItems = true, showCurrencies = true, showReputation = true,
    showHonor = true, showExperience = true, showGold = true,
    mergeWindow = 1.0,
    position = { point = "RIGHT", relPoint = "RIGHT", x = -160, y = 80 },
} }

local db, holder, eventFrame
local rows, active = {}, {}
local bagState, currencyState, factionState = {}, {}, {}
local pendingItems = {}
local lastMoney, lastXP, initialized = 0, 0, false
local unlockActive = false
local previewTicker, previewActive
local TrimActive

local function Profile() return db and db.profile end
local function CopyDefaults(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then dst[k] = type(v) == "table" and CopyDefaults({}, v) or v end
    end
    return dst
end

local function QualityColor(quality)
    local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    return c and c.hex or "|cffffffff"
end

local function FormatMoney(copper)
    local gold = floor(copper / 10000)
    local silver = floor((copper % 10000) / 100)
    local coin = copper % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = format("%d|cffffd700g|r", gold) end
    if silver > 0 or gold > 0 then parts[#parts + 1] = format("%d|cffc7c7cfs|r", silver) end
    parts[#parts + 1] = format("%d|cffeda55fc|r", coin)
    return table.concat(parts, " ")
end

local BIND_LABELS = {
    [1] = "BoP", [2] = "BoE", [3] = "BoU", [4] = "Quest",
    [5] = "BoA", [6] = "BoA", [7] = "WuE", [8] = "WuE",
}

local function EnsureHolder()
    if holder then return holder end
    holder = CreateFrame("Frame", "EllesmereUINotificationsFrame", UIParent)
    holder:SetPoint("RIGHT", UIParent, "RIGHT", -160, 80)
    holder:SetClampedToScreen(true)
    holder:Hide()
    return holder
end

local function ResolveFont(p)
    if p.fontName and p.fontName ~= "__global" then
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        local path = LSM and LSM:Fetch("font", p.fontName, true)
        if path then return path end
    end
    return (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

local function ApplyFontStyle(fontString, path, size, style)
    local shadow = style == "SHADOW" or style == "OUTLINE_SHADOW"
    local flags = style == "THICKOUTLINE" and "THICKOUTLINE"
        or ((style == "OUTLINE" or style == "OUTLINE_SHADOW") and "OUTLINE" or "")
    fontString:SetFont(path, size, flags)
    fontString:SetShadowOffset(shadow and 1 or 0, shadow and -1 or 0)
    fontString:SetShadowColor(0, 0, 0, shadow and .9 or 0)
end

local function EffectiveRowHeight(p,hasSecondLine)
    local iconSize=max(26,p.iconSize or 28)
    -- Reserve the two-line text block for every row so one- and two-line
    -- notifications always share exactly the same bar and icon dimensions.
    local textHeight=(p.fontSize or 14)+(p.valueFontSize or 12)+12
    return max(iconSize,textHeight)
end

local function ExternalPrice(itemInfo,p)
    if not itemInfo then return nil end
    local selected=p.externalPriceSource or "NONE"
    local provider,source=selected:match("^([^:]+):(.+)$")
    if provider=="TSM4" and TSM_API then
        local aliases={marketprice="DBMarket",minbuyout="DBMinBuyout",dbmarket="DBMarket",dbminbuyout="DBMinBuyout"}
        source=aliases[(source or "DBMarket"):lower()] or source
        local ok,itemString=pcall(TSM_API.ToItemString,itemInfo)
        if not ok or not itemString then return nil end
        local okPrice,value=pcall(TSM_API.GetCustomPriceValue,source,itemString)
        value=okPrice and tonumber(value) or nil
        if not value or value<=0 then
            local itemID=tonumber(tostring(itemInfo):match("item:(%d+)")) or tonumber(tostring(itemString):match("i:(%d+)"))
            if itemID then
                okPrice,value=pcall(TSM_API.GetCustomPriceValue,source,"i:"..itemID)
                value=okPrice and tonumber(value) or nil
            end
        end
        return value and value>0 and value or nil
    elseif provider=="AUCTIONATOR" and Auctionator and Auctionator.API and Auctionator.API.v1 then
        local api=Auctionator.API.v1
        local itemID=tonumber(tostring(itemInfo):match("item:(%d+)")) or tonumber(itemInfo)
        local ok,value
        if api.GetAuctionPriceByItemLink and type(itemInfo)=="string" and itemInfo:find("item:",1,true) then
            ok,value=pcall(api.GetAuctionPriceByItemLink,ADDON_NAME,itemInfo)
        end
        if (not ok or not value or value<=0) and itemID and api.GetAuctionPriceByItemID then
            ok,value=pcall(api.GetAuctionPriceByItemID,ADDON_NAME,itemID)
        end
        value=ok and tonumber(value) or nil
        return value and value>0 and value or nil
    end
    return nil
end

local function FindAlertRule(itemID, quality, bindType, p, itemLink, reagentQuality, tsmPrice)
    local matched=(p.externalPriceSource or "NONE")~="NONE" and (p.tsmAlertThreshold or 0)>0 and tsmPrice and tsmPrice>=p.tsmAlertThreshold
    if not matched and p.alertsEnabled then
        matched=p.alertEpicBoE and quality and quality >= 4 and bindType == 2
    end
    if not matched and p.alertsEnabled then
        matched = p.alertEpicWarbound and quality and quality >= 4
            and bindType and bindType >= 7 and bindType <= 8
    end
    if not matched and p.alertsEnabled and itemID and p.alertItemIDs and p.alertItemIDs ~= "" then
        local wanted = tonumber(itemID)
        for token in p.alertItemIDs:gmatch("%d+") do
            if tonumber(token) == wanted then
                local variant=p.alertItemVariants and (p.alertItemVariants[wanted] or p.alertItemVariants[tostring(wanted)])
                if not variant then
                    matched=true
                else
                    local current=itemLink and itemLink:match("(item:[^|]+)")
                    matched=current and current==variant
                end
                local requiredQuality=p.alertItemReagentQualities and
                    (p.alertItemReagentQualities[wanted] or p.alertItemReagentQualities[tostring(wanted)])
                if matched and requiredQuality then matched=tonumber(reagentQuality)==tonumber(requiredQuality) end
                break
            end
        end
    end
    if not matched then return nil end
    return {
        glow = p.alertGlow ~= false,
        notificationHighlight = p.alertBarHighlight == true,
        glowStyle = p.alertGlowStyle or 6,
        sound = p.alertSoundKey and p.alertSoundKey ~= "NONE",
        soundKey = p.alertSoundKey,
    }
end

local function PlayAlertSound(soundKey)
    if not soundKey then return end
    local builtin = soundKey:match("^builtin:(.+)$")
    if not builtin and not soundKey:find(":",1,true) then builtin=soundKey end
    if builtin then
        local sounds = {
            RAID_WARNING = SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959,
            READY_CHECK = SOUNDKIT and SOUNDKIT.READY_CHECK or 8960,
            QUEST_COMPLETE = SOUNDKIT and SOUNDKIT.UI_QUEST_COMPLETE or 619,
            LEVEL_UP = SOUNDKIT and SOUNDKIT.LEVEL_UP or 888,
        }
        PlaySound(sounds[builtin] or sounds.RAID_WARNING, "Master")
        return
    end
    local mediaName = soundKey:match("^lsm:(.+)$")
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local path = mediaName and LSM and LSM:Fetch("sound", mediaName, true)
    if path then PlaySoundFile(path, "Master") end
end
ns.PlayAlertSound = PlayAlertSound

local function Layout()
    local p = Profile(); if not p then return end
    local alignment = p.alignment == "RIGHT" and "RIGHT" or "LEFT"
    local iconMode = p.displayStyle == "ICON"
    local fontPath = ResolveFont(p)
    local separateConfigured = iconMode or (p.showIcons and p.iconPartOfBar == false)
    local rowSpacing=max(5,p.spacing or 5)
    local maxWidth,totalHeight=p.width or 310,0
    for i,row in ipairs(active) do
        local height=EffectiveRowHeight(p,row.hasValue==true)
        totalHeight=totalHeight+height+(i>1 and rowSpacing or 0)
        maxWidth=max(maxWidth,(p.width or 310)+(separateConfigured and (height+max(5,p.iconOffsetX or 5)) or 0))
    end
    EnsureHolder()
    local fixedX = alignment == "RIGHT" and holder:GetRight() or holder:GetLeft()
    local fixedY = p.growUp and holder:GetBottom() or holder:GetTop()
    holder:SetSize(maxWidth,max(1,totalHeight))
    holder:SetScale(1)
    if fixedX and fixedY then
        local uiLeft,uiBottom=UIParent:GetLeft() or 0,UIParent:GetBottom() or 0
        local uiTop=UIParent:GetTop() or UIParent:GetHeight()
        holder:ClearAllPoints()
        if alignment=="RIGHT" and p.growUp then
            local x=fixedX-(UIParent:GetRight() or UIParent:GetWidth())
            holder:SetPoint("BOTTOMRIGHT",UIParent,"BOTTOMRIGHT",x,fixedY-uiBottom)
            p.position={point="BOTTOMRIGHT",relPoint="BOTTOMRIGHT",x=x,y=fixedY-uiBottom}
        elseif alignment=="RIGHT" then
            local x=fixedX-(UIParent:GetRight() or UIParent:GetWidth())
            holder:SetPoint("TOPRIGHT",UIParent,"TOPRIGHT",x,fixedY-uiTop)
            p.position={point="TOPRIGHT",relPoint="TOPRIGHT",x=x,y=fixedY-uiTop}
        elseif p.growUp then
            local x=fixedX-uiLeft
            holder:SetPoint("BOTTOMLEFT",UIParent,"BOTTOMLEFT",x,fixedY-uiBottom)
            p.position={point="BOTTOMLEFT",relPoint="BOTTOMLEFT",x=x,y=fixedY-uiBottom}
        else
            local x=fixedX-uiLeft
            holder:SetPoint("TOPLEFT",UIParent,"TOPLEFT",x,fixedY-uiTop)
            p.position={point="TOPLEFT",relPoint="TOPLEFT",x=x,y=fixedY-uiTop}
        end
    end
    local stackOffset=0
    for i, row in ipairs(active) do
        local rowHeight=EffectiveRowHeight(p,row.hasValue==true)
        local barHeight=rowHeight
        local rowWidth=(p.width or 310)+(separateConfigured and (rowHeight+max(5,p.iconOffsetX or 5)) or 0)
        row:ClearAllPoints()
        if p.growUp then
            local point=alignment=="RIGHT" and "BOTTOMRIGHT" or "BOTTOMLEFT"
            row:SetPoint(point, holder, point, 0, stackOffset)
            row.basePoint, row.baseY = point, stackOffset
        else
            local point=alignment=="RIGHT" and "TOPRIGHT" or "TOPLEFT"
            row:SetPoint(point, holder, point, 0, -stackOffset)
            row.basePoint, row.baseY = point, -stackOffset
        end
        row:SetSize(rowWidth, rowHeight)
        stackOffset=stackOffset+rowHeight+rowSpacing
        local showRowIcon = (iconMode or p.showIcons) and row.iconPath ~= nil
        local iconRight = alignment == "RIGHT"
        local separateIcon = (iconMode or (p.showIcons and p.iconPartOfBar == false)) and row.iconPath
        local iconGap = max(5, p.iconOffsetX or 5)
        row.icon:SetSize(rowHeight, rowHeight)
        row.icon:SetShown(showRowIcon)
        row.divider:Hide()
        if not iconMode and p.showIcons and p.iconPartOfBar ~= false
            and p.showIconDivider and row.iconPath then
            row.divider:ClearAllPoints()
            row.divider:SetWidth(1)
            row.divider:SetColorTexture(0, 0, 0, 1)
            if iconRight then
                row.divider:SetPoint("TOP", row.icon, "TOPLEFT", 0, 0)
                row.divider:SetPoint("BOTTOM", row.icon, "BOTTOMLEFT", 0, 0)
            else
                row.divider:SetPoint("TOP", row.icon, "TOPRIGHT", 0, 0)
                row.divider:SetPoint("BOTTOM", row.icon, "BOTTOMRIGHT", 0, 0)
            end
            row.divider:Show()
        end
        row.qualityBadge:Hide()
        if showRowIcon and row.reagentQuality then
            local ok = pcall(row.qualityBadge.SetAtlas, row.qualityBadge,
                "Professions-Icon-Quality-Tier" .. tostring(row.reagentQualityAtlasTier or row.reagentQuality) .. "-Small", false)
            if ok then
                local badgeSize = math.min(20, math.max(9, rowHeight * .42))
                row.qualityBadge:SetSize(badgeSize, badgeSize)
                row.qualityBadge:ClearAllPoints()
                row.qualityBadge:SetPoint("TOPRIGHT", row.icon, "TOPRIGHT", 2, 2)
                row.qualityBadge:Show()
            end
        end
        row.icon:ClearAllPoints()
        if iconRight then row.icon:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        else row.icon:SetPoint("LEFT", row, "LEFT", 0, 0) end
        row.bg:ClearAllPoints()
        row.bg:SetHeight(barHeight)
        if separateIcon then
            if iconRight then
                row.bg:SetPoint("LEFT", row, "LEFT", 0, 0)
                row.bg:SetPoint("RIGHT", row.icon, "LEFT", -iconGap, 0)
            else
                row.bg:SetPoint("LEFT", row.icon, "RIGHT", iconGap, 0)
                row.bg:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            end
        else
            row.bg:SetPoint("LEFT",row,"LEFT",0,0); row.bg:SetPoint("RIGHT",row,"RIGHT",0,0)
        end
        if iconMode then
            row.bg:SetColorTexture(0, 0, 0, 0)
        else
            local barPath
            if p.barTexture and p.barTexture ~= "__solid" then
                local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
                barPath = LSM and LSM:Fetch("statusbar", p.barTexture, true)
            end
            if barPath then
                row.bg:SetTexture(barPath)
                row.bg:SetVertexColor(p.barR or .035, p.barG or .035, p.barB or .035, p.backgroundAlpha or .72)
            else
                row.bg:SetColorTexture(p.barR or .035, p.barG or .035, p.barB or .035, p.backgroundAlpha or .72)
            end
        end
        -- Configured icon size is a minimum; the icon grows with a taller two-line bar.
        ApplyFontStyle(row.text, fontPath, p.fontSize or 14, p.fontStyle or "OUTLINE_SHADOW")
        ApplyFontStyle(row.value, fontPath, p.valueFontSize or 12, p.fontStyle or "OUTLINE_SHADOW")
        row.text:ClearAllPoints()
        row.value:ClearAllPoints()
        local mainY=row.hasValue and (((p.valueFontSize or 12)+2)/2) or 0
        local valueY=-(((p.fontSize or 14)+2)/2)
        if separateIcon and not iconRight then
            row.text:SetPoint("LEFT", row.bg, "LEFT", 8, mainY)
            row.value:SetPoint("LEFT", row.bg, "LEFT", 8, valueY)
        elseif showRowIcon and not iconRight then
            row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, mainY)
            row.value:SetPoint("LEFT", row.icon, "RIGHT", 8, valueY)
        elseif showRowIcon and iconRight then
            row.text:SetPoint("LEFT", row, "LEFT", 10, mainY)
            row.value:SetPoint("LEFT", row, "LEFT", 10, valueY)
        else
            row.text:SetPoint("LEFT", row, "LEFT", 10, mainY)
            row.value:SetPoint("LEFT", row, "LEFT", 10, valueY)
        end
        if separateIcon and iconRight then
            row.text:SetPoint("RIGHT", row.bg, "RIGHT", -8, 0)
            row.value:SetPoint("RIGHT", row.bg, "RIGHT", -8, 0)
        elseif showRowIcon and iconRight then
            row.text:SetPoint("RIGHT", row.icon, "LEFT", -8, 0)
            row.value:SetPoint("RIGHT", row.icon, "LEFT", -8, 0)
        else
            row.text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            row.value:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        end
        row.text:Show()
        row.text:SetJustifyH(iconRight and "RIGHT" or "LEFT")
        row.value:SetJustifyH(iconRight and "RIGHT" or "LEFT")
        row.value:SetShown(row.hasValue == true)
        row.count:Hide()

        row.barBorder:ClearAllPoints(); row.barBorder:SetAllPoints(row.bg)
        row.iconBorder:ClearAllPoints(); row.iconBorder:SetAllPoints(row.icon)
        local alertRule = row.alertRule
        row.alertGlow:ClearAllPoints()
        row.alertGlow:SetAllPoints(row.icon)
        row.notificationGlow:ClearAllPoints(); row.notificationGlow:SetAllPoints(row)
        local size, tex = p.borderSize or 0, p.borderTexture or "solid"
        local r, g, b, a = p.borderR or 0, p.borderG or 0, p.borderB or 0, p.borderA or 1
        local borderLevel = p.borderBehind and max(0, row:GetFrameLevel() - 1) or row:GetFrameLevel() + 5
        row.barBorder:SetFrameLevel(borderLevel); row.iconBorder:SetFrameLevel(borderLevel)
        row.barBorder:SetShown(not iconMode and size > 0)
        row.iconBorder:SetShown((iconMode or separateIcon) and size > 0)
        EllesmereUI.ApplyBorderStyle(row.barBorder, not iconMode and size or 0, r, g, b, a, tex, p.borderOffsetX, p.borderOffsetY)
        EllesmereUI.ApplyBorderStyle(row.iconBorder, (iconMode or separateIcon) and size or 0, r, g, b, a, tex, p.borderOffsetX, p.borderOffsetY)
        local glowStyle = alertRule and (alertRule.glowStyle or 6) or 6
        if glowStyle~=1 and glowStyle~=2 and glowStyle~=6 then glowStyle=6 end
        local glowW = row.icon:GetWidth() or rowHeight
        local glowH = row.icon:GetHeight() or rowHeight
        local glowKey = tostring(glowStyle) .. ":" .. tostring(glowW) .. ":" .. tostring(glowH)
        if alertRule and alertRule.glow and EllesmereUI.Glows then
            row.alertGlow:Show()
            if row._alertGlowKey ~= glowKey then
                EllesmereUI.Glows.StartGlow(row.alertGlow, glowStyle, glowW,
                    p.alertR or 1, p.alertG or .65, p.alertB or .1, nil, glowH)
                row._alertGlowKey = glowKey
            end
        elseif row._alertGlowKey and EllesmereUI.Glows then
            EllesmereUI.Glows.StopGlow(row.alertGlow); row._alertGlowKey = nil
            row.alertGlow:Hide()
        else
            row.alertGlow:Hide()
        end
        local notificationKey=tostring(row:GetWidth())..":"..tostring(rowHeight)
        if alertRule and alertRule.notificationHighlight and EllesmereUI.Glows then
            row.notificationGlow:Show()
            if row._notificationGlowKey~=notificationKey then
                EllesmereUI.Glows.StartGlow(row.notificationGlow,4,row:GetWidth(),
                    p.alertR or 1,p.alertG or .65,p.alertB or .1,nil,rowHeight)
                row._notificationGlowKey=notificationKey
            end
        elseif row._notificationGlowKey and EllesmereUI.Glows then
            EllesmereUI.Glows.StopGlow(row.notificationGlow); row._notificationGlowKey=nil; row.notificationGlow:Hide()
        else row.notificationGlow:Hide() end
    end
    holder:SetShown(unlockActive or #active > 0)
end

local function AcquireRow()
    local row = table.remove(rows)
    if row then return row end
    row = CreateFrame("Frame", nil, EnsureHolder())
    row:EnableMouse(true)
    row.bg = row:CreateTexture(nil, "BACKGROUND"); row.bg:SetAllPoints()
    row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetTexCoord(.07, .93, .07, .93)
    row.qualityBadge = row:CreateTexture(nil, "OVERLAY")
    row.divider = row:CreateTexture(nil, "OVERLAY")
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    local fontPath = STANDARD_TEXT_FONT
    if (not fontPath or fontPath == "") and GameFontNormal then
        fontPath = GameFontNormal:GetFont()
    end
    row.text:SetFont(fontPath or "Fonts\\FRIZQT__.TTF", (Profile() and Profile().fontSize) or 14, "OUTLINE")
    row.text:SetJustifyH("LEFT"); row.text:SetWordWrap(false)
    row.value = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.value:SetFont(fontPath or "Fonts\\FRIZQT__.TTF", (Profile() and Profile().valueFontSize) or 12, "OUTLINE")
    row.value:SetJustifyH("LEFT"); row.value:SetTextColor(.82, .82, .82)
    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.count:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -1, 1)
    row.count:SetFont(fontPath or "Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    row.count:SetTextColor(1, 1, 1)
    row.barBorder = CreateFrame("Frame", nil, row); row.barBorder:SetFrameLevel(row:GetFrameLevel() + 5)
    row.iconBorder = CreateFrame("Frame", nil, row); row.iconBorder:SetFrameLevel(row:GetFrameLevel() + 5)
    row.alertGlow = CreateFrame("Frame", nil, row); row.alertGlow:SetFrameLevel(row:GetFrameLevel() + 12); row.alertGlow:EnableMouse(false)
    row.notificationGlow = CreateFrame("Frame", nil, row); row.notificationGlow:SetFrameLevel(row:GetFrameLevel() + 11); row.notificationGlow:EnableMouse(false)
    row:SetScript("OnEnter", function(self)
        local p = Profile()
        if not p or not p.showTooltip or not self.itemLink then return end
        self.hovered = true
        self.pausedRemaining = self.expires and max(.05, self.expires - GetTime()) or p.duration
        self.enterStarted = nil; self:SetAlpha(1); self:SetScale(1); Layout()
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
        GameTooltip:SetHyperlink(self.itemLink)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        if not self.hovered then return end
        self.hovered = nil
        self.expires = GetTime() + (self.pausedRemaining or (Profile() and Profile().duration) or 5)
        self.pausedRemaining = nil
        GameTooltip:Hide()
        if TrimActive then TrimActive() end
    end)
    return row
end

local function RemoveRow(row)
    for i, candidate in ipairs(active) do
        if candidate == row then table.remove(active, i); break end
    end
    if row.hovered then GameTooltip:Hide() end
    if row._alertGlowKey and EllesmereUI.Glows then EllesmereUI.Glows.StopGlow(row.alertGlow) end
    if row._notificationGlowKey and EllesmereUI.Glows then EllesmereUI.Glows.StopGlow(row.notificationGlow) end
    row._alertGlowKey, row._notificationGlowKey, row.alertRule = nil, nil, nil
    row.hovered, row.pausedRemaining = nil, nil
    row:Hide(); row:SetScript("OnUpdate", nil); row:SetAlpha(1); row:SetScale(1)
    rows[#rows + 1] = row; Layout()
end

TrimActive = function()
    local p = Profile(); if not p then return end
    while #active > p.maxVisible do
        local removeIndex
        for i = #active, 1, -1 do
            if not active[i].hovered then removeIndex = i; break end
        end
        if not removeIndex then break end
        RemoveRow(active[removeIndex])
    end
end

local function AnimateRow(row, style, progress, entering)
    local eased = 1 - (1 - progress) * (1 - progress) * (1 - progress)
    local alpha, scale, shiftX, shiftY = 1, 1, 0, 0
    if style == "FADE" then
        alpha = progress
    elseif style == "SLIDE" then
        alpha = progress
        local direction = Profile().alignment == "RIGHT" and 1 or -1
        shiftX = direction * 24 * (1 - eased)
    elseif style == "SLIDE_LEFT" or style == "SLIDE_RIGHT"
        or style == "SLIDE_TOP" or style == "SLIDE_BOTTOM" then
        alpha = .25 + .75 * progress
        local isVertical = style == "SLIDE_TOP" or style == "SLIDE_BOTTOM"
        local distance = isVertical and max(28, row:GetHeight() or 28) or 36
        local direction = entering and -1 or 1
        if style == "SLIDE_LEFT" then shiftX = -distance * direction * (1 - eased)
        elseif style == "SLIDE_RIGHT" then shiftX = distance * direction * (1 - eased)
        elseif style == "SLIDE_TOP" then shiftY = distance * direction * (1 - eased)
        else shiftY = -distance * direction * (1 - eased) end
    elseif style == "ZOOM_IN" then
        alpha = .35 + .65 * progress
        scale = .78 + .22 * eased
    elseif style == "ZOOM_OUT" then
        alpha = .35 + .65 * progress
        scale = 1.22 - .22 * eased
    elseif style == "SCALE" then
        alpha = progress
        scale = .72 + .28 * eased
    elseif style == "POP" then
        alpha = progress
        if entering then
            scale = 1 + math.sin(progress * math.pi) * .12 - (1 - progress) * .18
        else
            scale = 1 + (1 - progress) * .18
        end
    end
    row:SetAlpha(alpha); row:SetScale(scale)
    if row.basePoint then
        row:ClearAllPoints()
        row:SetPoint(row.basePoint, holder, row.basePoint, shiftX, (row.baseY or 0) + shiftY)
    end
end

local function ResetRowAnimation(row)
    row:SetAlpha(1); row:SetScale(1)
    if row.basePoint then
        row:ClearAllPoints()
        row:SetPoint(row.basePoint, holder, row.basePoint, 0, row.baseY or 0)
    end
end

local function ArmFade(row, isNew)
    local p = Profile(); if not p then return end
    row.expires = GetTime() + p.duration
    if row.hovered then row.pausedRemaining = p.duration end
    if isNew then row.enterStarted = GetTime() end
    if not isNew then row.enterStarted = nil; ResetRowAnimation(row) end
    row:SetScript("OnUpdate", function(self)
        if self.hovered then return end
        local now = GetTime()
        local enterDuration = max(.01, p.enterDuration or .2)
        local exitDuration = max(.01, p.exitDuration or 1.2)
        if self.enterStarted then
            local progress = (now - self.enterStarted) / enterDuration
            if progress < 1 then
                AnimateRow(self, p.enterAnimation or "SLIDE", max(0, progress), true)
                return
            end
            self.enterStarted = nil; ResetRowAnimation(self)
        end
        local remain = self.expires - now
        if remain <= 0 then RemoveRow(self)
        elseif remain < exitDuration then
            AnimateRow(self, p.exitAnimation or "FADE", remain / exitDuration, false)
        else ResetRowAnimation(self) end
    end)
end

local function Push(kind, key, amount, label, icon, quality, reagentQuality, sellPrice, bindType, itemLink)
    local p = Profile(); if not p or not p.enabled or not amount or amount <= 0 then return end
    local now = GetTime()
    local tsmPrice=kind=="item" and (bindType==nil or bindType==0 or bindType==2) and ExternalPrice(itemLink or key,p) or nil
    local mergeRow
    if kind == "item" then
        local currentVariant=itemLink and itemLink:match("(item:[^|]+)")
        -- Only the most recently displayed item is eligible, but it remains
        -- eligible for as long as its row exists. Repeated individual loot
        -- events therefore become x2, x3, ... instead of duplicate rows.
        for _, candidate in ipairs(active) do
            if candidate.kind == "item" then
                if candidate.itemKey == key and candidate.reagentQuality == reagentQuality
                    and candidate.itemVariant == currentVariant then mergeRow = candidate end
                break
            end
        end
    else
        for _, candidate in ipairs(active) do
            if candidate.mergeKey == kind .. ":" .. tostring(key)
                and now - (candidate.updated or 0) <= p.mergeWindow then
                mergeRow = candidate; break
            end
        end
    end
    if mergeRow then
        mergeRow.amount = mergeRow.amount + amount; mergeRow.updated = now
        if kind == "item" then mergeRow.alertRule = FindAlertRule(key, quality, bindType, p, itemLink, reagentQuality, tsmPrice) end
        mergeRow.text:SetText(mergeRow.formatter(mergeRow.amount))
        if mergeRow.valueFormatter then mergeRow.value:SetText(mergeRow.valueFormatter(mergeRow.amount)) end
        ArmFade(mergeRow, false); Layout(); return
    end
    local row = AcquireRow()
    row.mergeKey, row.amount, row.updated = kind .. ":" .. tostring(key), amount, now
    row.kind, row.itemKey, row.reagentQuality = kind, kind == "item" and key or nil, reagentQuality
    row.itemVariant=kind=="item" and itemLink and itemLink:match("(item:[^|]+)") or nil
    row.reagentQualityAtlasTier=reagentQuality
    if reagentQuality==2 and itemLink then
        local expansionID=select(15,C_Item.GetItemInfo(itemLink))
        local midnightID=_G.LE_EXPANSION_MIDNIGHT or 11
        if expansionID and expansionID>=midnightID then row.reagentQualityAtlasTier=3 end
    end
    row.alertRule = kind == "item" and FindAlertRule(key, quality, bindType, p, itemLink, reagentQuality, tsmPrice) or nil
    row.itemLink = kind == "item" and itemLink or nil
    row.iconPath = icon; row.icon:SetTexture(icon)
    if kind == "item" then
        local binding = BIND_LABELS[bindType]
        if binding then label = label .. " |cffb8b8b8(" .. binding .. ")|r" end
        row.formatter = function(n)
            local qty = n > 1 and (" |cffffffffx" .. n .. "|r") or ""
            local rank = p.showItemQuality and reagentQuality
                and (" |cff60d9ff[Quality " .. reagentQuality .. "]|r") or ""
            return (p.showItemQuality and QualityColor(quality) or "|cffffffff") .. label .. "|r" .. rank .. qty
        end
        local hasVendor=p.showItemValue and sellPrice and sellPrice>0
        row.hasValue = hasVendor or tsmPrice~=nil
        row.valueFormatter = row.hasValue and function(n)
            local function PriceText(prefix,unitPrice)
                if not unitPrice then return nil end
                local text=prefix..": "..FormatMoney(unitPrice)
                if n>1 then text=text.." ("..FormatMoney(unitPrice*n)..")" end
                return text
            end
            local ah=PriceText("AH",tsmPrice)
            if p.tsmReplaceVendor and ah then return ah end
            local vendor=hasVendor and PriceText("Vendor",sellPrice)
            return vendor and ah and (vendor.."  |  "..ah) or vendor or ah or ""
        end or nil
    else
        if type(label)=="table" then
            row.formatter=label.main; row.hasValue=true
            row.valueFormatter=function() return label.sub or "" end
        else
            row.formatter = label
            row.hasValue, row.valueFormatter = false, nil
        end
    end
    row.text:SetText(row.formatter(amount)); row:SetAlpha(1); row:Show()
    row.value:SetText(row.valueFormatter and row.valueFormatter(amount) or "")
    table.insert(active, 1, row)
    TrimActive()
    Layout(); ArmFade(row, true)
    if row.alertRule and row.alertRule.sound then PlayAlertSound(row.alertRule.soundKey) end
end

local function ReagentQuality(itemInfo)
    if not C_TradeSkillUI or not C_TradeSkillUI.GetItemReagentQualityByItemInfo then return nil end
    local ok, value = pcall(C_TradeSkillUI.GetItemReagentQualityByItemInfo, tostring(itemInfo))
    return ok and value or nil
end

local function NotifyItem(itemID, amount)
    local name, itemLink, quality, _, _, _, _, _, _, icon, sellPrice, _, _, bindType = C_Item.GetItemInfo(itemID)
    if not name then
        pendingItems[itemID] = (pendingItems[itemID] or 0) + amount
        return
    end
    Push("item", itemID, amount, name, icon, quality, ReagentQuality(itemLink or itemID), sellPrice, bindType, itemLink)
end

local function ScanBags(notify)
    local nextState = {}
    for bag = 0, NUM_BAG_SLOTS do
        local slots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, slots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then nextState[info.itemID] = (nextState[info.itemID] or 0) + (info.stackCount or 1) end
        end
    end
    if notify and Profile().showItems then
        for itemID, count in pairs(nextState) do
            local delta = count - (bagState[itemID] or 0)
            if delta > 0 then
                NotifyItem(itemID, delta)
            end
        end
    end
    bagState = nextState
end

local function ScanCurrencies(notify)
    if not C_CurrencyInfo or not C_CurrencyInfo.GetCurrencyListSize then return end
    local nextState = {}
    for i = 1, C_CurrencyInfo.GetCurrencyListSize() do
        local info = C_CurrencyInfo.GetCurrencyListInfo(i)
        if info and not info.isHeader and info.currencyID then
            nextState[info.currencyID] = info.quantity or 0
            local delta = (info.quantity or 0) - (currencyState[info.currencyID] or 0)
            if notify and delta > 0 then
                if info.currencyID == 1792 and Profile().showHonor then
                    Push("honor", 1792, delta, function(n) return "+" .. n .. " Honor" end, info.iconFileID)
                elseif Profile().showCurrencies then
                    Push("currency", info.currencyID, delta, function(n) return info.name .. (n > 1 and (" x" .. n) or "") end, info.iconFileID)
                end
            end
        end
    end
    currencyState = nextState
end

local function ScanFactions(notify)
    local nextState = {}
    local count = C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetNumFactions() or GetNumFactions()
    for i = 1, count do
        local name, earned, isHeader, hasRep, factionID
        if C_Reputation and C_Reputation.GetFactionDataByIndex then
            local data = C_Reputation.GetFactionDataByIndex(i)
            if data then
                name, earned, isHeader, hasRep, factionID = data.name, data.currentStanding,
                    data.isHeader, data.hasRep, data.factionID
            end
        else
            local legacy = { GetFactionInfo(i) }
            name, earned, isHeader, hasRep, factionID = legacy[1], legacy[6], legacy[9], legacy[11], legacy[14]
        end
        if name and not isHeader and (hasRep or earned) and factionID then
            nextState[factionID] = earned or 0
            local delta = (earned or 0) - (factionState[factionID] or earned or 0)
            if notify and delta > 0 and Profile().showReputation then
                Push("reputation", factionID, delta, {main=function(n) return "+"..n.." "..EllesmereUI.L("Reputation") end,sub="["..name.."]"}, 236681)
            end
        end
    end
    factionState = nextState
end

local function InitializeSnapshots()
    ScanBags(false); ScanCurrencies(false); ScanFactions(false)
    lastMoney = GetMoney() or 0; lastXP = UnitXP("player") or 0; initialized = true
end

local function ApplyPosition()
    local p = Profile(); if not p then return end
    EnsureHolder():ClearAllPoints()
    local pos = p.position
    local x=pos and pos.x; if x==nil then x=-160 end
    local y=pos and pos.y; if y==nil then y=80 end
    holder:SetPoint(pos and pos.point or "RIGHT",UIParent,pos and pos.relPoint or "RIGHT",x,y)
end

function ns.Apply()
    local p = Profile()
    if p and not p.showTooltip then
        for _, row in ipairs(active) do
            if row.hovered then
                row.hovered, row.pausedRemaining = nil, nil
                row.expires = GetTime() + p.duration
            end
        end
        GameTooltip:Hide()
        if TrimActive then TrimActive() end
    end
    Layout(); ApplyPosition()
end
_G._EN_Apply = ns.Apply

local previewSamples = {
    function() Push("item", "preview-rare-alert", 1, "Rare BoE Alert Test", 135274, 3, nil, 182504, 2) end,
    function() Push("item", "preview-epic-alert", 1, "Epic BoE Alert Test", 133738, 4, nil, 425000, 2) end,
    function() Push("item", "preview-warbound-alert", 1, "Epic Warbound Alert Test", 4630437, 4, nil, 425000, 7) end,
    function() Push("item", "preview-reagent", math.random(1, 5), "Tempered Alloy", 4622299, 2, 3, 4875, nil) end,
    function() Push("currency", "preview-currency", math.random(8, 45), function(n) return "Valorstones x" .. n end, 5868902) end,
    function() Push("reputation", "preview-rep", math.random(25, 100), {main=function(n) return "+"..n.." "..EllesmereUI.L("Reputation") end,sub="["..EllesmereUI.L("The Assembly").."]"}, 236681) end,
    function() Push("honor", "preview-honor", math.random(20, 90), function(n) return "+" .. n .. " Honor" end, 1455894) end,
    function() Push("xp", "preview-xp", math.random(250, 900), function(n) return "+" .. n .. " Experience" end, 894556) end,
    function() Push("money", "preview-money", math.random(25000, 950000), function(n) return FormatMoney(n) end, 133784) end,
}

function ns.IsPreviewActive() return previewActive == true end
function ns.SetPreview(activePreview)
    previewActive = activePreview == true
    if previewTicker then previewTicker:Cancel(); previewTicker = nil end
    if not previewActive then return end
    local function AddPreview()
        previewSamples[math.random(1, #previewSamples)]()
    end
    -- Seed the Epic BoE sample so the single alert condition can be tested
    -- immediately from preview mode.
    previewSamples[2](); previewSamples[3](); AddPreview()
    previewTicker = C_Timer.NewTicker(0.9, function()
        if not previewActive then return end
        AddPreview()
    end)
end

eventFrame = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "CHAT_MSG_LOOT", "CURRENCY_DISPLAY_UPDATE", "UPDATE_FACTION", "PLAYER_MONEY", "PLAYER_XP_UPDATE", "GET_ITEM_INFO_RECEIVED" }) do eventFrame:RegisterEvent(event) end
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then C_Timer.After(1, InitializeSnapshots); return end
    if not initialized or not Profile() or not Profile().enabled then return end
    if event == "GET_ITEM_INFO_RECEIVED" then
        local itemID, success = ...
        local amount = success and pendingItems[itemID]
        if amount then pendingItems[itemID] = nil; NotifyItem(itemID, amount) end
    elseif event == "CHAT_MSG_LOOT" then
        local message = ...
        local senderGUID = select(12, ...)
        if not senderGUID or senderGUID == "" or senderGUID == UnitGUID("player") then
            local itemID = message and tonumber(message:match("|Hitem:(%d+)"))
            if itemID and Profile().showItems then
                local amount = tonumber(message:match("|h|r%s*[xX](%d+)")) or 1
                NotifyItem(itemID, amount)
            end
        end
    elseif event == "BAG_UPDATE_DELAYED" then ScanBags(false)
    elseif event == "CURRENCY_DISPLAY_UPDATE" then
        local currencyID, newQuantity, quantityChanged = ...
        local info = currencyID and C_CurrencyInfo.GetCurrencyInfo(currencyID)
        if info and quantityChanged and quantityChanged > 0 then
            currencyState[currencyID] = newQuantity or info.quantity or 0
            if currencyID == 1792 and Profile().showHonor then
                Push("honor", currencyID, quantityChanged, function(n) return "+" .. n .. " Honor" end, info.iconFileID)
            elseif Profile().showCurrencies then
                Push("currency", currencyID, quantityChanged, function(n) return info.name .. (n > 1 and (" x" .. n) or "") end, info.iconFileID)
            end
        else
            ScanCurrencies(true)
        end
    elseif event == "UPDATE_FACTION" then ScanFactions(true)
    elseif event == "PLAYER_MONEY" then
        local money = GetMoney() or 0; local delta = money - lastMoney; lastMoney = money
        if delta > 0 and Profile().showGold then Push("money", 0, delta, function(n) return FormatMoney(n) end, 133784) end
    elseif event == "PLAYER_XP_UPDATE" then
        local xp = UnitXP("player") or 0; local delta = xp - lastXP
        if delta < 0 then delta = xp end; lastXP = xp
        if delta > 0 and Profile().showExperience then Push("xp", 0, delta, function(n) return "+" .. n .. " Experience" end, 894556) end
    end
end)

function EN:OnInitialize()
    db = EllesmereUI.Lite.NewDB("EllesmereUINotificationsDB", DB_DEFAULTS)
    CopyDefaults(db.profile, DB_DEFAULTS.profile)
    if db.profile.externalPriceSource=="NONE" and db.profile.tsmEnabled then
        db.profile.externalPriceSource="TSM4:"..(db.profile.tsmPriceSource or "DBMarket")
    end
    if not db.profile.tsmThresholdDefaultApplied then
        if not db.profile.tsmAlertThreshold or db.profile.tsmAlertThreshold==0 then db.profile.tsmAlertThreshold=10000000 end
        db.profile.tsmThresholdDefaultApplied=true
    end
    _G._EN_AceDB = db
end

function EN:OnEnable()
    EnsureHolder(); ApplyPosition(); Layout()
    if EllesmereUI.RegisterUnlockModeListener then
        EllesmereUI:RegisterUnlockModeListener("EN_Notifications", function(activeMode)
            unlockActive = activeMode == true; Layout()
        end)
    end
    if EllesmereUI.RegisterUnlockElements and EllesmereUI.MakeUnlockElement then
        EllesmereUI:RegisterUnlockElements({ EllesmereUI.MakeUnlockElement({
            key="EN_Notifications", label="Notifications", group="QoL", order=540,
            noResize=true, getFrame=function() return EnsureHolder() end,
            getSize=function()
                local p=Profile(); local h=EffectiveRowHeight(p,true)
                local separate=p.displayStyle=="ICON" or (p.showIcons and p.iconPartOfBar==false)
                local w=(p.width or 310)+(separate and (h+max(5,p.iconOffsetX or 5)) or 0)
                local spacing=max(5,p.spacing or 5)
                return w,p.maxVisible*(h+spacing)-spacing
            end,
            isHidden=function() return false end,
            savePos=function(_, point, relPoint, x, y) Profile().position={point=point,relPoint=relPoint,x=x,y=y} end,
            loadPos=function() return Profile().position end,
            clearPos=function() Profile().position=nil end,
            applyPos=ApplyPosition,
        }) }, "EllesmereUINotifications")
    end
end
