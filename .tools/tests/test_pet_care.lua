-- Run from the repository root with Lua 5.1.
local root = arg[1] or "."
local ns = {}
local function Load(file) assert(loadfile(root .. "/EllesmereUIPetCare/" .. file))("EllesmereUIPetCare", ns) end
Load("EllesmereUIPetCare_Model.lua")
Load("EllesmereUIPetCare_Foods.lua")
assert(ns.FOODS == nil, "food database must be lazy")
ns.LoadFoodData()
local M = ns.Model
local function Same(actual, expected) assert(actual == expected, tostring(actual) .. " ~= " .. tostring(expected)) end
local function Stack(id, count, extra)
    local t = { id = id, count = count, bag = 0, slot = id }
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
end
local foods = { [1]={1,5,1}, [2]={2,10,1}, [3]={1,20,2}, [4]={1,15,3}, [5]={2,20,4} }
local cfg = {order="most", preferred={}, blacklist={}, customFoods={}}
local diet = {[1]=true}
local stacks = {Stack(1,10), Stack(1,5), Stack(2,80), Stack(3,50), Stack(4,40)}
local list = M.Candidates(stacks,cfg,diet,10,foods)
Same(#list,1); Same(list[1].count,15)
cfg.cooked = true
list = M.Candidates(stacks,cfg,diet,10,foods)
Same(list[1].id,3)
cfg.order = "least"
Same(M.Candidates(stacks,cfg,diet,10,foods)[1].id,1)
cfg.order = "level"
Same(M.Candidates(stacks,cfg,diet,10,foods)[1].id,3)
cfg.preferred = {1,3}
Same(M.Candidates(stacks,cfg,diet,10,foods)[1].id,1)
cfg.blacklist[1] = true
Same(M.Candidates(stacks,cfg,diet,10,foods)[1].id,3)
cfg.preferredOnly = true; cfg.preferred = {}
Same(#M.Candidates(stacks,cfg,diet,10,foods),0)
cfg.preferredOnly = false; cfg.rawMeat = true
Same(#M.Candidates(stacks,cfg,diet,10,foods),2)
cfg.customFoods[2] = {1,10,2}
Same(#M.Candidates(stacks,cfg,diet,10,foods),3)
Same(#M.Candidates({Stack(3,4,{locked=true}),Stack(4,3,{quest=true})},cfg,diet,10,foods),0)
Same(#M.Candidates(stacks,cfg,diet,100,foods),0)
list = {{id=1},{id=2},{id=3}}
Same(M.Select(list,2,false).id,2)
Same(M.Select(list,2,true).id,3)
Same(M.Select(list,3,true).id,1)
Same(M.Select(list,99,true).id,1)
Same(M.Select({},1,true),nil)
Same(M.Diet(ns.FOOD_NAMES.deDE,{"Fleisch","Fisch"})[1],true)
Same(M.Diet(ns.FOOD_NAMES.deDE,{"Fleisch","Fisch"})[3],nil)
Same(#M.ParseIDs("117, 787,117"),2)
Same(M.ParseIDs("117, bad"),nil)
Same(M.ParseIDs("1e309"),nil)
Same(M.ParseIDs("2147483648"),nil)
Same(M.IsItemID(math.huge),false)
Same(M.IsItemID(117),true)

local combat, shift, aura, mood, shown = false,false,nil,2,true
local restricted, auraError = false, false
local queued, built, registrations, attributes = {}, {}, {}, 0
local function Safe() assert(not combat,"protected mutation in combat") end
local methods = {}
function methods:SetScript(key,fn) self.scripts[key]=fn end
function methods:RegisterEvent(event) self.events[event]=true end
function methods:UnregisterEvent(event) self.events[event]=nil end
function methods:UnregisterAllEvents() self.events={} end
function methods:SetAttribute(key,value) Safe(); attributes=attributes+1; self.attrs[key]=value end
function methods:SetParent(p) Safe(); self.parent=p end
function methods:GetParent() return self.parent end
function methods:SetAllPoints() Safe() end
function methods:ClearAllPoints() Safe() end
function methods:GetFrameLevel() return 5 end
function methods:SetFrameLevel() Safe() end
function methods:GetWidth() return 20 end
function methods:GetHeight() return 20 end
function methods:IsShown() return shown end
function methods:IsMouseOver() return false end
function methods:RegisterForClicks() end
function methods:SetDrawEdge() end
function methods:SetHideCountdownNumbers() end
function methods:EnableMouse() end
function methods:Clear() end
function methods:SetCooldown() end
function methods:SetSize() end
function methods:SetPoint() Safe() end
function methods:SetFrameStrata(value) self.strata=value end
function methods:SetTextColor() end
function methods:SetText(value)
    assert(self.font, "Font not set")
    self.textValue = value
end
function methods:SetFont(path)
    self.font = path
    return true
end
function methods:SetIgnoreParentScale() end
function methods:Show() self.visible = true end
function methods:Hide() self.visible = false end
function methods:CreateFontString(_,_,template)
    return setmetatable({font=template}, {__index=methods})
end
function CreateFrame(_,name,parent,template)
    local f=setmetatable({scripts={},events={},attrs={},parent=parent,name=name,template=template},{__index=methods})
    built[#built+1]=f
    return f
end
local petFrame=CreateFrame("Frame")
local icon=CreateFrame("Frame",nil,petFrame)
local uf={GetPetHappinessIcon=function() return icon end}
local db
local function Clone(t)
    local copy={}
    for k,v in pairs(t) do copy[k]=type(v)=="table" and Clone(v) or v end
    return copy
end
EllesmereUI={_ModuleNS={EllesmereUIUnitFrames=uf},L=function(s) return s end,
    AuraKit={AurasRestricted=function() return restricted end},
    Lite={NewAddon=function() ns.addon={} return ns.addon end,
          NewDB=function(_,defaults) db={profile=Clone(defaults.profile)} return db end},
    NewCombatQueue=function() return {Defer=function(key,fn) queued[key]=fn end} end,
    Glows={StopGlow=function() end,SpecFromPrefix=function(_,cfg)
        return cfg.feedGlowType > 0 and {} or nil end,StartSpecGlow=function() end},
    ShowWidgetTooltip=function() end, HideWidgetTooltip=function() end, GetFontPath=function() return "font" end}
function InCombatLockdown() return combat end
function IsShiftKeyDown() return shift end
function UnitClass() return "Hunter","HUNTER" end
function UnitExists() return true end
function UnitIsDead() return false end
function UnitAffectingCombat() return false end
function UnitLevel() return 10 end
function HasPetUI() return true,true end
function GetLocale() return "enUS" end
function issecretvalue() return false end
function RegisterStateDriver(frame,_,condition) Safe(); frame.driver=condition end
NUM_BAG_SLOTS=0
Enum={ItemClass={Consumable=0,Tradegoods=7}}
local bag={{itemID=117,stackCount=5},{itemID=2287,stackCount=3}}
C_Container={GetContainerNumSlots=function() return #bag end,
    GetContainerItemInfo=function(_,slot) return bag[slot] end,
    GetContainerItemQuestInfo=function() return {} end}
C_Item={GetItemInfoInstant=function(id) return id,nil,nil,nil,nil,0 end,
    GetItemNameByID=function(id) return tostring(id) end,RequestLoadItemDataByID=function() end}
C_PetInfo={GetPetFoodTypes=function() return {"Meat"} end,GetPetHappiness=function() return mood end}
C_SpellBook={IsSpellKnown=function() return true end}
C_Spell={IsSpellUsable=function() return true end,GetSpellName=function() return "Feed Pet" end}
C_UnitAuras={GetUnitAuraBySpellID=function()
    assert(not restricted, "must not query restricted auras")
    if auraError then error("aura restriction changed") end
    return aura end}
SlashCmdList={}
Load("EllesmereUIPetCare.lua")
ns.addon:OnInitialize(); ns.addon:OnEnable()
for _,f in ipairs(built) do Same(next(f.events),nil) end
Same(uf.PetCareRefresh,nil)
db.profile.enabled=true; ns.Apply()
local button
for _,f in ipairs(built) do if f.name=="EllesmereUIPetCareFeedButton" then button=f end end
assert(button)
Same(ns.Selected().id,117)
bag[2].stackCount=9; ns.Refresh()
Same(ns.Selected().id,2287)
bag[2].stackCount=3; ns.Refresh()
Same(ns.Selected().id,117)
assert(button.attrs.macrotext1:find("/use [nocombat,@pet,exists,nodead] 0 1",1,true))
Same(button.attrs["shift-type1"],"")
local warning
for _,f in ipairs(built) do assert(f.name~="EllesmereUIPetCareWarning", "warning must be opt-in") end
db.profile.screenWarning=true; ns.Refresh()
for _,f in ipairs(built) do if f.name=="EllesmereUIPetCareWarning" then warning=f end end
assert(warning and warning.visible)
Same(warning.text.textValue,"Your pet needs feeding!")
mood=3; ns.Refresh(); Same(warning.visible,false)
mood=2; db.profile.warningAt=1; ns.Refresh(); Same(warning.visible,false)
db.profile.warningAt=2; ns.Refresh(); Same(warning.visible,true)
db.profile.screenWarning=false; ns.Apply(); Same(warning.visible,false)
ns.SetWarningPreview(true); Same(warning.visible,true)
Same(warning.strata,"FULLSCREEN_DIALOG")
ns.Apply(); Same(ns.WarningPreviewActive(),true); Same(warning.visible,true)
assert(warning.events.PLAYER_REGEN_DISABLED)
db.profile.warningSize=40; ns.UpdateWarning(); Same(warning.visible,true)
combat=true; warning.scripts.OnEvent(); Same(warning.visible,false)
Same(ns.WarningPreviewActive(),false); Same(next(warning.events),nil)
combat=false
ns.SetWarningPreview(true); ns.SetWarningPreview(false); Same(warning.visible,false)
db.profile.screenWarning=true; ns.Apply(); Same(warning.visible,true)
Same(warning.strata,"HIGH")
mood=3; ns.Refresh(); Same(button.attrs.macrotext1,nil)
Same(ns.Status(),"Your pet does not need feeding.")
shift=true; button.scripts.PreClick(); Same(ns.Selected().id,117)
shift=false; button.scripts.PreClick(); Same(button.attrs.macrotext1,nil)
db.profile.selectedFood=nil; mood=2; ns.Refresh()
db.profile.feedGlowType=0; ns.Refresh(); Same(button.attrs.macrotext1,nil)
shift=true; button.scripts.PreClick(); Same(ns.Selected().id,117)
shift=false
db.profile.feedGlowType=2; ns.Refresh(); assert(button.attrs.macrotext1)
shift=true; button.scripts.PreClick()
Same(ns.Selected().id,2287)
shift=false; button.scripts.PreClick()
Same(ns.Selected().id,2287)
aura={duration=10,expirationTime=50}; ns.Refresh()
Same(button.attrs.macrotext1,nil)
shift=true; button.scripts.PreClick(); Same(ns.Selected().id,2287)
shift=false
Same(warning.visible,false)
aura=nil
restricted=true; ns.Refresh(); Same(button.attrs.macrotext1,nil); Same(warning.visible,false)
restricted=false; auraError=true; ns.Refresh(); Same(button.attrs.macrotext1,nil)
auraError=false; ns.Refresh(); assert(button.attrs.macrotext1)
bag={{itemID=117,stackCount=5}}; ns.Refresh()
Same(ns.Selected().id,117)
combat=true
local before=attributes
ns.Refresh(); db.profile.enabled=false; ns.Apply()
Same(attributes,before)
Same(warning.visible,false)
assert(queued.apply and queued.refresh)
combat=false
queued.apply(); queued.refresh()
Same(button.attrs.macrotext1,nil); Same(button.driver,"hide")
Same(uf.PetCareRefresh,nil)
db.profile.enabled=true; ns.Apply()
shown=false; uf.PetCareRefresh()
Same(button.driver,"hide"); Same(ns.Selected(),nil)
local module
local cogs={}
local refreshes={}
EllesmereUI.EYE_VISIBLE_ICON="eye"
EllesmereUI.EYE_INVISIBLE_ICON="eye-active"
EllesmereUI.GlowOptions={
    PrefixSite=function() return {} end,
    RegisterSite=function(entry) assert(entry.label and entry.page and entry.desc) end,
    DropdownSpec=function() return {type="dropdown",text="Feeding Glow",values={}} end,
    AttachInline=function() end,
    BuildPreview=function(_,_,opts) Same(opts.atlas,"UI-PetHappiness") end,
}
EllesmereUI.Widgets={
    SectionHeader=function() return nil,20 end,
    DualRow=function(_,_,_,left,right)
        assert(left and right and left.type and right.type)
        assert(left.text~="Test Screen Warning" and right.text~="Test Screen Warning")
        assert(left.text~="Warn When" and right.text~="Warn When")
        if left.getValue then left.getValue() end
        if right.getValue then right.getValue() end
        return {_leftRegion={},_rightRegion={}},50
    end,
}
EllesmereUI.BuildNoteRow=function(_,y) return y-40 end
EllesmereUI.BuildInlineCog=function(_,opts)
    local b={_euiCogState=function() end}
    b._icon={SetTexture=function(_,value) b.icon=value end}
    opts.button=b
    cogs[#cogs+1]=opts
    return b
end
EllesmereUI.BlankRowCfg=function() return {type="label",text=""} end
EllesmereUI.SetContentHeader=function(_,builder) Same(builder({}),76) end
EllesmereUI.RegisterWidgetRefresh=function(fn) refreshes[#refreshes+1]=fn end
EllesmereUI.RegisterOnHide=function() end
EllesmereUI.RegisterOnCollapse=function() end
EllesmereUI.RefreshPage=function() for _,fn in ipairs(refreshes) do fn() end end
EllesmereUI.RegisterModule=function(_,name,cfg) Same(name,"EllesmereUIPetCare");module=cfg end
assert(loadfile(root .. "/EllesmereUIOptions/EUI_PetCare_Options.lua"))()
assert(module.buildPage("Pet Feeding",{},0)>0)
local eye, warningSettings
for _,cfg in ipairs(cogs) do
    if cfg.icon=="eye" then eye=cfg end
    if cfg.title=="Screen Warning Settings" then warningSettings=cfg end
end
assert(eye and warningSettings)
Same(warningSettings.rows[1].label,"Warn When")
Same(eye.button.icon,"eye")
eye.show(); Same(ns.WarningPreviewActive(),true); Same(warning.strata,"FULLSCREEN_DIALOG")
Same(eye.button.icon,"eye-active")
eye.show(); Same(ns.WarningPreviewActive(),false); Same(eye.button.icon,"eye")
assert(module.buildPage("Food Database",{},0)>0)
print("PASS: pet food database/model, localized diet, priorities, exclusions, cycling, secure macro, feeding effect, combat deferral, enable/disable")
