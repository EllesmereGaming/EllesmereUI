if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if EllesmereUI.IS_FOREVER then return end

local controller
local function KeystoneControlsEnabled()
    return EllesmereUIDB and EllesmereUIDB.mythicKeystoneControls == true
end

local function CreateKeystoneStartController()
    local ksFrame = CreateFrame("Frame")
    local state = { phase = "idle", generation = 0 }
    local enabled = false
    local buttonsByFrame = setmetatable({}, { __mode = "k" })
    local keystoneFrame, pullTimer, requestTimer
    local UpdateKeystoneButtons

    local function Option(key)
        return EllesmereUIDB and EllesmereUIDB[key] == true
    end

    local function IsLocked()
        return InCombatLockdown()
            or (C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
                and C_ChatInfo.InChatMessagingLockdown())
    end

    local function IsActive()
        return C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
            and C_ChallengeMode.IsChallengeModeActive()
    end

    local function SlottedKeystone()
        if not C_ChallengeMode or not C_ChallengeMode.GetSlottedKeystoneInfo then return end
        local mapID, affixes, level = C_ChallengeMode.GetSlottedKeystoneInfo()
        if not mapID or not level then return end
        return mapID .. ":" .. level .. ":" .. table.concat(affixes or {}, ",")
    end

    local function GroupCategory()
        if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return LE_PARTY_CATEGORY_INSTANCE end
        return LE_PARTY_CATEGORY_HOME
    end

    local function GetPullChatChannel()
        if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
        if IsInRaid() then return "RAID" end
        if IsInGroup() then return "PARTY" end
    end

    local function CanControlKeystoneStart(action)
        if not enabled or not KeystoneControlsEnabled()
            or not state.open or not keystoneFrame or not keystoneFrame:IsShown()
            or not C_ChallengeMode or not C_ChallengeMode.IsChallengeModeActive
            or IsLocked() or IsActive() or state.phase == "starting"
            or state.phase == "active" or not SlottedKeystone() then return false end
        local category = GroupCategory()
        if not IsInGroup(category) then return action ~= "ready" end
        return UnitIsGroupLeader("player", category)
            or (IsInRaid(category) and UnitIsGroupAssistant("player", category))
    end

    local function ReadyCheckRunning()
        return GetReadyCheckTimeLeft and GetReadyCheckTimeLeft() > 0
    end

    local function GroupSnapshot()
        if IsLocked() then return end
        local category = GroupCategory()
        local members, signature = {}, { tostring(category) }
        local raid = IsInRaid(category)
        local count = GetNumGroupMembers(category)
        local function AddUnit(unit)
            local guid = UnitGUID(unit)
            if not guid then return false end
            members[guid] = unit
            signature[#signature + 1] = guid .. ":"
                .. (UnitIsGroupLeader(unit, category) and "L" or "-")
                .. (UnitIsGroupAssistant(unit, category) and "A" or "-")
                .. (UnitIsConnected(unit) and "C" or "-")
            return true
        end
        if raid then
            for i = 1, count do if not AddUnit("raid" .. i) then return end end
        else
            if not AddUnit("player") then return end
            for i = 1, math.max(0, count - 1) do
                if not AddUnit("party" .. i) then return end
            end
        end
        table.sort(signature)
        return table.concat(signature, ";"), members
    end

    local function CancelRequestTimer()
        if requestTimer then requestTimer:Cancel(); requestTimer = nil end
    end

    local function CancelPull()
        state.generation = state.generation + 1
        if pullTimer then pullTimer:Cancel(); pullTimer = nil end
        CancelRequestTimer()
        state.pull, state.cancelPending = nil, nil
    end

    local function ResetKeystoneStartState(clearSlot)
        CancelPull()
        state.ready = nil
        if clearSlot then
            state.slot, state.startAttempted = nil, nil
        end
        state.phase = IsActive() and "active" or (state.slot and "keystone_slotted" or "idle")
        if UpdateKeystoneButtons then UpdateKeystoneButtons() end
    end

    local function SamePreparation(snapshot, slot)
        return CanControlKeystoneStart("pull") and SlottedKeystone() == slot
            and GroupSnapshot() == snapshot
    end

    local function LocalMessage(message)
        if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff0cd29fEllesmereUI:|r " .. message) end
    end

    local function SendPullMessage(message, channel)
        if IsLocked() then return false end
        if not channel then return true end
        if not C_ChatInfo or not C_ChatInfo.SendChatMessage then return false end
        return pcall(C_ChatInfo.SendChatMessage, message, channel)
    end

    local function CancelPullFromButton()
        local pull = state.pull
        if not pull then return end
        local canAnnounce = SamePreparation(pull.roster, pull.slot)
        -- Invalidate Auto Start before the cancellation API can dispatch an event.
        ResetKeystoneStartState(false)
        if not canAnnounce then return end
        if C_PartyInfo and C_PartyInfo.DoCountdown then
            local cancellation = {}
            state.cancelPending = cancellation
            UpdateKeystoneButtons()
            requestTimer = C_Timer.NewTimer(3, function()
                if state.cancelPending == cancellation then ResetKeystoneStartState(false) end
            end)
            local ok, success = pcall(C_PartyInfo.DoCountdown, 0)
            if (not ok or success == false) and state.cancelPending == cancellation then
                ResetKeystoneStartState(false)
            end
        end
        SendPullMessage("Pull cancelado!", pull.channel)
    end

    local function TryStartChallenge(pull)
        if not pull.autoStart or not Option("autoStartKeystone") or state.startAttempted
            or state.generation ~= pull.generation
            or not SamePreparation(pull.roster, pull.slot) then return end
        local startButton = keystoneFrame.StartButton
        if not startButton or not startButton:IsEnabled()
            or not C_ChallengeMode or not C_ChallengeMode.StartChallengeMode then
            LocalMessage("Use the official Start button to begin the keystone.")
            return
        end
        state.startAttempted = true
        state.phase = "starting"
        UpdateKeystoneButtons()
        local ok, success = pcall(C_ChallengeMode.StartChallengeMode)
        if (not ok or success ~= true) and state.phase == "starting" then
            state.phase = "keystone_slotted"
            LocalMessage("Auto Start was not confirmed. Use the official Start button.")
            UpdateKeystoneButtons()
        end
    end

    local function StartChatCountdown(timeLeft)
        local pull = state.pull
        pull.pending = false
        CancelRequestTimer()
        pull.deadline = GetTime() + timeLeft
        pull.last = math.ceil(timeLeft)
        if not SendPullMessage("Pull in " .. pull.seconds, pull.channel)
            or not SendPullMessage(tostring(pull.last), pull.channel) then
            ResetKeystoneStartState(false)
            return
        end
        local function Tick()
            if state.pull ~= pull or state.generation ~= pull.generation then return end
            pullTimer = nil
            if not SamePreparation(pull.roster, pull.slot) or ReadyCheckRunning() then
                ResetKeystoneStartState(false)
                return
            end
            local timeRemaining = pull.deadline - GetTime()
            local remaining = math.max(0, math.ceil(timeRemaining))
            if remaining > 0 then
                if remaining < pull.last and not SendPullMessage(tostring(remaining), pull.channel) then
                    ResetKeystoneStartState(false)
                    return
                end
                pull.last = remaining
                -- Schedule from the official deadline; delayed frames skip old numbers.
                pullTimer = C_Timer.NewTimer(math.max(0.01, timeRemaining - remaining + 1), Tick)
                return
            end
            state.pull = nil
            state.phase = "keystone_slotted"
            if SendPullMessage("GO!", pull.channel) then TryStartChallenge(pull) end
            UpdateKeystoneButtons()
        end
        pullTimer = C_Timer.NewTimer(math.max(0.01, timeLeft - pull.last + 1), Tick)
    end

    local function StartPull(seconds)
        if seconds ~= 5 and seconds ~= 10 then return end
        if not CanControlKeystoneStart("pull") or state.ready or ReadyCheckRunning()
            or state.pull or state.cancelPending
            or not C_PartyInfo or not C_PartyInfo.DoCountdown then return end
        local roster = GroupSnapshot()
        if not roster then return end
        CancelPull()
        local pull = {
            generation = state.generation, seconds = seconds, pending = true,
            roster = roster, slot = SlottedKeystone(), channel = GetPullChatChannel(),
            autoStart = Option("autoStartKeystone"),
        }
        state.pull = pull
        UpdateKeystoneButtons()
        requestTimer = C_Timer.NewTimer(3, function()
            if state.pull == pull and pull.pending then ResetKeystoneStartState(false) end
        end)
        local ok, success = pcall(C_PartyInfo.DoCountdown, seconds)
        if (not ok or success == false) and state.pull == pull then ResetKeystoneStartState(false) end
    end

    local function IsPlayerInitiator(name, members)
        if type(name) ~= "string" then return false end
        local playerName, realm = UnitFullName("player")
        if not playerName then return false end
        if realm and name == playerName .. "-" .. realm then return true end
        if name ~= playerName then return false end
        for guid, unit in pairs(members) do
            if guid ~= UnitGUID("player") and UnitName(unit) == name then return false end
        end
        return true
    end

    local function BeginKeystoneReadyCheck()
        if not CanControlKeystoneStart("ready") or state.ready or state.pull or state.cancelPending
            or ReadyCheckRunning() or not C_PartyInfo or not C_PartyInfo.DoReadyCheck then return end
        local roster, members = GroupSnapshot()
        if not roster then return end
        local ready = { roster = roster, members = members, answers = {}, pending = true,
            slot = SlottedKeystone() }
        state.ready = ready
        UpdateKeystoneButtons()
        requestTimer = C_Timer.NewTimer(3, function()
            if state.ready == ready and ready.pending then ResetKeystoneStartState(false) end
        end)
        local ok = pcall(C_PartyInfo.DoReadyCheck)
        if not ok and state.ready == ready then ResetKeystoneStartState(false) end
    end

    local function HandleReadyCheck(initiator, timeLeft)
        if IsLocked() or (issecretvalue and (issecretvalue(initiator) or issecretvalue(timeLeft))) then
            ResetKeystoneStartState(false)
            return
        end
        local ready = state.ready
        if not ready or not ready.pending or not SamePreparation(ready.roster, ready.slot)
            or not IsPlayerInitiator(initiator, ready.members)
            or type(timeLeft) ~= "number" or timeLeft <= 0 then
            ResetKeystoneStartState(false)
            return
        end
        CancelRequestTimer()
        ready.pending = false
        ready.deadline = GetTime() + timeLeft
        for guid, unit in pairs(ready.members) do
            ready.answers[guid] = UnitIsConnected(unit) and GetReadyCheckStatus(unit) == "ready"
        end
        requestTimer = C_Timer.NewTimer(timeLeft, function()
            if state.ready == ready then ResetKeystoneStartState(false) end
        end)
        UpdateKeystoneButtons()
    end

    local function HandleReadyCheckResponse(unit, isReady)
        local ready = state.ready
        if not ready or ready.pending then return end
        if not SamePreparation(ready.roster, ready.slot) then ResetKeystoneStartState(false); return end
        local guid = UnitGUID(unit)
        if not guid or not ready.members[guid] then return end
        if isReady ~= true then
            ResetKeystoneStartState(false)
            return
        end
        ready.answers[guid] = true
    end

    local function HandleReadyCheckFinished(preempted)
        local ready = state.ready
        local allReady = ready and not ready.pending and preempted == false
            and GetTime() < ready.deadline and SamePreparation(ready.roster, ready.slot)
        if allReady then
            local _, members = GroupSnapshot()
            for guid, unit in pairs(members) do
                if not ready.answers[guid] or not UnitIsConnected(unit) then allReady = false; break end
            end
        end
        ResetKeystoneStartState(false)
        if allReady then LocalMessage("Everyone is ready. Click PULL when you are ready to count down.") end
    end

    local function HandleKeystoneSlotted()
        if not state.open or IsLocked() then return end
        local slot = SlottedKeystone()
        if not slot then ResetKeystoneStartState(true); return end
        if state.slot == slot then return end
        ResetKeystoneStartState(true)
        state.slot, state.phase = slot, "keystone_slotted"
        UpdateKeystoneButtons()
        if Option("autoKeystoneReadyCheck") then BeginKeystoneReadyCheck() end
    end

    UpdateKeystoneButtons = function()
        local buttons = keystoneFrame and buttonsByFrame[keystoneFrame]
        if not buttons then return end
        if not enabled or not KeystoneControlsEnabled() or not state.open then
            buttons.ready:Hide()
            buttons.pull:Hide()
            return
        end
        buttons.ready:Show()
        buttons.pull:Show()
        local busy = state.ready or state.cancelPending or ReadyCheckRunning()
        local readyEnabled = not busy and not state.pull and CanControlKeystoneStart("ready")
            and C_PartyInfo and C_PartyInfo.DoReadyCheck ~= nil
        local pullEnabled = state.pull ~= nil or (not busy
            and CanControlKeystoneStart("pull")
            and C_PartyInfo and C_PartyInfo.DoCountdown ~= nil)
        local function Enable(button, enabled)
            button:SetEnabled(not not enabled)
            button:SetAlpha(enabled and 1 or 0.35)
        end
        Enable(buttons.ready, readyEnabled)
        Enable(buttons.pull, pullEnabled)
    end

    local function CreateKeystoneStartButtons()
        if not enabled or not KeystoneControlsEnabled()
            or buttonsByFrame[keystoneFrame] or not keystoneFrame.StartButton
            or not EllesmereUI.MakeStyledButton then return end
        local buttons = {}
        buttonsByFrame[keystoneFrame] = buttons
        local function Button(key, text, point, relativePoint, x, onClick)
            local button = CreateFrame("Button", nil, keystoneFrame)
            button:SetSize(88, 24)
            button:SetPoint(point, keystoneFrame.StartButton, relativePoint, x, 0)
            EllesmereUI.MakeStyledButton(button, text, 12, EllesmereUI.WB_COLOURS, onClick)
            local onEnter = button:GetScript("OnEnter")
            button:SetScript("OnEnter", function(self)
                if self:IsEnabled() and onEnter then onEnter(self) end
            end)
            buttons[key] = button
            return button
        end
        Button("ready", "READY", "RIGHT", "LEFT", -8, BeginKeystoneReadyCheck)
        local pull = Button("pull", "PULL", "LEFT", "RIGHT", 8)
        pull:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        -- The shared styled-button callback does not forward the mouse button.
        pull:SetScript("OnClick", function(_, mouseButton)
            if not enabled or not KeystoneControlsEnabled() then return end
            if mouseButton ~= "LeftButton" and mouseButton ~= "RightButton" then return end
            if state.pull then CancelPullFromButton()
            elseif mouseButton == "LeftButton" then StartPull(5)
            elseif mouseButton == "RightButton" then StartPull(10) end
        end)
        local onEnter, onLeave = pull:GetScript("OnEnter"), pull:GetScript("OnLeave")
        pull:SetScript("OnEnter", function(self)
            if onEnter then onEnter(self) end
            if EllesmereUI.ShowWidgetTooltip then
                EllesmereUI.ShowWidgetTooltip(self, "Left click: PULL 5\nRight click: PULL 10\nDuring a pull, either click cancels it and pending Auto Start.")
            end
        end)
        pull:SetScript("OnLeave", function(self)
            if onLeave then onLeave(self) end
            if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
        end)
        pull:HookScript("OnHide", function()
            if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip(true) end
        end)
        UpdateKeystoneButtons()
    end

    local function HandleRosterChanged()
        local pending = state.ready or state.pull
        if pending and not SamePreparation(pending.roster, pending.slot) then ResetKeystoneStartState(false) end
        UpdateKeystoneButtons()
    end

    local function HandleCountdownStarted(initiatorGUID, timeLeft, totalTime)
        if IsLocked() or (issecretvalue and (issecretvalue(initiatorGUID)
            or issecretvalue(timeLeft) or issecretvalue(totalTime))) then
            ResetKeystoneStartState(false)
            return
        end
        local pull = state.pull
        if not pull then return end
        if initiatorGUID == UnitGUID("player") and totalTime == pull.seconds and pull.pending
            and type(timeLeft) == "number" and timeLeft > 0 and timeLeft <= totalTime
            and SamePreparation(pull.roster, pull.slot) then
            StartChatCountdown(timeLeft)
            UpdateKeystoneButtons()
        else
            ResetKeystoneStartState(false)
        end
    end

    local sessionEvents = {
        CHALLENGE_MODE_KEYSTONE_SLOTTED = HandleKeystoneSlotted,
        CHALLENGE_MODE_START = function() ResetKeystoneStartState(true); state.phase = "active"; UpdateKeystoneButtons() end,
        GROUP_ROSTER_UPDATE = HandleRosterChanged,
        PARTY_LEADER_CHANGED = HandleRosterChanged,
        READY_CHECK = HandleReadyCheck,
        READY_CHECK_CONFIRM = HandleReadyCheckResponse,
        READY_CHECK_FINISHED = HandleReadyCheckFinished,
        START_PLAYER_COUNTDOWN = HandleCountdownStarted,
        CANCEL_PLAYER_COUNTDOWN = function()
            if state.pull or state.cancelPending then ResetKeystoneStartState(false) end
        end,
        PLAYER_ENTERING_WORLD = function() ResetKeystoneStartState(true) end,
        PLAYER_REGEN_DISABLED = function() ResetKeystoneStartState(false) end,
        PLAYER_REGEN_ENABLED = function() UpdateKeystoneButtons() end,
    }

    local function OpenKeystoneSession()
        if not enabled or not KeystoneControlsEnabled()
            or state.open or not keystoneFrame:IsShown() then return end
        state.open = true
        ResetKeystoneStartState(true)
        for event in pairs(sessionEvents) do ksFrame:RegisterEvent(event) end
        CreateKeystoneStartButtons()
        HandleKeystoneSlotted()
    end

    local function CloseKeystoneSession()
        if not enabled or not KeystoneControlsEnabled() then return end
        state.open = false
        ResetKeystoneStartState(true)
        for event in pairs(sessionEvents) do ksFrame:UnregisterEvent(event) end
    end

    local function AttachKeystoneFrame()
        if not enabled or not KeystoneControlsEnabled()
            or keystoneFrame or not ChallengesKeystoneFrame then return end
        keystoneFrame = ChallengesKeystoneFrame
        ksFrame:UnregisterEvent("ADDON_LOADED")
        keystoneFrame:HookScript("OnShow", OpenKeystoneSession)
        keystoneFrame:HookScript("OnHide", CloseKeystoneSession)
        if keystoneFrame.Reset then
            hooksecurefunc(keystoneFrame, "Reset", function()
                if not enabled or not KeystoneControlsEnabled() then return end
                ResetKeystoneStartState(true)
            end)
        end
        OpenKeystoneSession()
    end

    ksFrame:SetScript("OnEvent", function(_, event, ...)
        if not enabled or not KeystoneControlsEnabled() then return end
        if event == "ADDON_LOADED" then
            if ... == "Blizzard_ChallengesUI" then AttachKeystoneFrame() end
        elseif event == "CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN" then
            AttachKeystoneFrame()
            if keystoneFrame then OpenKeystoneSession() end
        elseif state.open and sessionEvents[event] then
            sessionEvents[event](...)
        end
    end)

    local function ApplyKeystoneStart()
        local shouldEnable = KeystoneControlsEnabled()
        if enabled and shouldEnable then
            ResetKeystoneStartState(false)
            return
        end
        enabled = shouldEnable
        state.open = false
        ResetKeystoneStartState(true)
        ksFrame:UnregisterAllEvents()
        if not enabled then return end
        ksFrame:RegisterEvent("CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN")
        if not keystoneFrame then ksFrame:RegisterEvent("ADDON_LOADED") end
        AttachKeystoneFrame()
        if keystoneFrame then OpenKeystoneSession() end
    end

    local function RefreshKeystoneStart()
        if not enabled then return end
        ApplyKeystoneStart()
    end
    for _, name in ipairs({ "RefreshAllAddons", "SwitchProfile", "ApplyProfileData" }) do
        if EllesmereUI[name] then hooksecurefunc(EllesmereUI, name, RefreshKeystoneStart) end
    end
    return ApplyKeystoneStart
end

EllesmereUI._applyKeystoneStart = function()
    if not controller and KeystoneControlsEnabled() then
        controller = CreateKeystoneStartController()
    end
    if controller then controller() end
end
