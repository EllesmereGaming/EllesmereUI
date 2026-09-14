local e, damage, healing, extra = EllesmereUI, unpack(DM._windows)
local frameCount = #FRAMES
DM.ApplyChatMeters()
assert(#FRAMES == frameCount and not DM._chatMeters, "Disabled means no host, frames, events or hooks")
CONFIG.chatEmbedEnabled = true
DM.RegisterDMUnlock()
local host = DM._chatMeters
assert(host and host.enabled and not host.active)
assert(VISIBILITY_GENERATION==1, "Adoption invalidates the cached mouseover predicate")
assert(damage.frame:GetParent()==host.body and healing.frame:GetParent()==host.body)
assert(extra.frame:GetParent()==UIParent and extra.frame:IsVisible())
assert(host.button:IsShown() and host.button:GetParent()==CHAT_DATA.sidebar)
local _, anchor = CHAT_DATA.settingsBtn:GetPoint()
assert(anchor==host.button, "Sidebar entry precedes Settings")
host:SetActive(true)
assert(damage.frame:IsVisible() and healing.frame:IsVisible())
assert(CHAT._chatWins[ChatFrame1].smf:GetAlpha()==0)
assert(damage.frame._bg:GetAlpha()==0 and damage.header._hdrBg:GetAlpha()==0)
for _, b in ipairs(damage.hdrBtns) do assert(b:IsVisible(), "Every header button remains") end
assert(not damage.resizeGrip:IsVisible() and not damage.lockBtn:IsVisible())

local parentChanges = damage.frame.parentChanges
local element = e._unlockRegisteredElements.EDM_Win1
local originalVisibility = damage.UpdateVisibility
for flags=0,15 do
    EDIT_MODE=flags%2==1
    e._unlockActive=math.floor(flags/2)%2==1
    DM._optionsOpen=math.floor(flags/4)%2==1
    CHAT._chatSizingActive=math.floor(flags/8)%2==1
    for _, active in ipairs({false,true}) do
        host:SetActive(active)
        DM.ApplyDMSize()
        damage.ApplyPosition()
        damage.UpdateVisibility()
        damage.frame:Show() -- settings preview uses direct Show calls
        assert(damage.frame:GetParent()==host.body and damage.frame:IsVisible()==active)
        assert(host.button:IsShown() and damage.frame.parentChanges==parentChanges)
        assert(element.getFrame("EDM_Win1")==nil)
        element.setWidth("EDM_Win1",900)
        element.setHeight("EDM_Win1",900)
        element.savePos("EDM_Win1","CENTER","CENTER",7,8)
        element.clearPos("EDM_Win1")
        assert(SAVED.width==375 and SAVED.height==180 and SAVED.position.x==1000)
    end
end
assert(damage.UpdateVisibility==originalVisibility)
e._unlockActive, DM._optionsOpen, CHAT._chatSizingActive = false, false, false
host:SetActive(true)
local refreshes=damage.refreshes
for width=160,700,20 do
    PANEL:SetSize(width,300)
    assert(damage.frame:GetWidth()==(width-8)/2)
    assert(damage.frame:GetParent()==host.body and damage.frame:IsVisible())
end
assert(damage.refreshes==refreshes, "Resize only changes geometry, not combat-data fetches")
assert(damage.frame.parentChanges==parentChanges)
assert(element.getSize("EDM_Win1")==375, "Mover size is the saved standalone size")
HIDE_METERS=true; damage.UpdateVisibility(); assert(damage.frame:IsVisible()); HIDE_METERS=false

ChatFrame1Tab.mouseOver=true
Event("GLOBAL_MOUSE_DOWN","LeftButton")
ChatFrame1Tab.mouseOver=false
assert(not host.active and not damage.frame:IsVisible())
assert(CHAT._chatWins[ChatFrame1].smf:GetAlpha()==1)
host:SetActive(true)
SELECTED=ChatFrame2; CHAT._onMetersSelectionChanged(SELECTED)
assert(not host.active)
CHAT.ECHAT.EngineUpdateCombatLogHost()
host:SetActive(true)
assert(ChatFrame2.FontStringContainer:GetAlpha()==0 and CombatLogQuickButtonFrame_Custom:GetAlpha()==0)
host:SetActive(false)
assert(ChatFrame2.FontStringContainer:GetAlpha()==1 and CombatLogQuickButtonFrame_Custom:GetAlpha()==1)
host:SetActive(true)
SELECTED=ChatFrame1; CHAT._onMetersSelectionChanged(SELECTED)
assert(ChatFrame2.FontStringContainer:GetAlpha()==0, "Selection change cannot reveal deselected log")

ZONE_KIND,ZONE_ID="party",1; Event("ZONE_CHANGED_NEW_AREA")
assert(not host.active, "Auto dungeon defaults off")
CONFIG.chatEmbedAutoDungeon=true
ZONE_ID=2; Event("ZONE_CHANGED_NEW_AREA"); assert(host.active)
host:SetActive(false); Event("PLAYER_ENTERING_WORLD"); assert(not host.active)
CONFIG.chatEmbedAutoRaid=true
ZONE_KIND,ZONE_ID="raid",3; Event("ZONE_CHANGED_NEW_AREA"); assert(host.active)
ZONE_KIND,ZONE_ID="none",0; Event("ZONE_CHANGED_NEW_AREA"); assert(host.active)
CONFIG.chatEmbedReturnOnExit=true
ZONE_KIND,ZONE_ID="raid",4; Event("ZONE_CHANGED_NEW_AREA")
ZONE_KIND,ZONE_ID="none",0; Event("ZONE_CHANGED_NEW_AREA"); assert(not host.active)

CHAT_CONFIG.showSettings=false; CHAT.ECHAT.ApplySidebarIcons()
assert(host.button:IsShown() and not CHAT_DATA.settingsBtn:IsShown())
CHAT_CONFIG.sidebarVisibility="never"; CHAT.ECHAT.ApplySidebarIconVisibility()
assert(not host.button:IsShown())
CHAT_CONFIG.sidebarVisibility="always"; CHAT.ECHAT.ApplySidebarIcons()
host:SetActive(true)
CHAT._chatPassthrough=true; CHAT._onMetersHostChanged()
assert(not damage.frame:IsVisible() and damage.frame:GetParent()==host.body)
CHAT._chatPassthrough=false; CHAT._onMetersHostChanged(); assert(damage.frame:IsVisible())
local panel=CHAT_DATA.bg; CHAT_DATA.bg=nil; CHAT._onMetersHostChanged()
assert(not host.root:IsShown() and damage.frame:GetParent()==host.body)
CHAT_DATA.bg=panel; CHAT._onMetersHostChanged(); assert(damage.frame:IsVisible())
CHAT_CONFIG.enabled=false; CHAT._onMetersHostChanged()
assert(not damage.frame:IsVisible() and damage.frame:GetParent()==host.body)
CHAT_CONFIG.enabled=true; CHAT._onMetersHostChanged()

damage.curDMType=5; DM.ApplyChatMeters(); assert(host.left==damage)
host:Retire(healing); healing.frame:Hide(); healing.frame:SetParent(nil)
table.remove(DM._windows,2); DM.ApplyChatMeters()
assert(host.left==damage and not host.right and damage.frame:IsVisible() and host.button:IsShown())
local replacement=NewWindow(2); replacement.idx=3; InstallWindowWriters(replacement)
table.insert(DM._windows,replacement); DM.RegisterDMUnlock()
assert(host.right==replacement and replacement.frame:GetParent()==host.body)

CONFIG.chatEmbedEnabled=false; DM.ApplyChatMeters()
assert(not host.enabled and not host.button:IsShown() and not next(host.events.events))
assert(not CHAT._onMetersHostChanged and not CHAT._onMetersSelectionChanged and not CHAT._onMetersStyleChanged)
assert(VISIBILITY_GENERATION>=3, "Disable invalidates mouseover visibility")
assert(damage.frame:GetParent()==UIParent and damage.frame:GetWidth()==375)
assert(damage.frame._bg:GetAlpha()==1 and damage.header._hdrBg:GetAlpha()==1)
assert(damage.resizeGrip:GetParent()==damage.frame and not damage._chatHost)
assert(element.getFrame("EDM_Win1")==damage.frame)
frameCount=#FRAMES; DM.ApplyChatMeters(); assert(#FRAMES==frameCount)
CONFIG.chatEmbedEnabled=true; DM.ApplyChatMeters(); assert(#FRAMES==frameCount, "Reuse lazily allocated host")
-- Profile rebuild: retired frames stay dead; replacements are adopted in the
-- same lifecycle call, while a profile with embedding off stays standalone.
for i=#DM._windows,1,-1 do
    local w=DM._windows[i]
    if w._chatHost then host:Retire(w) end
    w.frame:Hide(); w.frame:SetParent(nil); table.remove(DM._windows,i)
end
DM.ApplyChatMeters(); assert(host.waiting:IsShown() and host.button:IsShown())
DM._windows[1]=NewWindow(0); DM._windows[1].idx=1; InstallWindowWriters(DM._windows[1])
DM.ApplyChatMeters(); assert(DM._windows[1].frame:GetParent()==host.body)
CONFIG.chatEmbedEnabled=false; DM.ApplyChatMeters()
assert(DM._windows[1].frame:GetParent()==UIParent and not healing.frame:IsShown())
