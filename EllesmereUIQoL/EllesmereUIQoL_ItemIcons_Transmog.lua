if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIQoL_ItemIcons_Transmog.lua
--  Item Icons transmog element: a check when the item's appearance is learned
--  (from any source), else a transmog glyph when this character can learn it
--  or when only another character of the account can. Each state has its own
--  color; the learned and other-character states can be switched off. States
--  are memoized per link (per source ID when the frame passes it in
--  facts.transmogSourceID): wiped when the collection changes, dropped per
--  source when its collectability changes. The events register only while the
--  element is placed and Item Icons is on. The element contract:
--  EllesmereUIQoL_ItemIcons.lua.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI
local II = EllesmereUI.ItemIcons

-- Not proven on WoW Forever: without the whole collection API the element
-- never registers
local TC = C_TransmogCollection
local GetItemAppearance = TC and TC.GetItemInfo
local GetAppearanceInfo = TC and TC.GetAppearanceInfoBySource
local PlayerCanCollect = TC and TC.PlayerCanCollectSource
local AccountCanCollect = TC and TC.AccountCanCollectSource
if not (GetItemAppearance and GetAppearanceInfo and PlayerCanCollect and AccountCanCollect) then return end

local GetItemInfo = C_Item.GetItemInfo

-- Blizzard's "appearance known" check (DressUpFrames) and its transmog roll
-- glyph (LootHistory), desaturated and tinted with the state's color
local CHECK_ATLAS, GLYPH_ATLAS = "common-icon-checkmark", "lootroll-icon-transmog"
-- Per state: its style color, the style switch that hides it, its atlas
local LEARNED    = { color = "learnedColor", toggle = "showLearned", atlas = CHECK_ATLAS }
local THIS_CHAR  = { color = "thisCharColor", atlas = GLYPH_ATLAS }
local OTHER_CHAR = { color = "otherCharColor", toggle = "showOtherChar", atlas = GLYPH_ATLAS }

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

-- WoW Forever is not proven in game: an event the client does not know is
-- never registered, so it cannot raise an error
local function Watch(event, on)
    if not C_EventUtils.IsEventValid(event) then return end
    if on then ev:RegisterEvent(event) else ev:UnregisterEvent(event) end
end

ev:SetScript("OnEvent", function(_, event, sourceID)
    if event == ITEM_UPDATE or event == COLLECTABILITY_UPDATE then
        if next(waiting) then
            Watch(ITEM_UPDATE, false)
            -- Kept while active: it also updates memoized states
            if not active then Watch(COLLECTABILITY_UPDATE, false) end
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
        Watch(ITEM_UPDATE, true)
        Watch(COLLECTABILITY_UPDATE, true)
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
        local info = GetAppearanceInfo(sourceID)
        if info and info.appearanceIsCollected then
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
    elseif GetItemInfo(link) then
        state = false
    else
        -- Not proven to answer before the item's data loads (GetItemInfo
        -- requests it): ask again once it arrives
        item.pending = true
        return nil
    end
    Remember(key, state, sourceID)
    return state
end

II.RegisterElement("transmog", {
    kind = "icon",
    Apply = function(item, style, out)
        local state = State(item)
        if not state or (state.toggle and not style[state.toggle]) then return false end
        local c = style[state.color]
        out.atlas, out.desaturate = state.atlas, true
        out.r, out.g, out.b = c.r, c.g, c.b
        return true
    end,
})

-- Off, the memo goes: the collection may change unseen
II.Subscribe(function()
    local want = II.IsEnabled() and II.GetElementSlot("transmog") ~= nil
    if want == active then return end
    active = want
    if want then
        for i = 1, #ACTIVE_EVENTS do Watch(ACTIVE_EVENTS[i], true) end
    else
        ev:UnregisterAllEvents()
        Forget()
        wipe(waiting)
    end
end)
