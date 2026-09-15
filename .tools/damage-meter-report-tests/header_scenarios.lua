-- Execute the real window's report-button lifecycle with lightweight controls.
local cfg, created, opened, closed = {}, 0, 0, 0
local W = {settingsBtn={}, segmentBtn={}, modeBtn={}, resetBtn={}, winActionBtn={}}
W.hdrBtns = {W.settingsBtn, W.segmentBtn, W.modeBtn, W.resetBtn, W.winActionBtn}
local env = setmetatable({
    W = W,
    DB = function() return cfg end,
    EllesmereUI = {L=function(s) return s end},
    ns = {Report={
        Open=function(window) assert(window==W); opened=opened+1 end,
        Close=function(window) assert(window==W); closed=closed+1 end,
    }},
    MakeHeaderBtn=function(texture, offset, tooltip, click)
        created=created+1
        assert(texture=="dm_report.png" and tooltip=="Report to Chat")
        return {Click=click, Hide=function(self) self.hidden=true end}
    end,
}, {__index=_G})
local factory=assert(loadstring(REPORT_BUTTON_SOURCE, "report-button lifecycle"))
setfenv(factory, env); factory()
W.SyncReportButton()
assert(created==0 and #W.hdrBtns==5, "default-off builds no button")
cfg.reportEnabled=true
local hooked=0
W.HookHeaderButton=function(button) assert(button==W.reportBtn); hooked=hooked+1 end
W.SyncReportButton()
assert(created==1 and #W.hdrBtns==6 and W.hdrBtns[4]==W.reportBtn, "enable inserts report control")
assert(hooked==1, "late-created report button inherits header hover behavior")
assert(W.hdrBtns[5]==W.resetBtn and W.hdrBtns[6]==W.winActionBtn, "existing controls keep order")
W.reportBtn.Click()
assert(opened==1, "click reports from owning window")
W.SyncReportButton()
assert(created==1 and #W.hdrBtns==6, "header refresh does not duplicate controls")
cfg.reportEnabled=false
W.SyncReportButton()
assert(W.reportBtn.hidden and #W.hdrBtns==5 and closed==1, "disable hides control and closes dialog")
cfg.reportEnabled=true
W.SyncReportButton()
assert(created==1 and #W.hdrBtns==6, "re-enable reuses control")
assert(hooked==1, "re-enable does not duplicate hover hooks")
assert(W.hdrBtns[1]==W.settingsBtn and W.hdrBtns[3]==W.modeBtn, "other header controls unchanged")
print("PASS: header opt-in, ordering, ownership, disable and re-enable scenarios")
