if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_BlizzardParty.lua
--  Shared "Hide Blizzard Party Panel" feature.
--
--  Hides the Blizzard CompactRaidFrameManager -- the collapsed sidebar panel on
--  the left of the screen (ready check, role poll, raid world markers, etc.).
--  Lives in the parent so the QoL and Raid Frames modules drive the EXACT same
--  implementation and the same saved setting (EllesmereUIDB.hideBlizzardPartyFrame),
--  with no behaviour differing between the two toggles.
--
--  Default: whatever the user has saved; unset = shown (off).
--
--  Mechanism: reparent the manager to a hidden frame. SetParent is blocked in
--  combat, so the state is reconciled again when combat ends. When the setting
--  is off, the manager is reparented back to its original parent.
-------------------------------------------------------------------------------

local _partyHiddenParent
local _partyOrigParent
local _deferred

local function ApplyHideBlizzardPartyFrame()
    local shouldHide = EllesmereUIDB and EllesmereUIDB.hideBlizzardPartyFrame
    local mgr = CompactRaidFrameManager or _G["CompactRaidFrameManager"]
    if not mgr then return end
    if InCombatLockdown() then _deferred = true; return end
    _deferred = nil

    if shouldHide then
        if not _partyHiddenParent then
            _partyHiddenParent = CreateFrame("Frame")
            _partyHiddenParent:Hide()
        end
        if not _partyOrigParent then
            _partyOrigParent = mgr:GetParent()
        end
        if mgr:GetParent() ~= _partyHiddenParent then
            mgr:SetParent(_partyHiddenParent)
        end
    elseif _partyOrigParent and mgr:GetParent() ~= _partyOrigParent then
        mgr:SetParent(_partyOrigParent)
        mgr:Show()
    end
end

EllesmereUI._applyHideBlizzardPartyFrame = ApplyHideBlizzardPartyFrame

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
initFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
initFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    elseif event == "PLAYER_REGEN_ENABLED" and not _deferred
        and not (EllesmereUIDB and EllesmereUIDB.hideBlizzardPartyFrame) then
        return
    end
    ApplyHideBlizzardPartyFrame()
end)
