if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not EllesmereUI.IS_FOREVER then return end
-------------------------------------------------------------------------------
-- EllesmereUIQuestTracker_QuestAudio.lua  (WoW Forever only)
--
-- A one-off bridge for the quest voice-over addon (owner pick 2026-11-07). Its
-- Play button sits on Blizzard's tracker blocks, which the Custom Quest
-- Tracker keeps muted, so the same button goes on our quest title rows
-- through the row hooks (EllesmereUI.RegisterQuestTrackerRow), made and bound
-- by that addon's own functions: its public button dressing, and its quest
-- log's play binding, reached through the one global it keeps stable.
-- Installed at login only while the custom tracker is in use and that addon
-- offers every function used here. A call that fails later turns the bridge
-- off for the session and hides its buttons, instead of reporting each row.
-------------------------------------------------------------------------------
local _, ns = ...

local SIZE, WIDTH = 14, 16                     -- the button, and the room it takes right of a title
local BOX = "QuestLog-icon-ticksquare"         -- the quest log's tracking box, which the button matches
local ORIGIN = "EllesmereUI's quest tracker"   -- names the button in that addon's own debug log

local function Install()
    if not ns.UseCustomTracker() then return end
    local env, spoken = _G.VoiceOver, _G.Spoken
    local ui = type(env) == "table" and rawget(env, "QuestOverlayUI")
    if type(ui) ~= "table" or type(spoken) ~= "table"
       or type(ui.ShowsTrackerButton) ~= "function" or type(ui.BindPlayButton) ~= "function"
       or type(ui.SetPlayButtonState) ~= "function" or type(ui.FollowQueue) ~= "function"
       or type(spoken.DressBoxButton) ~= "function" or type(spoken.RegisterCallback) ~= "function" then
        return
    end

    local buttons = {}   -- slot -> its button
    local voiced = {}    -- questID -> whether the addon shows Play for it
    local off = false

    local function Voiced(questID)
        local v = voiced[questID]
        if v == nil then
            v = ui:ShowsTrackerButton(questID) and true or false
            voiced[questID] = v
        end
        return v
    end

    local function Dress(slot, questID)
        local b = buttons[slot]
        if not Voiced(questID) then
            if b then b:Hide() end
            return
        end
        if not b then
            b = CreateFrame("Button", nil, slot)
            b:SetSize(SIZE, SIZE)
            b:SetHitRectInsets(1, 1, 1, 1)
            b:SetPoint("TOPRIGHT", slot, "TOPRIGHT", 0, 0)
            spoken:DressBoxButton(b)
            b:SetBox(BOX, SIZE, SIZE)
            -- Its glyph follows the addon's queue (play, stop, replay).
            b.setPlayState = ui.FollowQueue
            -- Dark behind the box: the tracker can sit straight on the world.
            local back = b:CreateTexture(nil, "BACKGROUND", nil, -1)
            back:SetPoint("TOPLEFT", 1, -1)
            back:SetPoint("BOTTOMRIGHT", -1, 1)
            back:SetColorTexture(0, 0, 0, 0.6)
            buttons[slot] = b
        end
        -- Bound again only when the pooled row shows another quest: a binding
        -- sets new scripts.
        if b.questID ~= questID then
            b.soundData = nil
            ui:BindPlayButton(b, questID, C_QuestLog.GetTitleForQuestID(questID) or "", ORIGIN)
            ui:SetPlayButtonState(b)
        end
        b:Show()
    end

    local function Row(slot, questID)
        if off then return end
        if not pcall(Dress, slot, questID) then
            off = true
            for _, b in pairs(buttons) do b:Hide() end
        end
    end
    -- Under the addon's own name: should it register a row hook of its own,
    -- the first registration stands and the other is refused, so no row ever
    -- gets two buttons.
    if not EllesmereUI.RegisterQuestTrackerRow("Spoken", Row, WIDTH) then return end

    -- What Voiced reads: the voice packs (loaded after login), the addon's
    -- quest part being on, and its tracker button setting (whose change, like
    -- every settings refresh, runs the addon's tracker sweep).
    local function Changed()
        wipe(voiced)
        EllesmereUI.RefreshQuestTrackerRows()
    end
    spoken:RegisterCallback("VOICE_PACKS_LOADED", Changed)
    spoken:RegisterCallback("PART_SWITCHED", function(part)
        if part == "quests" then Changed() end
    end)
    if type(ui.UpdateTrackerButtons) == "function" then
        hooksecurefunc(ui, "UpdateTrackerButtons", Changed)
    end
end

-- The addon loads after this one: everything it offers is there by login.
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Install()
end)
