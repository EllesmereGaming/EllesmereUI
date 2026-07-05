-------------------------------------------------------------------------------
--  EllesmereUI_RaidControl.lua
--  Raid Control -- a compact, movable raid-management panel that enhances
--  Blizzard's raid tools, in the spirit of ElvUI's RaidUtility.
--
--  A small "Raid Control" button appears whenever you are in a (non-PvP) group.
--  Its placement is configured through Unlock Mode. Left-click opens the panel:
--    * Raid target / world markers (left = target icon, right = world marker)
--    * Raid Menu, Disband, Ready Check, Role Poll, Main Tank, Main Assist,
--      Countdown
--    * Dungeon Difficulty / Convert (raid<->party) / Restrict Pings dropdowns
--    * Everyone is Assistant toggle
--
--  Self-contained: built on EllesmereUI primitives (PP / SolidTex / MakeBorder /
--  MakeFont) -- no Ace, no oUF, no ElvUI dependency. Toggled from Settings via
--  EllesmereUIDB.raidControl (global, like Party Mode).
--
--  Taint awareness: the panel hosts SecureActionButton children (markers, main
--  tank/assist), so it cannot be Show/Hidden from insecure Lua during combat.
--  The user-facing open/close therefore runs through SecureHandlerClickTemplate
--  snippets (ElvUI's approach); the automatic group-based show/hide is deferred
--  out of combat via PLAYER_REGEN_ENABLED.
--
--  Shared across all EllesmereUI addons -- only the first to load runs.
-------------------------------------------------------------------------------
if _G._EllesmereUIRaidControlLoaded then return end
_G._EllesmereUIRaidControlLoaded = true

local EllesmereUI = _G.EllesmereUI
if not EllesmereUI then return end

local PP         = EllesmereUI.PP
local SolidTex   = EllesmereUI.SolidTex
local MakeBorder = EllesmereUI.MakeBorder
local MakeFont   = EllesmereUI.MakeFont
local L          = EllesmereUI.L

local GREEN  = EllesmereUI.ELLESMERE_GREEN
local DARK   = EllesmereUI.DARK_BG
local BORDER = EllesmereUI.BORDER_COLOR

local CreateFrame      = CreateFrame
local InCombatLockdown = InCombatLockdown
local IsInGroup        = IsInGroup
local IsInRaid         = IsInRaid
local IsInInstance     = IsInInstance
local UnitIsGroupLeader    = UnitIsGroupLeader
local UnitIsGroupAssistant = UnitIsGroupAssistant
local floor, mod = math.floor, mod or function(a, b) return a % b end

-- Localized slash tokens for target / world markers (mirrors ElvUI). The
-- numbered marker buttons drive these via secure macros -- the only reliable
-- way to set a raid target icon on the current target. Clearing all world
-- markers is done via the secure "worldmarker" action, not a slash.
local TM = _G.SLASH_TARGET_MARKER4 or _G.SLASH_TARGET_MARKER1 or "/tm"
local WM = _G.SLASH_WORLD_MARKER1  or "/wm"

-------------------------------------------------------------------------------
--  Layout constants
-------------------------------------------------------------------------------
local PANEL_WIDTH = 232
local PAD         = 8
local BH          = 22          -- standard button height
local GAP         = 5
local COL_W       = (PANEL_WIDTH - PAD * 2 - GAP) / 2
local NUM_MARKERS = 8
local MARKER_GAP  = 5            -- spacing between marker buttons

-- World markers (ground flares) use a different index order than the raid
-- target icons. This remaps a target-icon index (1=star..8=skull) to the
-- world-marker index whose flare matches that icon's color (from ElvUI).
local GROUND_MARKER = { 5, 6, 3, 2, 7, 1, 4, 8 }

-------------------------------------------------------------------------------
--  Group / permission helpers (mirrors ElvUI semantics)
-------------------------------------------------------------------------------
local function NotInPVP()
    local _, instanceType = IsInInstance()
    return instanceType ~= "pvp" and instanceType ~= "arena"
end
local function InGroup()       return IsInGroup() and NotInPVP() end
local function HasPermission() return (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) and NotInPVP() end
local function IsLeader()      return UnitIsGroupLeader("player") and NotInPVP() end

-------------------------------------------------------------------------------
--  Module state
-------------------------------------------------------------------------------
local built        = false
local pendingBuild = false   -- set when enable is requested during combat
local deferFrame             -- single shared PLAYER_REGEN_ENABLED handler
local groupEvents            -- GROUP_ROSTER_UPDATE / PARTY_LEADER_CHANGED listener
local ShowButton, Panel, CloseButton
local permButtons = {}   -- buttons whose enabled/dimmed state tracks permission

-------------------------------------------------------------------------------
--  Styling helpers (game context -> default PP)
-------------------------------------------------------------------------------
local function StyleBackdrop(frame, bgAlpha)
    local bg = SolidTex(frame, "BACKGROUND", DARK.r, DARK.g, DARK.b, bgAlpha or 0.92)
    bg:SetAllPoints(frame)
    frame._bg = bg
    frame._border = MakeBorder(frame, BORDER.r, BORDER.g, BORDER.b, BORDER.a or 0.6)
    return frame
end

-- A clickable button styled like the EllesmereUI palette. `template` may be a
-- secure template (e.g. "SecureActionButtonTemplate") for protected actions.
local function MakeButton(name, parent, label, template, onClick)
    local btn = CreateFrame("Button", name, parent, template)
    StyleBackdrop(btn, 0.9)

    if label then
        local fs = MakeFont(btn, 12, nil, 1, 1, 1)
        fs:SetPoint("CENTER", btn, "CENTER", 0, 0)
        fs:SetText(L(label))
        btn._text = fs
        btn._label = label
    end

    btn:HookScript("OnEnter", function(self)
        if self._disabled then return end
        self._border:SetColor(GREEN.r, GREEN.g, GREEN.b, 1)
        self._bg:SetColorTexture(DARK.r, DARK.g, DARK.b, 1)
    end)
    btn:HookScript("OnLeave", function(self)
        self._border:SetColor(BORDER.r, BORDER.g, BORDER.b, BORDER.a or 0.6)
        self._bg:SetColorTexture(DARK.r, DARK.g, DARK.b, 0.9)
    end)

    if onClick then btn:SetScript("OnClick", onClick) end
    return btn
end

-- Grey out / restore a button's text to signal lack of permission.
local function SetButtonEnabled(btn, enabled)
    btn._disabled = not enabled
    if btn._text then
        btn._text:SetTextColor(enabled and 1 or 0.5, enabled and 1 or 0.5, enabled and 1 or 0.5, 1)
    end
end

-------------------------------------------------------------------------------
--  Raid target icon texcoords (4x4 grid; first 8 cells are the usable icons)
-------------------------------------------------------------------------------
local function ApplyMarkerTexCoord(tex, index)
    local c = 0.25
    local left   = mod(index - 1, 4) * c
    local top    = floor((index - 1) / 4) * c
    tex:SetTexCoord(left, left + c, top, top + c)
end

-------------------------------------------------------------------------------
--  Permission refresh -- dims leader/assist-only buttons when unavailable
-------------------------------------------------------------------------------
local function RefreshPermissions()
    local has    = HasPermission()
    local leader = IsLeader()
    for _, entry in ipairs(permButtons) do
        if entry.leaderOnly then
            SetButtonEnabled(entry.btn, leader)
        else
            SetButtonEnabled(entry.btn, has)
        end
    end
    if Panel and Panel._everyoneAssist then
        Panel._everyoneAssist:SetChecked(C_PartyInfo and IsEveryoneAssistant and IsEveryoneAssistant() or false)
    end
end

-------------------------------------------------------------------------------
--  Auto show/hide based on group membership (deferred out of combat)
-------------------------------------------------------------------------------
local function ToggleRaidControl(_, event)
    if not built then return end

    if InCombatLockdown() then
        if deferFrame then deferFrame:RegisterEvent("PLAYER_REGEN_ENABLED") end
        return
    end

    local enabled = EllesmereUIDB and EllesmereUIDB.raidControl
    local status  = enabled and InGroup()
    ShowButton:SetShown(status and not Panel.toggled)
    Panel:SetShown(status and Panel.toggled or false)
    if status then RefreshPermissions() end
end
EllesmereUI._RaidControl_Toggle = ToggleRaidControl

-------------------------------------------------------------------------------
--  Position (managed by Unlock Mode). Stored as CENTER coords relative to the
--  UIParent center in EllesmereUIDB.raidControlPos (global, like the feature).
--  The panel is anchored to the Show button, so moving the button moves both.
-------------------------------------------------------------------------------
-- Default placement mirrors ElvUI's RaidUtility: anchored to the top of the
-- screen, offset 400px left of center, flush with the top edge.
local DEFAULT_POINT, DEFAULT_X, DEFAULT_Y = "TOP", -400, -1

local function ApplyPosition()
    if not ShowButton then return end
    local pos = EllesmereUIDB and EllesmereUIDB.raidControlPos
    ShowButton:ClearAllPoints()
    if pos and pos.centerX and pos.centerY then
        ShowButton:SetPoint("CENTER", UIParent, "CENTER", pos.centerX, pos.centerY)
    else
        ShowButton:SetPoint(DEFAULT_POINT, UIParent, DEFAULT_POINT, DEFAULT_X, DEFAULT_Y)
    end
end

local function SavePosition()
    if not ShowButton then return end
    local left, bottom = ShowButton:GetLeft(), ShowButton:GetBottom()
    if not left or not bottom then return end
    local fw, fh = ShowButton:GetSize()
    local cx = left + fw / 2 - UIParent:GetWidth() / 2
    local cy = bottom + fh / 2 - UIParent:GetHeight() / 2
    if not EllesmereUIDB then EllesmereUIDB = {} end
    EllesmereUIDB.raidControlPos = { centerX = cx, centerY = cy }
end

-------------------------------------------------------------------------------
--  Build the panel (once, out of combat)
-------------------------------------------------------------------------------
local function BuildMarkers(parent, yTop)
    -- 9 cells (8 icons + clear) with MARKER_GAP between them.
    local mw    = (PANEL_WIDTH - PAD * 2 - NUM_MARKERS * MARKER_GAP) / (NUM_MARKERS + 1)
    local prev
    for i = 1, NUM_MARKERS + 1 do
        -- ElvUI order: skull(8), cross, square, moon, triangle, diamond,
        -- circle, star(1), then the clear button (id 0) at the right end.
        local id      = (NUM_MARKERS + 1) - i
        local isClear = (id == 0)
        local btn = CreateFrame("Button", "EllesmereUIRaidControl_Marker" .. i, parent, "SecureActionButtonTemplate")
        PP.Size(btn, mw, mw)
        if i == 1 then
            PP.Point(btn, "TOPLEFT", parent, "TOPLEFT", PAD, yTop)
        else
            PP.Point(btn, "LEFT", prev, "RIGHT", MARKER_GAP, 0)
        end
        prev = btn

        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints(btn)
        if isClear then
            tex:SetTexture([[Interface\Buttons\UI-GroupLoot-Pass-Up]])
        else
            tex:SetTexture([[Interface\TargetingFrame\UI-RaidTargetingIcons]])
            ApplyMarkerTexCoord(tex, id)
        end

        -- Secure macros: left-click sets the raid target icon on the current
        -- target; right-click places/clears the world marker. Mirrors ElvUI's
        -- numbered-marker path (the secure "raidtarget" type only clears).
        btn:RegisterForClicks("AnyUp")
        -- Act on mouse-up regardless of the "cast on key down" CVar. Without
        -- this, SecureActionButton_OnClick's clickAction gate silently skips the
        -- action on the up-click when ActionButtonUseKeyDown is on (see
        -- EllesmereUI_Kick.lua) -- which made every marker click a no-op.
        btn:SetAttribute("useOnKeyDown", false)
        btn:SetAttribute("type1", "macro")
        btn:SetAttribute("type2", "macro")
        if isClear then
            -- Left: clear the target's icon. Right: clear ALL world markers via
            -- the secure "worldmarker" action with no index (`/cwm N` only clears
            -- one marker and `/cwm 0` is a no-op, so a macro can't clear all).
            btn:SetAttribute("macrotext1", TM .. " 0")
            btn:SetAttribute("type2", "worldmarker")
            btn:SetAttribute("action", "clear")
        else
            btn:SetAttribute("macrotext1", TM .. " " .. id)                  -- set target raid icon
            btn:SetAttribute("macrotext2", WM .. " " .. GROUND_MARKER[id])    -- matching world flare
        end

        btn:HookScript("OnEnter", function(self) self:SetAlpha(0.7) end)
        btn:HookScript("OnLeave", function(self) self:SetAlpha(1) end)
    end
    return mw
end

local function Build()
    if built then return end
    if InCombatLockdown() then return end   -- caller retries on PLAYER_REGEN_ENABLED
    built = true

    -----------------------------------------------------------------------
    --  Show button (secure: can reveal the protected panel in combat)
    -----------------------------------------------------------------------
    ShowButton = CreateFrame("Button", "EllesmereUIRaidControlShowButton", UIParent, "SecureHandlerClickTemplate")
    PP.Size(ShowButton, 136, BH)
    ShowButton:SetFrameStrata("HIGH")
    ShowButton:SetClampedToScreen(true)
    ShowButton:RegisterForClicks("LeftButtonUp")
    StyleBackdrop(ShowButton, 0.92)
    ApplyPosition()   -- placement is configured via Unlock Mode

    local sbText = MakeFont(ShowButton, 12, nil, GREEN.r, GREEN.g, GREEN.b)
    sbText:SetPoint("CENTER", ShowButton, "CENTER", 0, 0)
    sbText:SetText(L("Raid Control"))

    ShowButton:HookScript("OnEnter", function(self)
        self._border:SetColor(GREEN.r, GREEN.g, GREEN.b, 1)
    end)
    ShowButton:HookScript("OnLeave", function(self)
        self._border:SetColor(BORDER.r, BORDER.g, BORDER.b, BORDER.a or 0.6)
    end)

    -----------------------------------------------------------------------
    --  Panel (secure base; hosts secure children)
    -----------------------------------------------------------------------
    Panel = CreateFrame("Frame", "EllesmereUIRaidControlPanel", UIParent, "SecureHandlerBaseTemplate")
    PP.Width(Panel, PANEL_WIDTH)
    Panel:SetFrameStrata("HIGH")
    Panel:SetFrameLevel(ShowButton:GetFrameLevel() + 5)
    Panel:Hide()
    Panel.toggled = false
    StyleBackdrop(Panel, 0.94)
    -- Top-align the panel with the (hidden) show button so expanding keeps the
    -- same top-left position instead of shifting down by the button height.
    PP.Point(Panel, "TOP", ShowButton, "TOP", 0, 0)

    -- Secure wiring: clicking the show button hides it and reveals the panel.
    ShowButton:SetFrameRef("RaidControlPanel", Panel)
    ShowButton:SetAttribute("_onclick", [=[
        self:Hide()
        self:GetFrameRef("RaidControlPanel"):Show()
    ]=])
    ShowButton:HookScript("OnClick", function() Panel.toggled = true end)

    -----------------------------------------------------------------------
    --  Content (top -> bottom). y is negative, measured from panel top.
    -----------------------------------------------------------------------
    local y = -PAD

    -- Helper: add a two-column row of buttons; returns updated y.
    local function Row2(leftCfg, rightCfg)
        local left = MakeButton(leftCfg.name, Panel, leftCfg.label, leftCfg.template, leftCfg.onClick)
        PP.Size(left, COL_W, BH)
        PP.Point(left, "TOPLEFT", Panel, "TOPLEFT", PAD, y)
        if leftCfg.setup then leftCfg.setup(left) end

        if rightCfg then
            local right = MakeButton(rightCfg.name, Panel, rightCfg.label, rightCfg.template, rightCfg.onClick)
            PP.Size(right, COL_W, BH)
            PP.Point(right, "TOPLEFT", left, "TOPRIGHT", GAP, 0)
            if rightCfg.setup then rightCfg.setup(right) end
        end
        y = y - BH - GAP
        return left
    end

    -- Raid Menu | Disband Group
    Row2(
        { name = "EllesmereUIRaidControl_RaidMenu", label = "Raid Menu", onClick = function()
            if ToggleFriendsFrame then ToggleFriendsFrame() end
        end },
        { name = "EllesmereUIRaidControl_Disband", label = "Disband Group", onClick = function(self)
            if self._disabled then return end
            if InGroup() then StaticPopup_Show("ELLESMEREUI_DISBAND_GROUP") end
        end, setup = function(b) permButtons[#permButtons + 1] = { btn = b, leaderOnly = true } end }
    )

    -- Ready Check | Role Poll
    Row2(
        { name = "EllesmereUIRaidControl_ReadyCheck", label = "Ready Check", onClick = function(self)
            if self._disabled then return end
            if InGroup() and not InCombatLockdown() then
                if C_PartyInfo and C_PartyInfo.DoReadyCheck then C_PartyInfo.DoReadyCheck() else DoReadyCheck() end
            end
        end, setup = function(b) permButtons[#permButtons + 1] = { btn = b } end },
        { name = "EllesmereUIRaidControl_RolePoll", label = "Role Poll", onClick = function(self)
            if self._disabled then return end
            if InGroup() and InitiateRolePoll then InitiateRolePoll() end
        end, setup = function(b) permButtons[#permButtons + 1] = { btn = b } end }
    )

    -- Main Tank | Main Assist (secure unit actions)
    Row2(
        { name = "EllesmereUIRaidControl_MainTank", label = "Main Tank", template = "SecureActionButtonTemplate",
          setup = function(b)
            b:RegisterForClicks("AnyUp")
            b:SetAttribute("useOnKeyDown", false)
            b:SetAttribute("type", "maintank")
            b:SetAttribute("unit", "target")
            b:SetAttribute("action", "toggle")
        end },
        { name = "EllesmereUIRaidControl_MainAssist", label = "Main Assist", template = "SecureActionButtonTemplate",
          setup = function(b)
            b:RegisterForClicks("AnyUp")
            b:SetAttribute("useOnKeyDown", false)
            b:SetAttribute("type", "mainassist")
            b:SetAttribute("unit", "target")
            b:SetAttribute("action", "toggle")
        end }
    )

    -- Countdown (full width)
    do
        local cd = MakeButton("EllesmereUIRaidControl_Countdown", Panel, "Countdown", nil, function(self)
            if self._disabled then return end
            if InGroup() and not InCombatLockdown() and C_PartyInfo and C_PartyInfo.DoCountdown then
                C_PartyInfo.DoCountdown(10)
            end
        end)
        PP.Size(cd, PANEL_WIDTH - PAD * 2, BH)
        PP.Point(cd, "TOPLEFT", Panel, "TOPLEFT", PAD, y)
        permButtons[#permButtons + 1] = { btn = cd }
        y = y - BH - GAP
    end

    -----------------------------------------------------------------------
    --  Dropdowns (Blizzard WowStyle1DropdownTemplate + SetupMenu)
    -----------------------------------------------------------------------
    -- The collapsed text is derived from whichever radio's IsSelected() returns
    -- true, evaluated at menu-generation time. The game-state changes these
    -- dropdowns drive (difficulty, raid/party, pings) are ASYNC -- the getters
    -- only reflect the new value after a server round-trip event. So we
    -- re-generate the menu when those events fire (mirrors ElvUI), which is what
    -- actually refreshes the displayed text.
    local function MakeDropdownRow(name, labelText, events, setupFn)
        local label = MakeFont(Panel, 11, nil, 0.8, 0.8, 0.8)
        PP.Point(label, "TOPLEFT", Panel, "TOPLEFT", PAD, y - 2)
        label:SetText(L(labelText))

        local dd = CreateFrame("DropdownButton", name, Panel, "WowStyle1DropdownTemplate")
        PP.Size(dd, PANEL_WIDTH - PAD * 2, BH)
        PP.Point(dd, "TOPLEFT", Panel, "TOPLEFT", PAD, y - 16)
        dd:SetupMenu(setupFn)
        if events then
            dd:SetScript("OnEvent", function(self) self:GenerateMenu() end)
            for _, e in ipairs(events) do dd:RegisterEvent(e) end
        end
        y = y - 16 - BH - GAP
        return dd
    end

    -- Dungeon / Raid Difficulty
    MakeDropdownRow("EllesmereUIRaidControl_Difficulty", "Difficulty",
        { "PLAYER_DIFFICULTY_CHANGED" },
        function(dropdown, root)
        local function IsSelected(id) return GetDungeonDifficultyID and GetDungeonDifficultyID() == id end
        local function SetSelected(id)
            if SetDungeonDifficultyID then SetDungeonDifficultyID(id) end
            dropdown:GenerateMenu()
        end
        root:CreateRadio(_G.PLAYER_DIFFICULTY1 or "Normal", IsSelected, SetSelected, 1)
        root:CreateRadio(_G.PLAYER_DIFFICULTY2 or "Heroic", IsSelected, SetSelected, 2)
        root:CreateRadio(_G.PLAYER_DIFFICULTY6 or "Mythic", IsSelected, SetSelected, 23)
    end)

    -- Convert to Raid / Party
    MakeDropdownRow("EllesmereUIRaidControl_Convert", "Group Type",
        { "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED", "PLAYER_ENTERING_WORLD" },
        function(dropdown, root)
        local function IsSelected(isRaid) return IsInRaid() == isRaid end
        local function SetSelected(isRaid)
            if not InCombatLockdown() and C_PartyInfo then
                if isRaid then C_PartyInfo.ConvertToRaid() else C_PartyInfo.ConvertToParty() end
            end
            dropdown:GenerateMenu()
        end
        root:CreateRadio(_G.RAID or "Raid", IsSelected, SetSelected, true)
        root:CreateRadio(_G.PARTY or "Party", IsSelected, SetSelected, false)
    end)

    -- Restrict Pings (retail only)
    if C_PartyInfo and C_PartyInfo.SetRestrictPings and Enum and Enum.RestrictPingsTo then
        MakeDropdownRow("EllesmereUIRaidControl_RestrictPings", "Restrict Pings",
            { "PLAYER_ROLES_ASSIGNED", "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED" },
            function(dropdown, root)
            local R = Enum.RestrictPingsTo
            local function IsSelected(v) return C_PartyInfo.GetRestrictPings() == v end
            local function SetSelected(v)
                if not InCombatLockdown() then
                    C_PartyInfo.SetRestrictPings(IsSelected(v) and R.None or v)
                end
                dropdown:GenerateMenu()
            end
            root:CreateRadio(_G.NONE or "None", IsSelected, SetSelected, R.None)
            root:CreateRadio(_G.RAID_MANAGER_RESTRICT_PINGS_TO_LEAD or "Leader", IsSelected, SetSelected, R.Lead)
            root:CreateRadio(_G.RAID_MANAGER_RESTRICT_PINGS_TO_ASSIST or "Assist", IsSelected, SetSelected, R.Assist)
            root:CreateRadio(_G.RAID_MANAGER_RESTRICT_PINGS_TO_TANKS_HEALERS or "Tanks & Healers", IsSelected, SetSelected, R.TankHealer)
        end)
    end

    -----------------------------------------------------------------------
    --  Everyone is Assistant (checkbox)
    -----------------------------------------------------------------------
    do
        local cb = CreateFrame("CheckButton", "EllesmereUIRaidControl_EveryoneAssist", Panel, "UICheckButtonTemplate")
        PP.Size(cb, BH, BH)
        PP.Point(cb, "TOPLEFT", Panel, "TOPLEFT", PAD, y)
        local cbLabel = cb.text or cb.Text or _G["EllesmereUIRaidControl_EveryoneAssistText"]
        if cbLabel then
            cbLabel:SetText(L("Everyone is Assistant"))
            cbLabel:SetFontObject("GameFontHighlightSmall")
        end
        cb:SetChecked(IsEveryoneAssistant and IsEveryoneAssistant() or false)
        cb:SetScript("OnClick", function(self)
            if not IsLeader() or InCombatLockdown() then
                self:SetChecked(IsEveryoneAssistant and IsEveryoneAssistant() or false)
                return
            end
            local set = C_PartyInfo and C_PartyInfo.SetEveryoneIsAssistant or SetEveryoneIsAssistant
            if set then set(self:GetChecked()) end
        end)
        Panel._everyoneAssist = cb
        y = y - BH - GAP
    end

    -----------------------------------------------------------------------
    --  Raid target / world markers (bottom of the panel, ElvUI-style)
    -----------------------------------------------------------------------
    local mh = BuildMarkers(Panel, y)
    y = y - mh - GAP

    -----------------------------------------------------------------------
    --  Close button below the panel (secure: hides panel, shows button)
    -----------------------------------------------------------------------
    PP.Height(Panel, -y + PAD - GAP)

    CloseButton = CreateFrame("Button", "EllesmereUIRaidControl_CloseButton", Panel, "SecureHandlerClickTemplate")
    PP.Size(CloseButton, PANEL_WIDTH * 0.6, BH)
    PP.Point(CloseButton, "TOP", Panel, "BOTTOM", 0, -2)
    StyleBackdrop(CloseButton, 0.92)
    local cbText = MakeFont(CloseButton, 12, nil, 1, 1, 1)
    cbText:SetPoint("CENTER", CloseButton, "CENTER", 0, 0)
    cbText:SetText(L("Close"))
    CloseButton:HookScript("OnEnter", function(self) self._border:SetColor(GREEN.r, GREEN.g, GREEN.b, 1) end)
    CloseButton:HookScript("OnLeave", function(self) self._border:SetColor(BORDER.r, BORDER.g, BORDER.b, BORDER.a or 0.6) end)

    CloseButton:SetFrameRef("RaidControlShowButton", ShowButton)
    CloseButton:SetAttribute("_onclick", [=[
        self:GetParent():Hide()
        self:GetFrameRef("RaidControlShowButton"):Show()
    ]=])
    CloseButton:HookScript("OnClick", function() Panel.toggled = false end)

    ShowButton:Hide()
end

-------------------------------------------------------------------------------
--  Disband-group confirmation popup
-------------------------------------------------------------------------------
StaticPopupDialogs["ELLESMEREUI_DISBAND_GROUP"] = {
    text = _G.CONFIRM_LEAVE_INSTANCE_PARTY or "Disband the group?",
    button1 = _G.YES or "Yes",
    button2 = _G.NO or "No",
    OnAccept = function()
        if not (UnitIsGroupLeader("player")) then return end
        if IsInRaid() then
            for i = 1, GetNumGroupMembers() do
                local name = GetRaidRosterInfo(i)
                if name then UninviteUnit(name) end
            end
        else
            for i = MAX_PARTY_MEMBERS or 4, 1, -1 do
                if UnitExists("party" .. i) then UninviteUnit(UnitName("party" .. i)) end
            end
        end
    end,
    timeout = 0, whileDead = 1, hideOnEscape = 1,
}

-------------------------------------------------------------------------------
--  Public enable / disable API (called from the options toggle and login)
-------------------------------------------------------------------------------
local function RegisterGroupEvents()
    if not groupEvents then
        groupEvents = CreateFrame("Frame")
        groupEvents:SetScript("OnEvent", ToggleRaidControl)
    end
    groupEvents:RegisterEvent("GROUP_ROSTER_UPDATE")
    groupEvents:RegisterEvent("PARTY_LEADER_CHANGED")
    groupEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
end

local function UnregisterGroupEvents()
    if not groupEvents then return end
    groupEvents:UnregisterEvent("GROUP_ROSTER_UPDATE")
    groupEvents:UnregisterEvent("PARTY_LEADER_CHANGED")
    groupEvents:UnregisterEvent("PLAYER_ENTERING_WORLD")
end

-- Single shared "do it after combat" handler. Builds the secure frames if a
-- build was requested during combat, then reconciles visibility.
local function EnsureDeferFrame()
    if deferFrame then return deferFrame end
    deferFrame = CreateFrame("Frame")
    deferFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if pendingBuild and EllesmereUIDB and EllesmereUIDB.raidControl then
            pendingBuild = false
            Build()
        end
        ToggleRaidControl()
    end)
    return deferFrame
end

function EllesmereUI_EnableRaidControl()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    EllesmereUIDB.raidControl = true
    RegisterGroupEvents()
    -- Hide the Blizzard raid manager, which Raid Control replaces (the helper
    -- handles combat deferral internally).
    if EllesmereUI._applyHideBlizzardPartyFrame then EllesmereUI._applyHideBlizzardPartyFrame() end

    if InCombatLockdown() then
        -- Secure frames must be created/attributed out of combat.
        pendingBuild = not built
        EnsureDeferFrame():RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end

    Build()
    ToggleRaidControl()
end

function EllesmereUI_DisableRaidControl()
    if EllesmereUIDB then EllesmereUIDB.raidControl = false end
    pendingBuild = false
    UnregisterGroupEvents()
    -- Restore the Blizzard raid manager (unless the user hides it separately).
    if EllesmereUI._applyHideBlizzardPartyFrame then EllesmereUI._applyHideBlizzardPartyFrame() end
    if not built then return end

    if InCombatLockdown() then
        -- Can't hide protected frames mid-combat; reconcile when it ends.
        EnsureDeferFrame():RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    Panel.toggled = false
    Panel:Hide()
    ShowButton:Hide()
end

function EllesmereUI_IsRaidControlEnabled()
    return EllesmereUIDB and EllesmereUIDB.raidControl or false
end

-- Create the shared defer frame now (Build is in scope) so ToggleRaidControl
-- can rely on it existing at runtime.
EnsureDeferFrame()

-------------------------------------------------------------------------------
--  Unlock Mode registration -- the Show button (and the panel anchored to it)
--  is positioned through Unlock Mode, not by dragging. The mover only appears
--  while the feature is enabled.
-------------------------------------------------------------------------------
local function RegisterUnlock()
    if not EllesmereUI.RegisterUnlockElements then return end
    local MK = EllesmereUI.MakeUnlockElement
    if not MK then return end

    EllesmereUI:RegisterUnlockElements({
        MK({
            key            = "EUI_RaidControl",
            label          = "Raid Control",
            group          = "Raid Control",
            order          = 650,
            noResize       = true,
            noAnchorTarget = true,
            isHidden = function()
                return not (EllesmereUIDB and EllesmereUIDB.raidControl)
            end,
            getFrame = function()
                if not built then Build() end
                return ShowButton
            end,
            getSize = function()
                return 136, BH
            end,
            savePos = function(_, _, _, x, y)
                if ShowButton and ShowButton:GetLeft() then
                    SavePosition()
                elseif x and y then
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    EllesmereUIDB.raidControlPos = { centerX = x, centerY = y }
                end
            end,
            loadPos = function()
                local pos = EllesmereUIDB and EllesmereUIDB.raidControlPos
                if pos and pos.centerX and pos.centerY then
                    return { point = "CENTER", relPoint = "CENTER", x = pos.centerX, y = pos.centerY }
                end
                return { point = DEFAULT_POINT, relPoint = DEFAULT_POINT, x = DEFAULT_X, y = DEFAULT_Y }
            end,
            clearPos = function()
                if EllesmereUIDB then EllesmereUIDB.raidControlPos = nil end
            end,
            applyPos = function()
                ApplyPosition()
            end,
        }),
    }, "EllesmereUIRaidControl")
end
_G._EUI_RaidControl_RegisterUnlock = RegisterUnlock

-------------------------------------------------------------------------------
--  Login bootstrap
-------------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if EllesmereUIDB and EllesmereUIDB.raidControl then
        EllesmereUI_EnableRaidControl()
    end
    RegisterUnlock()
end)
