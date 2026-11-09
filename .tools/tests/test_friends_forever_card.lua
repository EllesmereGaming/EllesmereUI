-- Stub harness: the WoW Forever Friends List card's Custom Friends List Tiles
-- switch (friendsListCard.customTiles) in
-- EllesmereUIBlizzardSkin/EllesmereUIBlizzardSkin_FriendsForever.lua. Unset, it
-- follows the card's look (on while the card is skinned, off under Blizz
-- Default); a pick is kept only where it differs from that; the kit's host and
-- the custom list start at login while the card is skinned or the switch is
-- on, and later when the switch is first turned on, the host hooking
-- Blizzard's cards only while the card was skinned at login.
--   lua .tools/tests/test_friends_forever_card.lua        (from the repository root)
local ROOT = arg and arg[1] or "."
local fh = assert(io.open(ROOT .. "/EllesmereUIBlizzardSkin/EllesmereUIBlizzardSkin_FriendsForever.lua", "rb"))
local SRC = fh:read("*a")
fh:close()

local style = "eui"
local calls, frames

function CreateFrame()
    local fr = { _scripts = {}, _events = {} }
    function fr:RegisterEvent(e) self._events[e] = true end
    function fr:UnregisterEvent(e) self._events[e] = nil end
    function fr:SetScript(k, fn) self._scripts[k] = fn end
    frames[#frames + 1] = fr
    return fr
end

-- A fresh load of the file, as each session has one
local function Load()
    calls = { starts = {}, listStarts = 0, refreshes = 0, redecorates = 0 }
    frames = {}
    EllesmereUI = {
        IS_FOREVER = true,
        NewFrameData = function()
            local t = {}
            return t, function(k) t[k] = t[k] or {}; return t[k] end
        end,
        GetBlizzWindowStyle = function(win)
            assert(win == "socialui", "another card's look was read")
            return style
        end,
        FriendsList = {
            TileRange = function() return 24, 70, 40 end,
            Start = function() calls.listStarts = calls.listStarts + 1 end,
            Refresh = function() calls.refreshes = calls.refreshes + 1 end,
        },
        FriendsKit = {
            StartTiles = function(h) calls.starts[#calls.starts + 1] = h end,
            RedecorateTiles = function() calls.redecorates = calls.redecorates + 1 end,
            SyncAutoAccept = function() end,
        },
    }
    local ns = { WSkin = { RegisterWindow = function() end, Shell = function() end } }
    assert(loadstring(SRC, "=EllesmereUIBlizzardSkin_FriendsForever.lua"))("EllesmereUIBlizzardSkin", ns)
    local boot
    for _, fr in ipairs(frames) do
        if fr._events.PLAYER_LOGIN then boot = fr end
    end
    assert(boot, "no login frame")
    return ns, boot
end

local function Login(boot)
    boot._scripts.OnEvent(boot, "PLAYER_LOGIN")
end

local function Saved()
    return EllesmereUIDB and EllesmereUIDB.friendsListCard and EllesmereUIDB.friendsListCard.customTiles
end

-- 1. a card on EllesmereUI or Modern with nothing saved: the list on, as before the switch; the kit's
--    host starts at login with its cards, then the list
EllesmereUIDB = { friendsListCard = { tileHeight = 50, factionBanners = true } }
style = "eui"
local ns, boot = Load()
assert(ns.FriendsCardGet("customTiles") == true, "the switch reads off on a skinned card")
Login(boot)
assert(#calls.starts == 1 and calls.starts[1].cards == true and calls.starts[1].style == "eui"
    and calls.starts[1].fontKey == "blizzardSkin" and calls.listStarts == 1, "the skinned card's start")
assert(calls.starts[1].onlineCards == 0.25, "a skinned card's list does not wear Blizzard's online cards at a quarter")
assert(calls.starts[1].Settings().customTiles == true, "the list's settings read the switch off")
style = "modern"
assert(ns.FriendsCardGet("customTiles") == true)
assert(ns.FriendsCardGet("tileHeight") == 50 and ns.FriendsCardGet("factionBanners") == true
    and ns.FriendsCardGet("showRegionIcons") == true, "the card's other settings changed")
assert(Saved() == nil, "reading the switch wrote it")

-- 2. a card on Blizz Default with nothing saved: the list off, as before the switch; nothing starts
EllesmereUIDB = { friendsListCard = { tileHeight = 50 } }
style = "off"
ns, boot = Load()
assert(ns.FriendsCardGet("customTiles") == false, "the switch reads on under Blizz Default")
Login(boot)
assert(#calls.starts == 0 and calls.listStarts == 0, "something started under Blizz Default with the list off")
-- turned on: kept, and the host starts for the list alone, with no hook on Blizzard's cards
ns.FriendsCardSet("customTiles", true)
assert(Saved() == true and ns.FriendsCardGet("customTiles") == true)
assert(#calls.starts == 1 and calls.starts[1].cards == false and calls.listStarts == 1 and calls.refreshes >= 1,
    "turning the switch on under Blizz Default did not start the list")
-- turned off again: Blizz Default's own answer, so nothing is kept
local refreshes = calls.refreshes
ns.FriendsCardSet("customTiles", false)
assert(Saved() == nil and ns.FriendsCardGet("customTiles") == false, "a pick equal to the look's answer was kept")
assert(calls.refreshes == refreshes + 1 and #calls.starts == 1, "turning the switch off started something")

-- 3. Blizz Default with the switch on at login: the host starts without its cards
EllesmereUIDB = { friendsListCard = { customTiles = true } }
style = "off"
ns, boot = Load()
Login(boot)
assert(#calls.starts == 1 and calls.starts[1].cards == false and calls.listStarts == 1,
    "the list did not start at login under Blizz Default")
assert(calls.starts[1].onlineCards == 1, "the list under Blizz Default does not wear Blizzard's online cards whole")

-- 4. a skinned card turned off: kept, and it survives a change of look; turned on again: dropped, so
--    the switch follows the look again
EllesmereUIDB = {}
style = "eui"
ns, boot = Load()
Login(boot)
ns.FriendsCardSet("customTiles", false)
assert(Saved() == false and ns.FriendsCardGet("customTiles") == false)
style = "off"
assert(ns.FriendsCardGet("customTiles") == false)
style = "modern"
assert(ns.FriendsCardGet("customTiles") == false, "a kept pick did not survive a change of look")
ns.FriendsCardSet("customTiles", true)
assert(Saved() == nil and ns.FriendsCardGet("customTiles") == true, "a pick equal to the look's answer was kept")
style = "off"
assert(ns.FriendsCardGet("customTiles") == false, "the switch did not follow the look once the pick was dropped")
-- the look changed after login (its reload still to come): a start keeps the login look's cards
ns.FriendsCardSet("customTiles", true)
assert(Saved() == true and calls.starts[#calls.starts].cards == true, "a later start changed the cards")

-- 5. a Custom Friends List switch a tester build saved (customList) is not read
EllesmereUIDB = { friendsListCard = { customList = false } }
style = "eui"
ns, boot = Load()
assert(ns.FriendsCardGet("customTiles") == true, "an old customList switch was read")
Login(boot)
assert(calls.starts[1].cards == true and calls.listStarts == 1)
EllesmereUIDB = { friendsListCard = { customList = true } }
style = "off"
ns, boot = Load()
assert(ns.FriendsCardGet("customTiles") == false, "an old customList switch was read")
Login(boot)
assert(#calls.starts == 0)

-- 6. a reset that clears the card's settings: the switch follows the look again
EllesmereUIDB = { friendsListCard = { customTiles = true } }
style = "off"
ns, boot = Load()
Login(boot)
EllesmereUIDB.friendsListCard = nil
ns.FriendsCardRefresh()
assert(ns.FriendsCardGet("customTiles") == false and calls.refreshes >= 1)
-- the same on a skinned card whose list was off at login: the reset starts nothing new and turns it on
EllesmereUIDB = { friendsListCard = { customTiles = false } }
style = "eui"
ns, boot = Load()
Login(boot)
EllesmereUIDB.friendsListCard = nil
ns.FriendsCardRefresh()
assert(ns.FriendsCardGet("customTiles") == true and calls.starts[#calls.starts].cards == true)
-- Blizz Default at login with the list off, the look then changed (its reload still to come) and the
-- settings reset: the switch now reads on, and the list starts with the login look's host, no cards
EllesmereUIDB = { friendsListCard = { tileHeight = 30 } }
style = "off"
ns, boot = Load()
Login(boot)
assert(#calls.starts == 0)
style = "eui"
EllesmereUIDB.friendsListCard = nil
ns.FriendsCardRefresh()
assert(#calls.starts == 1 and calls.starts[1].cards == false and calls.listStarts == 1,
    "a reset that turned the list on did not start it")

-- 7. a fresh install: no saved data at all, on each look
EllesmereUIDB = nil
style = "eui"
ns, boot = Load()
assert(ns.FriendsCardGet("customTiles") == true and ns.FriendsCardGet("tileHeight") == 40)
style = "off"
assert(ns.FriendsCardGet("customTiles") == false)
Login(boot)
assert(#calls.starts == 0 and EllesmereUIDB == nil, "a fresh install under Blizz Default started or wrote something")

print("friends forever card harness: ok")
