if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if EllesmereUI.IS_FOREVER then return end -- no premade group list on WoW Forever: no hooks, no API (the option rows are not built there)
-------------------------------------------------------------------------------
--  EllesmereUI_SignupHelpers.lua
--  Premade group sign-up helpers. Quality of Life's and Group Finder's option
--  rows drive the same account-wide settings on EllesmereUIDB:
--
--  Quick Signup (quickSignup): double-clicking a group listing signs up, the
--  Sign Up dialog confirms itself, and the Dungeon Finder role check accepts
--  itself with the saved roles. Holding Shift keeps either dialog open.
--
--  Persistent Signup Note (persistSignupNote, the note in signupNote): the
--  Sign Up dialog keeps the note typed into it between sign-ups, and a Copy
--  button beside the note field offers the saved note for Ctrl+C.
--
--  API: EllesmereUI._applyQuickSignup() / _applyPersistSignupNote() after a
--  setting changes, EllesmereUI.GetPersistentSignupNote() /
--  SetPersistentSignupNote(note). The saved state is applied at PLAYER_LOGIN
--  while Quality of Life or Group Finder is loaded (the API does nothing
--  before it, or at all with neither loaded). Nothing is hooked until a
--  setting is first turned on; hooks cannot be removed, so their bodies
--  return at once while it is off, and the role-check event is registered
--  only while Quick Signup is on.
-------------------------------------------------------------------------------

local ready = false   -- set at PLAYER_LOGIN

-------------------------------------------------------------------------------
--  Quick Signup
-------------------------------------------------------------------------------
local lastClickTime  = 0
local lastClickEntry = nil
local DOUBLE_CLICK_THRESHOLD = 0.4
local installed = false   -- hooks are installed ONCE, on first enable
local roleFrame           -- Dungeon Finder role-check listener (created on install)

local function InstallQuickSignupHooks()
    if installed then return end
    installed = true

    hooksecurefunc("LFGListSearchEntry_OnClick", function(entry, button)
        if not (EllesmereUIDB and EllesmereUIDB.quickSignup) then return end
        if button == "RightButton" then return end

        local panel = LFGListFrame and LFGListFrame.SearchPanel
        if not panel then return end
        -- Blizzard's select check tests the result's fields, which are secret
        -- during chat messaging lockdown: stand down instead of erroring.
        local resultID = entry.resultID
        if issecretvalue(resultID) then return end
        local info = C_LFGList.GetSearchResultInfo(resultID)
        if type(info) ~= "table" or issecretvalue(info) or not canaccesstable(info)
            or issecretvalue(info.isDelisted) then return end
        if not LFGListSearchPanelUtil_CanSelectResult(resultID) then return end
        if not panel.SignUpButton or not panel.SignUpButton:IsEnabled() then return end

        local now = GetTime()
        if lastClickEntry == resultID and (now - lastClickTime) < DOUBLE_CLICK_THRESHOLD then
            if panel.selectedResult ~= resultID then
                LFGListSearchPanel_SelectResult(panel, resultID)
            end
            LFGListSearchPanel_SignUp(panel)
            lastClickEntry = nil
            lastClickTime  = 0
        else
            lastClickEntry = resultID
            lastClickTime  = now
        end
    end)

    -- Confirm the Sign Up dialog; holding Shift keeps it open (e.g. to type a
    -- signup note).
    if LFGListApplicationDialog then
        LFGListApplicationDialog:HookScript("OnShow", function(self)
            if not (EllesmereUIDB and EllesmereUIDB.quickSignup) then return end
            if self.SignUpButton:IsEnabled() and not IsShiftKeyDown() then
                self.SignUpButton:Click()
            end
        end)
    end

    -- Dungeon Finder role check
    roleFrame = CreateFrame("Frame")
    roleFrame:SetScript("OnEvent", function()
        if not (EllesmereUIDB and EllesmereUIDB.quickSignup) then return end
        if not UnitInParty("player") then return end
        -- Holding Shift skips the auto role-check accept
        if IsShiftKeyDown() then return end
        local leader, tank, healer, dps = GetLFGRoles()
        if LFDRoleCheckPopupRoleButtonTank.checkButton:IsEnabled() then
            LFDRoleCheckPopupRoleButtonTank.checkButton:SetChecked(tank)
        end
        if LFDRoleCheckPopupRoleButtonHealer.checkButton:IsEnabled() then
            LFDRoleCheckPopupRoleButtonHealer.checkButton:SetChecked(healer)
        end
        if LFDRoleCheckPopupRoleButtonDPS.checkButton:IsEnabled() then
            LFDRoleCheckPopupRoleButtonDPS.checkButton:SetChecked(dps)
        end
        LFDRoleCheckPopupAcceptButton:Enable()
        LFDRoleCheckPopupAcceptButton:Click()
    end)
end

-- Installs the hooks on first enable and matches the role-check event to the
-- setting.
EllesmereUI._applyQuickSignup = function()
    if not ready then return end
    local on = EllesmereUIDB and EllesmereUIDB.quickSignup
    if on then InstallQuickSignupHooks() end
    if roleFrame then
        if on then
            roleFrame:RegisterEvent("LFG_ROLE_CHECK_SHOW")
        else
            roleFrame:UnregisterEvent("LFG_ROLE_CHECK_SHOW")
        end
    end
end

-------------------------------------------------------------------------------
--  Persistent Signup Note
-------------------------------------------------------------------------------
local vanilla            -- Blizzard's LFGListApplicationDialog_Show, taken at PLAYER_LOGIN
local patched = false
local copyHooked = false
local copyHelper
local hidingCopyField = false

local function LimitNote(text)
    if type(text) ~= "string" then return "" end
    text = text:gsub("[\r\n]+", " ")
    local bytes, position, count, last = #text, 1, 0, 0
    while position <= bytes and count < 63 do
        local byte = text:byte(position)
        local width = byte < 128 and 1 or byte < 224 and 2 or byte < 240 and 3 or 4
        if position + width - 1 > bytes then break end
        last = position + width - 1
        position = last + 1
        count = count + 1
    end
    return text:sub(1, last)
end

local function SavedNote()
    return LimitNote(EllesmereUIDB and EllesmereUIDB.signupNote)
end

local function NoteEnabled()
    return EllesmereUIDB and EllesmereUIDB.persistSignupNote
end

local function HideCopyField(focusTarget)
    if not copyHelper then return end
    copyHelper.buttonText:SetText(EllesmereUI.L("Copy"))
    if copyHelper.copyBox:IsShown() then
        hidingCopyField = true
        copyHelper.copyBox:Hide()
        copyHelper.copyBox:ClearFocus()
        hidingCopyField = false
    end
    if focusTarget and copyHelper.targetEditBox then
        copyHelper.targetEditBox:SetFocus()
    end
end

local function RefreshCopyHelper(dialog)
    if not NoteEnabled() or not dialog or not dialog:IsShown() then return end
    local description = dialog and dialog.Description
    local editBox = description and description.EditBox
    if not editBox then return end
    if SavedNote() == "" then
        if copyHelper then copyHelper:Hide() end
        return
    end

    if not copyHelper then
        local EG = EllesmereUI.ELLESMERE_GREEN
        local FONT = EllesmereUI.GetFontPath("main")
            or EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF"
        local PP = EllesmereUI.PP

        local helper = CreateFrame("Frame", nil, dialog)
        helper:SetAllPoints(dialog)
        helper:EnableMouse(false)

        local button = CreateFrame("Button", nil, helper)
        button:SetSize(42, 20)
        button:SetPoint("LEFT", description, "RIGHT", 4, 0)
        button:EnableMouse(true)

        local buttonBg = button:CreateTexture(nil, "BACKGROUND")
        buttonBg:SetAllPoints()
        buttonBg:SetColorTexture(0.030, 0.023, 0.018, 0.92)
        local buttonBorder = EllesmereUI.MakeBorder(button, EG.r, EG.g, EG.b, 0.72, PP)

        local buttonText = button:CreateFontString(nil, "OVERLAY")
        buttonText:SetFont(FONT, 9, "")
        buttonText:SetPoint("CENTER", 0, 0)
        buttonText:SetText(EllesmereUI.L("Copy"))
        buttonText:SetTextColor(EG.r, EG.g, EG.b, 0.92)

        local copyBox = CreateFrame("EditBox", nil, helper)
        copyBox:SetPoint("TOPLEFT", description, "TOPLEFT", 0, 0)
        copyBox:SetPoint("BOTTOMRIGHT", description, "BOTTOMRIGHT", 0, 0)
        copyBox:SetAutoFocus(false)
        copyBox:SetFont(FONT, 11, "")
        copyBox:SetTextColor(1, 1, 1, 0.96)
        copyBox:SetTextInsets(5, 5, 0, 0)
        copyBox:SetJustifyH("LEFT")
        copyBox:SetHighlightColor(EG.r, EG.g, EG.b, 0.45)
        copyBox:EnableMouse(true)
        local copyBg = copyBox:CreateTexture(nil, "BACKGROUND")
        copyBg:SetAllPoints()
        copyBg:SetColorTexture(0.030, 0.023, 0.018, 1)
        EllesmereUI.MakeBorder(copyBox, EG.r, EG.g, EG.b, 0.9, PP)
        copyBox:Hide()

        copyBox:SetScript("OnEditFocusLost", function()
            if not hidingCopyField and not button:IsMouseOver() then
                HideCopyField(false)
            end
        end)
        copyBox:SetScript("OnKeyUp", function(_, key)
            if key == "C" and IsControlKeyDown() then
                HideCopyField(true)
            end
        end)

        button:SetScript("OnEnter", function()
            buttonBorder:SetColor(EG.r, EG.g, EG.b, 1)
            buttonText:SetTextColor(EG.r, EG.g, EG.b, 1)
        end)
        button:SetScript("OnLeave", function()
            buttonBorder:SetColor(EG.r, EG.g, EG.b, 0.72)
            buttonText:SetTextColor(EG.r, EG.g, EG.b, 0.92)
        end)
        button:SetScript("OnClick", function()
            if copyBox:IsShown() then
                HideCopyField(false)
                return
            end
            local note = SavedNote()
            if note == "" then return end
            copyBox:SetText(note)
            copyBox:Show()
            copyBox:SetFocus()
            copyBox:HighlightText()
            buttonText:SetText("Ctrl+C")
        end)

        helper.button = button
        helper.buttonText = buttonText
        helper.copyBox = copyBox
        copyHelper = helper
    end

    copyHelper.targetEditBox = editBox
    copyHelper:SetFrameLevel(dialog:GetFrameLevel() + 20)
    copyHelper.button:SetFrameLevel(copyHelper:GetFrameLevel() + 1)
    copyHelper.copyBox:SetFrameLevel(copyHelper:GetFrameLevel() + 2)
    HideCopyField()
    copyHelper:Show()
end

-- Blizzard's show without its clear of the application text fields, so the
-- typed note stays.
local function PatchedShow(self, resultID)
    if resultID then
        self.resultID = resultID
        -- Apply-phase search result is SECRET: activityID can be secret and
        -- activityIDs a secret table whose indexing throws. Guard every read; degrade to nil rather than erroring the dialog.
        pcall(function()
            -- Cleared up-front so a mid-read throw can't leave a stale activityID from a previous dialog open.
            self.activityID = nil
            local info = C_LFGList.GetSearchResultInfo(resultID)
            if type(info) ~= "table" then return end
            local aid = info.activityID
            if issecretvalue(aid) then aid = nil end
            if aid == nil and info.activityIDs and not issecretvalue(info.activityIDs) then
                aid = info.activityIDs[1]
                if issecretvalue(aid) then aid = nil end
            end
            self.activityID = aid
        end)
    end
    LFGListApplicationDialog_UpdateRoles(self)
    StaticPopupSpecial_Show(self)
end

EllesmereUI.GetPersistentSignupNote = function()
    return SavedNote()
end

local function SyncPatch()
    if not ready then return end
    if NoteEnabled() then
        if not patched then
            LFGListApplicationDialog_Show = PatchedShow
            patched = true
        end
        -- Another addon can replace the show function after login; the dialog hook survives it.
        if LFGListApplicationDialog and not copyHooked then
            LFGListApplicationDialog:HookScript("OnShow", RefreshCopyHelper)
            copyHooked = true
        end
        RefreshCopyHelper(LFGListApplicationDialog)
    else
        if patched then
            if LFGListApplicationDialog_Show == PatchedShow then
                LFGListApplicationDialog_Show = vanilla
            end
            patched = false
        end
        if copyHelper then copyHelper:Hide() end
    end
end

EllesmereUI.SetPersistentSignupNote = function(note)
    if not EllesmereUIDB then EllesmereUIDB = {} end
    EllesmereUIDB.signupNote = LimitNote(note)
    SyncPatch()
end

EllesmereUI._applyPersistSignupNote = SyncPatch

-------------------------------------------------------------------------------
--  Login: apply the saved settings
-------------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    -- Only while a module with the option rows is loaded; with neither, the
    -- API stays inert and nothing is hooked.
    local hosts = EllesmereUI._ModuleNS
    if not (hosts.EllesmereUIQoL or hosts.EllesmereUIGroupFinder) then return end
    vanilla = LFGListApplicationDialog_Show
    ready = true
    EllesmereUI._applyQuickSignup()
    SyncPatch()
end)
