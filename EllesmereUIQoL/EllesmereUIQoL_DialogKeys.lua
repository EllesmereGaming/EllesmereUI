if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if EllesmereUI and EllesmereUI.IS_FOREVER then return end -- retail dialog windows only; the options row is not built on WoW Forever
-------------------------------------------------------------------------------
--  EllesmereUIQoL_DialogKeys.lua
--  Dialog Keys: answer NPC windows from the keyboard. The dialog key (Space
--  unless the player picks another) presses the window's main button --
--  Accept, Continue, Complete Quest, or in a gossip window the top choice: a
--  quest ready to turn in, else a new quest, else the first open option.
--  Number keys 1-9 and 0, on the top row or the numpad, press the numbered
--  choices (gossip rows, greeting quests, quest rewards), and each of those
--  shows its number. The number keys can be turned off on their own.
--  Confirm Popups (off by default) lets the dialog key press Yes on the
--  popups in POPUPS: confirmations of something the player just asked for.
--
--  Taint (read before editing): every press is a real click on Blizzard's own
--  button, made by the secure "click" action of a SecureActionButtonTemplate
--  proxy that a priority override binding fires. Blizzard's handler runs
--  exactly as it does for the mouse and nothing of ours runs inside it. This
--  file only reads Blizzard's frames: it calls no Blizzard function that
--  changes anything and writes no Blizzard frame, field or button. The button
--  to click reaches the proxy as an attribute, which carries no taint.
--  Blizzard's own confirmations (a PvP quest, a turn-in that costs gold, a
--  gossip choice that asks) come up as they do for a click, and no popup is
--  ever answered except the POPUPS confirmations, through the same click.
--
--  Combat: none. Binding writes and secure attributes are combat-restricted,
--  so keys are laid down only while a supported window is open out of combat
--  and are all lifted at PLAYER_REGEN_DISABLED: InCombatLockdown() already
--  reports true there, but protected writes stay legal until the handler
--  returns (Party Mode and the Fishing helper rely on the same window).
--  Anything that changes in combat waits for combat end on the CombatQueue.
--
--  Cost: nothing is built until the first enable. The events and the gossip
--  list callback are registered only while on; the three secure hooks
--  (installed once) return at once while off, and the popup hooks are
--  installed only once Confirm Popups is first turned on.
-------------------------------------------------------------------------------
local EUI = EllesmereUI
local ns = select(2, ...)

local LOCKOUT    = 0.5  -- seconds the dialog key stays ours after it answers, so a quick extra press never jumps
local HOLD_LIMIT = 3    -- longest a pressed key stays ours after its window closes, waiting for the release
local LABEL_SIZE = 12   -- number labels: the size of EUI's action bar keybind text
local NUM_KEYS = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" }  -- slot n presses choice n
local NUMPAD_KEYS = { "NUMPAD1", "NUMPAD2", "NUMPAD3", "NUMPAD4", "NUMPAD5",
                      "NUMPAD6", "NUMPAD7", "NUMPAD8", "NUMPAD9", "NUMPAD0" }  -- the same choices on the numpad
local MAX_SLOT = #NUM_KEYS                                              -- slot 0 is the dialog key
-- Popups the dialog key may press Yes on (Confirm Popups): only confirmations
-- of something the player just asked for. Never one the game or another player
-- sends (summons, invites, duels, trades): the dialog key is usually the jump
-- key, and a jump at the wrong moment would accept it.
local POPUPS = { ABANDON_QUEST = true, ABANDON_QUEST_WITH_ITEMS = true }
local EVENTS = {
    "GOSSIP_SHOW", "GOSSIP_CLOSED",
    "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_FINISHED",
    "PLAYER_REGEN_DISABLED",
}

local enabled, built = false, false
local owner             -- event frame and override-binding owner
local proxies = {}      -- [slot] secure click proxy, built on first use
local bound = {}        -- [key] = slot whose proxy the key is laid on
local boundTo = {}      -- [slot] Blizzard button the proxy clicks (nil = a press does nothing)
local heldAt = {}       -- [slot] when a press began whose release has not arrived yet
local want = {}         -- Sync scratch: [slot] = button, false (bound, does nothing) or nil (not bound)
local wantKey = {}      -- Sync scratch: [key] = slot the key should be laid on
local keyed = {}        -- Sync scratch: [slot] = true when the slot holds at least one key
local labels = setmetatable({}, { __mode = "k" })  -- [Blizzard button] = our number FontString on it (weak keys: nothing is written onto the button)
local shown = {}        -- [Blizzard button] = true while its number shows
local pickable = {}     -- [gossip row type] = "active" | "available" | "option"
local popups = {}       -- StaticPopup1-4, hooked once Confirm Popups is first on
local lockUntil = 0
local syncQueued, expiry
local Sync              -- forward

local function QueueSync()
    if syncQueued then return end
    syncQueued = true
    C_Timer.After(0, Sync)
end

-- nil = never set (Space), false = unbound by the player, else a key chord.
local function DialogKey()
    local k = EllesmereUIDB and EllesmereUIDB.dialogKeysKey
    if k == nil then return "SPACE" end
    return k or nil
end

-- The number keys (top row and numpad) are on unless the player turned them off.
local function NumbersOn()
    return not (EllesmereUIDB and EllesmereUIDB.dialogKeysNumbers == false)
end

-- Confirm Popups is off unless the player turned it on.
local function PopupsOn()
    return EllesmereUIDB and EllesmereUIDB.dialogKeysPopups == true
end

-------------------------------------------------------------------------------
--  Proxies and bindings
-------------------------------------------------------------------------------
-- Before the secure click. The press is marked held and the lockout started
-- here, ahead of the click: a window or popup the click closes (and the Sync
-- that runs inside it) must still find the key ours.
local function OnPreClick(self, _, down)
    local slot = self.slot
    if down then
        heldAt[slot] = GetTime()
    elseif not heldAt[slot] and boundTo[slot] then
        -- A release whose press began before the key was ours (held as the
        -- window or popup opened). With cast-on-key-up it would click, so this
        -- one goes nowhere and Sync re-aims after. Keys are only ever bound out
        -- of combat, so the attribute write is allowed.
        self:SetAttribute("clickbutton", nil)
        boundTo[slot] = nil
    end
    -- Either phase can click (the one that matches the player's cast-on-key-down
    -- setting), so the lockout runs from whichever came last.
    if slot == 0 and boundTo[0] then lockUntil = GetTime() + LOCKOUT end
end

local function OnPostClick(self, _, down)
    if not down then
        heldAt[self.slot] = nil
        QueueSync()
    end
end

local function Proxy(slot)
    local p = proxies[slot]
    if not p then
        p = CreateFrame("Button", "EUI_DialogKeysBtn" .. slot, UIParent, "SecureActionButtonTemplate")
        p:SetSize(1, 1)
        p:SetAlpha(0)
        p:EnableMouse(false)
        -- Both phases, as on the quest item hotkey: the secure handler acts on
        -- the one that matches the player's cast-on-key-down setting.
        p:RegisterForClicks("AnyDown", "AnyUp")
        p:SetAttribute("type", "click")
        p.slot = slot
        p:SetScript("PreClick", OnPreClick)
        p:SetScript("PostClick", OnPostClick)
        proxies[slot] = p
    end
    return p
end

-- The keys each wanted slot should hold, into wantKey and keyed: the dialog
-- key on slot 0, and both number keys of every wanted choice. A dialog key set
-- to a number key takes that one key from its choice.
local function CollectKeys()
    wipe(wantKey)
    for slot = 0, MAX_SLOT do keyed[slot] = nil end
    local dialogKey = DialogKey()
    if want[0] ~= nil and dialogKey then
        wantKey[dialogKey] = 0
        keyed[0] = true
    end
    if not NumbersOn() then return end
    for slot = 1, MAX_SLOT do
        if want[slot] ~= nil then
            local top, pad = NUM_KEYS[slot], NUMPAD_KEYS[slot]
            if top ~= dialogKey then wantKey[top] = slot; keyed[slot] = true end
            if pad ~= dialogKey then wantKey[pad] = slot; keyed[slot] = true end
        end
    end
end

-------------------------------------------------------------------------------
--  What each window's keys press (reads only)
-------------------------------------------------------------------------------
-- A listed popup sits on top of everything, so it comes first.
local function ActiveWindow()
    if PopupsOn() then
        for i = 1, #popups do
            local d = popups[i]
            if d:IsVisible() and POPUPS[d.which] then return "popup", d end
        end
    end
    if QuestFrame and QuestFrame:IsVisible() then
        if QuestFrameRewardPanel:IsVisible() then return "reward" end
        if QuestFrameProgressPanel:IsVisible() then return "progress" end
        if QuestFrameDetailPanel:IsVisible() then return "detail" end
        if QuestFrameGreetingPanel:IsVisible() then return "greeting" end
    end
    if GossipFrame and GossipFrame:IsVisible() then return "gossip" end
end

-- Gossip rows in view, numbered by Blizzard's own row index (quests, then
-- options). The dialog key takes the best rank, the lowest number within it.
local topRank, topN, topBtn
local function ConsiderGossipRow(frame, ed)
    local n = ed and ed.index
    local kind = n and pickable[ed.buttonType]
    if not kind then return end
    if n <= MAX_SLOT then want[n] = frame end
    local info, rank = ed.info, nil
    if kind == "active" then
        if info and info.isComplete then rank = 1 end
    elseif kind == "available" then
        rank = 2
    else
        local status = info and info.status
        if status == nil or status == Enum.GossipOptionStatus.Available then rank = 3 end
    end
    if rank and (not topRank or rank < topRank or (rank == topRank and n < topN)) then
        topRank, topN, topBtn = rank, n, frame
    end
end

local function GossipBox()
    local panel = GossipFrame and GossipFrame.GreetingPanel
    return panel and panel.ScrollBox
end

local function GossipTargets()
    local sb = GossipBox()
    if not (sb and sb.ForEachFrame) then return end
    topRank, topN, topBtn = nil, nil, nil
    sb:ForEachFrame(ConsiderGossipRow)
    want[0] = topBtn or false
    topBtn = nil
end

-- Greeting quests in Blizzard's order: current quests first, then available.
local function GreetingTargets()
    local pool = QuestFrameGreetingPanel.titleButtonPool
    if not pool then return end
    local numActive = GetNumActiveQuests()
    local turnIn, turnInN, offer, offerN
    for btn in pool:EnumerateActive() do
        local id = btn:GetID()
        local isActive = btn.isActive == 1
        local n = isActive and id or numActive + id
        if n >= 1 and n <= MAX_SLOT then want[n] = btn end
        if isActive then
            local _, isComplete = GetActiveTitle(id)
            if isComplete and (not turnInN or n < turnInN) then turnIn, turnInN = btn, n end
        elseif not offerN or n < offerN then
            offer, offerN = btn, n
        end
    end
    want[0] = turnIn or offer or false
end

local function QuestTargets(win)
    if win == "detail" then
        want[0] = QuestFrameAcceptButton
    elseif win == "progress" then
        want[0] = QuestFrameCompleteButton
    else
        want[0] = QuestFrameCompleteQuestButton
        -- With several rewards a number key picks one (Blizzard's own pick and
        -- highlight); the dialog key then completes with it.
        local n = GetNumQuestChoices()
        local rb = n > 1 and QuestInfoRewardsFrame and QuestInfoRewardsFrame.RewardButtons
        if rb then
            for i = 1, #rb do
                local b = rb[i]
                if b.type == "choice" and b:IsVisible() then
                    local id = b:GetID()
                    if id >= 1 and id <= n and id <= MAX_SLOT then want[id] = b end
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Number labels: our own FontStrings, parented to the buttons they number so
--  they scroll, clip and hide with them. Blizzard's text and icons are untouched.
-------------------------------------------------------------------------------
local function Label(btn)
    local fs = labels[btn]
    if not fs then
        fs = btn:CreateFontString(nil, "OVERLAY")
        fs:SetDrawLayer("OVERLAY", 7)  -- above a reward tile's quality ring and overlays
        labels[btn] = fs
    end
    local path = EUI.GetFontPath("extras") or STANDARD_TEXT_FONT
    local flags = EUI.GetFontOutlineFlag("extras") or ""
    if fs.euiPath ~= path or fs.euiFlags ~= flags then
        EUI.PrimeFontShadow(fs, flags == "")
        fs:SetFont(path, LABEL_SIZE, flags)
        fs:SetTextColor(1, 1, 1)
        fs.euiPath, fs.euiFlags = path, flags
    end
    return fs
end

local function HideLabels()
    for btn in pairs(shown) do
        labels[btn]:Hide()
        shown[btn] = nil
    end
end

-- A number shows exactly on the buttons a number key is bound to right now.
local function UpdateLabels()
    for btn in pairs(shown) do shown[btn] = false end
    for _, slot in pairs(bound) do
        local btn = slot > 0 and boundTo[slot]
        if btn and not shown[btn] then
            local fs = Label(btn)
            local icon = btn.Icon or btn
            fs:ClearAllPoints()
            if btn.type == "choice" then
                fs:SetPoint("TOPLEFT", icon, "TOPLEFT", 2, -2)  -- reward tile: a keybind corner
            else
                fs:SetPoint("CENTER", icon, "CENTER")           -- dialog row: on its bullet icon
            end
            fs:SetText(NUM_KEYS[slot])
            fs:Show()
            shown[btn] = true
        end
    end
    for btn, on in pairs(shown) do
        if not on then
            labels[btn]:Hide()
            shown[btn] = nil
        end
    end
end

-------------------------------------------------------------------------------
--  Sync: the one place keys are laid down, re-aimed and lifted
-------------------------------------------------------------------------------
local function ScheduleExpiry()
    if expiry then expiry:Cancel(); expiry = nil end
    local now, at = GetTime(), nil
    if lockUntil > now then at = lockUntil end
    for slot = 0, MAX_SLOT do
        local t = heldAt[slot]
        if t then
            t = t + HOLD_LIMIT
            if not at or t < at then at = t end
        end
    end
    if at then
        expiry = C_Timer.NewTimer(at - now + 0.02, function()
            expiry = nil
            Sync()
        end)
    end
end

Sync = function()
    syncQueued = false
    if not owner then return end
    if InCombatLockdown() then
        -- Nothing is bound in combat (all lifted at PLAYER_REGEN_DISABLED); catch up after.
        if enabled then ns.CombatQueue.Defer("DialogKeys", Sync) end
        return
    end
    for slot = 0, MAX_SLOT do want[slot] = nil end
    if enabled then
        local win, popup = ActiveWindow()
        if win == "popup" then
            want[0] = popup:GetButton1() or false  -- Yes; the number keys stay the game's
        elseif win == "gossip" then
            GossipTargets()
        elseif win == "greeting" then
            GreetingTargets()
        elseif win then
            QuestTargets(win)
        end
        local now = GetTime()
        -- Lockout: right after an answer the dialog key stays ours, doing
        -- nothing, so a quick extra press cannot jump.
        if want[0] == nil and lockUntil > now then want[0] = false end
        -- A pressed key stays ours (doing nothing) until it is released: a lifted
        -- override would hand the release to the game's own binding, and an
        -- action button set to cast on key up would fire. Once its window is
        -- gone it waits at most HOLD_LIMIT for that release.
        for slot = 0, MAX_SLOT do
            local t = heldAt[slot]
            if t and want[slot] == nil then
                if now - t > HOLD_LIMIT then
                    heldAt[slot] = nil
                else
                    want[slot] = false
                end
            end
        end
    end
    CollectKeys()
    -- Lift first: a key can move between slots (a number key becoming the
    -- dialog key), and a lift after the lay-down would clear its new owner.
    for key, slot in pairs(bound) do
        if wantKey[key] ~= slot then
            SetOverrideBinding(owner, true, key, nil)
            bound[key] = nil
        end
    end
    -- Aim each proxy before its keys go down. Every write is a change.
    for slot = 0, MAX_SLOT do
        if keyed[slot] then
            local to = want[slot] or nil
            if boundTo[slot] ~= to then
                Proxy(slot):SetAttribute("clickbutton", to)
                boundTo[slot] = to
            end
        end
    end
    for key, slot in pairs(wantKey) do
        if bound[key] ~= slot then
            SetOverrideBindingClick(owner, true, key, Proxy(slot):GetName(), "LeftButton")
            bound[key] = slot
        end
    end
    UpdateLabels()
    ScheduleExpiry()
end

-- Combat start. InCombatLockdown() already reports true at PLAYER_REGEN_DISABLED,
-- but protected writes stay legal until this handler returns: lift every key now.
local function ReleaseForCombat()
    local had = next(bound) ~= nil
    wipe(bound)
    for slot = 0, MAX_SLOT do heldAt[slot] = nil end
    if had then ClearOverrideBindings(owner) end
    lockUntil = 0
    if expiry then expiry:Cancel(); expiry = nil end
    HideLabels()
    if had then ns.CombatQueue.Defer("DialogKeys", Sync) end
end

local function OnEvent(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        ReleaseForCombat()
        return
    end
    -- Now, for whatever Blizzard has already shown, and again next frame,
    -- once every handler of this event has run.
    Sync()
    QueueSync()
end

-- Blizzard rebuilt a list (gossip rows, greeting quests, reward tiles): re-aim
-- in the same call, before another key press can arrive.
local function OnListRefresh()
    if enabled then Sync() end
end

-- A popup showed or hid: re-aim in the same call, only while both are on.
local function OnPopupChange()
    if enabled and PopupsOn() then Sync() end
end

-- Installed once, on the first apply with Confirm Popups on, as the skin's
-- resurrection glow does; each returns at once while off. Blizzard never
-- refills a popup that is showing for another popup: it hides it, sets its
-- which and shows it again, so OnShow and OnHide see every change.
local popupsHooked = false
local function InstallPopupHooks()
    if popupsHooked then return end
    popupsHooked = true
    for i = 1, STATICPOPUP_NUMDIALOGS or 4 do
        local d = _G["StaticPopup" .. i]
        if d then
            popups[#popups + 1] = d
            d:HookScript("OnShow", OnPopupChange)
            d:HookScript("OnHide", OnPopupChange)
        end
    end
end

local function Build()
    built = true
    owner = CreateFrame("Frame")
    owner:SetScript("OnEvent", OnEvent)
    if GOSSIP_BUTTON_TYPE_ACTIVE_QUEST then pickable[GOSSIP_BUTTON_TYPE_ACTIVE_QUEST] = "active" end
    if GOSSIP_BUTTON_TYPE_AVAILABLE_QUEST then pickable[GOSSIP_BUTTON_TYPE_AVAILABLE_QUEST] = "available" end
    if GOSSIP_BUTTON_TYPE_OPTION then pickable[GOSSIP_BUTTON_TYPE_OPTION] = "option" end
    -- Installed once, never removable; each returns at once while off.
    -- QUEST_LOG_UPDATE rebuilds call the greeting function directly, while the
    -- XML OnShow holds the original function, so both are hooked.
    hooksecurefunc("QuestFrameGreetingPanel_OnShow", OnListRefresh)
    QuestFrameGreetingPanel:HookScript("OnShow", OnListRefresh)
    hooksecurefunc("QuestInfo_Display", OnListRefresh)
end

-- Login, the options toggle and the key picker share this path.
function EUI._applyDialogKeys()
    local on = (EllesmereUIDB and EllesmereUIDB.dialogKeys) == true
    if InCombatLockdown() then
        if enabled and not on then
            -- Nothing is bound in combat, so turning off needs no protected call.
            enabled = false
            for i = 1, #EVENTS do owner:UnregisterEvent(EVENTS[i]) end
            local sb = GossipBox()
            if sb and sb.UnregisterCallback then sb:UnregisterCallback(ScrollBoxListMixin.Event.OnUpdate, owner) end
            HideLabels()
        end
        -- Turning on, or a new key, waits for combat end.
        ns.CombatQueue.Defer("DialogKeysApply", EUI._applyDialogKeys)
        return
    end
    if on and not built then Build() end
    if on and PopupsOn() then InstallPopupHooks() end
    if on ~= enabled then
        enabled = on
        local sb = GossipBox()
        if on then
            for i = 1, #EVENTS do owner:RegisterEvent(EVENTS[i]) end
            if sb and sb.RegisterCallback then sb:RegisterCallback(ScrollBoxListMixin.Event.OnUpdate, OnListRefresh, owner) end
        else
            for i = 1, #EVENTS do owner:UnregisterEvent(EVENTS[i]) end
            if sb and sb.UnregisterCallback then sb:UnregisterCallback(ScrollBoxListMixin.Event.OnUpdate, owner) end
            lockUntil = 0
            for slot = 0, MAX_SLOT do heldAt[slot] = nil end
        end
    end
    if built then Sync() end
end
