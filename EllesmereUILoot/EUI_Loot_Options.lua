local ADDON_NAME, ns = ...
local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not EllesmereUI or not EllesmereUI.RegisterModule then return end

    -- Keep SavedVariables access behind this tiny adapter. Options are loaded
    -- independently from the runtime module, so they must tolerate a profile
    -- that is not available yet during login or reload transitions.
    local function P()
        local database=_G._EL_AceDB
        return database and database.profile
    end
    local function Get(key)
        local profile=P()
        return profile and profile[key]
    end
    local function Set(key,value)
        local profile=P()
        if profile then profile[key]=value end
        if _G._EL_Apply then _G._EL_Apply() end
    end

    local lootFeedHeaderBuilder
    local function Build(pageName, parent, y)
        local W, h, row = EllesmereUI.Widgets, nil, nil
        local startY = y
        local optionsFrame = _G.EllesmereUIFrame
        if optionsFrame and not optionsFrame._enPreviewHook then
            optionsFrame._enPreviewHook = true
            optionsFrame:HookScript("OnHide", function() if ns.SetPreview then ns.SetPreview(false) end end)
        end
        if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end

        -- Provider discovery intentionally happens while this page is built:
        -- TSM/Auctionator may be enabled or disabled between UI reloads.
        if pageName == "External Price Source" then
            local pageStartY=y
            local CPAD=EllesmereUI.CONTENT_PAD or 45
            local contentWidth=math.max(320,parent:GetWidth()-CPAD*2)
            _,h=W:SectionHeader(parent,"EXTERNAL PRICE SOURCES",y); y=y-h
            local info=EllesmereUI.MakeFont(parent,12,nil,1,1,1,.68)
            info:SetPoint("TOPLEFT",parent,"TOPLEFT",CPAD,y-2)
            info:SetWidth(contentWidth)
            info:SetJustifyH("LEFT"); info:SetJustifyV("TOP")
            info:SetWordWrap(true)
            info:SetText(EllesmereUI.L("External price sources provide auction house values for notifications.").."\n"..
                EllesmereUI.L("Supported addons: TSM4 and Auctionator. Sources are only available while the corresponding addon is enabled and loaded."))
            info:SetHeight(34); y=y-44

            local sourceValues,sourceOrder={NONE="None"},{"NONE"}
            local tsmLoaded=TSM_API~=nil
            local auctionatorLoaded=Auctionator and Auctionator.API and Auctionator.API.v1
            if tsmLoaded then
                -- Keep this list deliberately limited to TSM's common monetary
                -- market sources. Rates and sold-per-day statistics are not prices.
                local commonTSMSources={
                    {"DBMarket","Market Value"},
                    {"DBMinBuyout","Minimum Buyout"},
                    {"DBRecent","Recent Value"},
                    {"DBHistorical","Historical Price"},
                    {"DBRegionMarketAvg","Region Market Value Average"},
                    {"DBRegionHistorical","Region Historical Price"},
                    {"DBRegionSaleAvg","Region Sale Average"},
                }
                local available
                if TSM_API.GetPriceSourceKeys then
                    local ok,keys=pcall(TSM_API.GetPriceSourceKeys,{})
                    if ok and type(keys)=="table" then
                        available={}
                        for key,value in pairs(keys) do
                            available[type(key)=="number" and value or key]=true
                        end
                    end
                end
                for _,entry in ipairs(commonTSMSources) do
                    local key,fallback=entry[1],entry[2]
                    if not available or available[key] then
                        local okDesc,desc=false,nil
                        if TSM_API.GetPriceSourceDescription then
                            okDesc,desc=pcall(TSM_API.GetPriceSourceDescription,key)
                        end
                        local value="TSM4:"..key
                        sourceValues[value]="(TSM4) "..(okDesc and desc and desc or fallback).." ("..key..")"
                        sourceOrder[#sourceOrder+1]=value
                    end
                end
            end
            if auctionatorLoaded then
                sourceValues["AUCTIONATOR:MARKET"]="(Auctionator) Market Price"
                sourceOrder[#sourceOrder+1]="AUCTIONATOR:MARKET"
            end
            if not tsmLoaded and not auctionatorLoaded then
                local warning=EllesmereUI.MakeFont(parent,12,nil,1,.35,.35,.95)
                warning:SetPoint("TOPLEFT",parent,"TOPLEFT",CPAD,y)
                warning:SetWidth(contentWidth)
                warning:SetJustifyH("LEFT")
                warning:SetText(EllesmereUI.L("No supported price addon is loaded. Enable TSM4 or Auctionator, then reload the UI."))
                warning:SetHeight(18); y=y-28
            end
            local function HasPriceSource()
                local selected=Get("externalPriceSource") or "NONE"
                return selected~="NONE" and sourceValues[selected]~=nil
            end
            _,h=W:WideDropdown(parent,"Notification Price Source",y,sourceValues,
                function() local v=Get("externalPriceSource") or "NONE"; return sourceValues[v] and v or "NONE" end,
                function(v) Set("externalPriceSource",v); if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage() end end,
                sourceOrder,math.min(650,math.max(420,contentWidth-80))); y=y-h
            local vendorTooltip="Replaces the displayed vendor value with the selected external auction-house price when one is available."
            _,h=W:DualRow(parent,y,
                {type="toggle",text="Replace Vendor Price",tooltip=vendorTooltip,
                    disabled=function() return not HasPriceSource() end,
                    disabledTooltip="Select an available external price source first.",
                    getValue=function() return Get("tsmReplaceVendor")==true end,
                    setValue=function(v) if HasPriceSource() then Set("tsmReplaceVendor",v) end end},
                {type="toggle",text="Show Total Value",
                    disabled=function() return not HasPriceSource() end,
                    disabledTooltip="Select an available external price source first.",
                    tooltip="Shows the combined value in parentheses when multiple copies of an item are looted.",
                    getValue=function() return Get("showStackTotalValue")~=false end,
                    setValue=function(v) if HasPriceSource() then Set("showStackTotalValue",v) end end}); y=y-h

            _,h=W:SectionHeader(parent,"TOTAL VALUE DISPLAY",y); y=y-h
            local priceDisabled=function() return not HasPriceSource() end
            local priceDisabledTooltip="Select an available external price source first."
            _,h=W:DualRow(parent,y,
                {type="toggle",text="Show Total Loot Value",
                    disabled=priceDisabled,disabledTooltip=priceDisabledTooltip,
                    getValue=function() return Get("showTotalLootValue")==true end,
                    setValue=function(v)
                        Set("showTotalLootValue",v)
                        if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage() end
                    end},
                {type="slider",text="Display Duration",min=0,max=10,step=.5,
                    disabled=function() return not HasPriceSource() or Get("showTotalLootValue")~=true end,
                    disabledTooltip="Enable Show Total Loot Value first.",
                    getValue=function() return Get("totalValueDuration") or 2 end,
                    setValue=function(v) Set("totalValueDuration",v) end}); y=y-h
            local function TotalOptionsDisabled()
                return not HasPriceSource() or Get("showTotalLootValue")~=true
            end
            local totalOptionsTooltip="Enable Show Total Loot Value first."
            local totalFontValues,totalFontOrder={__global="EllesmereUI Global"},{"__global"}
            local LSM=LibStub and LibStub("LibSharedMedia-3.0",true)
            local totalFonts=LSM and LSM:HashTable("font") or {}
            local totalFontNames={}; for name in pairs(totalFonts) do totalFontNames[#totalFontNames+1]=name end
            table.sort(totalFontNames)
            for _,name in ipairs(totalFontNames) do totalFontValues[name]=name; totalFontOrder[#totalFontOrder+1]=name end
            _,h=W:DualRow(parent,y,
                {type="colorpicker",text="Font Color",
                    disabled=TotalOptionsDisabled,disabledTooltip=totalOptionsTooltip,
                    getValue=function() return Get("totalValueR") or 1,Get("totalValueG") or .82,Get("totalValueB") or .2,1 end,
                    setValue=function(r,g,b)
                        local p=P(); if p then p.totalValueR,p.totalValueG,p.totalValueB=r,g,b end
                        if _G._EL_Apply then _G._EL_Apply() end
                    end},
                {type="dropdown",text="Font",values=totalFontValues,order=totalFontOrder,
                    disabled=TotalOptionsDisabled,disabledTooltip=totalOptionsTooltip,
                    getValue=function() return Get("totalValueFontName") or "__global" end,
                    setValue=function(v) Set("totalValueFontName",v) end}); y=y-h
            local totalStyleValues={NONE="None",OUTLINE="Outline",THICKOUTLINE="Thick Outline",SHADOW="Shadow",OUTLINE_SHADOW="Outline + Shadow"}
            local totalStyleOrder={"NONE","OUTLINE","THICKOUTLINE","SHADOW","OUTLINE_SHADOW"}
            _,h=W:DualRow(parent,y,
                {type="slider",text="Font Size",min=8,max=32,step=1,
                    disabled=TotalOptionsDisabled,disabledTooltip=totalOptionsTooltip,
                    getValue=function() return Get("totalValueFontSize") or 14 end,
                    setValue=function(v) Set("totalValueFontSize",v) end},
                {type="dropdown",text="Font Outline",values=totalStyleValues,order=totalStyleOrder,
                    disabled=TotalOptionsDisabled,disabledTooltip=totalOptionsTooltip,
                    getValue=function() return Get("totalValueFontStyle") or "OUTLINE_SHADOW" end,
                    setValue=function(v) Set("totalValueFontStyle",v) end}); y=y-h
            _,h=W:DualRow(parent,y,
                {type="slider",text="X Offset",min=0,max=30,step=1,
                    disabled=TotalOptionsDisabled,disabledTooltip=totalOptionsTooltip,
                    getValue=function() return math.min(30,math.max(0,Get("totalValueOffsetX") or 0)) end,
                    setValue=function(v) Set("totalValueOffsetX",math.min(30,math.max(0,v))) end,
                    tooltip="Moves the total value inward from the aligned notification edge."},
                {type="slider",text="Y Offset",min=0,max=30,step=1,
                    disabled=TotalOptionsDisabled,disabledTooltip=totalOptionsTooltip,
                    getValue=function() return math.min(30,math.max(0,Get("totalValueOffsetY") or 0)) end,
                    setValue=function(v) Set("totalValueOffsetY",math.min(30,math.max(0,v))) end,
                    tooltip="Moves the total value farther down below the notifications."}); y=y-h
            parent:SetHeight(math.abs(y-pageStartY)); return math.abs(y-pageStartY)
        end

        if pageName == "Alerts" then
            local alertStartY=y
            _,h=W:SectionHeader(parent,"GENERAL",y); y=y-h
            _,h=W:Toggle(parent,"Enable Alerts",y,function() return Get("alertsEnabled")==true end,function(v) Set("alertsEnabled",v) end); y=y-h

            _,h=W:SectionHeader(parent,"APPEARANCE",y); y=y-h
            local glowStyleValues,glowStyleOrder={},{}
            if EllesmereUI.Glows and EllesmereUI.Glows.STYLES then
                for i,entry in ipairs(EllesmereUI.Glows.STYLES) do
                    if i==1 or i==2 or i==6 then glowStyleValues[i]=entry.name; glowStyleOrder[#glowStyleOrder+1]=i end
                end
            end
            local glowRow
            glowRow,h=W:DualRow(parent,y,
                {type="toggle",text="Enable Glow",getValue=function() return Get("alertGlow")~=false end,setValue=function(v) Set("alertGlow",v) end},
                {type="dropdown",text="Glow Style",values=glowStyleValues,order=glowStyleOrder,getValue=function() local v=Get("alertGlowStyle") or 6; return (v==1 or v==2 or v==6) and v or 6 end,setValue=function(v) Set("alertGlowStyle",v) end}); y=y-h
            do
                local region=glowRow._rightRegion
                local control=region and region._control
                if region and EllesmereUI.BuildColorSwatch then
                    local swatch=EllesmereUI.BuildColorSwatch(region,glowRow:GetFrameLevel()+3,
                        function() return Get("alertR") or 1,Get("alertG") or .65,Get("alertB") or .1,1 end,
                        function(r,g,b)
                            local p=P(); if p then p.alertR,p.alertG,p.alertB=r,g,b end
                            if _G._EL_Apply then _G._EL_Apply() end
                        end,false,22)
                    if control then
                        control:ClearAllPoints()
                        control:SetPoint("RIGHT",region,"RIGHT",-14,0)
                        swatch:SetPoint("RIGHT",control,"LEFT",-10,0)
                    else
                        swatch:SetPoint("RIGHT",region,"RIGHT",-14,0)
                    end
                end
            end
            local LSM=LibStub and LibStub("LibSharedMedia-3.0",true)
            local soundValues={NONE="No Sound",["builtin:RAID_WARNING"]="Raid Warning",["builtin:READY_CHECK"]="Ready Check",["builtin:QUEST_COMPLETE"]="Quest Complete",["builtin:LEVEL_UP"]="Level Up"}
            local soundOrder={"NONE","builtin:RAID_WARNING","builtin:READY_CHECK","builtin:QUEST_COMPLETE","builtin:LEVEL_UP"}
            local soundMedia=LSM and LSM:HashTable("sound") or {}; local soundNames={}
            for name in pairs(soundMedia) do soundNames[#soundNames+1]=name end; table.sort(soundNames)
            for _,name in ipairs(soundNames) do local key="lsm:"..name; soundValues[key]=name; soundOrder[#soundOrder+1]=key end
            _,h=W:DualRow(parent,y,
                {type="toggle",text="Enable Sound",getValue=function() return Get("alertSoundEnabled")==true end,setValue=function(v)
                    Set("alertSoundEnabled",v); if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage() end
                end},
                {type="dropdown",text="Sound",values=soundValues,order=soundOrder,
                    disabled=function() return Get("alertSoundEnabled")~=true end,
                    disabledTooltip="Enable Sound first.",
                    getValue=function()
                        local v=Get("alertSoundKey") or "NONE"
                        return v~="NONE" and not v:find(":",1,true) and ("builtin:"..v) or v
                    end,setValue=function(v)
                        Set("alertSoundKey",v); if v~="NONE" and ns.PlayAlertSound then ns.PlayAlertSound(v) end
                    end}); y=y-h

            _,h=W:SectionHeader(parent,"TRIGGERS",y); y=y-h
            _,h=W:DualRow(parent,y,
                {type="toggle",text="Alert on Epic BoE",getValue=function() return Get("alertEpicBoE")~=false end,setValue=function(v) Set("alertEpicBoE",v) end},
                {type="toggle",text="Alert on Epic Warbound",getValue=function() return Get("alertEpicWarbound")~=false end,setValue=function(v) Set("alertEpicWarbound",v) end}); y=y-h
            local function HasExternalPriceSource() return (Get("externalPriceSource") or "NONE")~="NONE" end
            local RefreshPriceAlertRow
            local priceAlertRow
            priceAlertRow,h=W:DualRow(parent,y,
                {type="toggle",text="Alert on AH Price",
                    disabled=function() return not HasExternalPriceSource() end,
                    disabledTooltip="Select an external price source first.",
                    getValue=function() return Get("externalPriceAlertEnabled")==true end,
                    setValue=function(v)
                        if not HasExternalPriceSource() then return end
                        Set("externalPriceAlertEnabled",v)
                        if RefreshPriceAlertRow then RefreshPriceAlertRow() end
                    end,
                    tooltip="Minimum unit price required to trigger the external-price alert."},
                {type="toggle",text="Alert on Custom Item",
                    getValue=function() return Get("alertCustomItems")==true end,
                    setValue=function(v) Set("alertCustomItems",v) end}); y=y-h

            -- Threshold and switch deliberately share one setting row. The input
            -- is the gold value; the switch enables the rule as a whole.
            local priceAlertRegion=priceAlertRow._leftRegion
            local alertToggle=priceAlertRegion and priceAlertRegion._control
            local thresholdBox=CreateFrame("EditBox",nil,priceAlertRegion or priceAlertRow)
            thresholdBox:SetSize(112,28)
            thresholdBox:SetPoint("RIGHT",alertToggle or priceAlertRow,"LEFT",-12,0)
            thresholdBox:SetAutoFocus(false)
            thresholdBox:SetJustifyH("CENTER")
            thresholdBox:SetFontObject(GameFontHighlightSmall)
            thresholdBox:SetTextInsets(8,8,0,0)
            local thresholdBg=thresholdBox:CreateTexture(nil,"BACKGROUND")
            thresholdBg:SetAllPoints()
            thresholdBg:SetColorTexture(.02,.025,.03,.9)
            if EllesmereUI.MakeBorder then
                EllesmereUI.MakeBorder(thresholdBox,1,1,1,.12,EllesmereUI.PanelPP or EllesmereUI.PP)
            end
            local function ThresholdGold()
                return math.floor((Get("tsmAlertThreshold") or 10000000)/10000+.5)
            end
            local function SaveThreshold()
                local text=tostring(thresholdBox:GetText() or ""):lower():gsub("%s+",""):gsub(",",".")
                local number=tonumber(text:match("^[%d%.]+")) or 0
                if text:find("k",1,true) then number=number*1000 elseif text:find("m",1,true) then number=number*1000000 end
                Set("tsmAlertThreshold",math.max(0,math.floor(number*10000+.5)))
                thresholdBox:SetText(tostring(ThresholdGold()))
            end
            thresholdBox:SetScript("OnEnterPressed",function(self) SaveThreshold(); self:ClearFocus() end)
            thresholdBox:SetScript("OnEditFocusLost",SaveThreshold)
            thresholdBox:SetScript("OnEscapePressed",function(self)
                self:SetText(tostring(ThresholdGold()))
                self:ClearFocus()
            end)
            RefreshPriceAlertRow=function()
                local sourceAvailable=HasExternalPriceSource()
                local alertEnabled=Get("externalPriceAlertEnabled")==true
                if alertToggle then
                    alertToggle:EnableMouse(sourceAvailable)
                    alertToggle:SetAlpha(sourceAvailable and 1 or .3)
                end
                thresholdBox:EnableMouse(sourceAvailable and alertEnabled)
                thresholdBox:SetAlpha(sourceAvailable and alertEnabled and 1 or .3)
                if not thresholdBox:HasFocus() then thresholdBox:SetText(tostring(ThresholdGold())) end
            end
            if EllesmereUI.RegisterWidgetRefresh then EllesmereUI.RegisterWidgetRefresh(RefreshPriceAlertRow) end
            RefreshPriceAlertRow()

            _,h=W:SectionHeader(parent,"CUSTOM ITEMS",y); y=y-h
            local function ItemIDs()
                local ids,seen={},{}
                for token in tostring(Get("alertItemIDs") or ""):gmatch("%d+") do
                    local id=tonumber(token)
                    if id and id>0 and not seen[id] then seen[id]=true; ids[#ids+1]=id end
                end
                return ids
            end
            local function SaveIDs(ids)
                local p=P(); if p then
                    p.alertItemVariants=p.alertItemVariants or {}
                    p.alertItemReagentQualities=p.alertItemReagentQualities or {}
                    local keep,out={},{}
                    for _,id in ipairs(ids) do keep[id]=true; out[#out+1]=tostring(id) end
                    for key in pairs(p.alertItemVariants) do if not keep[tonumber(key)] then p.alertItemVariants[key]=nil end end
                    for key in pairs(p.alertItemReagentQualities) do if not keep[tonumber(key)] then p.alertItemReagentQualities[key]=nil end end
                    p.alertItemIDs=table.concat(out,", ")
                end
                if _G._EL_Apply then _G._EL_Apply() end
                if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage(true) end
            end
            local function AddCustomItem(id,itemLink,reagentQuality)
                id=tonumber(id); if not id or id<=0 then return false end
                local current=ItemIDs()
                local exists=false; for _,existing in ipairs(current) do if existing==id then exists=true; break end end
                if not exists then current[#current+1]=id end
                local p=P(); if p then
                    p.alertItemVariants=p.alertItemVariants or {}
                    p.alertItemReagentQualities=p.alertItemReagentQualities or {}
                    local variant=itemLink and tostring(itemLink):match("(item:[^|]+)")
                    p.alertItemVariants[id]=variant
                    p.alertItemVariants[tostring(id)]=nil
                    p.alertItemReagentQualities[id]=reagentQuality
                    p.alertItemReagentQualities[tostring(id)]=nil
                end
                SaveIDs(current); return true
            end
            ns._AddCustomAlertItem=AddCustomItem

            local CPAD=EllesmereUI.CONTENT_PAD or 45
            local ids=ItemIDs()
            local cards={}
            local drop=CreateFrame("Button",nil,parent); drop:SetHeight(math.max(42,#ids*39-5)); drop:RegisterForClicks("LeftButtonUp")
            drop:SetPoint("TOPLEFT",parent,"TOPLEFT",CPAD,y); drop:SetPoint("TOPRIGHT",parent,"TOPRIGHT",-CPAD,y)
            drop:SetFrameLevel(parent:GetFrameLevel()+30)
            local dropBg=drop:CreateTexture(nil,"BACKGROUND"); dropBg:SetAllPoints(); dropBg:SetColorTexture(.05,.07,.09,.9)
            if EllesmereUI.MakeBorder then EllesmereUI.MakeBorder(drop,1,1,1,.18,EllesmereUI.PanelPP or EllesmereUI.PP) end
            local dropText=EllesmereUI.MakeFont(drop,12,nil,1,1,1,.55); dropText:SetPoint("CENTER"); dropText:SetText(EllesmereUI.L("Item loslassen"))
            local function AcceptCursorItem()
                local cursorType,itemID,itemLink=GetCursorInfo()
                if cursorType~="item" then return end
                itemID=tonumber(itemID) or (itemLink and tonumber(tostring(itemLink):match("item:(%d+)")))
                local reagentQuality
                if itemLink and C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo then
                    local ok,value=pcall(C_TradeSkillUI.GetItemReagentQualityByItemInfo,itemLink)
                    if ok then reagentQuality=value end
                end
                if itemID and AddCustomItem(itemID,itemLink,reagentQuality) then ClearCursor() end
            end
            drop:SetScript("OnClick",AcceptCursorItem); drop:SetScript("OnReceiveDrag",AcceptCursorItem)
            drop:SetScript("OnEnter",function() dropBg:SetColorTexture(.08,.12,.14,.95); dropText:SetAlpha(.9) end)
            drop:SetScript("OnLeave",function() dropBg:SetColorTexture(.05,.07,.09,.9); dropText:SetAlpha(.55) end)
            drop:Hide()
            for index,id in ipairs(ids) do
                local removeIndex=index
                local card=CreateFrame("Frame",nil,parent); card:SetHeight(34); card:EnableMouse(true)
                cards[#cards+1]=card
                card:SetPoint("TOPLEFT",parent,"TOPLEFT",CPAD,y); card:SetPoint("TOPRIGHT",parent,"TOPRIGHT",-CPAD,y)
                local bg=card:CreateTexture(nil,"BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(1,1,1,.025)
                local p=P(); local variant=p and p.alertItemVariants and (p.alertItemVariants[id] or p.alertItemVariants[tostring(id)])
                local reagentQuality=p and p.alertItemReagentQualities and (p.alertItemReagentQualities[id] or p.alertItemReagentQualities[tostring(id)])
                local lookup=variant or id
                local name,itemLink,quality=C_Item.GetItemInfo(lookup)
                if not name and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
                local label=EllesmereUI.MakeFont(card,12,nil,1,1,1,.75)
                if reagentQuality then
                    local qualityIcon=card:CreateTexture(nil,"ARTWORK"); qualityIcon:SetSize(18,18); qualityIcon:SetPoint("LEFT",card,"LEFT",10,0)
                    local atlas=ns.GetReagentQualityAtlas and ns.GetReagentQualityAtlas(lookup,reagentQuality)
                    if not atlas then
                        local atlasTier=ns.GetReagentQualityAtlasTier and ns.GetReagentQualityAtlasTier(reagentQuality) or reagentQuality
                        atlas="Professions-Icon-Quality-Tier"..tostring(atlasTier).."-Small"
                    end
                    qualityIcon:SetAtlas(atlas,false)
                    label:SetPoint("LEFT",qualityIcon,"RIGHT",7,0)
                else
                    label:SetPoint("LEFT",card,"LEFT",12,0)
                end
                local qualityColor=quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
                local qualityHex=qualityColor and qualityColor.hex or "|cffffffff"
                label:SetText((name and (qualityHex..name.."|r") or "Loading item...").."  |cff7f8792"..id.."|r")
                card:SetScript("OnEnter",function(self)
                    bg:SetColorTexture(1,1,1,.055)
                    if itemLink and GameTooltip then
                        GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
                        GameTooltip:SetHyperlink(itemLink)
                        GameTooltip:Show()
                    end
                end)
                card:SetScript("OnLeave",function()
                    bg:SetColorTexture(1,1,1,.025)
                    if GameTooltip then GameTooltip:Hide() end
                end)
                local del=CreateFrame("Button",nil,card); del:SetSize(22,22); del:SetPoint("RIGHT",card,"RIGHT",-7,0)
                local x=EllesmereUI.MakeFont(del,12,nil,1,1,1,.4); x:SetPoint("CENTER"); x:SetText("X")
                del:SetScript("OnEnter",function() x:SetAlpha(.9) end); del:SetScript("OnLeave",function() x:SetAlpha(.4) end)
                del:SetScript("OnClick",function() table.remove(ids,removeIndex); SaveIDs(ids) end)
                y=y-39
            end
            local cursorWatcher=ns._customItemCursorWatcher
            if not cursorWatcher then
                cursorWatcher=CreateFrame("Frame",nil,parent)
                ns._customItemCursorWatcher=cursorWatcher
                cursorWatcher:RegisterEvent("CURSOR_CHANGED")
                cursorWatcher._Refresh=function(self)
                    local activeDrop,activeCards=self._drop,self._cards
                    if not activeDrop or not activeCards then return end
                    local picking=CursorHasItem and CursorHasItem() or select(1,GetCursorInfo())=="item"
                    activeDrop:SetShown(picking)
                    for _,card in ipairs(activeCards) do card:SetShown(not picking) end
                end
                cursorWatcher:SetScript("OnEvent",cursorWatcher._Refresh)
                cursorWatcher:SetScript("OnHide",function(self) self:UnregisterEvent("CURSOR_CHANGED") end)
                cursorWatcher:SetScript("OnShow",function(self)
                    self:RegisterEvent("CURSOR_CHANGED")
                    self:_Refresh()
                end)
            else
                cursorWatcher:SetParent(parent)
            end
            cursorWatcher._drop,cursorWatcher._cards=drop,cards
            cursorWatcher:RegisterEvent("CURSOR_CHANGED")
            cursorWatcher:Show()
            cursorWatcher:_Refresh()
            local addRow,showAdd
            local addValue=""
            if not ns._customItemLinkHook and ChatEdit_InsertLink then
                ns._customItemLinkHook=true
                hooksecurefunc("ChatEdit_InsertLink",function(link)
                    local pf=ns._customItemPopup
                    local box=ns._customItemInput
                    if pf and pf:IsShown() and box and link then
                        box:Insert(link); box:SetFocus()
                    end
                end)
            end
            _,showAdd=EllesmereUI.BuildCogPopup({title="Add Custom Item",minWidth=410,noOwnerDim=true,rows={
                {type="input",label="ID, Link or Name",inputWidth=250,get=function() return addValue end,set=function(value)
                    addValue=tostring(value or ""):match("^%s*(.-)%s*$") or ""
                    local id=tonumber(addValue) or tonumber(addValue:match("item:(%d+)"))
                    if not id and addValue~="" then
                        id=C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(addValue)
                        if not id then local _,link=C_Item.GetItemInfo(addValue); id=link and tonumber(link:match("item:(%d+)")) end
                    end
                    if not id then print("EllesmereUI Loot Feed: Item not found. Use an item ID or item link."); return end
                    if ns._customItemPopup then ns._customItemPopup:Hide() end
                    local link=addValue:find("item:",1,true) and addValue or nil
                    local reagentQuality
                    if link and C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo then
                        local ok,value=pcall(C_TradeSkillUI.GetItemReagentQualityByItemInfo,link)
                        if ok then reagentQuality=value end
                    end
                    AddCustomItem(id,link,reagentQuality)
                end},
            }})
            local function EnsureCustomItemCloseButton(popup)
                if not popup or popup._enCloseButton then return end
                local close=CreateFrame("Button",nil,popup)
                popup._enCloseButton=close
                close:SetSize(24,24)
                close:SetPoint("TOPRIGHT",popup,"TOPRIGHT",-8,-7)
                close:SetFrameLevel(popup:GetFrameLevel()+20)
                local icon=close:CreateTexture(nil,"ARTWORK")
                icon:SetAllPoints()
                icon:SetTexture((EllesmereUI.MEDIA_PATH or "Interface\\AddOns\\EllesmereUI\\media\\").."icons/close-popup-4.png")
                icon:SetAlpha(.4)
                icon:SetSnapToPixelGrid(false)
                icon:SetTexelSnappingBias(0)
                close:SetScript("OnEnter",function() icon:SetAlpha(.65) end)
                close:SetScript("OnLeave",function() icon:SetAlpha(.4) end)
                close:SetScript("OnClick",function() popup:Hide() end)
            end
            local function OpenAddItem()
                addValue=""; showAdd(addRow)
                local pf=showAdd._popupFrame
                if pf and pf:IsShown() then
                    -- Shift-clicking a bag item counts as an outside click. Keep
                    -- the automatic outside handler disabled, but provide an
                    -- explicit close button and Escape handling instead.
                    pf:SetScript("OnUpdate",nil); pf:SetAlpha(1)
                    EnsureCustomItemCloseButton(pf)
                    local box=pf._inputBoxes and pf._inputBoxes[1]
                    ns._customItemPopup,ns._customItemInput=pf,box
                    if box then
                        box:SetText(""); box:SetFocus()
                        if not box._enCloseOnEscape then
                            box._enCloseOnEscape=true
                            box:HookScript("OnEscapePressed",function() pf:Hide() end)
                        end
                    end
                    if not pf._enCustomItemHideHook then
                        pf._enCustomItemHideHook=true
                        pf:HookScript("OnHide",function()
                            local activeBox=ns._customItemInput
                            if activeBox and activeBox:HasFocus() then activeBox:ClearFocus() end
                            if GameTooltip then GameTooltip:Hide() end
                            if ns._customItemPopup==pf then ns._customItemPopup,ns._customItemInput=nil,nil end
                        end)
                    end
                end
            end

            local transferRow,showExport,showImport
            local importValue=""
            local importMode="MERGE"
            _,showExport=EllesmereUI.BuildCogPopup({title="Export Item List",minWidth=440,noOwnerDim=true,rows={
                {type="input",label="Item IDs",inputWidth=310,commitOnBlur=true,
                    get=function() return Get("alertItemIDs") or "" end,set=function() end},
            }})
            _,showImport=EllesmereUI.BuildCogPopup({title="Import Item List",minWidth=440,noOwnerDim=true,rows={
                {type="segmented",label="Import Mode",keys={"MERGE","REPLACE"},labels={MERGE="Items ergänzen",REPLACE="Liste ersetzen"},
                    get=function() return importMode end,set=function(v) importMode=v end},
                {type="input",label="Item ID String",inputWidth=290,get=function() return importValue end,set=function(value)
                    importValue=tostring(value or "")
                    local imported,seen={},{}
                    if importMode=="MERGE" then
                        for _,id in ipairs(ItemIDs()) do seen[id]=true; imported[#imported+1]=id end
                    end
                    for token in importValue:gmatch("%d+") do
                        local id=tonumber(token)
                        if id and id>0 and not seen[id] then seen[id]=true; imported[#imported+1]=id end
                    end
                    if importMode=="REPLACE" then
                        local p=P(); if p then wipe(p.alertItemVariants or {}); wipe(p.alertItemReagentQualities or {}) end
                    end
                    local pf=showImport and showImport._popupFrame; if pf then pf:Hide() end
                    SaveIDs(imported)
                end},
            }})
            transferRow,h=W:WideTripleButton(parent,"+ Add Custom Item","Export Liste","Import Liste",y,function()
                addRow=transferRow
                OpenAddItem()
            end,function()
                local other=showImport._popupFrame; if other then other:Hide() end
                showExport(transferRow)
                local pf=showExport._popupFrame; local box=pf and pf._inputBoxes and pf._inputBoxes[1]
                if box then box:SetFocus(); box:HighlightText() end
            end,function()
                local other=showExport._popupFrame; if other then other:Hide() end
                importValue=""; importMode="MERGE"; showImport(transferRow)
                local pf=showImport._popupFrame; local box=pf and pf._inputBoxes and pf._inputBoxes[1]
                if box then box:SetText(""); box:SetFocus() end
            end,160); y=y-h
            parent:SetHeight(math.abs(y-alertStartY)); return math.abs(y-alertStartY)
        end

        -- The header preview is deliberately independent from live preview.
        -- Shuffle changes only these two local sample rows; Live Preview sends
        -- simulated events through the real notification feed.
        lootFeedHeaderBuilder=function(hdr,hdrW)
            local fy=-20
            local shuffle=CreateFrame("Button",nil,hdr)
            shuffle:SetSize(220,34); shuffle:SetPoint("TOP",hdr,"TOP",-99,fy)
            shuffle:SetFrameLevel(hdr:GetFrameLevel()+5)
            local ar,ag,ab=0,.82,.72
            if EllesmereUI.GetAccentColor then ar,ag,ab=EllesmereUI.GetAccentColor() end
            local shuffleBg=shuffle:CreateTexture(nil,"BACKGROUND"); shuffleBg:SetAllPoints()
            local idleR,idleG,idleB=.025+ar*.10,.03+ag*.10,.035+ab*.10
            local hoverR,hoverG,hoverB=.04+ar*.17,.045+ag*.17,.05+ab*.17
            shuffleBg:SetColorTexture(idleR,idleG,idleB,.96)
            local outline=CreateFrame("Frame",nil,shuffle)
            outline:SetAllPoints(shuffle); outline:SetFrameLevel(shuffle:GetFrameLevel()+2)
            if EllesmereUI.PP and EllesmereUI.PP.CreateBorder then
                EllesmereUI.PP.CreateBorder(outline,ar,ag,ab,.9,1,"OVERLAY",7)
            elseif EllesmereUI.MakeBorder then
                EllesmereUI.MakeBorder(outline,ar,ag,ab,.9,EllesmereUI.PanelPP or EllesmereUI.PP)
            end
            local shuffleText=EllesmereUI.MakeFont(shuffle,13,nil,1,1,1,.94)
            shuffleText:SetPoint("CENTER"); shuffleText:SetText(EllesmereUI.L("Shuffle"))
            shuffle:SetScript("OnEnter",function()
                shuffleBg:SetColorTexture(hoverR,hoverG,hoverB,1)
                shuffleText:SetAlpha(1)
            end)
            shuffle:SetScript("OnLeave",function() shuffleBg:SetColorTexture(idleR,idleG,idleB,.96); shuffleText:SetAlpha(.94) end)
            shuffle:SetScript("OnClick",function() if ns.ShuffleSettingsPreview then ns.ShuffleSettingsPreview() end end)
            local liveRow=CreateFrame("Frame",nil,hdr); liveRow:SetSize(180,34)
            liveRow:SetPoint("LEFT",shuffle,"RIGHT",18,0)
            local liveLabel=EllesmereUI.MakeFont(liveRow,12,nil,1,1,1,.8)
            liveLabel:SetPoint("LEFT",liveRow,"LEFT",4,0); liveLabel:SetText(EllesmereUI.L("Live Preview"))
            if EllesmereUI.BuildToggleControl then
                local liveToggle=EllesmereUI.BuildToggleControl(liveRow,hdr:GetFrameLevel()+5,
                    function() return ns.IsPreviewActive and ns.IsPreviewActive() or false end,
                    function(v) if ns.SetPreview then ns.SetPreview(v) end end)
                liveToggle:SetPoint("RIGHT",liveRow,"RIGHT",-4,0)
            end
            fy=fy-54
            local host=CreateFrame("Frame",nil,hdr); host:SetHeight(140)
            host:SetPoint("TOPLEFT",hdr,"TOPLEFT",24,fy); host:SetPoint("TOPRIGHT",hdr,"TOPRIGHT",-24,fy)
            host:SetClipsChildren(true)
            local preview=ns.CreateSettingsPreview and ns.CreateSettingsPreview(host)
            if preview then
                if ns.RefreshSettingsPreview then ns.RefreshSettingsPreview() end
            end
            return 20+34+20+140+20
        end
        EllesmereUI:SetContentHeader(lootFeedHeaderBuilder)

        _,h=W:SectionHeader(parent,"GENERAL",y); y=y-h

        _,h=W:DualRow(parent,y,
            {type="toggle",text="Enabled",getValue=function() return Get("enabled")~=false end,setValue=function(v) Set("enabled",v) end},
            {type="spacer"}); y=y-h
        _,h=W:DualRow(parent,y,
            {type="toggle",text="Show Tooltip",getValue=function() return Get("showTooltip")~=false end,setValue=function(v) Set("showTooltip",v) end},
            {type="toggle",text="Show Vendor Value",getValue=function() return Get("showItemValue")==true end,setValue=function(v) Set("showItemValue",v) end}); y=y-h
        _,h=W:DualRow(parent,y,
            {type="dropdown",text="Alignment",values={LEFT="Left",RIGHT="Right"},order={"LEFT","RIGHT"},getValue=function() return Get("alignment") or "LEFT" end,setValue=function(v)
                local p=P(); if not p then return end
                local old=p.alignment or "LEFT"
                p.alignment=v
                if old~=v then
                    if p.barTexture=="gradient-lr" then p.barTexture="gradient-rl"
                    elseif p.barTexture=="gradient-rl" then p.barTexture="gradient-lr" end
                end
                if _G._EL_Apply then _G._EL_Apply() end
                if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage() end
            end},
            {type="dropdown",text="Grow",values={UP="Up",DOWN="Down",CENTER="Centered"},order={"UP","DOWN","CENTER"},
                getValue=function() return Get("growMode") or "UP" end,setValue=function(v)
                local p=P(); if not p then return end
                p.growMode=v
                if v=="UP" then
                    if p.enterAnimation=="SLIDE_BOTTOM" then p.enterAnimation="SLIDE_TOP" end
                elseif v=="DOWN" then
                    if p.enterAnimation=="SLIDE_TOP" then p.enterAnimation="SLIDE_BOTTOM" end
                end
                if _G._EL_Apply then _G._EL_Apply() end
                if EllesmereUI.RefreshPage then C_Timer.After(0,function() EllesmereUI:RefreshPage(true) end) end
            end}); y=y-h
        _,h=W:DualRow(parent,y,
            {type="slider",text="Spacing",min=5,max=20,step=1,getValue=function() return math.max(5,Get("spacing") or 5) end,setValue=function(v) Set("spacing",math.max(5,v)) end},
            {type="slider",text="Maximum Shown",min=1,max=12,step=1,getValue=function() return Get("maxVisible") or 6 end,setValue=function(v) Set("maxVisible",v) end}); y=y-h

        _,h=W:SectionHeader(parent,"APPEARANCE",y); y=y-h
        local displayStyleRow
        displayStyleRow,h=W:DualRow(parent,y,
            {type="dropdown",text="Display Style",values={BAR="Bar",ICON="Icon"},order={"BAR","ICON"},
                getValue=function() return Get("displayStyle") or "BAR" end,
                setValue=function(v) Set("displayStyle",v); if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage() end end},
            {type="slider",text="Width",min=180,max=600,step=5,getValue=function() return Get("width") or 310 end,setValue=function(v) Set("width",v) end}); y=y-h
        do
            local _,showCog=EllesmereUI.BuildCogPopup({title="Display Style Options",rows={
                {type="toggle",label="Icon Part of Bar",disabled=function() return Get("displayStyle")=="ICON" end,get=function() return Get("iconPartOfBar")~=false end,set=function(v) if Get("displayStyle")~="ICON" then Set("iconPartOfBar",v) end end},
                {type="slider",label="Icon Gap to Bar",min=5,max=30,step=1,
                    disabled=function() return Get("displayStyle")=="ICON" or Get("iconPartOfBar")~=false end,
                    get=function() return Get("displayStyle")=="ICON" and 5 or math.max(5,Get("iconOffsetX") or 5) end,
                    set=function(v) if Get("displayStyle")~="ICON" then Set("iconOffsetX",v) end end},
            }})
            local region=displayStyleRow._leftRegion; local control=region and region._control
            local cog=CreateFrame("Button",nil,region); cog:SetSize(22,22)
            if control then cog:SetPoint("RIGHT",control,"LEFT",-8,0) end
            local tex=cog:CreateTexture(nil,"OVERLAY"); tex:SetAllPoints(); tex:SetTexture(EllesmereUI.COGS_ICON)
            cog:SetAlpha(.45); cog:SetScript("OnEnter",function(s) s:SetAlpha(.8) end); cog:SetScript("OnLeave",function(s) s:SetAlpha(.45) end)
            cog:SetScript("OnClick",function(s) showCog(s) end)
        end
        _,h=W:DualRow(parent,y,
            {type="slider",text="Inner Padding X",min=5,max=15,step=1,getValue=function() return math.max(5,math.min(15,Get("innerPaddingX") or 5)) end,setValue=function(v) Set("innerPaddingX",v) end},
            {type="slider",text="Inner Padding Y",min=5,max=15,step=1,getValue=function() return math.max(5,math.min(15,Get("innerPaddingY") or 5)) end,setValue=function(v) Set("innerPaddingY",v) end}); y=y-h
        local textureNames=ns.notificationBarTextureNames or {__solid="Solid"}
        local textureOrder=ns.notificationBarTextureOrder or {"__solid"}
        local statusbars=ns.notificationBarTextures or {}
        if EllesmereUI.AppendSharedMediaTextures then
            EllesmereUI.AppendSharedMediaTextures(textureNames,textureOrder,nil,statusbars)
        end
        local barValues,barOrder={},{}
        for _,key in ipairs(textureOrder) do
            if key~="---" then barValues[key]=textureNames[key] or key; barOrder[#barOrder+1]=key end
        end
        barValues._menuOpts={
            itemHeight=28,
            background=function(key) return statusbars[key] end,
            onItemHover=function(key) if ns.SetSettingsPreviewTextureOverride then ns.SetSettingsPreviewTextureOverride(key) end end,
            onItemLeave=function() if ns.ClearSettingsPreviewTextureOverride then ns.ClearSettingsPreviewTextureOverride() end end,
        }
        _,h=W:DualRow(parent,y,
            {type="dropdown",text="Bar Texture",values=barValues,order=barOrder,
                disabled=function() return Get("displayStyle")=="ICON" end,
                disabledTooltip="Bar settings are unavailable in Icon mode.",getValue=function()
                local current=Get("barTexture") or "gradient-lr"
                if barValues[current] then return current end
                return barValues["sm:"..tostring(current)] and ("sm:"..tostring(current)) or "gradient-lr"
            end,setValue=function(v) Set("barTexture",v) end},
            {type="slider",text="Bar Opacity",min=0,max=100,step=5,
                disabled=function() return Get("displayStyle")=="ICON" end,
                disabledTooltip="Bar settings are unavailable in Icon mode.",
                getValue=function() return (Get("backgroundAlpha") or 1)*100 end,setValue=function(v) Set("backgroundAlpha",v/100) end}); y=y-h
        _,h=W:SectionHeader(parent,"COLOR SETTINGS",y); y=y-h
        local function BackgroundDisabled() return Get("displayStyle")=="ICON" end
        local function AddToggleColor(rowFrame,side,getColor,setColor)
            local region=side=="left" and rowFrame._leftRegion or rowFrame._rightRegion
            if not region or not EllesmereUI.BuildColorSwatch then return end
            local control=region._control
            local swatch,refresh=EllesmereUI.BuildColorSwatch(region,region:GetFrameLevel()+5,getColor,setColor,false,18)
            if control then
                control:ClearAllPoints()
                control:SetPoint("RIGHT",region,"RIGHT",-14,0)
                swatch:SetPoint("RIGHT",control,"LEFT",-9,0)
            else
                swatch:SetPoint("RIGHT",region,"RIGHT",-14,0)
            end
            local function RefreshColor()
                local enabled=not BackgroundDisabled()
                swatch:SetAlpha(enabled and 1 or .3)
                swatch:EnableMouse(enabled)
                if refresh then refresh() end
            end
            if EllesmereUI.RegisterWidgetRefresh then EllesmereUI.RegisterWidgetRefresh(RefreshColor) end
            RefreshColor()
        end
        _,h=W:DualRow(parent,y,
            {type="colorpicker",text="Background Color",disabled=BackgroundDisabled,
                disabledTooltip="Background colors are unavailable in Icon mode.",
                getValue=function() return Get("barR") or .035,Get("barG") or .035,Get("barB") or .035,1 end,
                setValue=function(r,g,b) local p=P(); if p then p.barR,p.barG,p.barB=r,g,b end; if _G._EL_Apply then _G._EL_Apply() end end},
            {type="toggle",text="Background Color by Item Quality",disabled=BackgroundDisabled,
                disabledTooltip="Background colors are unavailable in Icon mode.",getValue=function() return Get("colorItemBackgroundByQuality")==true end,setValue=function(v) Set("colorItemBackgroundByQuality",v) end}); y=y-h
        local experienceHonorRow
        experienceHonorRow,h=W:DualRow(parent,y,
            {type="toggle",text="Background Color Experience",disabled=BackgroundDisabled,
                disabledTooltip="Background colors are unavailable in Icon mode.",getValue=function() return Get("colorExperienceBar")==true end,setValue=function(v) Set("colorExperienceBar",v) end},
            {type="toggle",text="Background Color Honor",disabled=BackgroundDisabled,
                disabledTooltip="Background colors are unavailable in Icon mode.",getValue=function() return Get("colorHonorBar")==true end,setValue=function(v) Set("colorHonorBar",v) end}); y=y-h
        AddToggleColor(experienceHonorRow,"left",
            function() return Get("experienceBarR") or .48,Get("experienceBarG") or .22,Get("experienceBarB") or .82,1 end,
            function(r,g,b) local p=P(); if p then p.experienceBarR,p.experienceBarG,p.experienceBarB=r,g,b end; if _G._EL_Apply then _G._EL_Apply() end end)
        AddToggleColor(experienceHonorRow,"right",
            function() return Get("honorBarR") or .75,Get("honorBarG") or .18,Get("honorBarB") or .22,1 end,
            function(r,g,b) local p=P(); if p then p.honorBarR,p.honorBarG,p.honorBarB=r,g,b end; if _G._EL_Apply then _G._EL_Apply() end end)
        local currencyReputationRow
        currencyReputationRow,h=W:DualRow(parent,y,
            {type="toggle",text="Background Color Currency",disabled=BackgroundDisabled,
                disabledTooltip="Background colors are unavailable in Icon mode.",getValue=function() return Get("colorCurrencyBar")==true end,setValue=function(v) Set("colorCurrencyBar",v) end},
            {type="toggle",text="Background Color Reputation by Standing",disabled=BackgroundDisabled,
                disabledTooltip="Background colors are unavailable in Icon mode.",getValue=function() return Get("colorReputationBar")==true end,setValue=function(v) Set("colorReputationBar",v) end}); y=y-h
        AddToggleColor(currencyReputationRow,"left",
            function() return Get("currencyBarR") or 0,Get("currencyBarG") or 0,Get("currencyBarB") or 0,1 end,
            function(r,g,b) local p=P(); if p then p.currencyBarR,p.currencyBarG,p.currencyBarB=r,g,b end; if _G._EL_Apply then _G._EL_Apply() end end)
        _,h=W:DualRow(parent,y,
            {type="toggle",text="Item Quality Color",
                getValue=function() return Get("showItemQuality")~=false end,
                setValue=function(v) Set("showItemQuality",v) end},
            {type="spacer",text=""}); y=y-h

        _,h=W:SectionHeader(parent,"BORDER",y); y=y-h
        local borderValues,borderOrder=EllesmereUI.GetBorderTextureDropdown()
        local borderSizeValues={none="None",thin="Thin",normal="Normal",heavy="Heavy",strong="Strong"}
        local borderSizeOrder={"none","thin","normal","heavy","strong"}
        local borderSizeToNumber={none=0,thin=1,normal=2,heavy=3,strong=4}
        local borderNumberToSize={[0]="none",[1]="thin",[2]="normal",[3]="heavy",[4]="strong"}
        row,h=W:DualRow(parent,y,
            {type="dropdown",text="Border Style",values=borderValues,order=borderOrder,
                tooltip="Controls which element receives the border. In Icon mode only the icon is bordered. In Bar mode the entire notification is bordered; a detached icon also receives its own border.",
                getValue=function() return Get("borderTexture") or "solid" end,setValue=function(v) Set("borderTexture",v); Set("borderOffsetX",0); Set("borderOffsetY",0) end},
            {type="dropdown",text="Border Size",values=borderSizeValues,order=borderSizeOrder,
                getValue=function() local v=Get("borderSize"); if v==nil then v=0 end; return borderNumberToSize[v] or "none" end,
                setValue=function(v) Set("borderSize",borderSizeToNumber[v] or 1) end}); y=y-h
        do
            local region=row._rightRegion
            local control=region and region._control
            if region and EllesmereUI.BuildColorSwatch then
                local swatch,refresh=EllesmereUI.BuildColorSwatch(region,row:GetFrameLevel()+3,
                    function() return Get("borderR") or 0,Get("borderG") or 0,Get("borderB") or 0,Get("borderA") or 1 end,
                    function(r,g,b,a)
                        local p=P(); if p then p.borderR,p.borderG,p.borderB,p.borderA=r,g,b,a end
                        if _G._EL_Apply then _G._EL_Apply() end
                    end,true,22)
                if control then
                    control:ClearAllPoints()
                    control:SetPoint("RIGHT",region,"RIGHT",-14,0)
                    swatch:SetPoint("RIGHT",control,"LEFT",-10,0)
                else
                    swatch:SetPoint("RIGHT",region,"RIGHT",-14,0)
                end
                if EllesmereUI.RegisterWidgetRefresh then EllesmereUI.RegisterWidgetRefresh(refresh) end
            end
        end
        do
            local _,showCog=EllesmereUI.BuildCogPopup({title="Border Options",rows={
                {type="slider",label="Offset X",min=-10,max=10,step=1,get=function() return Get("borderOffsetX") or 0 end,set=function(v) Set("borderOffsetX",v) end},
                {type="slider",label="Offset Y",min=-10,max=10,step=1,get=function() return Get("borderOffsetY") or 0 end,set=function(v) Set("borderOffsetY",v) end},
                {type="toggle",label="Show Behind",get=function() return Get("borderBehind")==true end,set=function(v) Set("borderBehind",v) end},
            }})
            local region=row._leftRegion; local cog=CreateFrame("Button",nil,region); cog:SetSize(22,22)
            local ctrl=region._control; if ctrl then cog:SetPoint("RIGHT",ctrl,"LEFT",-8,0) end
            local tex=cog:CreateTexture(nil,"OVERLAY"); tex:SetAllPoints(); tex:SetTexture(EllesmereUI.DIRECTIONS_ICON)
            cog:SetAlpha(.45); cog:SetScript("OnEnter",function(s) s:SetAlpha(.8) end); cog:SetScript("OnLeave",function(s) s:SetAlpha(.45) end)
            cog:SetScript("OnClick",function(s) showCog(s) end)
        end

        _,h=W:SectionHeader(parent,"DISPLAY & ANIMATION",y); y=y-h
        local verticalSlide=Get("growMode")=="DOWN" and "SLIDE_BOTTOM" or "SLIDE_TOP"
        local animValues={NONE="None",FADE="Fade",SLIDE_LEFT="Slide (Left)",SLIDE_RIGHT="Slide (Right)",ZOOM_IN="Zoom In",ZOOM_OUT="Zoom Out"}
        animValues[verticalSlide]=verticalSlide=="SLIDE_TOP" and "Slide (Top)" or "Slide (Bottom)"
        local animOrder={"NONE","FADE","SLIDE_LEFT","SLIDE_RIGHT",verticalSlide,"ZOOM_IN","ZOOM_OUT"}
        local function CurrentAnimation(key,fallback)
            local value=Get(key) or fallback
            if value=="SLIDE" then return Get("alignment")=="RIGHT" and "SLIDE_RIGHT" or "SLIDE_LEFT" end
            if value=="SCALE" or value=="POP" then return "ZOOM_IN" end
            if value=="SLIDE_TOP" or value=="SLIDE_BOTTOM" then return verticalSlide end
            return value
        end
        _,h=W:DualRow(parent,y,
            {type="dropdown",text="Enter Animation",values=animValues,order=animOrder,getValue=function() return CurrentAnimation("enterAnimation","SLIDE_LEFT") end,setValue=function(v) Set("enterAnimation",v) end},
            {type="slider",text="Duration",min=.2,max=1,step=.05,getValue=function() return math.max(.2,math.min(1,Get("enterDuration") or .2)) end,setValue=function(v) Set("enterDuration",v) end}); y=y-h
        _,h=W:DualRow(parent,y,
            {type="dropdown",text="Exit Animation",values={FADE="Fade",SLIDE_LEFT="Slide (Left)",SLIDE_RIGHT="Slide (Right)"},order={"FADE","SLIDE_LEFT","SLIDE_RIGHT"},getValue=function()
                local value=CurrentAnimation("exitAnimation","FADE")
                return (value=="FADE" or value=="SLIDE_LEFT" or value=="SLIDE_RIGHT") and value or "FADE"
            end,setValue=function(v) Set("exitAnimation",v) end},
            {type="slider",text="Duration",min=.2,max=1,step=.05,getValue=function() return math.max(.2,math.min(1,Get("exitDuration") or 1)) end,setValue=function(v) Set("exitDuration",v) end}); y=y-h
        _,h=W:DualRow(parent,y,
            {type="slider",text="Display Duration",min=1,max=10,step=.5,getValue=function() return math.max(1,math.min(10,Get("duration") or 5)) end,setValue=function(v) Set("duration",v) end},
            {type="slider",text="Item Merge Window",min=.2,max=3,step=.1,getValue=function() return Get("mergeWindow") or 1 end,setValue=function(v) Set("mergeWindow",v) end}); y=y-h

        _,h=W:SectionHeader(parent,"TYPOGRAPHY",y); y=y-h
        local fontValues,fontOrder={__global="EllesmereUI Global"},{"__global"}
        local LSM=LibStub and LibStub("LibSharedMedia-3.0",true)
        local fonts=LSM and LSM:HashTable("font") or {}
        local names={}; for name in pairs(fonts) do names[#names+1]=name end; table.sort(names)
        for _,name in ipairs(names) do fontValues[name]=name; fontOrder[#fontOrder+1]=name end
        local styleValues={NONE="None",OUTLINE="Outline",THICKOUTLINE="Thick Outline",SHADOW="Shadow",OUTLINE_SHADOW="Outline + Shadow"}
        local styleOrder={"NONE","OUTLINE","THICKOUTLINE","SHADOW","OUTLINE_SHADOW"}
        _,h=W:DualRow(parent,y,
            {type="dropdown",text="Font",values=fontValues,order=fontOrder,getValue=function() return Get("fontName") or "__global" end,setValue=function(v) Set("fontName",v) end},
            {type="dropdown",text="Font Style",values=styleValues,order=styleOrder,getValue=function() return Get("fontStyle") or "OUTLINE_SHADOW" end,setValue=function(v) Set("fontStyle",v) end}); y=y-h
        _,h=W:DualRow(parent,y,
            {type="slider",text="Font Size",min=9,max=24,step=1,getValue=function() return Get("fontSize") or 14 end,setValue=function(v) Set("fontSize",v) end},
            {type="slider",text="Secondary Font Size",min=7,max=20,step=1,getValue=function() return Get("valueFontSize") or 12 end,setValue=function(v) Set("valueFontSize",v) end}); y=y-h

        _,h=W:SectionHeader(parent,"NOTIFICATIONS",y); y=y-h
        local toggles={{"showItems","Items"},{"showCurrencies","Currencies"},{"showReputation","Reputation"},{"showHonor","Honor"},{"showExperience","Experience"},{"showGold","Gold"}}
        for i=1,#toggles,2 do
            local a,b=toggles[i],toggles[i+1]
            _,h=W:DualRow(parent,y,
                {type="toggle",text=a[2],getValue=function() return Get(a[1])~=false end,setValue=function(v) Set(a[1],v) end},
                {type="toggle",text=b[2],getValue=function() return Get(b[1])~=false end,setValue=function(v) Set(b[1],v) end}); y=y-h
        end
        parent:SetHeight(math.abs(y-startY))
    end

    local pages={"Loot Feed","Alerts","External Price Source"}
    EllesmereUI:RegisterModule("EllesmereUILoot",{
        title="Loot", description="Loot feed, alerts, prices and tracking.",
        pages=pages, buildPage=Build,
        getHeaderBuilder=function(pageName) return pageName=="Loot Feed" and lootFeedHeaderBuilder or nil end,
        onReset=function() local p=P(); if p then wipe(p) end end,
    })
    SLASH_ELLESMERELOOT1="/eloot"
    SlashCmdList.ELLESMERELOOT=function()
        if InCombatLockdown and InCombatLockdown() then print("Cannot open options in combat"); return end
        EllesmereUI:ShowModule("EllesmereUILoot")
    end
end)
