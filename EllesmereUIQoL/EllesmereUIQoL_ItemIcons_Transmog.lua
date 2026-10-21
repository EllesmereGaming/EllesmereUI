if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIQoL_ItemIcons_Transmog.lua
--  Item Icons transmog element: a check when the item's appearance is learned
--  (from any source), else a transmog glyph when this character can learn it
--  or when only another character of the account can. Each state has its own
--  color; the learned and other-character states can be switched off. States
--  are memoized per link: wiped when the collection changes, dropped per
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

local memo, memoN = {}, 0   -- link -> state; false when no state shows
local bySource = {}         -- source ID -> set of the memoized links that have it
local waiting = {}          -- frame keys holding items whose transmog data loads
local active = false
-- Inert until the element is placed while Item Icons is on
local ev = CreateFrame("Frame")

local function Forget()
    wipe(memo)
    wipe(bySource)
    memoN = 0
end

ev:SetScript("OnEvent", function(self, event, sourceID)
    if event == ITEM_UPDATE or event == COLLECTABILITY_UPDATE then
        if next(waiting) then
            self:UnregisterEvent(ITEM_UPDATE)
            -- Kept while active: it also updates memoized states
            if not active then self:UnregisterEvent(COLLECTABILITY_UPDATE) end
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

-- The item's state, false for none; nil while its data loads (not memoized)
local function State(item)
    local link = item.link
    local state = memo[link]
    if state ~= nil then return state end
    -- Battle pets, keystones and other non-item links have no appearance
    if not link:find("|Hitem:", 1, true) then
        Remember(link, false)
        return false
    end
    local _, sourceID = GetItemAppearance(link)
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
    Remember(link, state, sourceID)
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
        for i = 1, #ACTIVE_EVENTS do ev:RegisterEvent(ACTIVE_EVENTS[i]) end
    else
        ev:UnregisterAllEvents()
        Forget()
        wipe(waiting)
    end
end)
