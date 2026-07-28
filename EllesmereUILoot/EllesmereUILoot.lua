-------------------------------------------------------------------------------
-- EllesmereUILoot.lua - loot feed and tracking module
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EN = EllesmereUI.Lite.NewAddon(ADDON_NAME)

local floor, max = math.floor, math.max
local format = string.format
local BAR_TEXTURE_BASE="Interface\\AddOns\\EllesmereUI\\media\\textures\\"
local BAR_TEXTURES={
    ["__solid"]=nil,
    ["melli"]=BAR_TEXTURE_BASE.."melli.tga", ["atrocity"]=BAR_TEXTURE_BASE.."atrocity.tga",
    ["fade-left"]=BAR_TEXTURE_BASE.."fade.tga", ["fade-right"]=BAR_TEXTURE_BASE.."fade-right.tga",
    ["thin-line-top"]=BAR_TEXTURE_BASE.."thin-line-top.tga", ["thin-line-bottom"]=BAR_TEXTURE_BASE.."thin-line-bottom.tga",
    ["beautiful"]=BAR_TEXTURE_BASE.."beautiful.tga", ["plating"]=BAR_TEXTURE_BASE.."plating.tga",
    ["divide"]=BAR_TEXTURE_BASE.."divide.tga", ["glass"]=BAR_TEXTURE_BASE.."glass.tga",
    ["gradient-lr"]=BAR_TEXTURE_BASE.."gradient-lr.tga", ["gradient-rl"]=BAR_TEXTURE_BASE.."gradient-rl.tga",
    ["gradient-bt"]=BAR_TEXTURE_BASE.."gradient-bt.tga", ["gradient-tb"]=BAR_TEXTURE_BASE.."gradient-tb.tga",
    ["matte"]=BAR_TEXTURE_BASE.."matte.tga", ["sheer"]=BAR_TEXTURE_BASE.."sheer.tga",
    ["blinkii-diamonds"]=BAR_TEXTURE_BASE.."blinkii-diamonds.tga", ["kringel-window"]=BAR_TEXTURE_BASE.."kringel-window.tga",
}
local BAR_TEXTURE_ORDER={"__solid","melli","atrocity","fade-left","fade-right","thin-line-top","thin-line-bottom",
    "beautiful","plating","divide","glass","gradient-lr","gradient-rl","gradient-bt","gradient-tb","matte","sheer",
    "blinkii-diamonds","kringel-window"}
local BAR_TEXTURE_NAMES={
    ["__solid"]="Solid",melli="Melli (ElvUI)",atrocity="Atrocity",["fade-left"]="Fade Left",["fade-right"]="Fade Right",
    ["thin-line-top"]="Thin Line Top",["thin-line-bottom"]="Thin Line Bottom",beautiful="Beautiful",plating="Plating",
    divide="Divide",glass="Glass",["gradient-lr"]="Gradient Right",["gradient-rl"]="Gradient Left",
    ["gradient-bt"]="Gradient Up",["gradient-tb"]="Gradient Down",matte="Matte",sheer="Sheer",
    ["blinkii-diamonds"]="Blinkii Diamonds",["kringel-window"]="Kringel Window",
}
ns.notificationBarTextures=BAR_TEXTURES
ns.notificationBarTextureOrder=BAR_TEXTURE_ORDER
ns.notificationBarTextureNames=BAR_TEXTURE_NAMES

-- Same lifecycle as Damage Meters: bundled textures form the stable base
-- catalog, while LibSharedMedia entries are discovered at runtime (including
-- media registered later by other addons). Unlike Damage Meters, Loot can be
-- toggled off internally, so its SharedMedia consumer is detached again to
-- preserve the module's Zero Cost contract.
local sharedMediaAttached=false
local function AttachBarSharedMedia()
    if sharedMediaAttached or not EllesmereUI.AppendSharedMediaTextures then return end
    EllesmereUI.AppendSharedMediaTextures(BAR_TEXTURE_NAMES,BAR_TEXTURE_ORDER,nil,BAR_TEXTURES)

    -- Reattaching after a disable may reuse an order table that already owns
    -- its separator. Tell the shared helper so a late media registration does
    -- not append a second separator.
    local consumer=EllesmereUI._smTexConsumers and EllesmereUI._smTexConsumers[BAR_TEXTURES]
    if not consumer then return end
    sharedMediaAttached=true
    if not consumer.sepAdded then
        for _,key in ipairs(BAR_TEXTURE_ORDER) do
            if key=="---" then consumer.sepAdded=true; break end
        end
    end
end

local function DetachBarSharedMedia()
    if not sharedMediaAttached then return end
    if EllesmereUI._smTexConsumers then EllesmereUI._smTexConsumers[BAR_TEXTURES]=nil end
    sharedMediaAttached=false
end

ns.AttachNotificationBarSharedMedia=AttachBarSharedMedia
local DB_DEFAULTS = { profile = {
    -- Feed behavior and geometry
    enabled = true, duration = 5, maxVisible = 6,
    enterAnimation = "SLIDE_LEFT", exitAnimation = "FADE",
    enterDuration = 0.2, exitDuration = 1.0,
    width = 340, spacing = 5, alignment = "LEFT",
    fontSize = 16, valueFontSize = 14, innerPaddingX = 10, innerPaddingY = 5,
    iconSize = 44, backgroundAlpha = .3,
    growMode = "UP",
    showItemValue = false, showTooltip = true,
    displayStyle = "BAR", borderTexture = "solid", borderSize = 0,
    borderR = 0, borderG = 0, borderB = 0, borderA = 1,
    borderOffsetX = 0, borderOffsetY = 0, borderBehind = false,
    fontName = "__global", fontStyle = "OUTLINE_SHADOW",
    barTexture = "gradient-lr", barR = 0.035, barG = 0.035, barB = 0.035,
    experienceBarR = .48, experienceBarG = .22, experienceBarB = .82,
    honorBarR = .75, honorBarG = .18, honorBarB = .22,
    currencyBarR = 0, currencyBarG = 0, currencyBarB = 0,
    iconPartOfBar = true, iconOffsetX = 5,
    -- Alerts
    alertsEnabled = false, alertEpicBoE = true, alertEpicWarbound = true, alertCustomItems = false,
    alertItemIDs = "", alertItemVariants = {}, alertItemReagentQualities = {},
    alertGlow = true, alertGlowStyle = 6,
    alertSoundEnabled = false, alertSoundKey = "NONE",
    -- External prices
    externalPriceSource = "NONE", showMarketValue = true,
    showTotalLootValue = false, showStackTotalValue = true,
    showPriceLabels = false,
    externalPriceAlertEnabled = false,
    totalValueFontName = "__global", totalValueFontSize = 14,
    totalValueFontStyle = "OUTLINE_SHADOW",
    totalValueDuration = 2,
    totalValueOffsetX = 0, totalValueOffsetY = 0,
    totalValueR = 1, totalValueG = .82, totalValueB = .2,
    tsmAlertThreshold = 10000000,
    alertR = 1, alertG = .65, alertB = .1,
    -- Per-notification visibility and contextual background colors
    showItems = true, showCurrencies = true, showReputation = true,
    showHonor = true, showExperience = true, showGold = true,
    colorItemBackgroundByQuality = true, colorExperienceBar = true,
    colorHonorBar = true, colorCurrencyBar = true, colorReputationBar = true,
    mergeWindow = 1.0,
    position = { point = "CENTER", relPoint = "CENTER", x = 440, y = 40 },
} }

-- Runtime state is kept outside SavedVariables. Rows are pooled instead of
-- recreated for every loot event to avoid garbage spikes during mass looting.
-- Heavy runtime objects are lazy: holder, eventFrame and animationDriver stay
-- nil when the feed starts disabled, so the off state owns no hidden frames.
local db, holder, eventFrame
local rows, active = {}, {}
local currencyState, factionState = {}, {}
local currencyScratch, factionScratch = {}, {}
local pendingItems = {}
local lastMoney, lastXP, initialized = 0, 0, false
local unlockActive = false
local previewTicker, previewActive
local snapshotTimer
local TrimActive
local animationDriver, StartAnimationDriver
-- Replaces per-frame polling during a row's static hold time. It wakes the
-- animation driver only when the next exit/fade animation must begin.
local animationWakeTimer
-- `runtimeEnabled` is the single source of truth for every background path.
-- Forward declarations let settings changes reach the lifecycle code without
-- exposing internal implementation functions globally.
local runtimeEnabled = false
local SetRuntimeEnabled
local SetRuntimeEvent
local ConfigureRuntimeEvents
local RegisterUnlockIntegration
local unlockIntegrationRegistered = false
local nextCenteredSide=1

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

-- One formatter serves both live rows and the settings preview. Keeping value
-- labels short leaves more width for prices, while the muted labels and dot
-- separator create hierarchy without adding more frames or textures.
local function FormatItemValueLine(p,amount,vendorUnitValue,marketUnitValue)
    amount=amount or 1
    local showTotal=amount>1 and p.showStackTotalValue~=false
    local function Part(label,unitValue)
        if not unitValue or unitValue<=0 then return nil end
        local text=(p.showPriceLabels and ("|cff9ca3af"..label.."|r ") or "")..FormatMoney(unitValue)
        if showTotal then text=text.." |cff8a919c("..FormatMoney(unitValue*amount)..")|r" end
        return text
    end

    local market=p.showMarketValue~=false and Part(EllesmereUI.L("AH"),marketUnitValue) or nil
    local vendor=p.showItemValue and Part(EllesmereUI.L("Vendor"),vendorUnitValue) or nil
    if vendor and market then return vendor.."  |cff68707c•|r  "..market end
    return vendor or market or ""
end

local BIND_LABELS = {
    [1] = "BoP", [2] = "BoE", [3] = "BoU", [4] = "Quest",
    [5] = "BoA", [6] = "BoA", [7] = "WuE", [8] = "WuE",
}

-- The client supplies profession quality as the visual rank. Midnight still
-- uses ranks 1/2, but its rank artwork is silver/gold instead of the older
-- bronze/silver/gold palette. Do not shift the rank: doing so turns Midnight
-- rank 1 into the two-stone rank-2 icon.
local function ReagentQualityAtlasTier(quality)
    return tonumber(quality)
end
ns.GetReagentQualityAtlasTier=ReagentQualityAtlasTier

-- Midnight has its own one-star/two-star artwork. Ask the client for the
-- atlas belonging to the concrete item instead of deriving an old atlas name
-- from its numeric rank. The fallback keeps the module compatible with older
-- clients where GetItemReagentQualityInfo is not available yet.
local function ReagentQualityAtlas(itemInfo,quality)
    if itemInfo and C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityInfo then
        local ok,info=pcall(C_TradeSkillUI.GetItemReagentQualityInfo,itemInfo)
        if ok and info then
            return info.iconSmall or info.iconInventory or info.icon
        end
    end
    local tier=ReagentQualityAtlasTier(quality)
    return tier and ("Professions-Icon-Quality-Tier"..tier.."-Small") or nil
end
ns.GetReagentQualityAtlas=ReagentQualityAtlas

local function EnsureHolder()
    if holder then return holder end
    holder = CreateFrame("Frame", "EllesmereUILootFrame", UIParent)
    holder:SetPoint("CENTER", UIParent, "CENTER", 380, 80)
    holder:SetClampedToScreen(true)
    holder.totalValueFrame=CreateFrame("Frame",nil,UIParent)
    holder.totalValueFrame:SetSize(310,20)
    holder.totalValueFrame:SetPoint("TOP",holder,"BOTTOM",0,-8)
    holder.totalValue=holder.totalValueFrame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    holder.totalValue:SetPoint("CENTER")
    holder.totalValue:SetTextColor(1,.82,.2)
    holder.totalValueFrame:Hide()
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
    if fontString._elFontPath==path and fontString._elFontSize==size
        and fontString._elFontFlags==flags and fontString._elFontShadow==shadow then return end
    fontString._elFontPath,fontString._elFontSize=path,size
    fontString._elFontFlags,fontString._elFontShadow=flags,shadow
    fontString:SetFont(path, size, flags)
    fontString:SetShadowOffset(shadow and 1 or 0, shadow and -1 or 0)
    fontString:SetShadowColor(0, 0, 0, shadow and .9 or 0)
end

local function RequestedIconSize(p)
    return max(30,math.min(80,tonumber(p.iconSize) or 44))
end

local function UniformRowHeight(p)
    -- Bar mode reserves the two-line text block and lets vertical padding set
    -- both bar height and its attached icon size. Icon mode has no bar interior,
    -- so padding must not leak into geometry. The row still honors the text
    -- block's minimum height to prevent two-line notifications from overlapping.
    local textHeight=(p.fontSize or 14)+(p.valueFontSize or 12)+4
    if p.displayStyle=="ICON" then
        return max(textHeight,RequestedIconSize(p))
    end
    return max(26,textHeight+max(5,math.min(15,p.innerPaddingY or 5))*2)
end

local function VisualIconSize(p,rowHeight)
    return p.displayStyle=="ICON" and RequestedIconSize(p) or (rowHeight or UniformRowHeight(p))
end

local function HorizontalTextPadding(p)
    -- Horizontal padding remains useful in both modes: in Icon mode it acts as
    -- the configurable gap between the symbol and its text block.
    return max(5,math.min(15,p.innerPaddingX or 5))
end

-- These helpers are shared by the live feed and the settings preview. Keeping
-- presentation decisions in one place prevents both render paths from slowly
-- drifting apart as new notification types or media sources are added.
local function ResolveBarTexture(textureKey)
    if not textureKey or textureKey=="__solid" then return nil end
    local path=EllesmereUI.ResolveTexturePath and EllesmereUI.ResolveTexturePath(BAR_TEXTURES,textureKey)
    if path then return path end
    local LSM=LibStub and LibStub("LibSharedMedia-3.0",true)
    return LSM and LSM:Fetch("statusbar",textureKey,true) or nil
end

local function ResolveBackgroundColor(p,kind,quality,customColor)
    local r,g,b=p.barR or .035,p.barG or .035,p.barB or .035
    kind=kind and kind:lower() or ""
    if kind=="experience" then kind="xp" end
    if kind=="item" and p.colorItemBackgroundByQuality and quality then
        local color=ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
        if color then return color.r,color.g,color.b end
    elseif kind=="xp" and p.colorExperienceBar then
        return p.experienceBarR or .48,p.experienceBarG or .22,p.experienceBarB or .82
    elseif kind=="honor" and p.colorHonorBar then
        return p.honorBarR or .75,p.honorBarG or .18,p.honorBarB or .22
    elseif kind=="currency" and p.colorCurrencyBar then
        return p.currencyBarR or 0,p.currencyBarG or 0,p.currencyBarB or 0
    elseif kind=="reputation" and p.colorReputationBar and customColor then
        return customColor[1],customColor[2],customColor[3]
    end
    return r,g,b
end

local function ResolveTotalValueFont(p,fallback)
    if p.totalValueFontName and p.totalValueFontName~="__global" then
        local LSM=LibStub and LibStub("LibSharedMedia-3.0",true)
        return (LSM and LSM:Fetch("font",p.totalValueFontName,true)) or fallback
    end
    return fallback
end

local TOTAL_VALUE_OFFSET_MAX=30
local function TotalValueOffsets(p)
    return math.min(TOTAL_VALUE_OFFSET_MAX,max(0,p.totalValueOffsetX or 0)),
        math.min(TOTAL_VALUE_OFFSET_MAX,max(0,p.totalValueOffsetY or 0))
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
    local matched=p.alertsEnabled and p.externalPriceAlertEnabled and (p.externalPriceSource or "NONE")~="NONE"
        and (p.tsmAlertThreshold or 0)>0 and tsmPrice and tsmPrice>=p.tsmAlertThreshold
    if not matched and p.alertsEnabled then
        matched=p.alertEpicBoE and quality and quality >= 4 and bindType == 2
    end
    if not matched and p.alertsEnabled then
        matched = p.alertEpicWarbound and quality and quality >= 4
            and bindType and bindType >= 7 and bindType <= 8
    end
    if not matched and p.alertsEnabled and p.alertCustomItems and itemID then
        local wanted = tonumber(itemID)
        local customMatch=false
        if p.alertItemIDs and p.alertItemIDs~="" then
            for token in p.alertItemIDs:gmatch("%d+") do
                if tonumber(token)==wanted then customMatch=true; break end
            end
        end
        if customMatch then
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
        end
    end
    if not matched then return nil end
    return {
        glow = p.alertGlow ~= false,
        glowStyle = p.alertGlowStyle or 6,
        sound = p.alertSoundEnabled==true and p.alertSoundKey and p.alertSoundKey ~= "NONE",
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

local function UpdateTotalValueFade(self)
    local now=GetTime()
    if now<(self._fadeStarted or now) then self:SetAlpha(1); return end
    local duration=max(.2,(Profile() and Profile().exitDuration) or 1)
    local progress=(now-(self._fadeStarted or now))/duration
    if progress>=1 then
        self._fadeStarted,self._holdUntil=nil,nil
        self:SetAlpha(1); self:Hide()
    else
        self:SetAlpha(1-progress)
    end
end

local function ApplyBorderStyleCached(frame,size,r,g,b,a,texture,offsetX,offsetY)
    -- Border construction is relatively expensive. Cache the complete input
    -- tuple on the frame and skip EllesmereUI.ApplyBorderStyle when a normal
    -- layout pass would only reapply identical appearance data.
    offsetX,offsetY=offsetX or 0,offsetY or 0
    if frame._elBorderSize==size and frame._elBorderR==r and frame._elBorderG==g
        and frame._elBorderB==b and frame._elBorderA==a and frame._elBorderTexture==texture
        and frame._elBorderOffsetX==offsetX and frame._elBorderOffsetY==offsetY then return end
    frame._elBorderSize,frame._elBorderR,frame._elBorderG=size,r,g
    frame._elBorderB,frame._elBorderA,frame._elBorderTexture=b,a,texture
    frame._elBorderOffsetX,frame._elBorderOffsetY=offsetX,offsetY
    EllesmereUI.ApplyBorderStyle(frame,size,r,g,b,a,texture,offsetX,offsetY)
end

-- Layout is the single source of truth for both geometry and presentation of
-- live rows. Event handlers only update row data, then request a relayout.
local function Layout()
    local p = Profile(); if not p then return end
    local alignment = p.alignment == "RIGHT" and "RIGHT" or "LEFT"
    local growMode=p.growMode or "UP"
    local centered=growMode=="CENTER"
    local iconMode = p.displayStyle == "ICON"
    local fontPath = ResolveFont(p)
    -- Display style never alters bar geometry. Icon mode only suppresses the
    -- bar artwork/border; a detached icon is positioned outside this width.
    local rowSpacing=max(5,p.spacing or 5)
    local maxWidth,totalHeight=p.width or 310,0
    for i,row in ipairs(active) do
        local height=UniformRowHeight(p)
        totalHeight=totalHeight+height+(i>1 and rowSpacing or 0)
        maxWidth=max(maxWidth,p.width or 310)
    end
    if centered and #active>0 then
        local upCount,downCount=0,0
        for _,row in ipairs(active) do
            if (row.centerSide or 1)>0 then upCount=upCount+1 else downCount=downCount+1 end
        end
        if #active==1 then
            totalHeight=UniformRowHeight(p)
        else
            local sideCount=max(upCount,downCount)
            local rowHeight=UniformRowHeight(p)
            totalHeight=sideCount*2*rowHeight+max(0,sideCount*2-1)*rowSpacing
        end
    end
    if unlockActive then
        local previewHeight=UniformRowHeight(p)
        if centered then
            local sideCount=math.ceil((p.maxVisible or 1)/2)
            totalHeight=max(totalHeight,sideCount*2*previewHeight+max(0,sideCount*2-1)*rowSpacing)
        else
            totalHeight=max(totalHeight,p.maxVisible*(previewHeight+rowSpacing)-rowSpacing)
        end
        maxWidth=max(maxWidth,p.width or 310)
    end
    EnsureHolder()
    local totalValue=0
    if p.enabled and p.showTotalLootValue and (p.externalPriceSource or "NONE")~="NONE" then
        for _,row in ipairs(active) do
            if row.externalUnitPrice then totalValue=totalValue+row.externalUnitPrice*(row.amount or 1) end
        end
    end
    local totalFrame=holder.totalValueFrame
    totalFrame:SetWidth(maxWidth)
    if #active>0 then
        local referenceRow=active[1]
        local hasIcon=referenceRow.iconPath~=nil
        if hasIcon then
            local iconExtent=VisualIconSize(p,UniformRowHeight(p))
            if p.iconPartOfBar==false then
                iconExtent=iconExtent+max(5,p.iconOffsetX or 5)
            end
            totalFrame._iconAlignOffset=iconExtent
        else
            totalFrame._iconAlignOffset=0
        end
    end
    local totalAlignOffset=totalFrame._iconAlignOffset or 0
    local totalFontPath=ResolveTotalValueFont(p,fontPath)
    ApplyFontStyle(holder.totalValue,totalFontPath,p.totalValueFontSize or 14,p.totalValueFontStyle or "OUTLINE_SHADOW")
    holder.totalValue:SetTextColor(p.totalValueR or 1,p.totalValueG or .82,p.totalValueB or .2)
    holder.totalValue:ClearAllPoints()
    local inwardX,downwardY=TotalValueOffsets(p)
    if p.alignment=="RIGHT" then
        holder.totalValue:SetPoint("RIGHT",totalFrame,"RIGHT",totalAlignOffset-inwardX,-downwardY)
        holder.totalValue:SetJustifyH("RIGHT")
    else
        holder.totalValue:SetPoint("LEFT",totalFrame,"LEFT",-totalAlignOffset+inwardX,-downwardY)
        holder.totalValue:SetJustifyH("LEFT")
    end
    if totalValue>0 then
        local totalMoney=FormatMoney(totalValue):gsub(" "," |cffffffff")
        holder.totalValue:SetText(EllesmereUI.L("Total loot value")..": |cffffffff"..totalMoney.."|r")
        totalFrame._fadeStarted=nil
        totalFrame._holdUntil=nil
        totalFrame:SetAlpha(1)
        totalFrame:Show()
    elseif not p.enabled or not p.showTotalLootValue or (p.externalPriceSource or "NONE")=="NONE" then
        totalFrame._fadeStarted=nil
        totalFrame._holdUntil=nil
        totalFrame:Hide()
    elseif #active>0 then
        -- Keep the last accumulated value visible for the lifetime of the
        -- notification batch, even if the remaining rows have no AH value.
        if totalFrame:IsShown() then
            totalFrame._fadeStarted=nil
            totalFrame:SetAlpha(1)
        end
    elseif totalFrame:IsShown() and not totalFrame._fadeStarted then
        totalFrame._holdUntil=GetTime()+max(0,p.totalValueDuration or 2)
        totalFrame._fadeStarted=totalFrame._holdUntil
        if StartAnimationDriver then StartAnimationDriver() end
    end
    local fixedX = alignment == "RIGHT" and holder:GetRight() or holder:GetLeft()
    local fixedY=centered and select(2,holder:GetCenter())
        or (growMode=="UP" and holder:GetBottom() or holder:GetTop())
    holder:SetSize(maxWidth,max(1,totalHeight))
    holder:SetScale(1)
    -- Never rewrite the holder anchor while Unlock Mode owns the frame.
    -- Incoming preview/loot rows call Layout repeatedly and would otherwise
    -- fight the drag handler, making the anchor jump beneath the cursor.
    if fixedX and fixedY and not unlockActive then
        local uiLeft,uiBottom=UIParent:GetLeft() or 0,UIParent:GetBottom() or 0
        local uiTop=UIParent:GetTop() or UIParent:GetHeight()
        holder:ClearAllPoints()
        if centered then
            local point=alignment=="RIGHT" and "RIGHT" or "LEFT"
            local x=fixedX-uiLeft
            holder:SetPoint(point,UIParent,"BOTTOMLEFT",x,fixedY-uiBottom)
            p.position={point=point,relPoint="BOTTOMLEFT",x=x,y=fixedY-uiBottom}
        elseif alignment=="RIGHT" and growMode=="UP" then
            local x=fixedX-(UIParent:GetRight() or UIParent:GetWidth())
            holder:SetPoint("BOTTOMRIGHT",UIParent,"BOTTOMRIGHT",x,fixedY-uiBottom)
            p.position={point="BOTTOMRIGHT",relPoint="BOTTOMRIGHT",x=x,y=fixedY-uiBottom}
        elseif alignment=="RIGHT" then
            local x=fixedX-(UIParent:GetRight() or UIParent:GetWidth())
            holder:SetPoint("TOPRIGHT",UIParent,"TOPRIGHT",x,fixedY-uiTop)
            p.position={point="TOPRIGHT",relPoint="TOPRIGHT",x=x,y=fixedY-uiTop}
        elseif growMode=="UP" then
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
    local centeredUpOffset=(UniformRowHeight(p)+rowSpacing)/2
    local centeredDownOffset=centeredUpOffset
    for i, row in ipairs(active) do
        local rowHeight=UniformRowHeight(p)
        local barHeight=rowHeight
        local rowWidth=p.width or 310
        row:ClearAllPoints()
        if centered then
            local point=alignment=="RIGHT" and "RIGHT" or "LEFT"
            local yOffset=0
            if #active>1 then
                if (row.centerSide or 1)>0 then
                    yOffset=centeredUpOffset
                    centeredUpOffset=centeredUpOffset+rowHeight+rowSpacing
                else
                    yOffset=-centeredDownOffset
                    centeredDownOffset=centeredDownOffset+rowHeight+rowSpacing
                end
            end
            row:SetPoint(point,holder,point,0,yOffset)
            row.basePoint,row.baseY=point,yOffset
        elseif growMode=="UP" then
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
        local showRowIcon = row.iconPath ~= nil
        local iconRight = alignment == "RIGHT"
        -- Display style only controls bar rendering; it must never alter icon
        -- geometry. The saved attachment state and gap therefore apply in
        -- both Bar and Icon mode.
        local separateIcon = p.iconPartOfBar == false and row.iconPath
        local iconGap = max(5, p.iconOffsetX or 5)
        local attachedIcon = showRowIcon and not separateIcon
        local visualIconSize=VisualIconSize(p,rowHeight)
        row.icon:SetSize(visualIconSize,visualIconSize)
        row.icon:SetShown(showRowIcon)
        row.icon:ClearAllPoints()
        local appliedGap=separateIcon and iconGap or 0
        if iconRight then row.icon:SetPoint("LEFT",row,"RIGHT",appliedGap,0)
        else row.icon:SetPoint("RIGHT",row,"LEFT",-appliedGap,0) end
        -- Keep the detached icon part of the row's tooltip hit area. Re-anchor
        -- after every layout pass so LEFT/RIGHT alignment changes are exact.
        row.iconHover:ClearAllPoints()
        row.iconHover:SetAllPoints(row.icon)
        row.iconHover:SetShown(showRowIcon)
        row.bg:ClearAllPoints()
        row.bg:SetHeight(barHeight)
        row.bg:SetPoint("LEFT",row,"LEFT",0,0); row.bg:SetPoint("RIGHT",row,"RIGHT",0,0)
        local barR,barG,barB=ResolveBackgroundColor(p,row.kind,row.itemQuality,row.customBarColor)
        if iconMode then
            row.bg:SetColorTexture(0, 0, 0, 0)
        else
            local barPath=ResolveBarTexture(p.barTexture)
            if barPath then
                row.bg:SetTexture(barPath)
                row.bg:SetVertexColor(barR,barG,barB,p.backgroundAlpha or 1)
            else
                row.bg:SetColorTexture(barR,barG,barB,p.backgroundAlpha or 1)
            end
        end
        -- Configured icon size is a minimum; the icon grows with a taller two-line bar.
        ApplyFontStyle(row.text, fontPath, p.fontSize or 14, p.fontStyle or "OUTLINE_SHADOW")
        ApplyFontStyle(row.value, fontPath, p.valueFontSize or 12, p.fontStyle or "OUTLINE_SHADOW")
        row.text:ClearAllPoints()
        row.value:ClearAllPoints()
        local lineGap=4
        local padX=HorizontalTextPadding(p)
        local mainY=row.hasValue and (((p.valueFontSize or 12)+lineGap)/2) or 0
        local valueY=-(((p.fontSize or 14)+lineGap)/2)
        if separateIcon and not iconRight then
            row.text:SetPoint("LEFT", row.bg, "LEFT", padX, mainY)
            row.value:SetPoint("LEFT", row.bg, "LEFT", padX, valueY)
        elseif showRowIcon and not iconRight then
            row.text:SetPoint("LEFT", row.icon, "RIGHT", padX, mainY)
            row.value:SetPoint("LEFT", row.icon, "RIGHT", padX, valueY)
        elseif showRowIcon and iconRight then
            row.text:SetPoint("LEFT", row, "LEFT", padX, mainY)
            row.value:SetPoint("LEFT", row, "LEFT", padX, valueY)
        else
            row.text:SetPoint("LEFT", row, "LEFT", padX, mainY)
            row.value:SetPoint("LEFT", row, "LEFT", padX, valueY)
        end
        if separateIcon and iconRight then
            row.text:SetPoint("RIGHT", row.bg, "RIGHT", -padX, 0)
            row.value:SetPoint("RIGHT", row.bg, "RIGHT", -padX, 0)
        elseif showRowIcon and iconRight then
            row.text:SetPoint("RIGHT", row.icon, "LEFT", -padX, 0)
            row.value:SetPoint("RIGHT", row.icon, "LEFT", -padX, 0)
        else
            row.text:SetPoint("RIGHT", row, "RIGHT", -padX, 0)
            row.value:SetPoint("RIGHT", row, "RIGHT", -padX, 0)
        end
        row.text:Show()
        row.text:SetJustifyH(iconRight and "RIGHT" or "LEFT")
        row.value:SetJustifyH(iconRight and "RIGHT" or "LEFT")
        row.value:SetShown(row.hasValue == true)

        row.barBorder:ClearAllPoints()
        if attachedIcon then
            if iconRight then
                row.barBorder:SetPoint("TOPLEFT",row,"TOPLEFT")
                row.barBorder:SetPoint("BOTTOMRIGHT",row.icon,"BOTTOMRIGHT")
            else
                row.barBorder:SetPoint("TOPLEFT",row.icon,"TOPLEFT")
                row.barBorder:SetPoint("BOTTOMRIGHT",row,"BOTTOMRIGHT")
            end
        else row.barBorder:SetAllPoints(row.bg) end
        row.iconBorder:ClearAllPoints(); row.iconBorder:SetAllPoints(row.icon)
        local alertRule = row.alertRule
        row.alertGlow:ClearAllPoints()
        row.alertGlow:SetAllPoints(row.icon)
        local size, tex = p.borderSize or 0, p.borderTexture or "solid"
        local r, g, b, a = p.borderR or 0, p.borderG or 0, p.borderB or 0, p.borderA or 1
        local borderLevel = p.borderBehind and max(0, row:GetFrameLevel() - 1) or row:GetFrameLevel() + 5
        row.barBorder:SetFrameLevel(borderLevel); row.iconBorder:SetFrameLevel(borderLevel)
        row.barBorder:SetShown(not iconMode and size > 0)
        row.iconBorder:SetShown((iconMode or separateIcon) and size > 0)
        ApplyBorderStyleCached(row.barBorder,not iconMode and size or 0,r,g,b,a,tex,p.borderOffsetX,p.borderOffsetY)
        ApplyBorderStyleCached(row.iconBorder,(iconMode or separateIcon) and size or 0,r,g,b,a,tex,p.borderOffsetX,p.borderOffsetY)
        local glowStyle = alertRule and (alertRule.glowStyle or 6) or 6
        if glowStyle~=1 and glowStyle~=2 and glowStyle~=6 then glowStyle=6 end
        if alertRule and alertRule.glow and EllesmereUI.Glows then
            local glowW=row.icon:GetWidth() or rowHeight
            local glowH=row.icon:GetHeight() or rowHeight
            local colorKey=format(":%.3f:%.3f:%.3f",p.alertR or 1,p.alertG or .65,p.alertB or .1)
            local glowKey=tostring(glowStyle)..":"..tostring(glowW)..":"..tostring(glowH)..colorKey
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
    end
    holder:SetShown(unlockActive or #active > 0)
end

local settingsPreview,settingsPreviewSecond,settingsPreviewTotal
local settingsPreviewKind="ITEM"
local settingsPreviewSecondKind="CURRENCY"
local settingsPreviewTextureOverride
local PREVIEW_KINDS={"ITEM","CURRENCY","HONOR","REPUTATION","EXPERIENCE","GOLD"}

-- Pick without replacement so both sample rows always demonstrate different
-- notification types.
function ns.ShuffleSettingsPreview()
    local first=math.random(1,#PREVIEW_KINDS)
    local second=math.random(1,#PREVIEW_KINDS-1)
    if second>=first then second=second+1 end
    settingsPreviewKind=PREVIEW_KINDS[first]
    settingsPreviewSecondKind=PREVIEW_KINDS[second]
    ns.RefreshSettingsPreview()
end
function ns.SetSettingsPreviewTextureOverride(texture)
    settingsPreviewTextureOverride=texture
    ns.RefreshSettingsPreview()
end
function ns.ClearSettingsPreviewTextureOverride()
    settingsPreviewTextureOverride=nil
    ns.RefreshSettingsPreview()
end
local function RefreshSettingsPreviewRow(row,previewKind,yOffset)
    local p=Profile(); if not row or not p then return end
    local iconMode=p.displayStyle=="ICON"
    local alignment=p.alignment=="RIGHT" and "RIGHT" or "LEFT"
    local iconRight=alignment=="RIGHT"
    local separateIcon=p.iconPartOfBar==false
    local sampleIcon,sampleText,sampleValue
    if previewKind=="CURRENCY" then sampleIcon,sampleText=5868902,"Valorstones x25"
    elseif previewKind=="HONOR" then sampleIcon,sampleText=1455894,"+74 Honor"
    elseif previewKind=="REPUTATION" then
        sampleIcon,sampleText,sampleValue=236681,"+250 "..EllesmereUI.L("Reputation"),"["..EllesmereUI.L("The Assembly").."]"
    elseif previewKind=="EXPERIENCE" then sampleIcon,sampleText=894556,"+850 Experience"
    elseif previewKind=="GOLD" then sampleIcon,sampleText=133784,FormatMoney(2545741)
    else
        previewKind="ITEM"
        sampleIcon=133738
        sampleText="|cffa335eeEpic Equipment|r |cffffffffx2|r"
    end
    if previewKind=="ITEM" then
        local marketValue=p.showMarketValue~=false and (p.externalPriceSource or "NONE")~="NONE" and 12500000 or nil
        sampleValue=FormatItemValueLine(p,2,425000,marketValue)
        if sampleValue=="" then sampleValue=nil end
    end
    local hasValue=sampleValue~=nil
    row.icon:SetTexture(sampleIcon); row.text:SetText(sampleText); row.value:SetText(sampleValue or "")
    local rowHeight=UniformRowHeight(p)
    local iconGap=max(5,p.iconOffsetX or 5)
    local attachedIcon=not separateIcon
    local rowWidth=p.width or 310
    local previewHasIcon=true
    local previewIconSize=VisualIconSize(p,rowHeight)
    local previewIconExtent=previewHasIcon and (previewIconSize+(separateIcon and iconGap or 0)) or 0
    row:ClearAllPoints()
    row:SetPoint("CENTER",row:GetParent(),"CENTER",iconRight and -previewIconExtent/2 or previewIconExtent/2,yOffset or 0)
    row:SetSize(rowWidth,rowHeight)
    row.icon:SetSize(previewIconSize,previewIconSize); row.icon:Show()
    row.icon:ClearAllPoints()
    local appliedGap=separateIcon and iconGap or 0
    if iconRight then row.icon:SetPoint("LEFT",row,"RIGHT",appliedGap,0)
    else row.icon:SetPoint("RIGHT",row,"LEFT",-appliedGap,0) end
    row.bg:ClearAllPoints(); row.bg:SetHeight(rowHeight)
    row.bg:SetPoint("LEFT"); row.bg:SetPoint("RIGHT")
    local previewBarTexture=settingsPreviewTextureOverride or p.barTexture
    local barPath=ResolveBarTexture(previewBarTexture)
    local previewQuality=previewKind=="ITEM" and 4 or nil
    local previewStanding=previewKind=="REPUTATION" and {.18,.72,.28} or nil
    local previewR,previewG,previewB=ResolveBackgroundColor(p,previewKind,previewQuality,previewStanding)
    if iconMode then row.bg:SetColorTexture(0,0,0,0)
    elseif barPath then row.bg:SetTexture(barPath); row.bg:SetVertexColor(previewR,previewG,previewB,p.backgroundAlpha or 1)
    else row.bg:SetColorTexture(previewR,previewG,previewB,p.backgroundAlpha or 1) end
    local fontPath=ResolveFont(p)
    ApplyFontStyle(row.text,fontPath,p.fontSize or 14,p.fontStyle or "OUTLINE_SHADOW")
    ApplyFontStyle(row.value,fontPath,p.valueFontSize or 12,p.fontStyle or "OUTLINE_SHADOW")
    row.text:ClearAllPoints(); row.value:ClearAllPoints()
    local lineGap=4
    local padX=HorizontalTextPadding(p)
    local mainY=hasValue and ((p.valueFontSize or 12)+lineGap)/2 or 0
    local valueY=-((p.fontSize or 14)+lineGap)/2
    local leftAnchor=separateIcon and row.bg or row.icon
    if iconRight then
        row.text:SetPoint("LEFT",row,"LEFT",padX,mainY); row.value:SetPoint("LEFT",row,"LEFT",padX,valueY)
        local rightBound=separateIcon and row.bg or row.icon
        local rightPoint=separateIcon and "RIGHT" or "LEFT"
        row.text:SetPoint("RIGHT",rightBound,rightPoint,-padX,0); row.value:SetPoint("RIGHT",rightBound,rightPoint,-padX,0)
    else
        local leftPoint=separateIcon and "LEFT" or (leftAnchor==row and "LEFT" or "RIGHT")
        local leftOffset=padX
        row.text:SetPoint("LEFT",leftAnchor,leftPoint,leftOffset,mainY)
        row.value:SetPoint("LEFT",leftAnchor,leftPoint,leftOffset,valueY)
        row.text:SetPoint("RIGHT",row,"RIGHT",-padX,0); row.value:SetPoint("RIGHT",row,"RIGHT",-padX,0)
    end
    row.text:SetJustifyH(iconRight and "RIGHT" or "LEFT"); row.value:SetJustifyH(iconRight and "RIGHT" or "LEFT")
    row.value:SetShown(hasValue)
    row.barBorder:ClearAllPoints()
    if attachedIcon then
        if iconRight then row.barBorder:SetPoint("TOPLEFT",row,"TOPLEFT"); row.barBorder:SetPoint("BOTTOMRIGHT",row.icon,"BOTTOMRIGHT")
        else row.barBorder:SetPoint("TOPLEFT",row.icon,"TOPLEFT"); row.barBorder:SetPoint("BOTTOMRIGHT",row,"BOTTOMRIGHT") end
    else row.barBorder:SetAllPoints(row.bg) end
    row.iconBorder:ClearAllPoints(); row.iconBorder:SetAllPoints(row.icon)
    local size=p.borderSize or 0; local r,g,b,a=p.borderR or 0,p.borderG or 0,p.borderB or 0,p.borderA or 1
    row.barBorder:SetShown(not iconMode and size>0); row.iconBorder:SetShown((iconMode or separateIcon) and size>0)
    ApplyBorderStyleCached(row.barBorder,not iconMode and size or 0,r,g,b,a,p.borderTexture or "solid",p.borderOffsetX,p.borderOffsetY)
    ApplyBorderStyleCached(row.iconBorder,(iconMode or separateIcon) and size or 0,r,g,b,a,p.borderTexture or "solid",p.borderOffsetX,p.borderOffsetY)
end

function ns.RefreshSettingsPreview()
    local p=Profile(); if not p or not settingsPreview then return end
    local previewStep=UniformRowHeight(p)+max(5,p.spacing or 5)
    RefreshSettingsPreviewRow(settingsPreview,settingsPreviewKind,previewStep/2)
    RefreshSettingsPreviewRow(settingsPreviewSecond,settingsPreviewSecondKind,-previewStep/2)
    if settingsPreviewTotal then
        local showTotal=p.showTotalLootValue==true and (p.externalPriceSource or "NONE")~="NONE"
        settingsPreviewTotal:SetShown(showTotal)
        if showTotal then
            local fontPath=ResolveTotalValueFont(p,ResolveFont(p))
            ApplyFontStyle(settingsPreviewTotal,fontPath,p.totalValueFontSize or 14,p.totalValueFontStyle or "OUTLINE_SHADOW")
            settingsPreviewTotal:SetTextColor(p.totalValueR or 1,p.totalValueG or .82,p.totalValueB or .2)
            settingsPreviewTotal:SetText(EllesmereUI.L("Total loot value")..": |cffffffff2,500g|r")
            settingsPreviewTotal:ClearAllPoints()
            local rowHeight=UniformRowHeight(p)
            local totalWidth=(p.width or 310)+VisualIconSize(p,rowHeight)+5
            local inwardX,downwardY=TotalValueOffsets(p)
            settingsPreviewTotal:SetWidth(max(1,totalWidth-inwardX))
            settingsPreviewTotal:SetPoint("TOP",settingsPreview:GetParent(),"CENTER",
                p.alignment=="RIGHT" and -inwardX/2 or inwardX/2,-previewStep-4-downwardY)
            settingsPreviewTotal:SetJustifyH(p.alignment=="RIGHT" and "RIGHT" or "LEFT")
        end
    end
end

function ns.CreateSettingsPreview(parent)
    -- The settings page can be rebuilt many times during one session. Reuse
    -- its three visual objects instead of leaving another pair of preview
    -- frames attached to every retired page container.
    if settingsPreview then
        settingsPreview:SetParent(parent)
        settingsPreviewSecond:SetParent(parent)
        settingsPreview:Show(); settingsPreviewSecond:Show()
        ns.RefreshSettingsPreview()
        return settingsPreview
    end
    local function CreatePreviewRow()
        local row=CreateFrame("Frame",nil,parent)
        row.bg=row:CreateTexture(nil,"BACKGROUND")
        row.icon=row:CreateTexture(nil,"ARTWORK")
        row.text=row:CreateFontString(nil,"OVERLAY")
        row.value=row:CreateFontString(nil,"OVERLAY")
        local p=Profile()
        local fontPath=p and ResolveFont(p) or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
        ApplyFontStyle(row.text,fontPath,p and p.fontSize or 14,p and p.fontStyle or "OUTLINE_SHADOW")
        ApplyFontStyle(row.value,fontPath,p and p.valueFontSize or 12,p and p.fontStyle or "OUTLINE_SHADOW")
        row.barBorder=CreateFrame("Frame",nil,row); row.iconBorder=CreateFrame("Frame",nil,row)
        return row
    end
    settingsPreview=CreatePreviewRow()
    settingsPreviewSecond=CreatePreviewRow()
    -- Parent the total label to the reusable first row so it follows that row
    -- when the options page is rebuilt and the preview is reparented.
    settingsPreviewTotal=settingsPreview:CreateFontString(nil,"OVERLAY")
    ns.RefreshSettingsPreview()
    return settingsPreview
end

local function HideTooltipOwnedBy(owner)
    -- An old row's deferred OnLeave may run after another row has already
    -- opened its tooltip. Never let that stale callback hide the tooltip now
    -- owned by the new row.
    if owner and GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end

local function AcquireRow()
    local row = table.remove(rows)
    if row then return row end
    row = CreateFrame("Frame", nil, EnsureHolder())
    row:EnableMouse(true)
    row.bg = row:CreateTexture(nil, "BACKGROUND"); row.bg:SetAllPoints()
    row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetTexCoord(.07, .93, .07, .93)
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
    row.barBorder = CreateFrame("Frame", nil, row); row.barBorder:SetFrameLevel(row:GetFrameLevel() + 5)
    row.iconBorder = CreateFrame("Frame", nil, row); row.iconBorder:SetFrameLevel(row:GetFrameLevel() + 5)
    row.iconHover = CreateFrame("Frame", nil, row)
    row.iconHover:SetAllPoints(row.icon)
    row.iconHover:SetFrameLevel(row:GetFrameLevel()+8)
    row.iconHover:EnableMouse(true)
    row.alertGlow = CreateFrame("Frame", nil, row); row.alertGlow:SetFrameLevel(row:GetFrameLevel() + 12); row.alertGlow:EnableMouse(false)

    local function BeginHover(self)
        local owner=self._lootFeedRow or self
        if owner._hoverLeaveTimer then owner._hoverLeaveTimer:Cancel(); owner._hoverLeaveTimer=nil end
        local p = Profile()
        if not p or not p.showTooltip or not owner.itemLink then return end
        if not owner.hovered then
            owner.hovered = true
            owner.pausedRemaining = owner.expires and max(.05, owner.expires - GetTime()) or p.duration
            owner.enterStarted = nil; owner:SetAlpha(1); owner:SetScale(1); Layout()
        end
        GameTooltip:SetOwner(owner, "ANCHOR_CURSOR_RIGHT")
        GameTooltip:SetHyperlink(owner.itemLink)
        GameTooltip:Show()
    end
    local function EndHover(self)
        local owner=self._lootFeedRow or self
        -- Moving between the detached icon and the bar fires OnLeave first.
        -- Defer one frame so both hit regions can be checked as one surface.
        if owner._hoverLeaveTimer then owner._hoverLeaveTimer:Cancel() end
        owner._hoverLeaveTimer=C_Timer.NewTimer(0,function()
            owner._hoverLeaveTimer=nil
            if not owner.hovered then return end
            if owner:IsMouseOver() or (owner.iconHover and owner.iconHover:IsMouseOver()) then return end
            owner.hovered = nil
            owner.expires = GetTime() + (owner.pausedRemaining or (Profile() and Profile().duration) or 5)
            owner.pausedRemaining = nil
            HideTooltipOwnedBy(owner)
            if TrimActive then TrimActive() end
            if StartAnimationDriver then StartAnimationDriver() end
        end)
    end
    row.iconHover._lootFeedRow=row
    row:SetScript("OnEnter",BeginHover); row:SetScript("OnLeave",EndHover)
    row.iconHover:SetScript("OnEnter",BeginHover); row.iconHover:SetScript("OnLeave",EndHover)
    return row
end

local function RemoveRow(row,deferLayout)
    for i, candidate in ipairs(active) do
        if candidate == row then table.remove(active, i); break end
    end
    -- A row can be recycled while a deferred leave from an older hover is
    -- pending. Only close the tooltip if this exact row still owns it.
    if row.hovered then HideTooltipOwnedBy(row) end
    if row._hoverLeaveTimer then row._hoverLeaveTimer:Cancel(); row._hoverLeaveTimer=nil end
    if row._alertGlowKey and EllesmereUI.Glows then EllesmereUI.Glows.StopGlow(row.alertGlow) end
    row._alertGlowKey, row.alertRule = nil, nil
    row.hovered, row.pausedRemaining, row.enterStarted, row.expires = nil, nil, nil, nil
    -- Drop loot-specific strings, closures and links while the visual row is
    -- idle in the pool. The frame itself remains reusable, but it no longer
    -- keeps item data (or external-price results) alive unnecessarily.
    row.formatter, row.valueFormatter = nil, nil
    row.itemLink, row.itemVariant, row.itemKey = nil, nil, nil
    row.reagentQuality, row.reagentQualityAtlas = nil, nil
    row.externalUnitPrice, row.iconPath, row.customBarColor = nil, nil, nil
    row.kind, row.mergeKey, row.amount, row.updated = nil, nil, nil, nil
    row.itemQuality, row.hasValue, row.centerSide = nil, nil, nil
    row.basePoint, row.baseY = nil, nil
    row.text:SetText(""); row.value:SetText("")
    row.icon:SetTexture(nil)
    row.iconHover:Hide()
    row:Hide(); row:SetScript("OnUpdate", nil); row:SetAlpha(1); row:SetScale(1)
    rows[#rows + 1] = row
    if not deferLayout then Layout() end
end

TrimActive = function(deferLayout)
    local p = Profile(); if not p then return end
    local removed=false
    while #active > p.maxVisible do
        local removeIndex
        -- Never discard the newest incoming notification merely because an
        -- older row is being held open by its tooltip.
        for i = #active, 2, -1 do
            if not active[i].hovered then removeIndex = i; break end
        end
        if not removeIndex then break end
        RemoveRow(active[removeIndex],true)
        removed=true
    end
    if removed and not deferLayout then Layout() end
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
    row._animationReset=false
    row:SetAlpha(alpha); row:SetScale(scale)
    if row.basePoint then
        row:ClearAllPoints()
        row:SetPoint(row.basePoint, holder, row.basePoint, shiftX, (row.baseY or 0) + shiftY)
    end
end

local function ResetRowAnimation(row)
    if row._animationReset then return end
    row:SetAlpha(1); row:SetScale(1)
    if row.basePoint then
        row:ClearAllPoints()
        row:SetPoint(row.basePoint, holder, row.basePoint, 0, row.baseY or 0)
    end
    row._animationReset=true
end

-- One shared update handler serves every pooled row. Keeping the current
-- profile lookup here avoids per-notification closures and stale profile
-- references after a profile/spec switch.
local function UpdateRowAnimation(self,now,p)
    if self.hovered then return false end
    local enterDuration=max(.01,p.enterDuration or .2)
    local exitDuration=max(.01,p.exitDuration or 1)
    if self.enterStarted then
        local progress=(now-self.enterStarted)/enterDuration
        if progress<1 then
            AnimateRow(self,p.enterAnimation or "SLIDE_LEFT",max(0,progress),true)
            return true
        end
        self.enterStarted=nil; ResetRowAnimation(self)
    end
    local remain=(self.expires or now)-now
    if remain<=0 then RemoveRow(self,true); return false,true
    elseif remain<exitDuration then
        AnimateRow(self,p.exitAnimation or "FADE",remain/exitDuration,false)
        return true
    else
        ResetRowAnimation(self)
    end
    return false
end

local function UpdateAnimations(self)
    local p=Profile()
    if not p then animationDriver:Hide(); return end
    local now=GetTime()
    local animating=false
    local removedAny=false
    -- Walk backwards because an expired row removes itself from `active`.
    for i=#active,1,-1 do
        local row=active[i]
        if row then
            local rowAnimating,rowRemoved=UpdateRowAnimation(row,now,p)
            if rowAnimating then animating=true end
            if rowRemoved then removedAny=true end
        end
    end
    if removedAny then Layout() end
    local totalFrame=holder and holder.totalValueFrame
    if totalFrame and totalFrame._fadeStarted then
        UpdateTotalValueFade(totalFrame)
        if totalFrame._fadeStarted and now>=totalFrame._fadeStarted then animating=true end
    end
    if animating then return end

    -- PERFORMANCE TRICK: entry/exit animations need per-frame interpolation,
    -- but a fully visible row does not change at all during its hold period.
    -- Hide OnUpdate completely and use one wake timer for the earliest row.
    -- This changes a five-second notification from hundreds of OnUpdate calls
    -- into animation frames plus a single timer callback.
    local wakeAt
    local exitDuration=max(.01,p.exitDuration or 1)
    for _,row in ipairs(active) do
        if not row.hovered and row.expires then
            local candidate=row.expires-exitDuration
            if not wakeAt or candidate<wakeAt then wakeAt=candidate end
        end
    end
    if totalFrame and totalFrame._fadeStarted
        and (not wakeAt or totalFrame._fadeStarted<wakeAt) then
        wakeAt=totalFrame._fadeStarted
    end
    self:Hide()
    if animationWakeTimer then animationWakeTimer:Cancel(); animationWakeTimer=nil end
    if wakeAt then
        animationWakeTimer=C_Timer.NewTimer(max(.01,wakeAt-now),function()
            animationWakeTimer=nil
            if runtimeEnabled and StartAnimationDriver then StartAnimationDriver() end
        end)
    end
end

StartAnimationDriver=function()
    if not runtimeEnabled then return end
    -- New/merged loot can move the next deadline. Cancel the old wake-up so
    -- only one scheduling primitive exists for the entire feed.
    if animationWakeTimer then animationWakeTimer:Cancel(); animationWakeTimer=nil end
    -- Lazy creation is important for Zero Cost: this frame never exists for a
    -- feed that has stayed disabled since login.
    if not animationDriver then
        animationDriver=CreateFrame("Frame")
        animationDriver:SetScript("OnUpdate",UpdateAnimations)
    end
    animationDriver:Show()
end

local function ArmFade(row, isNew)
    local p = Profile(); if not p then return end
    row.expires = GetTime() + p.duration
    if row.hovered then row.pausedRemaining = p.duration end
    if isNew then row.enterStarted = GetTime() end
    if not isNew then row.enterStarted = nil; ResetRowAnimation(row) end
    StartAnimationDriver()
end

-- Add or merge one logical reward. previewExternalPrice is intentionally the
-- only preview-specific input; all other preview behavior follows the same
-- path as real loot, including merging, alerts, animation, and total value.
local function Push(kind, key, amount, label, icon, quality, reagentQuality, sellPrice, bindType, itemLink, previewExternalPrice)
    local p = Profile(); if not p or not p.enabled or not amount or amount <= 0 then return end
    local now = GetTime()
    -- Simulated preview prices obey the same provider gate as real prices.
    -- This guarantees that Live Preview never advertises an AH value while
    -- "None" is selected on the External Price Source page.
    local hasExternalSource=(p.externalPriceSource or "NONE")~="NONE"
    -- Skip provider/API work entirely when the external value has no display,
    -- total-value or alert consumer.
    local needsExternalPrice=hasExternalSource and (p.showMarketValue~=false
        or p.showTotalLootValue==true or (p.alertsEnabled and p.externalPriceAlertEnabled))
    local tsmPrice=kind=="item" and needsExternalPrice and previewExternalPrice or nil
    if not tsmPrice then
        tsmPrice=kind=="item" and needsExternalPrice and (bindType==nil or bindType==0 or bindType==2)
            and ExternalPrice(itemLink or key,p) or nil
    end
    local mergeRow
    if kind == "item" then
        local currentVariant=itemLink and itemLink:match("(item:[^|]+)")
        -- Only the most recently displayed item is eligible. The configured
        -- merge window limits how long repeated loot becomes x2, x3, ...
        -- instead of a new notification.
        for _, candidate in ipairs(active) do
            if candidate.kind == "item" then
                if candidate.itemKey == key and candidate.reagentQuality == reagentQuality
                    and candidate.itemVariant == currentVariant
                    and now-(candidate.updated or 0)<=(p.mergeWindow or 1) then mergeRow = candidate end
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
        mergeRow.itemQuality=quality
        mergeRow.customBarColor=type(label)=="table" and label.barColor or mergeRow.customBarColor
        if tsmPrice then mergeRow.externalUnitPrice=tsmPrice end
        if kind == "item" then mergeRow.alertRule = FindAlertRule(key, quality, bindType, p, itemLink, reagentQuality, tsmPrice) end
        mergeRow.text:SetText(mergeRow.formatter(mergeRow.amount))
        if mergeRow.valueFormatter then mergeRow.value:SetText(mergeRow.valueFormatter(mergeRow.amount)) end
        ArmFade(mergeRow, false); Layout(); return
    end
    -- Recycle the oldest removable row before acquiring the new one. Under
    -- normal operation this keeps the frame pool at maxVisible rather than
    -- briefly allocating maxVisible+1 on every full batch.
    if #active>=p.maxVisible then
        for i=#active,1,-1 do
            if not active[i].hovered then RemoveRow(active[i],true); break end
        end
    end
    local row = AcquireRow()
    -- Centered mode keeps a stable side assignment for the lifetime of a row.
    -- New rows alternate sides; rows on the same side are pushed outward.
    row.centerSide=nextCenteredSide
    nextCenteredSide=-nextCenteredSide
    row.mergeKey, row.amount, row.updated = kind .. ":" .. tostring(key), amount, now
    row.kind, row.itemKey, row.reagentQuality = kind, kind == "item" and key or nil, reagentQuality
    row.itemQuality=quality
    row.customBarColor=type(label)=="table" and label.barColor or nil
    row.itemVariant=kind=="item" and itemLink and itemLink:match("(item:[^|]+)") or nil
    row.reagentQualityAtlas=ReagentQualityAtlas(itemLink or key,reagentQuality)
    row.alertRule = kind == "item" and FindAlertRule(key, quality, bindType, p, itemLink, reagentQuality, tsmPrice) or nil
    row.externalUnitPrice = kind == "item" and tsmPrice or nil
    row.itemLink = kind == "item" and itemLink or nil
    row.iconPath = icon; row.icon:SetTexture(icon)
    if kind == "item" then
        local binding = BIND_LABELS[bindType]
        if binding then label = label .. " |cffb8b8b8(" .. binding .. ")|r" end
        local qualityPrefix = ""
        if row.reagentQualityAtlas then
            local qualitySize = math.min(24, math.max(16, (p.fontSize or 14) + 4))
            qualityPrefix = format("|A:%s:%d:%d|a", row.reagentQualityAtlas, qualitySize, qualitySize)
        end
        row.formatter = function(n)
            local qty = n > 1 and (" |cffffffffx" .. n .. "|r") or ""
            -- Item names always use Blizzard's quality color. Keeping this
            -- unconditional avoids a profile branch in every row refresh.
            return qualityPrefix .. QualityColor(quality) .. label .. "|r" .. qty
        end
        local hasVendor=p.showItemValue and sellPrice and sellPrice>0
        local hasMarket=p.showMarketValue~=false and tsmPrice~=nil
        row.hasValue = hasVendor or hasMarket
        row.valueFormatter = row.hasValue and function(n)
            return FormatItemValueLine(p,n,hasVendor and sellPrice or nil,tsmPrice)
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
    TrimActive(true)
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
        -- Item cache misses are uncommon. Do not listen to the global
        -- GET_ITEM_INFO_RECEIVED stream permanently; register it only while
        -- at least one requested item is pending, then remove it immediately.
        pendingItems[itemID] = (pendingItems[itemID] or 0) + amount
        if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
        if runtimeEnabled and SetRuntimeEvent then SetRuntimeEvent("GET_ITEM_INFO_RECEIVED",true) end
        return
    end
    Push("item", itemID, amount, name, icon, quality, ReagentQuality(itemLink or itemID), sellPrice, bindType, itemLink)
end

local function IsDisplayableCurrency(info,currencyID)
    if not info or info.isHeader or info.isTypeUnused then return false end
    -- `discovered` may still be false on the very event that awards a new
    -- currency for the first time. Do not suppress that first acquisition.
    -- `isTypeUnused`, on the other hand, is Blizzard's marker for internal /
    -- hidden currency types and intentionally remains filtered.
    return info.name and info.name~="" and (currencyID or info.currencyID)~=nil
end

local function ScanCurrencies(notify)
    -- Builds the current currency snapshot. With notify=false it establishes a
    -- silent baseline; with notify=true it emits only positive deltas. The
    -- direct event payload handles the common path, so this full scan is mainly
    -- a compatibility fallback for incomplete CURRENCY_DISPLAY_UPDATE data.
    if not C_CurrencyInfo or not C_CurrencyInfo.GetCurrencyListSize then return end
    local nextState=currencyScratch
    wipe(nextState)
    for i = 1, C_CurrencyInfo.GetCurrencyListSize() do
        local info = C_CurrencyInfo.GetCurrencyListInfo(i)
        if IsDisplayableCurrency(info,info and info.currencyID) then
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
    -- Double-buffer swap: retain both tables and wipe/reuse the old snapshot
    -- next time instead of allocating a fresh table for every scan.
    currencyState,currencyScratch=nextState,currencyState
end

local function ScanFactions(notify)
    -- Reputation events do not identify the changed faction. Compare one
    -- complete snapshot against the previous one and emit positive deltas.
    local nextState=factionScratch
    wipe(nextState)
    local count = C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetNumFactions() or GetNumFactions()
    for i = 1, count do
        local name, earned, isHeader, hasRep, factionID, reaction
        if C_Reputation and C_Reputation.GetFactionDataByIndex then
            local data = C_Reputation.GetFactionDataByIndex(i)
            if data then
                name, earned, isHeader, hasRep, factionID, reaction = data.name, data.currentStanding,
                    data.isHeader, data.hasRep, data.factionID, data.reaction
            end
        else
            local factionData = { GetFactionInfo(i) }
            name, earned, isHeader, hasRep, factionID, reaction = factionData[1], factionData[6], factionData[9], factionData[11], factionData[14], factionData[3]
        end
        if name and not isHeader and (hasRep or earned) and factionID then
            nextState[factionID] = earned or 0
            local delta = (earned or 0) - (factionState[factionID] or earned or 0)
            if notify and delta > 0 and Profile().showReputation then
                local color
                if reaction then
                    if reaction<=2 then color={.85,.12,.12}
                    elseif reaction==3 then color={1,.38,.08}
                    elseif reaction==4 then color={.95,.78,.12}
                    else color={.18,.72,.28} end
                end
                Push("reputation", factionID, delta, {main=function(n) return "+"..n.." "..EllesmereUI.L("Reputation") end,sub="["..name.."]",barColor=color}, 236681)
            end
        end
    end
    -- Same allocation-free double-buffer pattern as currency snapshots.
    factionState,factionScratch=nextState,factionState
end

local function InitializeSnapshots()
    local p=Profile()
    if not runtimeEnabled or not p or p.enabled==false then return end
    -- Only snapshot counters that can currently produce a notification.
    -- Currency/reputation list walks are the most expensive baseline work, so
    -- disabling their display also removes their scan and scratch-table use.
    if p.showCurrencies or p.showHonor then ScanCurrencies(false)
    else wipe(currencyState); wipe(currencyScratch) end
    if p.showReputation then ScanFactions(false)
    else wipe(factionState); wipe(factionScratch) end
    lastMoney = p.showGold and (GetMoney() or 0) or 0
    lastXP = p.showExperience and (UnitXP("player") or 0) or 0
    initialized = true
end

local function ApplyPosition()
    local p = Profile(); if not p then return end
    EnsureHolder():ClearAllPoints()
    local pos = p.position
    local x=pos and pos.x; if x==nil then x=380 end
    local y=pos and pos.y; if y==nil then y=80 end
    holder:SetPoint(pos and pos.point or "CENTER",UIParent,pos and pos.relPoint or "CENTER",x,y)
end

function ns.Apply()
    local p = Profile()
    -- Apply is called by every option setter. Lifecycle synchronization comes
    -- first so changing Enabled to false tears down background work before any
    -- layout/preview code gets a chance to run.
    if SetRuntimeEnabled then SetRuntimeEnabled(p and p.enabled ~= false) end
    if not p or not runtimeEnabled then
        if ns.RefreshSettingsPreview then ns.RefreshSettingsPreview() end
        return
    end
    if ConfigureRuntimeEvents then ConfigureRuntimeEvents() end
    if p and not p.showTooltip then
        local tooltipOwner
        for _, row in ipairs(active) do
            if row.hovered then
                if GameTooltip:IsOwned(row) then tooltipOwner=row end
                row.hovered, row.pausedRemaining = nil, nil
                row.expires = GetTime() + p.duration
            end
        end
        HideTooltipOwnedBy(tooltipOwner)
        if TrimActive then TrimActive(true) end
    end
    for _,row in ipairs(active) do
        if row.valueFormatter then row.value:SetText(row.valueFormatter(row.amount)) end
    end
    Layout(); ApplyPosition(); ns.RefreshSettingsPreview()
end

local function RunInitializeSnapshots()
    snapshotTimer=nil
    InitializeSnapshots()
end

local function ScheduleSnapshotInitialization()
    if snapshotTimer then snapshotTimer:Cancel(); snapshotTimer=nil end
    local p=Profile()
    local needsBaseline=p and (p.showCurrencies or p.showHonor or p.showReputation or p.showGold or p.showExperience)
    if needsBaseline then
        -- Blizzard counters are not always final during loading screens. One
        -- cancellable delayed baseline prevents login values from appearing
        -- as newly earned loot. Item chat events need no numeric baseline.
        initialized=false
        snapshotTimer=C_Timer.NewTimer(1,RunInitializeSnapshots)
    else
        initialized=true
    end
end

local currencyScanTimer,factionScanTimer
local function RunScheduledCurrencyScan()
    currencyScanTimer=nil
    if initialized and Profile() and Profile().enabled then ScanCurrencies(true) end
end
local function RunScheduledFactionScan()
    factionScanTimer=nil
    if initialized and Profile() and Profile().enabled then ScanFactions(true) end
end
local function ScheduleCurrencyScan()
    -- Several currency events can arrive in one frame. A single zero-delay,
    -- cancellable timer coalesces them into one list scan.
    if currencyScanTimer then return end
    currencyScanTimer=C_Timer.NewTimer(0,RunScheduledCurrencyScan)
end
local function ScheduleFactionScan()
    -- UPDATE_FACTION has no useful delta payload, so a scan is necessary; the
    -- pending-timer guard prevents duplicate full scans in an event burst.
    if factionScanTimer then return end
    factionScanTimer=C_Timer.NewTimer(0,RunScheduledFactionScan)
end
_G._EL_Apply = ns.Apply

local previewSamples = {
    function() Push("item", "preview-rare-alert", 1, "Rare BoE Alert Test", 135274, 3, nil, 182504, 2, nil, 3500000) end,
    function() Push("item", "preview-epic-alert", 1, "Epic BoE Alert Test", 133738, 4, nil, 425000, 2, nil, 12500000) end,
    function() Push("item", "preview-warbound-alert", 1, "Epic Warbound Alert Test", 4630437, 4, nil, 425000, 7, nil, 18000000) end,
    function() Push("item", "preview-reagent", math.random(1, 5), "Tempered Alloy", 4622299, 2, 3, 4875, nil, nil, 150000) end,
    function() Push("currency", "preview-currency", math.random(8, 45), function(n) return "Valorstones x" .. n end, 5868902) end,
    function() Push("reputation", "preview-rep", math.random(25, 100), {main=function(n) return "+"..n.." "..EllesmereUI.L("Reputation") end,sub="["..EllesmereUI.L("The Assembly").."]",barColor={.18,.72,.28}}, 236681) end,
    function() Push("honor", "preview-honor", math.random(20, 90), function(n) return "+" .. n .. " Honor" end, 1455894) end,
    function() Push("xp", "preview-xp", math.random(250, 900), function(n) return "+" .. n .. " Experience" end, 894556) end,
    function() Push("money", "preview-money", math.random(25000, 950000), function(n) return FormatMoney(n) end, 133784) end,
}

function ns.IsPreviewActive() return previewActive == true end
function ns.SetPreview(activePreview)
    -- Preview is real runtime work (ticker, rows and animations), therefore it
    -- is impossible to start while the feed is disabled and is canceled by
    -- the same lifecycle teardown as live notifications.
    previewActive = activePreview == true and runtimeEnabled
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

local registeredRuntimeEvents = {}
local runtimeFeatures = {}
-- One dispatcher is cheaper and easier to tear down than feature-specific
-- frames. Only events selected by ConfigureRuntimeEvents ever reach it.
local function HandleRuntimeEvent(_, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        ScheduleSnapshotInitialization()
        return
    end
    if not Profile() or not Profile().enabled then return end
    -- Stateful counters must wait for their baseline; item chat messages can
    -- be handled immediately because they already contain the gained item.
    if not initialized and event~="CHAT_MSG_LOOT" and event~="GET_ITEM_INFO_RECEIVED" then return end
    if event == "GET_ITEM_INFO_RECEIVED" then
        local itemID, success = ...
        local amount=pendingItems[itemID]
        if amount then
            pendingItems[itemID]=nil
            if success then NotifyItem(itemID,amount) end
        end
        if not next(pendingItems) then SetRuntimeEvent("GET_ITEM_INFO_RECEIVED",false) end
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
    elseif event == "CURRENCY_DISPLAY_UPDATE" then
        local currencyID, newQuantity, quantityChanged = ...
        local info = currencyID and C_CurrencyInfo.GetCurrencyInfo(currencyID)
        if IsDisplayableCurrency(info,currencyID) and quantityChanged and quantityChanged > 0 then
            currencyState[currencyID] = newQuantity or info.quantity or 0
            if currencyID == 1792 and Profile().showHonor then
                Push("honor", currencyID, quantityChanged, function(n) return "+" .. n .. " Honor" end, info.iconFileID)
            elseif Profile().showCurrencies then
                Push("currency", currencyID, quantityChanged, function(n) return info.name .. (n > 1 and (" x" .. n) or "") end, info.iconFileID)
            end
        else
            ScheduleCurrencyScan()
        end
    elseif event == "UPDATE_FACTION" then ScheduleFactionScan()
    elseif event == "PLAYER_MONEY" then
        local money = GetMoney() or 0; local delta = money - lastMoney; lastMoney = money
        if delta > 0 and Profile().showGold then Push("money", 0, delta, function(n) return FormatMoney(n) end, 133784) end
    elseif event == "PLAYER_XP_UPDATE" then
        local xp = UnitXP("player") or 0; local delta = xp - lastXP
        if delta < 0 then delta = xp end; lastXP = xp
        if delta > 0 and Profile().showExperience then Push("xp", 0, delta, function(n) return "+" .. n .. " Experience" end, 894556) end
    end
end

local function EnsureEventFrame()
    -- Lazy frame: a profile that starts disabled allocates no runtime event
    -- frame at all. Once created it may persist in WoW, but with zero events it
    -- consumes no per-frame CPU while disabled.
    if eventFrame then return eventFrame end
    eventFrame=CreateFrame("Frame")
    eventFrame:SetScript("OnEvent",HandleRuntimeEvent)
    return eventFrame
end

SetRuntimeEvent = function(event, shouldRegister)
    -- Keep a mirror of registration state to avoid redundant API calls when a
    -- slider or unrelated appearance option invokes Apply repeatedly.
    if shouldRegister and not registeredRuntimeEvents[event] then
        EnsureEventFrame():RegisterEvent(event)
        registeredRuntimeEvents[event]=true
    elseif eventFrame and not shouldRegister and registeredRuntimeEvents[event] then
        eventFrame:UnregisterEvent(event)
        registeredRuntimeEvents[event]=nil
    end
end

ConfigureRuntimeEvents = function()
    if not runtimeEnabled then return end
    local p=Profile(); if not p then return end
    -- Register by feature, not by addon. An enabled feed that only shows items
    -- should not receive money, XP, currency or reputation traffic.
    local items=p.showItems==true
    local currencies=p.showCurrencies==true or p.showHonor==true
    local reputation=p.showReputation==true
    local money=p.showGold==true
    local experience=p.showExperience==true

    -- A feature enabled after the initial login snapshot needs its own
    -- baseline before its event is registered, otherwise old gains would be
    -- reported as fresh loot.
    if initialized then
        if currencies and not runtimeFeatures.currencies then ScanCurrencies(false) end
        if reputation and not runtimeFeatures.reputation then ScanFactions(false) end
        if money and not runtimeFeatures.money then lastMoney=GetMoney() or 0 end
        if experience and not runtimeFeatures.experience then lastXP=UnitXP("player") or 0 end
    end
    -- Feature shutdown also releases cached baselines and cancels a coalesced
    -- scan that might still be waiting for the end of the current frame.
    if not items then wipe(pendingItems) end
    if not currencies then
        if currencyScanTimer then currencyScanTimer:Cancel(); currencyScanTimer=nil end
        wipe(currencyState); wipe(currencyScratch)
    end
    if not reputation then
        if factionScanTimer then factionScanTimer:Cancel(); factionScanTimer=nil end
        wipe(factionState); wipe(factionScratch)
    end

    -- PLAYER_ENTERING_WORLD is the only common runtime event; it refreshes
    -- baselines after zoning/reloads. Item-info events remain demand-driven.
    SetRuntimeEvent("PLAYER_ENTERING_WORLD",true)
    SetRuntimeEvent("CHAT_MSG_LOOT",items)
    SetRuntimeEvent("GET_ITEM_INFO_RECEIVED",items and next(pendingItems)~=nil)
    SetRuntimeEvent("CURRENCY_DISPLAY_UPDATE",currencies)
    SetRuntimeEvent("UPDATE_FACTION",reputation)
    SetRuntimeEvent("PLAYER_MONEY",money)
    SetRuntimeEvent("PLAYER_XP_UPDATE",experience)
    runtimeFeatures.items=items
    runtimeFeatures.currencies=currencies
    runtimeFeatures.reputation=reputation
    runtimeFeatures.money=money
    runtimeFeatures.experience=experience
end

-- The addon's settings remain loaded so it can be enabled again, but its
-- runtime is completely dormant while the profile toggle is off. In
-- particular, no gameplay event, timer, ticker or OnUpdate remains active.
SetRuntimeEnabled = function(enabled)
    enabled = enabled == true
    -- Idempotence matters because every option change passes through Apply.
    -- Avoid re-registering events or rebuilding integration for visual edits.
    if runtimeEnabled == enabled then return end
    runtimeEnabled = enabled

    if enabled then
        -- Bring up only the pieces justified by current feature toggles. The
        -- holder is created later by OnEnable; the animation frame remains
        -- lazy until an actual notification needs interpolation.
        AttachBarSharedMedia()
        ConfigureRuntimeEvents()
        if RegisterUnlockIntegration then RegisterUnlockIntegration() end
        ScheduleSnapshotInitialization()
        return
    end

    -- ZERO-COST TEARDOWN ORDER:
    -- 1. Cut off new input first (events/listeners).
    -- 2. Cancel every scheduled callback/ticker.
    -- 3. Release snapshot/item data and stop OnUpdate.
    -- 4. Recycle/hide visuals last.
    -- This ordering prevents a callback from repopulating state mid-cleanup.
    if eventFrame then eventFrame:UnregisterAllEvents() end
    DetachBarSharedMedia()
    wipe(registeredRuntimeEvents)
    wipe(runtimeFeatures)
    if unlockIntegrationRegistered then
        if EllesmereUI.UnregisterUnlockModeListener then EllesmereUI:UnregisterUnlockModeListener("EL_LootFeed") end
        if EllesmereUI.UnregisterUnlockElement then EllesmereUI:UnregisterUnlockElement("EL_LootFeed") end
        unlockIntegrationRegistered = false
        unlockActive = false
    end
    if snapshotTimer then snapshotTimer:Cancel(); snapshotTimer = nil end
    if previewTicker then previewTicker:Cancel(); previewTicker = nil end
    if currencyScanTimer then currencyScanTimer:Cancel(); currencyScanTimer = nil end
    if factionScanTimer then factionScanTimer:Cancel(); factionScanTimer = nil end
    previewActive = false
    initialized = false
    lastMoney, lastXP = 0, 0
    wipe(currencyState); wipe(currencyScratch)
    wipe(factionState); wipe(factionScratch)
    wipe(pendingItems)

    if animationDriver then
        animationDriver:Hide()
    end
    if animationWakeTimer then animationWakeTimer:Cancel(); animationWakeTimer = nil end
    for i = #active, 1, -1 do RemoveRow(active[i], true) end
    if holder then
        holder:Hide()
        if holder.totalValueFrame then
            holder.totalValueFrame._fadeStarted = nil
            holder.totalValueFrame._holdUntil = nil
            holder.totalValueFrame:Hide()
        end
    end
end

RegisterUnlockIntegration = function()
    if unlockIntegrationRegistered then return end
    -- Unlock Mode is also runtime integration. Register it lazily on enable
    -- and explicitly unregister it on disable so moving/opening Unlock Mode
    -- cannot call back into a dormant loot feed.
    unlockIntegrationRegistered = true
    if EllesmereUI.RegisterUnlockModeListener then
        EllesmereUI:RegisterUnlockModeListener("EL_LootFeed", function(activeMode)
            unlockActive = activeMode == true
            if runtimeEnabled then Layout() elseif holder then holder:Hide() end
        end)
    end
    if EllesmereUI.RegisterUnlockElements and EllesmereUI.MakeUnlockElement then
        EllesmereUI:RegisterUnlockElements({ EllesmereUI.MakeUnlockElement({
            key="EL_LootFeed", label="Loot Feed", group="QoL", order=540,
            noResize=true, getFrame=function() return EnsureHolder() end,
            getSize=function()
                local p=Profile(); local h=UniformRowHeight(p)
                local w=p.width or 310
                local spacing=max(5,p.spacing or 5)
                return w,p.maxVisible*(h+spacing)-spacing
            end,
            isHidden=function() return not runtimeEnabled end,
            savePos=function(_, point, relPoint, x, y) Profile().position={point=point,relPoint=relPoint,x=x,y=y} end,
            loadPos=function() return Profile().position end,
            clearPos=function() Profile().position=nil end,
            applyPos=ApplyPosition,
        }) }, "EllesmereUILoot")
    end
end

function EN:OnInitialize()
    db = EllesmereUI.Lite.NewDB("EllesmereUILootDB", DB_DEFAULTS)
    CopyDefaults(db.profile, DB_DEFAULTS.profile)
    -- Validate the current schema's numeric ranges before creating frames.
    db.profile.innerPaddingX=math.max(5,math.min(15,tonumber(db.profile.innerPaddingX) or 5))
    db.profile.innerPaddingY=math.max(5,math.min(15,tonumber(db.profile.innerPaddingY) or 5))
    db.profile.iconSize=math.max(30,math.min(80,tonumber(db.profile.iconSize) or 44))
    db.profile.maxVisible=math.max(3,math.min(25,tonumber(db.profile.maxVisible) or 6))
    db.profile.duration=math.max(1,math.min(10,tonumber(db.profile.duration) or 5))
    db.profile.enterDuration=math.max(.2,math.min(1,tonumber(db.profile.enterDuration) or .2))
    db.profile.exitDuration=math.max(.2,math.min(1,tonumber(db.profile.exitDuration) or 1))
    if db.profile.exitAnimation~="FADE" and db.profile.exitAnimation~="SLIDE_LEFT" and db.profile.exitAnimation~="SLIDE_RIGHT" then
        db.profile.exitAnimation="FADE"
    end
    _G._EL_AceDB = db
end

function EN:OnEnable()
    SetRuntimeEnabled(Profile() and Profile().enabled ~= false)
    if runtimeEnabled then EnsureHolder(); ApplyPosition(); Layout() end
end

function EN:OnDisable()
    SetRuntimeEnabled(false)
end
