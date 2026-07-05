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
--  Also hidden whenever Raid Control is enabled (EllesmereUIDB.raidControl),
--  since that feature replaces the Blizzard raid manager.
--
--  Default: whatever the user has saved; unset = shown (off).
--
--  Mechanism: reparent the manager to a hidden frame (SetParent is blocked in
--  combat, so a PLAYER_REGEN_ENABLED watcher re-asserts it after combat). When
--  the setting is off, the manager is reparented back to its original parent.
-------------------------------------------------------------------------------

local hookedMgr = false

local _partyHiddenParent
local _partyOrigParent

local function ApplyHideBlizzardPartyFrame()
    -- Hidden when the user opts in OR when Raid Control is enabled (it replaces
    -- the Blizzard raid manager, so the Blizzard one must not also show).
    local shouldHide = EllesmereUIDB and (EllesmereUIDB.hideBlizzardPartyFrame or EllesmereUIDB.raidControl)
    local mgr = CompactRaidFrameManager or _G["CompactRaidFrameManager"]
    if not mgr then return end

    if shouldHide then
        if not _partyHiddenParent then
            _partyHiddenParent = CreateFrame("Frame")
            _partyHiddenParent:Hide()
        end
        if not _partyOrigParent then
            _partyOrigParent = mgr:GetParent()
        end
        if not InCombatLockdown() then
            mgr:SetParent(_partyHiddenParent)
        end
        if not hookedMgr then
            hookedMgr = true
            local regenFrame = CreateFrame("Frame")
            regenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            regenFrame:SetScript("OnEvent", function()
                if EllesmereUIDB and EllesmereUIDB.hideBlizzardPartyFrame then
                    if mgr:GetParent() ~= _partyHiddenParent then
                        mgr:SetParent(_partyHiddenParent)
                    end
                end
            end)
        end
    else
        if _partyOrigParent and not InCombatLockdown() then
            mgr:SetParent(_partyOrigParent)
            mgr:Show()
        end
    end
end

EllesmereUI._applyHideBlizzardPartyFrame = ApplyHideBlizzardPartyFrame

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
initFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    end
    ApplyHideBlizzardPartyFrame()
end)
