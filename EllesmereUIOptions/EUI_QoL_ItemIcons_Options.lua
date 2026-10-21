if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_QoL_ItemIcons_Options.lua
--  Builds the "Item Icons" page inside the Quality of Life module: the master
--  switch, the windows it manages (Show On), the eight slot lists and each
--  element's style. Reads and writes only through EllesmereUI.ItemIcons
--  (EllesmereUIQoL/EllesmereUIQoL_ItemIcons.lua).
-------------------------------------------------------------------------------
if not EllesmereUI._ModuleNS["EllesmereUIQoL"] then return end  -- module disabled: no options page

local II = EllesmereUI.ItemIcons

local SLOT_LABELS = {
    topleft = "Top Left", top = "Top", topright = "Top Right", right = "Right",
    bottomright = "Bottom Right", bottom = "Bottom", bottomleft = "Bottom Left", left = "Left",
}
-- Two slots per row: the top corners, the top and bottom edges, the sides,
-- then the bottom corners
local SLOT_ROWS = {
    { "topleft", "topright" }, { "top", "bottom" }, { "left", "right" }, { "bottomleft", "bottomright" },
}
local ELEMENT_LABELS = {
    itemLevel = "Item Level", upgradeRank = "Upgrade Rank", upgradeTrack = "Upgrade Track",
    transmog = "Transmog", stackCount = "Stack Count", bindType = "BoE / Warbound", setName = "Set Name",
    craftingQuality = "Crafting Quality", junkCoin = "Junk Coin", questMarker = "Quest Marker",
    keystoneLevel = "Keystone Level", keystoneDungeon = "Keystone Dungeon", pawnArrow = "Pawn Upgrade Arrow",
}
-- Whole strings, so each translates on its own
local SIZE_LABELS = {
    itemLevel = "Item Level Size", upgradeRank = "Upgrade Rank Size", upgradeTrack = "Upgrade Track Size",
    transmog = "Transmog Size", stackCount = "Stack Count Size", bindType = "BoE / Warbound Size",
    setName = "Set Name Size", craftingQuality = "Crafting Quality Size", junkCoin = "Junk Coin Size",
    questMarker = "Quest Marker Size", keystoneLevel = "Keystone Level Size",
    keystoneDungeon = "Keystone Dungeon Size", pawnArrow = "Pawn Upgrade Arrow Size",
}
local FRAME_LABELS = {
    eui_bags = "EllesmereUI Bags", blizz_bags = "Blizzard Bags", blizz_bank = "Blizzard Bank",
    merchant = "Vendor", guildbank = "Guild Bank", loot = "Loot Window", grouploot = "Group Loot Rolls",
    mail = "Mail", trade = "Trade", questrewards = "Quest Rewards", auctionhouse = "Auction House",
    blackmarket = "Black Market", encounterjournal = "Adventure Guide Loot", greatvault = "Great Vault",
    charsheet = "Character Sheet", flyout = "Gear Flyout", inspect = "Inspect",
    professions = "Professions", customerorders = "Crafting Orders",
}

-- Every control below the master switch requires it ("This option requires
-- Item Icons to be enabled")
local REQUIRES = "Item Icons"
local SLOT_TIP = "Check the elements to show at this spot on item buttons and drag them into priority order. Each item shows the first checked element that applies to it."
local SLOT_DD_W = 270
-- The slot rows' labelled half: the real control replaces this dropdown
local PLACEHOLDER, PLACEHOLDER_ORDER = { __placeholder = "..." }, { "__placeholder" }

local function Off() return not II.IsEnabled() end
local function Always() return true end
local function Placeholder() return "__placeholder" end
local function Nothing() end

local function Style(key) return II.GetSettings().styles[key] end

local function SameList(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

-- The elements slotKey holds, in the menu's row order (order), with key added
-- (on) or removed. Hidden elements it holds (retail-only ones on WoW Forever)
-- stay, at its end.
local function SlotList(slotKey, order, key, on)
    local list = {}
    for i = 1, #order do
        local k = order[i]
        if k == key then
            if on then list[#list + 1] = k end
        elseif II.GetElementSlot(k) == slotKey then
            list[#list + 1] = k
        end
    end
    local saved = II.GetSettings().slots[slotKey]
    for i = 1, #saved do
        if not II.IsElementAvailable(saved[i]) then list[#list + 1] = saved[i] end
    end
    return list
end

local function WriteSlot(slotKey, list)
    if not SameList(list, II.GetSettings().slots[slotKey]) then II.SetSlotList(slotKey, list) end
end

-- One slot's reorder checkbox list in place of the row half's placeholder. An
-- element placed in another slot is locked here, its slot named on hover.
local function BuildSlotDropdown(rgn, slotKey)
    if rgn._control then rgn._control:Hide() end
    -- The other slot holding key, or nil
    local function UsedIn(key)
        local where = II.GetElementSlot(key)
        if where ~= slotKey then return where end
    end
    local items = {}
    for _, key in ipairs(II.ELEMENT_ORDER) do
        if II.IsElementAvailable(key) then
            items[#items + 1] = { key = key, label = ELEMENT_LABELS[key],
                lockedFn = function() return UsedIn(key) ~= nil end,
                lockedTooltip = function()
                    return EllesmereUI.Lf("In %s", EllesmereUI.L(SLOT_LABELS[UsedIn(key)]))
                end }
        end
    end
    local cbDD, cbRefresh = EllesmereUI.BuildReorderCBDropdown(rgn, SLOT_DD_W, rgn:GetFrameLevel() + 2, items,
        function(key) return II.GetElementSlot(key) == slotKey end,
        function(key, on, order) WriteSlot(slotKey, SlotList(slotKey, order, key, on)) end,
        {
            hint2 = "Each item shows the first checked element that applies",
            -- This slot's elements first, in priority order, then the free ones,
            -- then the ones another slot holds
            openOrder = function()
                local keys, used = {}, {}
                local saved = II.GetSettings().slots[slotKey]
                for i = 1, #saved do keys[i] = saved[i] end
                for _, it in ipairs(items) do
                    local where = II.GetElementSlot(it.key)
                    if where == nil then
                        keys[#keys + 1] = it.key
                    elseif where ~= slotKey then
                        used[#used + 1] = it.key
                    end
                end
                for i = 1, #used do keys[#keys + 1] = used[i] end
                return keys
            end,
            setOrder = function(order) WriteSlot(slotKey, SlotList(slotKey, order)) end,
            summaryLabel = function()
                local names = {}
                for _, key in ipairs(II.GetSettings().slots[slotKey]) do
                    if II.IsElementAvailable(key) then names[#names + 1] = EllesmereUI.L(ELEMENT_LABELS[key]) end
                end
                return #names > 0 and table.concat(names, ", ") or EllesmereUI.L("None")
            end,
        })
    EllesmereUI.PanelPP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
    rgn._control = cbDD
    rgn._lastInline = nil
    EllesmereUI.RegisterWidgetRefresh(cbRefresh)
    -- The list has no disabled state of its own: grey it and block clicks; the
    -- placeholder's disabled overlay explains the requirement
    local function SyncDisabled()
        local off = Off()
        cbDD:SetAlpha(off and 0.3 or 1)
        cbDD:EnableMouse(not off)
    end
    SyncDisabled()
    EllesmereUI.RegisterWidgetRefresh(SyncDisabled)
end

-- Show On: one checkbox per managed window. Only the bags that show are
-- open to it: Blizzard's bags and bank, or EUI Bags (II.BlizzardBagsInUse).
local function BuildShowOn(rgn)
    if rgn._control then rgn._control:Hide() end
    local blizzBags = II.BlizzardBagsInUse()
    -- With EUI Bags running, Blizzard's bags show only while it stands down for
    -- WoW Forever's Gamepad interface style
    local euiBagsTip = "Requires the EllesmereUI Bags module"
    if EllesmereUI._BagsStandDown then euiBagsTip = "This option does not work with the Gamepad interface style." end
    local items = {}
    for _, key in ipairs(II.FRAME_ORDER) do
        -- A window the client lacks is not listed (no Great Vault on WoW Forever)
        if II.IsFrameAvailable(key) then
            local item = { key = key, label = FRAME_LABELS[key] }
            if key == "eui_bags" and blizzBags then
                item.locked, item.lockedTooltip = true, euiBagsTip
            elseif (key == "blizz_bags" or key == "blizz_bank") and not blizzBags then
                item.locked, item.lockedTooltip = true, "EllesmereUI Bags shows your bags and bank in place of Blizzard's"
            end
            if item.locked then item.excludeFromSummaryFn = Always end
            items[#items + 1] = item
        end
    end
    local dd, ddRefresh = EllesmereUI.BuildVisOptsCBDropdown(rgn, 210, rgn:GetFrameLevel() + 2, items,
        function(key) return II.GetSettings().frames[key] end,
        function(key, on) II.SetFrameEnabled(key, on) end,
        nil, 10, nil, nil, nil, { disabled = Off, disabledTooltip = REQUIRES })
    EllesmereUI.PanelPP.Point(dd, "RIGHT", rgn, "RIGHT", -20, 0)
    rgn._control = dd
    rgn._lastInline = nil
    EllesmereUI.RegisterWidgetRefresh(ddRefresh)
end

-- A BuildInlineSwatches spec for color field `field` of element `key`. off()
-- locks it besides the master switch; why explains that lock.
local function Swatch(key, field, tooltip, off, why)
    return {
        tooltip = tooltip,
        getValue = function()
            local c = Style(key)[field]
            return c.r, c.g, c.b, 1
        end,
        setValue = function(r, g, b) II.SetStyle(key, field, { r = r, g = g, b = b }) end,
        disabled = function() return Off() or (off ~= nil and off()) end,
        disabledTooltip = function() return Off() and REQUIRES or why end,
    }
end

local function SizeCfg(key)
    local spec = II.ELEMENTS[key]
    return { type="slider", text=SIZE_LABELS[key], min=spec.sizeMin, max=spec.sizeMax, step=1,
      disabled=Off, disabledTooltip=REQUIRES,
      getValue=function() return Style(key).size end,
      setValue=function(v) II.SetStyle(key, "size", v) end }
end

-- The style controls beside an element's size slider
local function BuildStyleExtras(rgn, key)
    if key == "transmog" then
        local function NoLearned() return not Style("transmog").showLearned end
        local function NoOtherChar() return not Style("transmog").showOtherChar end
        EllesmereUI.BuildInlineSwatches(rgn, {
            Swatch("transmog", "learnedColor", "Learned", NoLearned, "Show Learned Appearances"),
            Swatch("transmog", "thisCharColor", "Learnable on This Character"),
            Swatch("transmog", "otherCharColor", "Learnable on Another Character", NoOtherChar,
                "Show Learnable on Other Characters"),
        })
        EllesmereUI.BuildInlineCog(rgn, {
            disabled = Off, disabledTooltip = REQUIRES,
            title = "Transmog Options",
            rows = {
                { type="toggle", label="Show Learned Appearances",
                  tooltip="Marks items whose appearance you have already collected.",
                  get=function() return Style("transmog").showLearned end,
                  set=function(v)
                      II.SetStyle("transmog", "showLearned", v)
                      EllesmereUI:RefreshPage()  -- the Learned swatch's disabled state
                  end },
                { type="toggle", label="Show Learnable on Other Characters",
                  tooltip="Marks items whose appearance only another of your characters can learn.",
                  get=function() return Style("transmog").showOtherChar end,
                  set=function(v)
                      II.SetStyle("transmog", "showOtherChar", v)
                      EllesmereUI:RefreshPage()  -- the swatch's disabled state
                  end },
            },
        })
    elseif key == "upgradeTrack" then
        local rows = {}
        for _, track in ipairs(II.TRACK_ORDER) do
            rows[#rows + 1] = { type="colorpicker", label=track,
              get=function()
                  local c = Style("upgradeTrack")[track]
                  return c.r, c.g, c.b, 1
              end,
              set=function(r, g, b) II.SetStyle("upgradeTrack", track, { r = r, g = g, b = b }) end }
        end
        EllesmereUI.BuildInlineCog(rgn, {
            disabled = Off, disabledTooltip = REQUIRES,
            title = "Upgrade Track Colors",
            rows = rows,
        })
    end
end

_G._EUI_BuildItemIconsPage = function(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local prebuilding = EllesmereUI._prebuilding
    local y = yOffset
    local _, h

    parent._showRowDivider = true

    ---------------------------------------------------------------------------
    --  ITEM ICONS
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "ITEM ICONS", y);  y = y - h

    local mainRow
    mainRow, h = W:DualRow(parent, y,
        { type="toggle", text="Enable Item Icons",
          tooltip="Shows markers such as item level, upgrade track and transmog status on item buttons in the windows checked in Show On, laid out by the slots below. While a window is checked, this page replaces its own item level and overlay options.",
          getValue=function() return II.IsEnabled() end,
          setValue=function(v)
              II.SetEnabled(v)
              EllesmereUI:RefreshPage()  -- every other control's disabled state
          end },
        { type="dropdown", text="Show On",
          tooltip="The windows whose item buttons show the markers.",
          disabled=Off, disabledTooltip=REQUIRES,
          values=PLACEHOLDER, order=PLACEHOLDER_ORDER,
          getValue=Placeholder, setValue=Nothing });  y = y - h
    if not prebuilding then BuildShowOn(mainRow._rightRegion) end

    -- No upgrade tracks on WoW Forever
    if II.IsElementAvailable("upgradeTrack") then
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Upgrade Pip in Tooltips",
              tooltip="Starts the Upgrade Level line of item tooltips with the item's upgrade track pip.",
              disabled=Off, disabledTooltip=REQUIRES,
              getValue=function() return II.GetSettings().tooltipTrackPip end,
              setValue=function(v) II.SetTooltipPip(v) end },
            EllesmereUI.BlankRowCfg());  y = y - h
    end

    ---------------------------------------------------------------------------
    --  SLOTS
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "SLOTS", y);  y = y - h

    for _, pair in ipairs(SLOT_ROWS) do
        local cfgs = {}
        for i = 1, 2 do
            cfgs[i] = { type="dropdown", text=SLOT_LABELS[pair[i]], tooltip=SLOT_TIP,
              dropdownWidth=SLOT_DD_W, disabled=Off, disabledTooltip=REQUIRES,
              values=PLACEHOLDER, order=PLACEHOLDER_ORDER,
              getValue=Placeholder, setValue=Nothing }
        end
        local row
        row, h = W:DualRow(parent, y, cfgs[1], cfgs[2]);  y = y - h
        if not prebuilding then
            BuildSlotDropdown(row._leftRegion, pair[1])
            BuildSlotDropdown(row._rightRegion, pair[2])
        end
    end

    ---------------------------------------------------------------------------
    --  ELEMENTS
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "ELEMENTS", y);  y = y - h

    local ilvlRow
    ilvlRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Item Level Color",
          tooltip="Colors item levels and upgrade ranks by their upgrade track and quality, or in one color of your choice.",
          values={ default = "Default Colors", custom = "Custom Colored" }, order={ "default", "custom" },
          disabled=Off, disabledTooltip=REQUIRES,
          getValue=function() return Style("itemLevel").colorMode end,
          setValue=function(v)
              II.SetStyle("itemLevel", "colorMode", v)
              EllesmereUI:RefreshPage()  -- the swatch's disabled state
          end },
        SizeCfg("itemLevel"));  y = y - h
    if not prebuilding then
        EllesmereUI.BuildInlineSwatches(ilvlRow._leftRegion, {
            Swatch("itemLevel", "customColor", nil,
                function() return Style("itemLevel").colorMode ~= "custom" end,
                "This option requires Item Level Color to be set to Custom Colored"),
        })
    end

    -- Every other element's size, two per row in the elements' order
    local keys = {}
    for _, key in ipairs(II.ELEMENT_ORDER) do
        if key ~= "itemLevel" and II.IsElementAvailable(key) then keys[#keys + 1] = key end
    end
    for i = 1, #keys, 2 do
        local left, right = keys[i], keys[i + 1]
        local row
        row, h = W:DualRow(parent, y, SizeCfg(left), right and SizeCfg(right) or EllesmereUI.BlankRowCfg());  y = y - h
        if not prebuilding then
            BuildStyleExtras(row._leftRegion, left)
            if right then BuildStyleExtras(row._rightRegion, right) end
        end
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h
    return math.abs(y)
end
