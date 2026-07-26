local ADDON_NAME, ns = ...
local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not EllesmereUI or not EllesmereUI.RegisterModule then return end

    local function P() local d=_G._EN_AceDB; return d and d.profile end
    local function Get(k) local p=P(); return p and p[k] end
    local function Set(k,v) local p=P(); if p then p[k]=v end; if _G._EN_Apply then _G._EN_Apply() end end

    local function Build(pageName, parent, y)
        local W, h, row = EllesmereUI.Widgets, nil, nil
        local startY = y
        local optionsFrame = _G.EllesmereUIFrame
        if optionsFrame and not optionsFrame._enPreviewHook then
            optionsFrame._enPreviewHook = true
            optionsFrame:HookScript("OnHide", function() if ns.SetPreview then ns.SetPreview(false) end end)
        end
        if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end

        if pageName == "External Price Source" then
            local pageStartY=y
            _,h=W:SectionHeader(parent,"EXTERNAL PRICE SOURCES",y); y=y-h
            local info=EllesmereUI.MakeFont(parent,12,nil,1,1,1,.68)
            info:SetPoint("TOPLEFT",parent,"TOPLEFT",24,y-4)
            info:SetPoint("TOPRIGHT",parent,"TOPRIGHT",-24,y-4)
            info:SetJustifyH("LEFT"); info:SetJustifyV("TOP")
            info:SetText(EllesmereUI.L("External price sources provide auction house values from supported addons. TSM4 and Auctionator are currently supported. A source is only available while its addon is enabled and loaded."))
            info:SetHeight(48); y=y-56

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
                warning:SetPoint("TOPLEFT",parent,"TOPLEFT",24,y-2)
                warning:SetPoint("TOPRIGHT",parent,"TOPRIGHT",-24,y-2)
                warning:SetJustifyH("LEFT")
                warning:SetText(EllesmereUI.L("No supported external price source is currently loaded. Enable TSM4 or Auctionator and reload the UI."))
                warning:SetHeight(34); y=y-42
            end
            _,h=W:WideDropdown(parent,"Notification Price Source",y,sourceValues,
                function() local v=Get("externalPriceSource") or "NONE"; return sourceValues[v] and v or "NONE" end,
                function(v) Set("externalPriceSource",v) end,sourceOrder,math.max(360,parent:GetWidth()-96)); y=y-h
            _,h=W:Toggle(parent,"Replace Vendor Price",y,function() return Get("tsmReplaceVendor")==true end,function(v) Set("tsmReplaceVendor",v) end); y=y-h
            _,h=W:DualRow(parent,y,{type="input",text="Alert Threshold (Gold)",inputWidth=150,
                getValue=function() return math.floor((Get("tsmAlertThreshold") or 10000000)/10000+.5) end,
                setValue=function(value)
                    local text=tostring(value or ""):lower():gsub("%s+",""):gsub(",",".")
                    local number=tonumber(text:match("^[%d%.]+")) or 0
                    if text:find("k",1,true) then number=number*1000 elseif text:find("m",1,true) then number=number*1000000 end
                    Set("tsmAlertThreshold",math.max(0,math.floor(number*10000+.5)))
                end,tooltip="Minimum unit price. 0 disables the price alert."}); y=y-h
            parent:SetHeight(math.abs(y-pageStartY)); return math.abs(y-pageStartY)
        end

        if pageName == "Alerts" then
            local alertStartY=y
            _,h=W:SectionHeader(parent,"GENERAL",y); y=y-h
            _,h=W:Toggle(parent,"Enable Alerts",y,function() return Get("alertsEnabled")==true end,function(v) Set("alertsEnabled",v) end); y=y-h

            _,h=W:SectionHeader(parent,"TRIGGERS",y); y=y-h
            _,h=W:DualRow(parent,y,
                {type="toggle",text="Alert on Epic BoE",getValue=function() return Get("alertEpicBoE")~=false end,setValue=function(v) Set("alertEpicBoE",v) end},
                {type="toggle",text="Alert on Epic Warbound",getValue=function() return Get("alertEpicWarbound")~=false end,setValue=function(v) Set("alertEpicWarbound",v) end}); y=y-h

            _,h=W:SectionHeader(parent,"APPEARANCE",y); y=y-h
            local glowStyleValues,glowStyleOrder={},{}
            if EllesmereUI.Glows and EllesmereUI.Glows.STYLES then
                for i,entry in ipairs(EllesmereUI.Glows.STYLES) do
                    if i==1 or i==2 or i==6 then glowStyleValues[i]=entry.name; glowStyleOrder[#glowStyleOrder+1]=i end
                end
            end
            _,h=W:DualRow(parent,y,
                {type="toggle",text="Enable Glow",getValue=function() return Get("alertGlow")~=false end,setValue=function(v) Set("alertGlow",v) end},
                {type="toggle",text="Notification Highlighting",getValue=function() return Get("alertBarHighlight")==true end,setValue=function(v) Set("alertBarHighlight",v) end}); y=y-h
            _,h=W:DualRow(parent,y,
                {type="dropdown",text="Button Glow Style",values=glowStyleValues,order=glowStyleOrder,getValue=function() local v=Get("alertGlowStyle") or 6; return (v==1 or v==2 or v==6) and v or 6 end,setValue=function(v) Set("alertGlowStyle",v) end}); y=y-h

            _,h=W:SectionHeader(parent,"SOUND",y); y=y-h
            local LSM=LibStub and LibStub("LibSharedMedia-3.0",true)
            local soundValues={NONE="No Sound",["builtin:RAID_WARNING"]="Raid Warning",["builtin:READY_CHECK"]="Ready Check",["builtin:QUEST_COMPLETE"]="Quest Complete",["builtin:LEVEL_UP"]="Level Up"}
            local soundOrder={"NONE","builtin:RAID_WARNING","builtin:READY_CHECK","builtin:QUEST_COMPLETE","builtin:LEVEL_UP"}
            local soundMedia=LSM and LSM:HashTable("sound") or {}; local soundNames={}
            for name in pairs(soundMedia) do soundNames[#soundNames+1]=name end; table.sort(soundNames)
            for _,name in ipairs(soundNames) do local key="lsm:"..name; soundValues[key]=name; soundOrder[#soundOrder+1]=key end
            _,h=W:DualRow(parent,y,{type="dropdown",text="Alert Sound",values=soundValues,order=soundOrder,
                getValue=function()
                    local v=Get("alertSoundKey") or "NONE"
                    return v~="NONE" and not v:find(":",1,true) and ("builtin:"..v) or v
                end,setValue=function(v)
                    Set("alertSoundKey",v); if v~="NONE" and ns.PlayAlertSound then ns.PlayAlertSound(v) end
                end}); y=y-h

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
                local out={}; for _,id in ipairs(ids) do out[#out+1]=tostring(id) end
                local p=P(); if p then
                    p.alertItemVariants=p.alertItemVariants or {}
                    p.alertItemReagentQualities=p.alertItemReagentQualities or {}
                    local keep={}; for _,id in ipairs(ids) do keep[tonumber(id)]=true end
                    for key in pairs(p.alertItemVariants) do if not keep[tonumber(key)] then p.alertItemVariants[key]=nil end end
                    for key in pairs(p.alertItemReagentQualities) do if not keep[tonumber(key)] then p.alertItemReagentQualities[key]=nil end end
                end
                Set("alertItemIDs",table.concat(out,", "))
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
                local expansionID=select(15,C_Item.GetItemInfo(lookup))
                if not name and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
                local label=EllesmereUI.MakeFont(card,12,nil,1,1,1,.75)
                if reagentQuality then
                    local qualityIcon=card:CreateTexture(nil,"ARTWORK"); qualityIcon:SetSize(18,18); qualityIcon:SetPoint("LEFT",card,"LEFT",10,0)
                    local atlasTier=reagentQuality
                    local midnightID=_G.LE_EXPANSION_MIDNIGHT or 11
                    if reagentQuality==2 and expansionID and expansionID>=midnightID then atlasTier=3 end
                    qualityIcon:SetAtlas("Professions-Icon-Quality-Tier"..tostring(atlasTier).."-Small",false)
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
            local cursorWatcher=CreateFrame("Frame",nil,parent); local cursorElapsed=0
            cursorWatcher:SetScript("OnUpdate",function(_,elapsed)
                cursorElapsed=cursorElapsed+elapsed; if cursorElapsed<.05 then return end; cursorElapsed=0
                local cursorType=GetCursorInfo()
                local picking=cursorType=="item"
                drop:SetShown(picking)
                for _,card in ipairs(cards) do card:SetShown(not picking) end
            end)
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
                    if not id then print("EllesmereUI Notifications: Item not found. Use an item ID or item link."); return end
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
            addRow,h=W:Button(parent,"+ Add Custom Item",y,function()
                addValue=""; showAdd(addRow)
                local pf=showAdd._popupFrame
                if pf and pf:IsShown() then
                    -- Selecting an item in bags is an outside click. Keep this
                    -- picker open and route Shift-clicked links into its input.
                    pf:SetScript("OnUpdate",nil); pf:SetAlpha(1)
                    local box=pf._inputBoxes and pf._inputBoxes[1]
                    ns._customItemPopup,ns._customItemInput=pf,box
                    if box then box:SetText(""); box:SetFocus() end
                    if not pf._enCustomItemHideHook then
                        pf._enCustomItemHideHook=true
                        pf:HookScript("OnHide",function()
                            if ns._customItemPopup==pf then ns._customItemPopup,ns._customItemInput=nil,nil end
                        end)
                    end
                end
            end); y=y-h

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
            transferRow,h=W:WideDualButton(parent,"Export Liste","Import Liste",y,function()
                local other=showImport._popupFrame; if other then other:Hide() end
                showExport(transferRow)
                local pf=showExport._popupFrame; local box=pf and pf._inputBoxes and pf._inputBoxes[1]
                if box then box:SetFocus(); box:HighlightText() end
            end,function()
                local other=showExport._popupFrame; if other then other:Hide() end
                importValue=""; importMode="MERGE"; showImport(transferRow)
                local pf=showImport._popupFrame; local box=pf and pf._inputBoxes and pf._inputBoxes[1]
                if box then box:SetText(""); box:SetFocus() end
            end,180); y=y-h
            parent:SetHeight(math.abs(y-alertStartY)); return math.abs(y-alertStartY)
        end

        local generalHeader
        generalHeader,h=W:SectionHeader(parent,"GENERAL",y); y=y-h
        do
            local eye=CreateFrame("Button",nil,generalHeader); eye:SetSize(18,18)
            eye:SetPoint("LEFT",generalHeader._label,"RIGHT",8,0)
            local tex=eye:CreateTexture(nil,"ARTWORK"); tex:SetAllPoints()
            local function RefreshEye()
                local active=ns.IsPreviewActive and ns.IsPreviewActive()
                tex:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\"..(active and "eui-visible.png" or "eui-invisible.png"))
                tex:SetAlpha(active and 1 or .65)
            end
            eye:SetScript("OnClick",function() if ns.SetPreview then ns.SetPreview(not ns.IsPreviewActive()) end; RefreshEye() end)
            eye:SetScript("OnEnter",function(self) if EllesmereUI.ShowWidgetTooltip then EllesmereUI.ShowWidgetTooltip(self,EllesmereUI.L("Toggle notification preview")) end end)
            eye:SetScript("OnLeave",function() if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end end)
            RefreshEye()
        end

        _,h=W:DualRow(parent,y,
            {type="toggle",text="Enabled",getValue=function() return Get("enabled")~=false end,setValue=function(v) Set("enabled",v) end},
            {type="dropdown",text="Display Style",values={BAR="Bar",ICON="Icon"},order={"BAR","ICON"},getValue=function() return Get("displayStyle") or "BAR" end,setValue=function(v) Set("displayStyle",v) end}); y=y-h
        _,h=W:DualRow(parent,y,
            {type="dropdown",text="Alignment",values={LEFT="Left",RIGHT="Right"},order={"LEFT","RIGHT"},getValue=function() return Get("alignment") or "LEFT" end,setValue=function(v) Set("alignment",v) end},
            {type="toggle",text="Grow Up",getValue=function() return Get("growUp")~=false end,setValue=function(v)
                local p=P(); if not p then return end
                p.growUp=v
                if v then
                    if p.enterAnimation=="SLIDE_BOTTOM" then p.enterAnimation="SLIDE_TOP" end
                    if p.exitAnimation=="SLIDE_BOTTOM" then p.exitAnimation="SLIDE_TOP" end
                else
                    if p.enterAnimation=="SLIDE_TOP" then p.enterAnimation="SLIDE_BOTTOM" end
                    if p.exitAnimation=="SLIDE_TOP" then p.exitAnimation="SLIDE_BOTTOM" end
                end
                if _G._EN_Apply then _G._EN_Apply() end
                if EllesmereUI.RefreshPage then C_Timer.After(0,function() EllesmereUI:RefreshPage(true) end) end
            end}); y=y-h
        _,h=W:DualRow(parent,y,
            {type="slider",text="Spacing",min=5,max=20,step=1,getValue=function() return math.max(5,Get("spacing") or 5) end,setValue=function(v) Set("spacing",math.max(5,v)) end},
            {type="slider",text="Maximum Shown",min=1,max=12,step=1,getValue=function() return Get("maxVisible") or 6 end,setValue=function(v) Set("maxVisible",v) end}); y=y-h
        _,h=W:DualRow(parent,y,
            {type="slider",text="Window Width",min=180,max=600,step=5,getValue=function() return Get("width") or 310 end,setValue=function(v) Set("width",v) end},
            {type="toggle",text="Show Tooltip",getValue=function() return Get("showTooltip")~=false end,setValue=function(v) Set("showTooltip",v) end}); y=y-h

        _,h=W:SectionHeader(parent,"DISPLAY & ANIMATION",y); y=y-h
        local verticalSlide=Get("growUp")~=false and "SLIDE_TOP" or "SLIDE_BOTTOM"
        local animValues={NONE="None",FADE="Fade",SLIDE_LEFT="Slide (Left)",SLIDE_RIGHT="Slide (Right)",
            ZOOM_IN="Zoom In",ZOOM_OUT="Zoom Out"}
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
            {type="dropdown",text="Enter",values=animValues,order=animOrder,getValue=function() return CurrentAnimation("enterAnimation",verticalSlide) end,setValue=function(v) Set("enterAnimation",v) end},
            {type="slider",text="Duration",min=.05,max=1,step=.05,getValue=function() return Get("enterDuration") or .2 end,setValue=function(v) Set("enterDuration",v) end}); y=y-h
        _,h=W:DualRow(parent,y,
            {type="dropdown",text="Exit",values=animValues,order=animOrder,getValue=function() return CurrentAnimation("exitAnimation","FADE") end,setValue=function(v) Set("exitAnimation",v) end},
            {type="slider",text="Duration",min=.2,max=3,step=.1,getValue=function() return Get("exitDuration") or 1.2 end,setValue=function(v) Set("exitDuration",v) end}); y=y-h
        _,h=W:DualRow(parent,y,
            {type="slider",text="Display Duration",min=1,max=15,step=.5,getValue=function() return Get("duration") or 5 end,setValue=function(v) Set("duration",v) end},
            {type="slider",text="Item Merge Window",min=.2,max=3,step=.1,getValue=function() return Get("mergeWindow") or 1 end,setValue=function(v) Set("mergeWindow",v) end}); y=y-h

        _,h=W:SectionHeader(parent,"TYPOGRAPHY",y); y=y-h
        local fontValues, fontOrder = {__global="EllesmereUI Global"}, {"__global"}
        local LSM=LibStub and LibStub("LibSharedMedia-3.0",true)
        local fonts=LSM and LSM:HashTable("font") or {}
        local names={}; for name in pairs(fonts) do names[#names+1]=name end; table.sort(names)
        for _,name in ipairs(names) do fontValues[name]=name; fontOrder[#fontOrder+1]=name end
        local styleValues={NONE="None",OUTLINE="Outline",THICKOUTLINE="Thick Outline",SHADOW="Shadow",OUTLINE_SHADOW="Outline + Shadow"}
        local styleOrder={"NONE","OUTLINE","THICKOUTLINE","SHADOW","OUTLINE_SHADOW"}
        _,h=W:DualRow(parent,y,
            {type="dropdown",text="Font",values=fontValues,order=fontOrder,getValue=function() return Get("fontName") or "__global" end,setValue=function(v) Set("fontName",v) end},
            {type="dropdown",text="Font Style",values=styleValues,order=styleOrder,getValue=function() return Get("fontStyle") or "OUTLINE" end,setValue=function(v) Set("fontStyle",v) end}); y=y-h
        local iconSizeRow
        iconSizeRow,h=W:DualRow(parent,y,
            {type="slider",text="Font Size",min=9,max=24,step=1,getValue=function() return Get("fontSize") or 13 end,setValue=function(v) Set("fontSize",v) end},
            {type="slider",text="Secondary Font Size",min=7,max=20,step=1,getValue=function() return Get("valueFontSize") or 11 end,setValue=function(v) Set("valueFontSize",v) end}); y=y-h

        _,h=W:SectionHeader(parent,"APPEARANCE",y); y=y-h
        iconSizeRow,h=W:DualRow(parent,y,
            {type="slider",text="Icon Size",min=26,max=64,step=1,getValue=function() return math.max(26,Get("iconSize") or 28) end,setValue=function(v) Set("iconSize",math.max(26,v)) end},
            {type="toggle",text="Show Icons",getValue=function() return Get("showIcons")~=false end,setValue=function(v) Set("showIcons",v) end}); y=y-h
        do
            local _,showCog=EllesmereUI.BuildCogPopup({title="Icon Options",rows={
                {type="toggle",label="Icon Part of Bar",disabled=function() return Get("displayStyle")=="ICON" end,get=function() return Get("iconPartOfBar")~=false end,set=function(v) if Get("displayStyle")~="ICON" then Set("iconPartOfBar",v) end end},
                {type="toggle",label="Show Divider",
                    disabled=function() return Get("displayStyle")=="ICON" or Get("iconPartOfBar")==false end,
                    get=function() return Get("showIconDivider")==true end,
                    set=function(v) Set("showIconDivider",v) end},
                {type="slider",label="Gap to Bar",min=5,max=30,step=1,
                    disabled=function() return Get("displayStyle")~="ICON" and Get("iconPartOfBar")~=false end,
                    get=function() return math.max(5,Get("iconOffsetX") or 5) end,
                    set=function(v) Set("iconOffsetX",v) end},
            }})
            local region=iconSizeRow._leftRegion; local ctrl=region._control
            local cog=CreateFrame("Button",nil,region); cog:SetSize(22,22)
            if ctrl then cog:SetPoint("RIGHT",ctrl,"LEFT",-8,0) end
            local tex=cog:CreateTexture(nil,"OVERLAY"); tex:SetAllPoints(); tex:SetTexture(EllesmereUI.COGS_ICON)
            cog:SetAlpha(.45); cog:SetScript("OnEnter",function(s) s:SetAlpha(.8) end); cog:SetScript("OnLeave",function(s) s:SetAlpha(.45) end)
            cog:SetScript("OnClick",function(s) showCog(s) end)
        end
        local barValues,barOrder={__solid="Solid"},{"__solid"}
        local statusbars=LSM and LSM:HashTable("statusbar") or {}
        local barNames={}; for name in pairs(statusbars) do barNames[#barNames+1]=name end; table.sort(barNames)
        for _,name in ipairs(barNames) do barValues[name]=name; barOrder[#barOrder+1]=name end
        local barRow
        barRow,h=W:DualRow(parent,y,
            {type="dropdown",text="Bar Texture",values=barValues,order=barOrder,getValue=function() return Get("barTexture") or "__solid" end,setValue=function(v) Set("barTexture",v) end},
            {type="slider",text="Bar Opacity",min=0,max=100,step=5,getValue=function() return (Get("backgroundAlpha") or .72)*100 end,setValue=function(v) Set("backgroundAlpha",v/100) end}); y=y-h
        do
            local region=barRow._leftRegion; local ctrl=region._control
            local swatch,refresh=EllesmereUI.BuildColorSwatch(region,region:GetFrameLevel()+5,
                function() return Get("barR") or .035,Get("barG") or .035,Get("barB") or .035,1 end,
                function(r,g,b)
                    local p=P(); if p then p.barR,p.barG,p.barB=r,g,b end
                    if _G._EN_Apply then _G._EN_Apply() end
                end,false,18)
            if ctrl then swatch:SetPoint("RIGHT",ctrl,"LEFT",-8,0) end
            if EllesmereUI.RegisterWidgetRefresh then EllesmereUI.RegisterWidgetRefresh(refresh) end
        end
        local borderValues,borderOrder=EllesmereUI.GetBorderTextureDropdown()
        row,h=W:DualRow(parent,y,
            {type="dropdown",text="Border Style",values=borderValues,order=borderOrder,getValue=function() return Get("borderTexture") or "solid" end,setValue=function(v) Set("borderTexture",v); Set("borderOffsetX",0); Set("borderOffsetY",0) end},
            {type="slider",text="Border Size",min=0,max=4,step=1,getValue=function() return Get("borderSize") or 0 end,setValue=function(v) Set("borderSize",v) end}); y=y-h
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

        _,h=W:SectionHeader(parent,"NOTIFICATIONS",y); y=y-h
        local toggles={{"showItems","Items"},{"showCurrencies","Currencies"},{"showReputation","Reputation"},{"showHonor","Honor"},{"showExperience","Experience"},{"showGold","Gold"}}
        for i=1,#toggles,2 do
            local a,b=toggles[i],toggles[i+1]
            _,h=W:DualRow(parent,y,
                {type="toggle",text=a[2],getValue=function() return Get(a[1])~=false end,setValue=function(v) Set(a[1],v) end},
                {type="toggle",text=b[2],getValue=function() return Get(b[1])~=false end,setValue=function(v) Set(b[1],v) end}); y=y-h
        end
        _,h=W:DualRow(parent,y,
            {type="toggle",text="Item Quality Color",getValue=function() return Get("showItemQuality")~=false end,setValue=function(v) Set("showItemQuality",v) end},
            {type="toggle",text="Show Vendor Value",getValue=function() return Get("showItemValue")==true end,setValue=function(v) Set("showItemValue",v) end}); y=y-h

        -- Legacy rule editor intentionally retired. Kept unreachable for saved
        -- variable compatibility during this development cycle.
        if false then
        _,h=W:SectionHeader(parent,"ALERTS",y); y=y-h
        local glowValues,glowOrder={},{}
        if EllesmereUI.Glows and EllesmereUI.Glows.STYLES then
            for i,entry in ipairs(EllesmereUI.Glows.STYLES) do glowValues[i]=entry.name; glowOrder[#glowOrder+1]=i end
        end
        local conditionValues={RARE_BOE="Rare BoE",EPIC_BOE="Epic+ BoE",RARE_BOP="Rare BoP",EPIC_BOP="Epic+ BoP",RARE_ANY="Any Rare",EPIC_ANY="Any Epic+",BOE_ANY="Any BoE",BOA_ANY="Any Warbound / BoA"}
        local conditionOrder={"RARE_BOE","EPIC_BOE","RARE_BOP","EPIC_BOP","RARE_ANY","EPIC_ANY","BOE_ANY","BOA_ANY"}
        local soundValues={
            ["builtin:RAID_WARNING"]="Raid Warning",["builtin:READY_CHECK"]="Ready Check",
            ["builtin:QUEST_COMPLETE"]="Quest Complete",["builtin:LEVEL_UP"]="Level Up",
        }
        local soundOrder={"builtin:RAID_WARNING","builtin:READY_CHECK","builtin:QUEST_COMPLETE","builtin:LEVEL_UP"}
        local soundMedia=LSM and LSM:HashTable("sound") or {}
        local soundNames={}; for name in pairs(soundMedia) do soundNames[#soundNames+1]=name end; table.sort(soundNames)
        for _,name in ipairs(soundNames) do local key="lsm:"..name; soundValues[key]=name; soundOrder[#soundOrder+1]=key end
        local function Rules()
            local p=P()
            if not p then return nil end
            p.alertRules=p.alertRules or {}
            return p.alertRules
        end
        local function Rule(index)
            local rules=Rules(); return rules and rules[index]
        end
        local function SetRule(index,key,value)
            local rule=Rule(index); if rule then rule[key]=value end
            if _G._EN_Apply then _G._EN_Apply() end
        end
        local rules=Rules() or {}
        if #rules>0 then
            ns._selectedAlertRule=math.max(1,math.min(ns._selectedAlertRule or 1,#rules))
        else
            ns._selectedAlertRule=nil
        end
        local function RebuildAlerts()
            if _G._EN_Apply then _G._EN_Apply() end
            if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage(true) end
        end

        -- Compact rule cards modelled after the Class Resource threshold editor:
        -- select one rule here, edit only that rule below.
        local CPAD=EllesmereUI.CONTENT_PAD or 45
        local list=CreateFrame("Frame",nil,parent)
        list:SetPoint("TOPLEFT",parent,"TOPLEFT",CPAD,y)
        list:SetPoint("TOPRIGHT",parent,"TOPRIGHT",-CPAD,y)
        local CARD_H,GAP=34,5
        local function Card(index,rule)
            local b=CreateFrame("Button",nil,list)
            b:SetHeight(CARD_H)
            b:SetPoint("TOPLEFT",list,"TOPLEFT",0,-((index-1)*(CARD_H+GAP)))
            b:SetPoint("TOPRIGHT",list,"TOPRIGHT",0,-((index-1)*(CARD_H+GAP)))
            local selected=ns._selectedAlertRule==index
            local bg=b:CreateTexture(nil,"BACKGROUND"); bg:SetAllPoints()
            local EG=EllesmereUI.ELLESMERE_GREEN or {r=.05,g=.82,b=.62}
            bg:SetColorTexture(selected and EG.r or 1,selected and EG.g or 1,selected and EG.b or 1,selected and .10 or .025)
            local accent=b:CreateTexture(nil,"ARTWORK"); accent:SetPoint("TOPLEFT"); accent:SetPoint("BOTTOMLEFT"); accent:SetWidth(3)
            accent:SetColorTexture(EG.r,EG.g,EG.b,1); accent:SetShown(selected)
            local title=EllesmereUI.MakeFont(b,13,nil,1,1,1,.82)
            title:SetPoint("LEFT",b,"LEFT",12,0); title:SetJustifyH("LEFT")
            title:SetText((conditionValues[rule.condition] or "New Rule").."  |cff7f8792#"..index.."|r")
            local state=EllesmereUI.MakeFont(b,11,nil,rule.enabled and EG.r or .55,rule.enabled and EG.g or .55,rule.enabled and EG.b or .55,rule.enabled and .9 or .55)
            state:SetPoint("RIGHT",b,"RIGHT",-34,0); state:SetText(rule.enabled and "ACTIVE" or "OFF")
            local del=CreateFrame("Button",nil,b); del:SetSize(20,20); del:SetPoint("RIGHT",b,"RIGHT",-7,0)
            local x=EllesmereUI.MakeFont(del,12,nil,1,1,1,.38); x:SetPoint("CENTER"); x:SetText("X")
            del:SetScript("OnEnter",function() x:SetAlpha(.9) end); del:SetScript("OnLeave",function() x:SetAlpha(.38) end)
            del:SetScript("OnClick",function()
                table.remove(rules,index)
                if #rules==0 then ns._selectedAlertRule=nil else ns._selectedAlertRule=math.min(index,#rules) end
                RebuildAlerts()
            end)
            b:SetScript("OnClick",function() ns._selectedAlertRule=index; RebuildAlerts() end)
            b:SetScript("OnEnter",function() if not selected then bg:SetColorTexture(1,1,1,.06) end end)
            b:SetScript("OnLeave",function() if not selected then bg:SetColorTexture(1,1,1,.025) end end)
        end
        for i,rule in ipairs(rules) do Card(i,rule) end
        local addY=-#rules*(CARD_H+GAP)
        local add=CreateFrame("Button",nil,list); add:SetHeight(30)
        add:SetPoint("TOPLEFT",list,"TOPLEFT",0,addY); add:SetPoint("TOPRIGHT",list,"TOPRIGHT",0,addY)
        local addBg=add:CreateTexture(nil,"BACKGROUND"); addBg:SetAllPoints(); addBg:SetColorTexture(.05,.07,.09,.92)
        if EllesmereUI.MakeBorder then EllesmereUI.MakeBorder(add,1,1,1,.15,EllesmereUI.PanelPP or EllesmereUI.PP) end
        local addText=EllesmereUI.MakeFont(add,12,nil,1,1,1,.55); addText:SetPoint("CENTER"); addText:SetText("+ Add Alert Rule")
        add:SetScript("OnEnter",function() addText:SetAlpha(.85) end); add:SetScript("OnLeave",function() addText:SetAlpha(.55) end)
        local draft={condition="RARE_BOE",glow=true,glowStyle=6,sound=false,soundKey="builtin:RAID_WARNING"}
        local createPopup,showCreate
        createPopup,showCreate=EllesmereUI.BuildCogPopup({
            title="Create Alert Rule",minWidth=330,noOwnerDim=true,rows={
                {type="dropdown",label="Condition",values=conditionValues,order=conditionOrder,
                    get=function() return draft.condition end,set=function(v) draft.condition=v end},
                {type="toggle",label="Glow",get=function() return draft.glow end,set=function(v) draft.glow=v end},
                {type="dropdown",label="Glow Style",values=glowValues,order=glowOrder,
                    disabled=function() return not draft.glow end,
                    get=function() return draft.glowStyle end,set=function(v) draft.glowStyle=v end},
                {type="toggle",label="Sound",get=function() return draft.sound end,set=function(v) draft.sound=v end},
                {type="dropdown",label="Sound Selection",values=soundValues,order=soundOrder,
                    disabled=function() return not draft.sound end,
                    get=function() return draft.soundKey end,
                    set=function(v) draft.soundKey=v; if ns.PlayAlertSound then ns.PlayAlertSound(v) end end},
                {type="button",label="Create Rule",action=function()
                    rules[#rules+1]={
                        enabled=true,condition=draft.condition,
                        glow=draft.glow,glowStyle=draft.glowStyle,
                        sound=draft.sound,soundKey=draft.soundKey,
                    }
                    ns._selectedAlertRule=#rules
                    if showCreate and showCreate._popupFrame then showCreate._popupFrame:Hide() end
                    RebuildAlerts()
                end},
            },
        })
        add:SetScript("OnClick",function()
            draft.condition="RARE_BOE"; draft.glow=true; draft.glowStyle=6
            draft.sound=false; draft.soundKey="builtin:RAID_WARNING"
            showCreate(add)
            -- Alerts sits near the bottom of the options page. Open upward so the
            -- creation form never falls below the visible panel.
            local pf=showCreate._popupFrame
            if pf and pf:IsShown() then
                pf:SetScript("OnUpdate",pf._clickOutside)
                pf:SetAlpha(1); pf:ClearAllPoints(); pf:SetPoint("BOTTOM",add,"TOP",0,5)
            end
        end)
        local listH=#rules*(CARD_H+GAP)+30
        list:SetHeight(listH); y=y-listH-10

        local index=ns._selectedAlertRule
        if index then
            _,h=W:DualRow(parent,y,
                {type="toggle",text="Rule Enabled",getValue=function() local r=Rule(index); return r and r.enabled==true end,setValue=function(v) SetRule(index,"enabled",v); RebuildAlerts() end},
                {type="dropdown",text="Condition",values=conditionValues,order=conditionOrder,getValue=function() local r=Rule(index); return r and r.condition or "RARE_BOE" end,setValue=function(v) SetRule(index,"condition",v); RebuildAlerts() end}); y=y-h
            _,h=W:DualRow(parent,y,
                {type="toggle",text="Glow",getValue=function() local r=Rule(index); return r and r.glow~=false end,setValue=function(v) SetRule(index,"glow",v) end},
                {type="dropdown",text="Glow Style",values=glowValues,order=glowOrder,getValue=function() local r=Rule(index); return r and r.glowStyle or 6 end,setValue=function(v) SetRule(index,"glowStyle",v) end}); y=y-h
            _,h=W:DualRow(parent,y,
                {type="toggle",text="Sound",getValue=function() local r=Rule(index); return r and r.sound==true end,setValue=function(v) SetRule(index,"sound",v) end},
                {type="dropdown",text="Sound Selection",values=soundValues,order=soundOrder,getValue=function() local r=Rule(index); return r and r.soundKey or "builtin:RAID_WARNING" end,setValue=function(v) SetRule(index,"soundKey",v); if ns.PlayAlertSound then ns.PlayAlertSound(v) end end}); y=y-h
        end
        end
        parent:SetHeight(math.abs(y-startY))
    end

    local pages={"Notifications","Alerts","External Price Source"}
    EllesmereUI:RegisterModule("EllesmereUINotifications",{
        title="Notifications", description="Loot, currency and character progression notifications.",
        pages=pages, buildPage=Build,
        onReset=function() local p=P(); if p then wipe(p) end end,
    })
    SLASH_ELLESMERENOTIFICATIONS1="/enotify"
    SlashCmdList.ELLESMERENOTIFICATIONS=function()
        if InCombatLockdown and InCombatLockdown() then print("Cannot open options in combat"); return end
        EllesmereUI:ShowModule("EllesmereUINotifications")
    end
end)
