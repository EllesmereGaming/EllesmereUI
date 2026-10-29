if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIQoL_ItemIcons.lua
--  Item Icons core: settings (QoL profile key "itemIcons"), the element and
--  frame registries, the slot resolver and the painter. Off by default; while
--  off nothing is hooked and the event frame below stays inert. Providers:
--  _Elements.lua (the overlays EUI drew before), _Transmog.lua, _Track.lua.
--  Frame adapters: _FramesInventory.lua, _FramesExchange.lua, _FramesBrowse.lua.
--
--  API: EllesmereUI.ItemIcons. Every table it hands out is read-only.
--    SLOT_ORDER, ELEMENT_ORDER, FRAME_ORDER, TRACK_ORDER   keys in menu order
--    ELEMENTS[key] = { sizeMin, sizeMax, retailOnly, style = defaults }; every
--                  style has offsetX and offsetY, px within +-OFFSET_MAX
--    DIM_ALPHA     ctx.alpha for the marks of an item Blizzard dims
--
--    IsEnabled()                   master switch, as applied
--    IsFrameEnabled(frameKey)      true while that frame is managed (taken over)
--    IsFrameAvailable(frameKey)    false for a frame the client lacks (no Great
--                                  Vault on WoW Forever): it is never managed
--    BlizzardBagsInUse()           true while Blizzard's bags and bank show, not
--                                  EUI Bags': blizz_bags and blizz_bank are
--                                  managed only then, eui_bags only otherwise
--    IsElementAvailable(key)       false for a retail-only element on WoW Forever
--    GetSettings()                 the validated settings; write through setters
--    IsElementPlaced(key)          true while at least one slot lists the element
--    Subscribe(fn)                 fn(reason) after every change. reason:
--                                  "profile" (login, swap, import, reset),
--                                  "enabled", "frames", "layout", "styles", "tooltip"
--    SetEnabled(on), SetFrameEnabled(frameKey, on), SetTooltipPip(on)
--    SetSlotList(slotKey, keys)    keys in priority order; another slot may list
--                                  them too
--    SetStyle(key, field, value)   false when value is invalid for the field
--    Reset()                       drops itemIcons (the QoL module reset)
--
--    RegisterFrame(frameKey, adapter) -> bool, once per frame key. adapter:
--      Enable(frameKey)    the frame became managed: install hooks once (they
--                          stay inert while IsFrameEnabled is false), paint
--      Refresh(frameKey)   still managed, but the layout, styles or item data
--                          changed, or combat ended for buttons whose overlay
--                          waited for it: repaint the shown buttons
--      Disable(frameKey)   optional, on release. The core then clears every
--                          button painted for the frame and restores the
--                          marks HideNatives hid
--    RegisterLazyFrame(frameKey, addonName, Install, Repaint) -> bool,
--      RegisterFrame for a frame a Blizzard addon owns: Install() runs once, on
--      the frame's first Enable, as soon as addonName has loaded (at once or
--      when it loads); from then on Enable and Refresh call Repaint(), which
--      paints the frame's shown buttons
--    Paint(button, ctx, frameKey)  draws the layout on button; no-op unless the
--      frame is managed. ctx is read during the call only (reuse one table):
--        link        item hyperlink; nothing is drawn without one
--        bag, slot   container location, or location: an ItemLocation
--        count       the frame's stack count; quality, itemID when known
--        anchor      region to cover instead of button (optional)
--        alpha       overlay opacity 0..1 (optional, 1); DIM_ALPHA for an item
--                    Blizzard dims (search filter, item context)
--        scale       mark size factor (optional, 1) for an anchor smaller than
--                    an item button, e.g. a list-row icon: every element size
--                    is multiplied by it, and a text element it shrinks below
--                    MIN_TEXT_SIZE (8 pt) does not apply, so the next element
--                    in its slot can show
--        facts       precomputed values (optional): isGear, itemLevel,
--                    trackColor, upgradeLevel, isBound, isWuE, bindType,
--                    setName, isJunk, questStarter, transmogSourceID.
--                    nil = unknown (worked out), false = known absent.
--                    An item without a location counts as unbound: an adapter
--                    whose items may be bound but have no location (inspect)
--                    passes isBound = true. transmogSourceID: the item's
--                    appearance source when its link cannot tell it (an
--                    auction item key); false = none, so no transmog mark
--    Clear(button)                 hides everything painted on button
--    RequestRefresh(frameKey)      coalesced Refresh of a managed frame (nil: all)
--    WaitForItem(itemID, frameKey) an item whose ID is known but whose link is
--                                  not yet (its data is not cached): asks for
--                                  its data and refreshes frameKey when it comes
--    HideNatives(button, frameKey, countRegion, questMark, starter)
--      alpha-hides the Blizzard marks of button that elements replace, while
--      the frame is managed, whether their element is placed or not: the stack
--      count (countRegion, nil when the frame shows none), the crafting pip and
--      the junk coin. questMark (optional): Blizzard's quest texture, hidden
--      while starter (the item starts a quest; the questMarker element) and
--      shown otherwise (the border of other quest items). Call it on every
--      paint, after Blizzard's own update: ItemButtonMixin:SetAlpha sets the
--      alpha of Count, IconOverlay and icon again
--    RestoreNatives(button, countRegion, questMark)  gives them back, e.g. for
--      a button showing no item (a currency keeps Blizzard's count)
--    TooltipItemLink(data)         the item link of tooltip data (C_TooltipInfo),
--                                  read as TooltipUtil.GetDisplayedItem reads it;
--                                  nil when its GUID or hyperlink is secret
--
--    RegisterElement(key, def) -> bool, for a key of ELEMENTS. def:
--      kind        "text" | "icon"
--      Apply(item, style, out) -> true when the element shows for the item
--        item: link, itemID, quality, count, bag, slot, location (ItemLocation
--          or nil), facts, frameKey, styles (every element's style). Memoize
--          on "_"-prefixed fields (wiped each paint); set pending = true while
--          item data loads (the frame repaints when it arrives). An error is
--          reported and counts as not applying
--        out: text (text kind) or atlas / texture (icon kind); r, g, b (text
--          color or icon tint, white by default); desaturate
--      insetX, insetY  px in from the slot's corner, mirrored per slot (1); the
--                  style's offsetX, offsetY (times ctx.scale) move it from there
--      fitWidth    text: one line clipped to the button width
--      texCoord    icon file texture { l, r, t, b }; mask: a mask file
--    An icon is style.size tall, an atlas as wide as its aspect; text is
--    style.size pt in the QoL font (on eui_bags, the Bags font); both times
--    ctx.scale.
-------------------------------------------------------------------------------
local _, ns = ...
local EllesmereUI = _G.EllesmereUI
local IS_FOREVER = EllesmereUI.IS_FOREVER

local II = {}
EllesmereUI.ItemIcons = II

local FONT_KEY = "extras"      -- the QoL font (Fonts page)
-- Frames whose text keeps their module's font: the player's Bags font stays
-- on EUI Bags under the takeover
local FRAME_FONT = { eui_bags = "bags" }
local DEFER_KEY = "EUI_ItemIcons"
local REFRESH_DELAY = 0.1      -- a burst of item data or settings writes repaints once
local FAILED_CAP = 200         -- item IDs whose data failed to load, kept per session
local MIN_TEXT_SIZE = 8        -- pt: a text that ctx.scale shrinks below this does not apply
local OFFSET_MAX = 20          -- px an element may move from its slot's spot, per axis

-------------------------------------------------------------------------------
--  Catalog
-------------------------------------------------------------------------------
local SLOT_ORDER = { "topleft", "top", "topright", "right", "bottomright", "bottom", "bottomleft", "left", "center" }
local NUM_SLOTS = #SLOT_ORDER
-- Per slot: anchor point, x and y signs applied to an element's insets, text justification
local SLOT_GEOM = {
    { "TOPLEFT", 1, -1, "LEFT" },
    { "TOP", 0, -1, "CENTER" },
    { "TOPRIGHT", -1, -1, "RIGHT" },
    { "RIGHT", -1, 0, "RIGHT" },
    { "BOTTOMRIGHT", -1, 1, "RIGHT" },
    { "BOTTOM", 0, 1, "CENTER" },
    { "BOTTOMLEFT", 1, 1, "LEFT" },
    { "LEFT", 1, 0, "LEFT" },
    { "CENTER", 0, 0, "CENTER" },
}
local SLOT_INDEX = {}
for i = 1, NUM_SLOTS do SLOT_INDEX[SLOT_ORDER[i]] = i end

local FRAME_ORDER = {
    "eui_bags", "blizz_bags", "blizz_bank", "merchant", "guildbank", "loot", "grouploot", "mail",
    "trade", "questrewards", "auctionhouse", "blackmarket", "encounterjournal", "greatvault",
    "charsheet", "flyout", "inspect", "professions", "customerorders",
}
local FRAME_SET = {}
for i = 1, #FRAME_ORDER do FRAME_SET[FRAME_ORDER[i]] = true end
-- No Great Vault on WoW Forever
local RETAIL_FRAMES = { greatvault = true }

local function FrameAvailable(frameKey)
    return FRAME_SET[frameKey] == true and not (IS_FOREVER and RETAIL_FRAMES[frameKey])
end

-- Blizzard's bags and bank show unless EUI Bags replaces them: it is loaded
-- and did not stand down for the session (WoW Forever's Gamepad interface
-- style: EllesmereUI._BagsStandDown, EUI_Bags_Shared.lua)
local function BlizzardBagsInUse()
    local standDown = EllesmereUI._BagsStandDown
    return not standDown or standDown()
end

-- The frames that show the player's bags, true for Blizzard's: one of them is
-- managed only while it is the one showing them
local BAG_FRAMES = { eui_bags = false, blizz_bags = true, blizz_bank = true }

local function FrameInUse(frameKey)
    local blizz = BAG_FRAMES[frameKey]
    return blizz == nil or blizz == BlizzardBagsInUse()
end

-- Canonical track keys (EllesmereUI.GetUpgradeTrackKey)
local TRACK_ORDER = { "Explorer", "Adventurer", "Veteran", "Champion", "Hero", "Myth" }

local function RGB(r, g, b) return { r = r, g = g, b = b } end

local TEXT_SIZES, ICON_SIZES = { 6, 24 }, { 8, 48 }
-- Every element also starts at its slot's spot (offsets 0)
local function Element(sizes, style, retailOnly)
    style.offsetX, style.offsetY = 0, 0
    return { sizeMin = sizes[1], sizeMax = sizes[2], style = style, retailOnly = retailOnly or false }
end

local trackStyle = { size = 14 }
for i = 1, #TRACK_ORDER do
    local c = EllesmereUI.UPGRADE_TRACK_COLORS[TRACK_ORDER[i]]
    trackStyle[TRACK_ORDER[i]] = RGB(c.r, c.g, c.b)
end

-- Style defaults; sizes follow the EUI Bags overlays. upgradeTrack keeps a color
-- per TRACK_ORDER key; transmog two state switches.
local ELEMENTS = {
    itemLevel       = Element(TEXT_SIZES, { size = 12, colorMode = "default", customColor = RGB(1, 1, 1) }),
    upgradeRank     = Element(TEXT_SIZES, { size = 11 }),
    upgradeTrack    = Element(ICON_SIZES, trackStyle, true),
    transmog        = Element(ICON_SIZES, { size = 14, showLearned = true, showOtherChar = true }),
    stackCount      = Element(TEXT_SIZES, { size = 11 }),
    bindType        = Element(TEXT_SIZES, { size = 11 }),
    setName         = Element(TEXT_SIZES, { size = 9 }),
    craftingQuality = Element(ICON_SIZES, { size = 28 }, true),
    junkCoin        = Element(ICON_SIZES, { size = 12 }),
    questMarker     = Element(ICON_SIZES, { size = 22 }),
    keystoneLevel   = Element(TEXT_SIZES, { size = 11 }),
    keystoneDungeon = Element(TEXT_SIZES, { size = 9 }),
    upgradeArrow    = Element(ICON_SIZES, { size = 16 }),
}
local ELEMENT_ORDER = {
    "itemLevel", "upgradeRank", "upgradeTrack", "transmog", "stackCount", "bindType", "setName",
    "craftingQuality", "junkCoin", "questMarker", "keystoneLevel", "keystoneDungeon", "upgradeArrow",
}
-- The values of each string style field
local ENUMS = { colorMode = { default = true, custom = true } }

II.SLOT_ORDER, II.ELEMENT_ORDER, II.FRAME_ORDER, II.TRACK_ORDER = SLOT_ORDER, ELEMENT_ORDER, FRAME_ORDER, TRACK_ORDER
II.ELEMENTS = ELEMENTS
II.OFFSET_MAX = OFFSET_MAX
-- Blizzard's search filter lays black at 0.8 alpha over the items it dims
-- (ItemButtonMixin:UpdateItemContextOverlayTextures): the marks dim to match
II.DIM_ALPHA = 0.2

-------------------------------------------------------------------------------
--  Settings
-------------------------------------------------------------------------------
local db, cur           -- the shared QoL profile db; the validated settings in use
local detached          -- defaults in use until the first write stores them
local styleVer = 0      -- bumped whenever drawn regions must re-apply their style
local layoutDirty = true

local function Profile()
    if not db then db = EllesmereUI.Lite.NewDB("EllesmereUIQoLDB") end
    return db.profile
end

local function IsColor(v)
    if type(v) ~= "table" then return false end
    local r, g, b = v.r, v.g, v.b
    return type(r) == "number" and type(g) == "number" and type(b) == "number"
        and r >= 0 and r <= 1 and g >= 0 and g <= 1 and b >= 0 and b <= 1
end

local function Copy(v)
    if type(v) == "table" then return RGB(v.r, v.g, v.b) end
    return v
end

local function ValidStyle(key, field, v)
    local spec = ELEMENTS[key]
    local d = spec and spec.style[field]
    if d == nil then return false end
    if field == "size" then
        return type(v) == "number" and v >= spec.sizeMin and v <= spec.sizeMax
    end
    if field == "offsetX" or field == "offsetY" then
        return type(v) == "number" and v >= -OFFSET_MAX and v <= OFFSET_MAX
    end
    local t = type(d)
    if t == "table" then return IsColor(v) end
    if t == "string" then return ENUMS[field][v] == true end
    return type(v) == t
end

-- Keeps known element keys, once per slot; several slots may list one element
local function ValidateSlots(s)
    local slots = s.slots
    if type(slots) ~= "table" then slots = {}; s.slots = slots end
    for k in pairs(slots) do
        if not SLOT_INDEX[k] then slots[k] = nil end
    end
    for i = 1, NUM_SLOTS do
        local key = SLOT_ORDER[i]
        local list, clean, seen = slots[key], {}, {}
        if type(list) == "table" then
            for _, e in ipairs(list) do
                if ELEMENTS[e] and not seen[e] then
                    seen[e] = true
                    clean[#clean + 1] = e
                end
            end
        end
        slots[key] = clean
    end
end

-- Repairs each invalid field on its own: unknown frame, slot, element and
-- style keys go, anything else falls back to its default.
local function ValidateSettings(s)
    if type(s.enabled) ~= "boolean" then s.enabled = false end
    if type(s.seeded) ~= "boolean" then s.seeded = false end
    if type(s.tooltipTrackPip) ~= "boolean" then s.tooltipTrackPip = false end

    local frames = s.frames
    if type(frames) ~= "table" then frames = {}; s.frames = frames end
    for k in pairs(frames) do
        if not FRAME_SET[k] then frames[k] = nil end
    end
    for i = 1, #FRAME_ORDER do
        local k = FRAME_ORDER[i]
        if type(frames[k]) ~= "boolean" then frames[k] = false end
    end

    ValidateSlots(s)

    local styles = s.styles
    if type(styles) ~= "table" then styles = {}; s.styles = styles end
    for k in pairs(styles) do
        if not ELEMENTS[k] then styles[k] = nil end
    end
    for key, spec in pairs(ELEMENTS) do
        local st = styles[key]
        if type(st) ~= "table" then st = {}; styles[key] = st end
        for field in pairs(st) do
            if spec.style[field] == nil then st[field] = nil end
        end
        for field, d in pairs(spec.style) do
            if not ValidStyle(key, field, st[field]) then st[field] = Copy(d) end
        end
    end
end

-- Once, before the first stored write (or on enable, for a profile stored
-- unseeded): the layout follows the profile's Bags overlays and the vendor and
-- flyout item levels, and the bags that show (EUI Bags or Blizzard's) are
-- managed. Those settings are only read.
local function Seed(s)
    local bags = EllesmereUI._bagsDB
    local p = bags and bags.profile or {}
    local blizzBags = BlizzardBagsInUse()
    local slots = s.slots
    for i = 1, NUM_SLOTS do slots[SLOT_ORDER[i]] = {} end
    local ilvl = p.showItemlevelInBags ~= false
    local tl, br, bl = slots.topleft, slots.bottomright, slots.bottomleft
    if ilvl then tl[#tl + 1] = "itemLevel" end
    tl[#tl + 1] = "keystoneLevel"
    tl[#tl + 1] = "craftingQuality"
    br[#br + 1] = "upgradeArrow"
    -- EUI Bags draws the rank only beside item levels
    if ilvl and p.bagShowTrackRank then br[#br + 1] = "upgradeRank" end
    br[#br + 1] = "stackCount"
    br[#br + 1] = "keystoneDungeon"
    bl[#bl + 1] = "questMarker"
    if p.bagDisplayBindType then bl[#bl + 1] = "bindType" end
    -- Blizzard's bags have a junk coin (shown while a vendor is open): seeded for
    -- them, the coin shows on every Poor item with a sell price. In EUI Bags it is
    -- a Junk Marker visual, off with the marker's switch
    if blizzBags or (p.bagShowJunkIcon ~= false and p.bagShowJunkCoin == true) then bl[#bl + 1] = "junkCoin" end
    if p.bagShowSetGearName == true then slots.bottom[1] = "setName" end

    local frames = s.frames
    for i = 1, #FRAME_ORDER do frames[FRAME_ORDER[i]] = false end
    -- EUI Bags covers the bank too
    frames.eui_bags = not blizzBags
    frames.blizz_bags, frames.blizz_bank = blizzBags, blizzBags
    frames.merchant = EllesmereUIDB.merchantShowItemLevel == true
    frames.flyout = EllesmereUIDB.flyoutItemLevels and true or false

    local styles = s.styles
    local function Take(key, field, v)
        if ValidStyle(key, field, v) then styles[key][field] = Copy(v) end
    end
    Take("itemLevel", "size", p.itemlevelFontSize)
    Take("itemLevel", "colorMode", p.itemlevelUseCustomColor and "custom" or "default")
    Take("itemLevel", "customColor", p.itemlevelCustomColor)
    local count = p.bagCountFontSize
    Take("stackCount", "size", count)
    Take("upgradeRank", "size", count)
    Take("keystoneLevel", "size", count)
    if type(count) == "number" then Take("keystoneDungeon", "size", math.max(count - 2, 7)) end
    Take("bindType", "size", p.bagBindTypeFontSize)
    Take("setName", "size", p.bagSetNameFontSize)
    s.seeded = true
    layoutDirty = true
    styleVer = styleVer + 1
end

local function GetSettings()
    local p = Profile()
    local s = p.itemIcons
    if type(s) ~= "table" then
        s = detached
        if not s then s = {}; detached = s end
    end
    if s ~= cur then
        ValidateSettings(s)
        cur = s
        layoutDirty = true
        styleVer = styleVer + 1
    end
    return s
end

-- The settings, stored in the profile from their first write on. Seeded before
-- that write, so seeding never replaces a choice.
local function Writable()
    local s = GetSettings()
    if s == detached then
        detached = nil
        Profile().itemIcons = s
    end
    if not s.seeded then Seed(s) end
    return s
end

-------------------------------------------------------------------------------
--  Layout: per slot, the registered elements that can draw there
-------------------------------------------------------------------------------
local registry = {}      -- element key -> def
local layout = {}        -- slot index -> defs in priority order
local placed = {}        -- element key -> true while a slot lists it
for i = 1, NUM_SLOTS do layout[i] = {} end

-- The client has what the element shows
local function Available(key)
    local e = ELEMENTS[key]
    return e ~= nil and not (IS_FOREVER and e.retailOnly)
end

local function RebuildLayout()
    layoutDirty = false
    wipe(placed)
    for i = 1, NUM_SLOTS do
        local defs, list = layout[i], cur.slots[SLOT_ORDER[i]]
        wipe(defs)
        for j = 1, #list do
            local key = list[j]
            placed[key] = true
            if Available(key) then defs[#defs + 1] = registry[key] end
        end
    end
end

-------------------------------------------------------------------------------
--  Frames, refresh and native regions
-------------------------------------------------------------------------------
local adapters = {}      -- frame key -> adapter
local managed = {}       -- frame key -> true while managed
local subscribers = {}
local queued = {}        -- frame keys whose Refresh is due
local waiting = {}       -- frame keys holding items whose data is loading
local waitingIDs = {}    -- item IDs those items wait for
local failedIDs = {}     -- item IDs the server had no data for: never waited for again
local numFailed = 0
local flushKeys = {}
local flushScheduled = false
-- Inert until a painted item waits for its data (GET_ITEM_INFO_RECEIVED)
local ev = CreateFrame("Frame")

local states = setmetatable({}, { __mode = "k" })       -- button -> painter state
local deferred = setmetatable({}, { __mode = "k" })     -- button -> frame key; its overlay waits for combat to end
local nativeAlpha = setmetatable({}, { __mode = "k" })  -- region -> alpha before HideNative
local nativeOwner = setmetatable({}, { __mode = "k" })  -- region -> frame key

local function ErrorHandler(err) return geterrorhandler()(err) end

local function Call(fn, arg)
    if fn then xpcall(fn, ErrorHandler, arg) end
end

local function Flush()
    flushScheduled = false
    local n = 0
    for k in pairs(queued) do
        n = n + 1
        flushKeys[n] = k
    end
    wipe(queued)
    for i = 1, n do
        local k = flushKeys[i]
        flushKeys[i] = nil
        local a = adapters[k]
        if managed[k] and a then Call(a.Refresh, k) end
    end
end

local function ScheduleFlush()
    if flushScheduled or not next(queued) then return end
    flushScheduled = true
    C_Timer.After(REFRESH_DELAY, Flush)
end

ev:SetScript("OnEvent", function(self, _, itemID, success)
    if not waitingIDs[itemID] then return end
    if not success then
        -- No data will come for it: stop waiting for it, with nothing to repaint
        waitingIDs[itemID] = nil
        if numFailed >= FAILED_CAP then
            wipe(failedIDs)
            numFailed = 0
        end
        failedIDs[itemID] = true
        numFailed = numFailed + 1
        if next(waitingIDs) then return end
        self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
        wipe(waiting)
        return
    end
    self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
    for k in pairs(waiting) do queued[k] = true end
    wipe(waiting)
    wipe(waitingIDs)
    ScheduleFlush()
end)

-- frameKey repaints once the data of item id arrives; an item whose data
-- failed to load is not waited for again
local function Wait(id, frameKey)
    if failedIDs[id] then return end
    if not next(waiting) then ev:RegisterEvent("GET_ITEM_INFO_RECEIVED") end
    waiting[frameKey] = true
    waitingIDs[id] = true
end

-- Combat ended: the frames whose buttons still lack an overlay repaint
local function FlushDeferred()
    for button, key in pairs(deferred) do
        if managed[key] then queued[key] = true end
        deferred[button] = nil
    end
    ScheduleFlush()
end

local function HideSlot(st, si)
    local fs, tx = st.fs[si], st.tex[si]
    if fs then fs:Hide() end
    if tx then tx:Hide() end
end

local function HideAll(st)
    for si = 1, NUM_SLOTS do HideSlot(st, si) end
end

local function ReleaseFrame(frameKey)
    for _, st in pairs(states) do
        if st.frameKey == frameKey then
            HideAll(st)
            st.frameKey = nil
        end
    end
    for button, key in pairs(deferred) do
        if key == frameKey then deferred[button] = nil end
    end
    for region, key in pairs(nativeOwner) do
        if key == frameKey then
            nativeOwner[region] = nil
            region:SetAlpha(nativeAlpha[region])
            nativeAlpha[region] = nil
        end
    end
    queued[frameKey] = nil
    waiting[frameKey] = nil
    if not next(waiting) then
        ev:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
        wipe(waitingIDs)
    end
end

-- A profile change repaints at once; layout and style writes (slider drags)
-- merge into one coalesced repaint
local REPAINT = { profile = "now", layout = "queued", styles = "queued" }

local function Apply(reason)
    local s = GetSettings()
    -- A profile stored unseeded (an import) seeds on enable
    if s.enabled and not s.seeded then Seed(s) end
    local repaint = REPAINT[reason]
    for i = 1, #FRAME_ORDER do
        local key = FRAME_ORDER[i]
        local want = s.enabled and s.frames[key] and FrameAvailable(key) and FrameInUse(key) or false
        local a = adapters[key]
        if want ~= (managed[key] or false) then
            managed[key] = want or nil
            if want then
                if a then Call(a.Enable, key) end
            else
                if a then Call(a.Disable, key) end
                ReleaseFrame(key)
            end
        elseif want and a then
            if repaint == "now" then
                Call(a.Refresh, key)
            elseif repaint then
                queued[key] = true
            end
        end
    end
    ScheduleFlush()
    for i = 1, #subscribers do Call(subscribers[i], reason) end
end

-- Login (EllesmereUIQoL.lua) and profile swaps (RefreshAllAddons)
ns.ItemIcons_Apply = function() Apply("profile") end
EllesmereUI._applyItemIcons = ns.ItemIcons_Apply

-------------------------------------------------------------------------------
--  Painter
-------------------------------------------------------------------------------
local item, out = {}, {}
local scale = 1          -- the ctx.scale of the paint in progress
local bagLoc = ItemLocation:CreateEmpty()
local aspects = {}       -- atlas -> width / height

local function Aspect(atlas)
    local a = aspects[atlas]
    if not a then
        local info = C_Texture.GetAtlasInfo(atlas)
        a = (info and info.height > 0) and info.width / info.height or 1
        aspects[atlas] = a
    end
    return a
end

local function DrawText(st, si, def, style)
    local fs = st.fs[si]
    if not fs then
        fs = st.overlay:CreateFontString(nil, "OVERLAY", nil, 7)
        fs:SetWordWrap(false)
        st.fs[si] = fs
    end
    local fontKey = FRAME_FONT[st.frameKey] or FONT_KEY
    if fs._key ~= def.key or fs._ver ~= styleVer or fs._anchor ~= st.anchor or fs._font ~= fontKey
        or fs._scale ~= scale then
        local g = SLOT_GEOM[si]
        fs:ClearAllPoints()
        fs:SetPoint(g[1], st.overlay, g[1], g[2] * (def.insetX or 1) + style.offsetX * scale,
            g[3] * (def.insetY or 1) + style.offsetY * scale)
        fs:SetJustifyH(g[4])
        EllesmereUI.ApplyIconTextFont(fs, EllesmereUI.GetFontPath(fontKey), style.size * scale, fontKey)
        fs:SetWidth(def.fitWidth and math.max(st.anchor:GetWidth() - 4, 0) or 0)
        fs._key, fs._ver, fs._anchor, fs._font, fs._scale = def.key, styleVer, st.anchor, fontKey, scale
    end
    fs:SetText(out.text)
    fs:SetTextColor(out.r, out.g, out.b, 1)
    fs:Show()
    local tx = st.tex[si]
    if tx then tx:Hide() end
end

local function DrawIcon(st, si, def, style)
    local tx = st.tex[si]
    if not tx then
        tx = st.overlay:CreateTexture(nil, "OVERLAY", nil, 6)
        st.tex[si] = tx
    end
    local atlas = out.atlas
    local asset = atlas or out.texture
    if tx._asset ~= asset or tx._key ~= def.key or tx._ver ~= styleVer or tx._scale ~= scale then
        local h = style.size * scale
        if atlas then
            tx:SetAtlas(atlas)
            tx:SetSize(h * Aspect(atlas), h)
        else
            tx:SetTexture(asset)
            local c = def.texCoord
            if c then tx:SetTexCoord(c[1], c[2], c[3], c[4]) else tx:SetTexCoord(0, 1, 0, 1) end
            tx:SetSize(h, h)
        end
        local g = SLOT_GEOM[si]
        tx:ClearAllPoints()
        tx:SetPoint(g[1], st.overlay, g[1], g[2] * (def.insetX or 1) + style.offsetX * scale,
            g[3] * (def.insetY or 1) + style.offsetY * scale)
        local maskFile = def.mask
        if tx._mask ~= maskFile then
            local mask = st.mask[si]
            if tx._mask then tx:RemoveMaskTexture(mask) end
            if maskFile then
                if not mask then
                    mask = st.overlay:CreateMaskTexture()
                    mask:SetAllPoints(tx)
                    st.mask[si] = mask
                end
                mask:SetTexture(maskFile, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                tx:AddMaskTexture(mask)
            end
            tx._mask = maskFile
        end
        tx._asset, tx._key, tx._ver, tx._scale = asset, def.key, styleVer, scale
    end
    tx:SetDesaturated(out.desaturate)
    tx:SetVertexColor(out.r, out.g, out.b)
    tx:Show()
    local fs = st.fs[si]
    if fs then fs:Hide() end
end

function II.Paint(button, ctx, frameKey)
    if not managed[frameKey] then return end
    local st = states[button]
    if not st then
        -- No new frame on a protected button in combat: built when combat ends
        if InCombatLockdown() and button:IsProtected() then
            deferred[button] = frameKey
            ns.CombatQueue.Defer(DEFER_KEY, FlushDeferred)
            return
        end
        st = { overlay = CreateFrame("Frame", nil, button), fs = {}, tex = {}, mask = {} }
        states[button] = st
    end
    st.frameKey = frameKey
    local overlay = st.overlay
    local anchor = ctx.anchor or button
    if st.anchor ~= anchor then
        st.anchor = anchor
        overlay:ClearAllPoints()
        overlay:SetAllPoints(anchor)
    end
    -- Above the cooldown swipe and EUI Bags' text overlay, under its warband dim
    local level = button:GetFrameLevel() + 4
    if overlay:GetFrameLevel() ~= level then overlay:SetFrameLevel(level) end
    local alpha = ctx.alpha or 1
    if st.alpha ~= alpha then
        st.alpha = alpha
        overlay:SetAlpha(alpha)
    end

    local link = ctx.link
    if type(link) ~= "string" or issecretvalue(link) or link == "" then
        HideAll(st)
        return
    end
    if layoutDirty then RebuildLayout() end
    wipe(item)
    item.link, item.itemID, item.quality, item.count = link, ctx.itemID, ctx.quality, ctx.count
    item.bag, item.slot, item.facts, item.frameKey = ctx.bag, ctx.slot, ctx.facts, frameKey
    local styles = cur.styles
    item.styles = styles
    if ctx.bag and ctx.slot then
        bagLoc:SetBagAndSlot(ctx.bag, ctx.slot)
        item.location = bagLoc
    else
        item.location = ctx.location
    end
    local s = ctx.scale
    scale = (type(s) == "number" and s > 0) and s or 1

    for si = 1, NUM_SLOTS do
        local defs, shown = layout[si], false
        for i = 1, #defs do
            local def = defs[i]
            local style = styles[def.key]
            -- A text the scale shrinks out of reading size leaves the slot to the next element
            if def.kind == "icon" or scale >= 1 or style.size * scale >= MIN_TEXT_SIZE then
                out.text, out.atlas, out.texture = nil, nil, nil
                out.r, out.g, out.b, out.desaturate = 1, 1, 1, false
                -- An element's error reaches the error handler and never stops
                -- the caller's render (as EUI_Bags.RunItemOverlays)
                if securecallfunction(def.Apply, item, style, out) then
                    if def.kind == "text" then DrawText(st, si, def, style) else DrawIcon(st, si, def, style) end
                    shown = true
                    break
                end
            end
        end
        if not shown then HideSlot(st, si) end
    end

    if item.pending then
        local id = item.itemID or C_Item.GetItemInfoInstant(link)
        if id then Wait(id, frameKey) end
    end
end

function II.Clear(button)
    deferred[button] = nil
    local st = states[button]
    if st then
        HideAll(st)
        st.frameKey = nil
    end
end

function II.RequestRefresh(frameKey)
    if frameKey then
        if managed[frameKey] then queued[frameKey] = true end
    else
        for k in pairs(managed) do queued[k] = true end
    end
    ScheduleFlush()
end

function II.WaitForItem(itemID, frameKey)
    -- Asking for the item's info requests its data while it is not cached
    if type(itemID) ~= "number" or not managed[frameKey] or C_Item.GetItemInfo(itemID) then return end
    Wait(itemID, frameKey)
end

local function HideNative(region, frameKey)
    if not region then return end
    if nativeAlpha[region] == nil then
        local a = region:GetAlpha()
        nativeAlpha[region] = issecretvalue(a) and 1 or a
    end
    nativeOwner[region] = frameKey
    region:SetAlpha(0)
end

local function RestoreNative(region)
    local a = region and nativeAlpha[region]
    if a == nil then return end
    nativeAlpha[region], nativeOwner[region] = nil, nil
    region:SetAlpha(a)
end

-- The one list of Blizzard marks the elements replace (stackCount, craftingQuality,
-- junkCoin, questMarker)
function II.HideNatives(button, frameKey, countRegion, questMark, starter)
    if not managed[frameKey] then return end
    HideNative(countRegion, frameKey)
    HideNative(button.ProfessionQualityOverlay, frameKey)
    HideNative(button.JunkIcon, frameKey)
    if starter then HideNative(questMark, frameKey) else RestoreNative(questMark) end
end

function II.RestoreNatives(button, countRegion, questMark)
    RestoreNative(countRegion)
    RestoreNative(button.ProfessionQualityOverlay)
    RestoreNative(button.JunkIcon)
    RestoreNative(questMark)
end

function II.TooltipItemLink(data)
    local guid, link = data.guid, data.hyperlink
    if issecretvalue(guid) or issecretvalue(link) then return nil end
    if guid then return C_Item.GetItemLinkByGUID(guid) end
    return link
end

-------------------------------------------------------------------------------
--  Registries, state and settings writes
-------------------------------------------------------------------------------
function II.RegisterElement(key, def)
    if not ELEMENTS[key] or registry[key] or type(def) ~= "table" or type(def.Apply) ~= "function"
        or (def.kind ~= "text" and def.kind ~= "icon") then
        return false
    end
    def.key = key
    registry[key] = def
    layoutDirty = true
    return true
end

function II.RegisterFrame(frameKey, adapter)
    if not FRAME_SET[frameKey] or adapters[frameKey] or type(adapter) ~= "table"
        or type(adapter.Enable) ~= "function" or type(adapter.Refresh) ~= "function" then
        return false
    end
    adapters[frameKey] = adapter
    if managed[frameKey] then Call(adapter.Enable, frameKey) end
    return true
end

function II.RegisterLazyFrame(frameKey, addonName, Install, Repaint)
    local state  -- nil, then "waiting" for addonName, then "ready"
    local function Refresh()
        if state == "ready" then Repaint() end
    end
    return II.RegisterFrame(frameKey, {
        Enable = function()
            if state then
                Refresh()
                return
            end
            state = "waiting"
            EventUtil.ContinueOnAddOnLoaded(addonName, function()
                Install()
                state = "ready"
                if managed[frameKey] then Repaint() end
            end)
        end,
        Refresh = Refresh,
    })
end

function II.IsEnabled()
    return cur ~= nil and cur.enabled
end

function II.IsFrameEnabled(frameKey)
    return managed[frameKey] == true
end

II.IsFrameAvailable = FrameAvailable
II.BlizzardBagsInUse = BlizzardBagsInUse
II.IsElementAvailable = Available

II.GetSettings = GetSettings

function II.IsElementPlaced(key)
    GetSettings()
    if layoutDirty then RebuildLayout() end
    return placed[key] == true
end

function II.Subscribe(fn)
    if type(fn) == "function" then subscribers[#subscribers + 1] = fn end
end

function II.SetEnabled(on)
    Writable().enabled = on and true or false
    Apply("enabled")
end

function II.SetFrameEnabled(frameKey, on)
    if not FRAME_SET[frameKey] then return end
    Writable().frames[frameKey] = on and true or false
    Apply("frames")
end

function II.SetTooltipPip(on)
    Writable().tooltipTrackPip = on and true or false
    Apply("tooltip")
end

function II.SetSlotList(slotKey, keys)
    if not SLOT_INDEX[slotKey] or type(keys) ~= "table" then return end
    local s = Writable()
    local list, seen = {}, {}
    for i = 1, #keys do
        local k = keys[i]
        if ELEMENTS[k] and not seen[k] then
            seen[k] = true
            list[#list + 1] = k
        end
    end
    s.slots[slotKey] = list
    layoutDirty = true
    Apply("layout")
end

function II.SetStyle(key, field, value)
    if not ValidStyle(key, field, value) then return false end
    Writable().styles[key][field] = Copy(value)
    styleVer = styleVer + 1
    Apply("styles")
    return true
end

function II.Reset()
    Profile().itemIcons = nil
    Apply("profile")
end
