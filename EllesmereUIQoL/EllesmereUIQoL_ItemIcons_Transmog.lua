if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIQoL_ItemIcons_Transmog.lua
--  Item Icons transmog element: a check when the item's look is known (this
--  very look, or its appearance from any source), else a red cross when this
--  character can learn it, a yellow question mark when only another character
--  of the account can. Blizzard's icons in their own colors; the learned and
--  other-character states can be switched off. States are
--  memoized per link (per source ID when the frame passes it in
--  facts.transmogSourceID): wiped when the collection changes, dropped per
--  source when its collectability changes. A state whose data is still loading
--  is never memoized. The events register only while the element is placed and
--  Item Icons is on. The element contract: EllesmereUIQoL_ItemIcons.lua.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI
local II = EllesmereUI.ItemIcons

local TC = C_TransmogCollection
local GetItemAppearance, GetAppearanceInfo = TC.GetItemInfo, TC.GetAppearanceInfoBySource
local PlayerCanCollect, AccountCanCollect = TC.PlayerCanCollectSource, TC.AccountCanCollectSource
local HasSource, HasItemLook = TC.PlayerHasTransmogItemModifiedAppearance, TC.PlayerHasTransmogByItemInfo
local GetItemInfo, IsDressable = C_Item.GetItemInfo, C_Item.IsDressableItemByID

-- Per state: the style switch that hides it, its icon: Blizzard's ready check
-- icons, as the EUI tooltip skin marks an owned mount
local LEARNED    = { toggle = "showLearned", texture = "Interface\\RaidFrame\\ReadyCheck-Ready" }
local THIS_CHAR  = { texture = "Interface\\RaidFrame\\ReadyCheck-NotReady" }
local OTHER_CHAR = { toggle = "showOtherChar", texture = "Interface\\RaidFrame\\ReadyCheck-Waiting" }

local MEMO_CAP = 4000
local ITEM_UPDATE = "TRANSMOG_COLLECTION_ITEM_UPDATE"
local COLLECTABILITY_UPDATE = "TRANSMOG_SOURCE_COLLECTABILITY_UPDATE"
local ACTIVE_EVENTS = {
    "TRANSMOG_COLLECTION_SOURCE_ADDED", "TRANSMOG_COLLECTION_SOURCE_REMOVED", "TRANSMOG_COLLECTION_UPDATED",
    COLLECTABILITY_UPDATE,
}

local memo, memoN = {}, 0   -- link (or passed source ID) -> state; false when no state shows
local bySource = {}         -- source ID -> set of the memo keys that have it
local waiting = {}          -- frame keys holding items whose transmog data loads
local active = false
-- Inert until the element is placed while Item Icons is on
local ev = CreateFrame("Frame")

local function Forget()
    wipe(memo)
    wipe(bySource)
    memoN = 0
end

ev:SetScript("OnEvent", function(_, event, sourceID)
    if event == ITEM_UPDATE or event == COLLECTABILITY_UPDATE then
        if next(waiting) then
            ev:UnregisterEvent(ITEM_UPDATE)
            -- Kept while active: it also updates memoized states
            if not active then ev:UnregisterEvent(COLLECTABILITY_UPDATE) end
            for frameKey in pairs(waiting) do II.RequestRefresh(frameKey) end
            wipe(waiting)
        end
        local links = event == COLLECTABILITY_UPDATE and bySource[sourceID]
        if links then
            -- Only the states of that source go; the core merges a burst of
            -- these into one repaint
            bySource[sourceID] = nil
            for link in pairs(links) do
                memo[link] = nil
                memoN = memoN - 1
            end
            II.RequestRefresh(nil)
        end
        return
    end
    -- An appearance was learned or lost: any state may have changed
    Forget()
    II.RequestRefresh(nil)
end)

local function Remember(link, state, sourceID)
    if memoN >= MEMO_CAP then Forget() end
    memo[link] = state
    memoN = memoN + 1
    if sourceID then
        local links = bySource[sourceID]
        if not links then
            links = {}
            bySource[sourceID] = links
        end
        links[link] = true
    end
end

-- The item's transmog data is loading: its frame repaints once it arrives
local function Wait(frameKey)
    if not next(waiting) then
        ev:RegisterEvent(ITEM_UPDATE)
        ev:RegisterEvent(COLLECTABILITY_UPDATE)
    end
    waiting[frameKey] = true
end

-- The item's state, false for none; nil while its data loads (not memoized).
-- A frame whose link cannot tell the appearance passes its source in
-- facts.transmogSourceID; the memo keys such items by that source ID.
local function State(item)
    local link = item.link
    local f = item.facts
    local known = f and f.transmogSourceID
    if known == false then return false end
    local key = known or link
    local state = memo[key]
    if state ~= nil then return state end
    local sourceID = known
    if not sourceID then
        -- Battle pets, keystones and other non-item links have no appearance
        if not link:find("|Hitem:", 1, true) then
            Remember(link, false)
            return false
        end
        local _
        _, sourceID = GetItemAppearance(link)
    end
    if sourceID then
        -- This very look known (an item you wear or wore), or the appearance
        -- from any source
        local info = GetAppearanceInfo(sourceID)
        if HasSource(sourceID) or (info and info.appearanceIsCollected) then
            state = LEARNED
        else
            local hasData, canCollect = PlayerCanCollect(sourceID)
            if canCollect then
                state = THIS_CHAR
            elseif hasData then
                hasData, canCollect = AccountCanCollect(sourceID)
                if canCollect then
                    state = OTHER_CHAR
                elseif hasData then
                    state = false
                end
            end
            if state == nil then
                Wait(item.frameKey)
                return nil
            end
        end
    elseif not GetItemInfo(link) then
        -- Not proven to answer before the item's data loads (GetItemInfo
        -- requests it): ask again once it arrives
        item.pending = true
        return nil
    elseif HasItemLook(link) then
        state = LEARNED
    elseif IsDressable(link) then
        -- Gear with a look whose appearance has not loaded yet: ask again
        -- once transmog data arrives
        Wait(item.frameKey)
        return nil
    else
        state = false
    end
    Remember(key, state, sourceID)
    return state
end

II.RegisterElement("transmog", {
    kind = "icon",
    Apply = function(item, style, out)
        local state = State(item)
        if not state or (state.toggle and not style[state.toggle]) then return false end
        out.texture = state.texture
        return true
    end,
})

-- Off, the memo goes: the collection may change unseen
II.Subscribe(function()
    local want = II.IsEnabled() and II.IsElementPlaced("transmog")
    if want == active then return end
    active = want
    if want then
        for i = 1, #ACTIVE_EVENTS do ev:RegisterEvent(ACTIVE_EVENTS[i]) end
    else
        ev:UnregisterAllEvents()
        Forget()
        wipe(waiting)
    end
end)
