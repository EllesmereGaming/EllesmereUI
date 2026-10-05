if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  ActionBars_Options\XPBarPage_Options.lua
--  Action Bars options: the XP Bar page (BuildXPBarPage), in CORE, CORE TEXT
--  POSITIONS and DISPLAY sections. The data bar controls it shares with the
--  reputation and House Favor bars come from the data bar kit
--  (ns.ABO_DataBarKit, defined in MenuBagsRepPage_Options.lua and read at
--  build time); this file holds the XP bar's own: XP Bar Style, Show Dividers
--  and its settings row, Fill Style, Rested Color, Background, Quest XP
--  Overlay and its cog, the bar's texts (a list of the ones that show
--  something: what each shows, the position it sits at, its Size, offsets
--  and Show Rested cog; Add Text Slot), Text Background and the Visibility
--  cog (with Click Through). Definitions only; the shared helpers come from
--  ns._ABO_OptEnv (filled by EUI_ActionBars_Options.lua).
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUIActionBars"]
if not ns then return end  -- module disabled: no options page

local XP = "XPBar"

-- The profession skill-bar flipbooks Fill Style can offer (atlas, label).
local FLIP_CANDS = {
    { "Skillbar_Fill_Flipbook_Alchemy",        "Alchemy" },
    { "Skillbar_Fill_Flipbook_Blacksmithing",  "Blacksmithing" },
    { "Skillbar_Fill_Flipbook_Enchanting",     "Enchanting" },
    { "Skillbar_Fill_Flipbook_Engineering",    "Engineering" },
    { "Skillbar_Fill_Flipbook_Herbalism",      "Herbalism" },
    { "Skillbar_Fill_Flipbook_Inscription",    "Inscription" },
    { "Skillbar_Fill_Flipbook_Jewelcrafting",  "Jewelcrafting" },
    { "Skillbar_Fill_Flipbook_Leatherworking", "Leatherworking" },
    { "Skillbar_Fill_Flipbook_Mining",         "Mining" },
    { "Skillbar_Fill_Flipbook_Skinning",       "Skinning" },
    { "Skillbar_Fill_Flipbook_Tailoring",      "Tailoring" },
    { "Skillbar_Fill_Flipbook_Cooking",        "Cooking" },
    { "Skillbar_Fill_Flipbook_Fishing",        "Fishing" },
}

-- What a text can show (the bar reads a text's value through ns.XPTextItems):
-- the top items combine, " - " between them in the order dragged; a bottom
-- item shows on its own.
local TOP_ITEMS = {
    { key = "pct",       label = "Current %" },
    { key = "cur",       label = "Current" },
    { key = "curMax",    label = "Current / Max" },
    { key = "curMaxRem", label = "Current / Max (Remaining)" },
    { key = "restVal",   label = "Rested" },
    { key = "restPct",   label = "Rested %" },
    { key = "questVal",  label = "Completed Quests" },
    { key = "questPct",  label = "Completed Quests %" },
    { key = "level",     label = "Level" },
}
local SOLO_ITEMS = {
    { key = "xpPerHour",   label = "XP per Hour" },
    { key = "levelingIn",  label = "Leveling In" },
    { key = "timeLevel",   label = "Time This Level" },
    { key = "timeSession", label = "Time This Session" },
}
local ITEM_LABEL = {}
for _, list in ipairs({ TOP_ITEMS, SOLO_ITEMS }) do
    for _, it in ipairs(list) do ITEM_LABEL[it.key] = it.label end
end
-- Show Rested adds the rested XP after the first of these in a text.
local RESTED_ITEM = { pct = true, cur = true, curMax = true }
-- The text Add Text Slot just wrote (its key), across the rebuild it causes:
-- the new text's row reports the write to Spec Overrides once it exists.
local addedKey

---------------------------------------------------------------------------
--  XP Bar page  (dedicated tab)
--    CORE            XP Bar Style | Visibility, Width | Height, Show
--                    Dividers | Orientation (and 5% Line Style | Divider
--                    Text while dividers are on)
--    CORE TEXT POSITIONS  one slot per text that shows something (two to
--                    a row), then Add Text Slot
--    DISPLAY         Text Size | Text Background, Border Style | Border
--                    Size (and the offsets of a textured style), Fill
--                    Style | Rested Color, Background | Bar Texture,
--                    Quest XP Overlay
--  While the bar's visibility is Never only the first row is built.
---------------------------------------------------------------------------

local function BuildXPBarPage(pageName, parent, yOffset)
    local EAB = ns._ABO_OptEnv.EAB
    local W = EllesmereUI.Widgets
    local K = ns.ABO_DataBarKit(parent)
    local BLIZZ_DIS_TIP, _blizzDis = K.BLIZZ_DIS_TIP, K.BlizzDis
    local function S() return EAB.db.profile.bars[XP] end
    local function Vertical() return S().orientation == "VERTICAL" end
    -- Row chrome (frames: never on the search pre-build's absorber rows).
    local chrome = not EllesmereUI._prebuilding
    local y = yOffset
    local _, h

    -- Global settings page, no bar selector header
    EllesmereUI:ClearContentHeader()
    parent._showRowDivider = true

    -------------------------------------------------------------------
    --  CORE
    -------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "CORE", y);  y = y - h

    -- XP Bar Style: the EllesmereUI bar, plain, in the profession frame art or
    -- in WoW Forever's border (Forever: the chat and Damage Meters border,
    -- offered only on that client), or Blizzard's own bar. Blizz Default is
    -- the one saved switch for Blizzard's XP, reputation and House Favor bars,
    -- shared with Use Blizzard's Rep Bars (Menu, Bags & Rep Bars).
    local styleValues = { eui = "EllesmereUI", prof = "Professions", default = "Blizz Default" }
    local styleOrder = { "eui", "prof" }
    if EllesmereUI._XPBarArtAvailable("forever") then
        styleValues.forever = "Forever"
        styleOrder[#styleOrder + 1] = "forever"
    end
    styleOrder[#styleOrder + 1] = "default"
    -- The setting has no tooltip of its own: Blizz Default explains itself
    -- while hovered in the menu.
    styleValues._menuOpts = {
        onItemHover = function(key, item)
            if key == "default" and item then
                EllesmereUI.ShowWidgetTooltip(item, "Blizz Default also switches the reputation bars to Blizzard's.")
            end
        end,
        onItemLeave = function(key)
            if key == "default" then EllesmereUI.HideWidgetTooltip() end
        end,
    }
    -- XP Bar Style | Visibility (its cog: Click Through); a Never flip
    -- rebuilds the page.
    local visOpts = K.VisOpts(XP, "Visibility", _blizzDis, BLIZZ_DIS_TIP, true)
    visOpts.leftCfg = { type="dropdown", text="XP Bar Style", values=styleValues, order=styleOrder,
          -- A frame art this client lacks shows as the EllesmereUI bar it draws.
          getValue=function()
              local v = EllesmereUI._GetXPBarStyle()
              return styleValues[v] and v or "eui"
          end,
          setValue=function(v) K.AfterSwitch(EllesmereUI._SetXPBarStyle(v)) end }
    local visRow
    visRow, h = EllesmereUI.BuildVisibilityRow(W, parent, y, visOpts);  y = y - h
    if chrome then
        local rgn = visRow._rightRegion
        EllesmereUI.BuildInlineCog(rgn, {
            title = "Visibility",
            anchorTo = rgn._control,
            rows = { K.ClickThroughRow(XP) },
        })
    end
    -- Rows below are hidden while visibility is Never (a Never flip rebuilds).
    if K.BarIsNever(XP) then return math.abs(y) end

    y = K.SizeRow(y, XP)

    -- Show Dividers (its 5% and 10% colours inline; its settings row below
    -- exists only while it is on) | Orientation (its cog: Vertical Text).
    local divRowTop
    divRowTop, h = W:DualRow(parent, y,
        { type="toggle", text="Show Dividers",
          disabled=_blizzDis, disabledTooltip=BLIZZ_DIS_TIP, rawTooltip=true,
          getValue=function() return S().showDividers end,
          setValue=EllesmereUI.SectionToggleSetValue(function(v)
              S().showDividers = v
              ns.ApplyDataBarLayout(XP)
          end) },
        K.OrientCfg({ XP }));  y = y - h
    K.OrientCog(divRowTop._rightRegion, { XP }, true)
    if chrome then
        -- The 5% Ticks swatch also greys while 5% Line Style is None (its
        -- tooltip then names every lock, the row's included).
        EllesmereUI.BuildInlineSwatches(divRowTop._leftRegion, {
            { tooltip = "5% Ticks", hasAlpha = true,
              disabled = function() return S().divider5Style == "none" end,
              disabledTooltip = function()
                  if _blizzDis() then return BLIZZ_DIS_TIP end
                  if not S().showDividers then return "Show Dividers" end
                  return "This option requires a 5% Line Style other than None"
              end,
              rawTooltip = _blizzDis,
              getValue = function()
                  local c = S().tick5Color
                  if c then return c.r or 220/255, c.g or 167/255, c.b or 127/255, c.a or 0.9 end
                  return 220/255, 167/255, 127/255, 0.9
              end,
              setValue = function(r, g, b, a)
                  S().tick5Color = { r = r, g = g, b = b, a = a or 0.9 }
                  ns.ApplyDataBarLayout(XP)
              end },
            { tooltip = "10% Lines", hasAlpha = true,
              getValue = function()
                  local c = S().tick10Color
                  if c then return c.r or 1, c.g or 1, c.b or 1, c.a or 0.9 end
                  return 1, 1, 1, 0.9
              end,
              setValue = function(r, g, b, a)
                  S().tick10Color = { r = r, g = g, b = b, a = a or 0.9 }
                  ns.ApplyDataBarLayout(XP)
              end },
        }, { size = 20,
            disabled = function() return _blizzDis() or not S().showDividers end,
            disabledTooltip = function()
                if _blizzDis() then return BLIZZ_DIS_TIP end
                return "Show Dividers"
            end,
            rawTooltip = _blizzDis })
    end

    -- 5% Line Style (its cog: Show Ticks Over Fill Bar, the inverse of the
    -- saved smartTicks, which hides the marks the fill has passed) | Divider
    -- Text (its cog: the text's colour, size and offsets), while Show
    -- Dividers is on.
    if S().showDividers then
        local divRow
        divRow, h = W:DualRow(parent, y,
            { type="dropdown", text="5% Line Style",
              values={ dashed="Dashed", dotted="Dotted", solid="Solid", none="None" },
              order={ "none", "dashed", "dotted", "solid" },
              disabled=_blizzDis, disabledTooltip=BLIZZ_DIS_TIP, rawTooltip=true,
              getValue=function() return S().divider5Style or "dashed" end,
              setValue=function(v)
                  S().divider5Style = v
                  ns.ApplyDataBarLayout(XP)
                  EllesmereUI:RefreshPage()
              end },
            { type="toggle", text="Divider Text",
              disabled=_blizzDis, disabledTooltip=BLIZZ_DIS_TIP, rawTooltip=true,
              getValue=function() return S().showDividerText end,
              setValue=function(v)
                  S().showDividerText = v
                  ns.ApplyDataBarLayout(XP)
                  EllesmereUI:RefreshPage()
              end });  y = y - h
        if chrome then
            local lRgn, rRgn = divRow._leftRegion, divRow._rightRegion
            EllesmereUI.BuildInlineCog(lRgn, {
                title = "Ticks",
                anchorTo = lRgn._control,
                captureRegion = lRgn,
                disabled = _blizzDis, disabledTooltip = BLIZZ_DIS_TIP, rawTooltip = true,
                rows = {
                    { type="toggle", label="Show Ticks Over Fill Bar",
                      get=function() return not S().smartTicks end,
                      set=function(v)
                          S().smartTicks = not v
                          ns.ApplyDataBarLayout(XP)
                      end },
                },
            })
            EllesmereUI.BuildInlineCog(rRgn, {
                title = "Divider Text",
                anchorTo = rRgn._control,
                captureRegion = rRgn,
                disabled = function() return _blizzDis() or not S().showDividerText end,
                disabledTooltip = function()
                    if _blizzDis() then return BLIZZ_DIS_TIP end
                    return "Divider Text"
                end,
                rawTooltip = _blizzDis,
                rows = {
                    { type="colorpicker", label="Text Color",
                      get=function()
                          local c = S().dividerTextColor
                          if c then return c.r or 1, c.g or 1, c.b or 1 end
                          return 1, 1, 1
                      end,
                      set=function(r, g, b)
                          S().dividerTextColor = { r = r, g = g, b = b }
                          ns.ApplyDataBarLayout(XP)
                      end },
                    { type="slider", label="Text Size", min=6, max=18, step=1,
                      get=function() return S().dividerTextSize or 8 end,
                      set=function(v)
                          S().dividerTextSize = v
                          ns.ApplyDataBarLayout(XP)
                      end },
                    { type="slider", label="X Offset", min=-50, max=50, step=1,
                      get=function() return S().dividerTextOffX or 0 end,
                      set=function(v)
                          S().dividerTextOffX = v
                          ns.ApplyDataBarLayout(XP)
                      end },
                    { type="slider", label="Y Offset", min=-50, max=50, step=1,
                      get=function() return S().dividerTextOffY or 0 end,
                      set=function(v)
                          S().dividerTextOffY = v
                          ns.ApplyDataBarLayout(XP)
                      end },
                },
            })
        end
    end

    _, h = W:Spacer(parent, y, 12);  y = y - h

    -------------------------------------------------------------------
    --  CORE TEXT POSITIONS
    -------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "CORE TEXT POSITIONS", y);  y = y - h

    -- The bar's texts, one slot each: only the ones that show something, two
    -- to a row, then Add Text Slot, which asks where the new text goes. Up to
    -- TEXTS_PER_POS texts share a position:
    -- its first is saved as textSlot<Stem> (unset, Center shows the old
    -- Default and the others nothing), the second and third as
    -- textSlot<Stem>2 / 3, each with its own Size, offsets and Show Rested;
    -- Center's first is the bar text, placed by Text Size and the Bar Text
    -- Offsets cog, and the only one a vertical bar shows. A text's name opens
    -- the positions it can move to; its dropdown checks and drags the items it
    -- shows, picks a bottom item instead, or takes it off (Remove, or every
    -- item unchecked by the time the list closes). A value saved before the
    -- items existed shows as its items here (the bar draws it as it was) and
    -- is rewritten only when edited. Structure changes rebuild the page.
    local SLOT_TIP = "What this text shows."
    local MOVE_TIP = "Choose this text's slot position."
    local TEXTS_PER_POS = 3
    local POSITIONS = {
        { stem = "Center",      label = "Center Text",       name = "Center" },
        { stem = "Left",        label = "Left Text",         name = "Left" },
        { stem = "Right",       label = "Right Text",        name = "Right" },
        { stem = "TopLeft",     label = "Top Left Text",     name = "Top Left" },
        { stem = "TopRight",    label = "Top Right Text",    name = "Top Right" },
        { stem = "BottomLeft",  label = "Bottom Left Text",  name = "Bottom Left" },
        { stem = "BottomRight", label = "Bottom Right Text", name = "Bottom Right" },
    }
    local function SlotKey(stem, i) return "textSlot" .. stem .. (i > 1 and i or "") end
    -- Center's first text: the bar text itself.
    local function IsBarText(stem, i) return stem == "Center" and i == 1 end
    -- A text's saved value (the bar text: unset reads as the old Default).
    local function SlotRaw(stem, i)
        local v = S()[SlotKey(stem, i)]
        if v == nil and IsBarText(stem, i) then return "classic" end
        return v
    end
    -- Its items (into out) and their kind: "top", "solo" or nil for nothing,
    -- then true for the old Default text, then the value when the bar still
    -- draws it as it was. The bar text reads a value it does not know as
    -- Default, as the bar does.
    local function SlotItems(stem, i, out)
        local v = SlotRaw(stem, i)
        local kind, legacy, render = ns.XPTextItems(v, S(), out)
        if not kind and IsBarText(stem, i) and v ~= "none" then
            kind, legacy, render = ns.XPTextItems("classic", S(), out)
        end
        return kind, legacy, render
    end
    local scratch = {}
    local function Shows(stem, i) return SlotItems(stem, i, scratch) ~= nil end
    local function FreeIndex(stem)
        for i = 1, TEXTS_PER_POS do
            if not Shows(stem, i) then return i end
        end
    end
    -- Takes a text off: its value, Show Rested and its own size and offsets
    -- (the bar text: "none", its placement is the bar text's own).
    local function ClearSlot(stem, i)
        local s, key = S(), SlotKey(stem, i)
        s[key .. "Rested"] = nil
        if IsBarText(stem, i) then
            s[key] = "none"
        else
            s[key], s[key .. "Size"], s[key .. "XOffset"], s[key .. "YOffset"] = nil, nil, nil, nil
        end
    end
    local function Rebuild()
        ns.ApplyDataBarLayout(XP)
        EllesmereUI:RefreshPage(true)
    end
    -- Moves a text to the first free place at another position: its value and
    -- Show Rested, with its size and offsets unless either end is the bar text.
    local function MoveSlot(stem, i, toStem)
        if toStem == stem then return end
        local j = FreeIndex(toStem)
        if not j then return end
        local s, from, to = S(), SlotKey(stem, i), SlotKey(toStem, j)
        local v = SlotRaw(stem, i)
        -- The bar text shows a value it does not know as Default: so it moves.
        if not ns.XPTextItems(v, s, scratch) then v = "classic" end
        local rested = s[from .. "Rested"]
        local carry = not IsBarText(stem, i)
        local size, ox, oy = s[from .. "Size"], s[from .. "XOffset"], s[from .. "YOffset"]
        ClearSlot(stem, i)
        s[to] = v
        s[to .. "Rested"] = rested
        if not IsBarText(toStem, j) then
            s[to .. "Size"] = carry and size or nil
            s[to .. "XOffset"] = carry and ox or nil
            s[to .. "YOffset"] = carry and oy or nil
        end
        Rebuild()
    end
    -- Add Text Slot: a fresh text at the first free place of the position the
    -- player picked from the button's list, showing Current % with Show
    -- Rested on. The rebuild is immediate, so the new row reports the write.
    local function AddAt(stem)
        local idx = FreeIndex(stem)
        if not idx then return end
        local s, key = S(), SlotKey(stem, idx)
        if not IsBarText(stem, idx) then ClearSlot(stem, idx) end
        s[key] = "pct"
        s[key .. "Rested"] = true
        addedKey = key
        Rebuild()
        addedKey = nil
    end
    -- Room for another text: any free place, or on a vertical bar the bar
    -- text's own place (the only text a vertical bar draws).
    local function AddRoom()
        if Vertical() then return not Shows("Center", 1) end
        for _, p in ipairs(POSITIONS) do
            if FreeIndex(p.stem) then return true end
        end
        return false
    end

    -- The texts that show something, in position order; a position's second
    -- and third are numbered.
    local entries = {}
    for _, p in ipairs(POSITIONS) do
        local rank = 0
        for i = 1, TEXTS_PER_POS do
            if Shows(p.stem, i) then
                rank = rank + 1
                entries[#entries + 1] = { pos = p, i = i, rank = rank }
            end
        end
    end
    local function EntryLabel(e)
        local base = EllesmereUI.L(e.pos.label)
        return e.rank > 1 and (base .. " " .. e.rank) or base
    end
    -- Every text but the bar text draws on a horizontal bar only.
    local function EntryLocked(e)
        return _blizzDis() or (not IsBarText(e.pos.stem, e.i) and Vertical())
    end
    local function SlotLockTip()
        if _blizzDis() then return BLIZZ_DIS_TIP end
        return "Horizontal Orientation"
    end
    -- A value's name: its items' names, " - " between them (nil for nothing).
    local labelScratch = {}
    local function ValueLabel(v)
        if not ns.XPTextItems(v, S(), labelScratch) then return nil end
        local names = {}
        for n = 1, #labelScratch do names[n] = EllesmereUI.L(ITEM_LABEL[labelScratch[n]]) end
        return table.concat(names, " - ")
    end
    -- The row's own dropdown, hidden under the checkbox list: Spec Overrides
    -- read and write the text's value through it. One entry per item; any
    -- other value is named by its items.
    local PH_VALUES = setmetatable({ none = "Remove" }, { __index = function(_, k)
        if type(k) == "string" and k:sub(1, 1) ~= "_" then return ValueLabel(k) end
    end })
    local PH_ORDER = { "none" }
    for _, list in ipairs({ TOP_ITEMS, SOLO_ITEMS }) do
        PH_ORDER[#PH_ORDER + 1] = "---"
        for _, it in ipairs(list) do
            PH_VALUES[it.key] = it.label
            PH_ORDER[#PH_ORDER + 1] = it.key
        end
    end
    local function EntryCfg(e)
        local stem, i = e.pos.stem, e.i
        return { type="dropdown", text=EntryLabel(e), values=PH_VALUES, order=PH_ORDER,
              disabled=function() return EntryLocked(e) end, disabledTooltip=SlotLockTip, rawTooltip=_blizzDis,
              getValue=function() return SlotRaw(stem, i) or "none" end,
              setValue=function(v)
                  S()[SlotKey(stem, i)] = v
                  ns.ApplyDataBarLayout(XP)
              end }
    end

    -- Saves a text's new value; the old Default text keeps its rested part
    -- (Show Rested) once it is rewritten. rgn: the row, for Spec Overrides.
    local function WriteSlot(stem, i, v, rgn)
        local s, key = S(), SlotKey(stem, i)
        local _, legacy = SlotItems(stem, i, scratch)
        if legacy and s[key .. "Rested"] == nil then s[key .. "Rested"] = true end
        s[key] = v
        ns.ApplyDataBarLayout(XP)
        if rgn then EllesmereUI._NotifySettingWrite(rgn) end
    end

    -- Show Rested: the rested XP after the text's first Current %, Current or
    -- Current / Max (on for the old Default text until set).
    local function RestedRow(stem, i)
        local key = SlotKey(stem, i) .. "Rested"
        local function Eligible()
            if SlotItems(stem, i, scratch) ~= "top" then return false end
            for n = 1, #scratch do
                if RESTED_ITEM[scratch[n]] then return true end
            end
            return false
        end
        return { type="toggle", label="Show Rested",
              disabled=function() return not Eligible() end,
              disabledTooltip="This option requires Current %, Current or Current / Max",
              get=function()
                  local _, legacy = SlotItems(stem, i, scratch)
                  return ns.XPTextRested(S(), key, legacy)
              end,
              set=function(v)
                  -- An old value the bar still draws as it was (the old Default
                  -- aside, whose rested part follows this) becomes its items.
                  local _, _, render = SlotItems(stem, i, scratch)
                  if render and render ~= "classic" then
                      S()[SlotKey(stem, i)] = table.concat(scratch, ",")
                  end
                  S()[key] = v and true or false
                  ns.ApplyDataBarLayout(XP)
              end }
    end

    -- The text's items: a checkbox list over its value (the top items, in the
    -- order dragged), Remove above it and the bottom items below it as plain
    -- choices. Checked items come first, in their order, each time it opens;
    -- the text's order is the order of its checked rows. Unchecking every item
    -- takes the text off once the list closes (until then another can be
    -- checked); a bottom item shows alone.
    local function ItemsDropdown(rgn, e)
        local stem, i = e.pos.stem, e.i
        local own = {}
        local emptied
        local rows = {}
        for n, it in ipairs(TOP_ITEMS) do rows[n] = { key = it.key, label = it.label } end
        local function Checked(k)
            if SlotItems(stem, i, own) ~= "top" then return false end
            for n = 1, #own do
                if own[n] == k then return true end
            end
            return false
        end
        -- The checked items in the list's order (k turned on or off first).
        local function WriteChecked(order, k, on)
            local set = {}
            if SlotItems(stem, i, own) == "top" then
                for n = 1, #own do set[own[n]] = true end
            end
            if k then set[k] = on or nil end
            local out = {}
            for n = 1, #order do
                if set[order[n]] then out[#out + 1] = order[n] end
            end
            emptied = (#out == 0)
            WriteSlot(stem, i, emptied and "none" or table.concat(out, ","), rgn)
            EllesmereUI:RefreshPage()
        end
        local ctrl = rgn._control
        local ddW = ctrl and ctrl:GetWidth() or 0
        if ddW < 50 then ddW = 210 end
        local cbDD, cbRefresh = EllesmereUI.BuildReorderCBDropdown(rgn, ddW, rgn:GetFrameLevel() + 2, rows,
            Checked,
            function(k, v, order) WriteChecked(order, k, v) end,
            {
                hint = "Drag to Reorder",
                head = { { key = "none", label = "Remove" } },
                onHead = function()
                    emptied = nil
                    ClearSlot(stem, i)
                    EllesmereUI._NotifySettingWrite(rgn)
                    Rebuild()
                end,
                tail = SOLO_ITEMS,
                tailSelected = function(k)
                    return SlotItems(stem, i, own) == "solo" and own[1] == k
                end,
                onTail = function(k)
                    emptied = nil
                    WriteSlot(stem, i, k, rgn)
                    EllesmereUI:RefreshPage()
                end,
                openOrder = function()
                    if SlotItems(stem, i, own) ~= "top" then return nil end
                    local keys = {}
                    for n = 1, #own do keys[n] = own[n] end
                    return keys
                end,
                setOrder = function(order)
                    if SlotItems(stem, i, own) == "top" then WriteChecked(order) end
                end,
                onClose = function()
                    if emptied and not Shows(stem, i) then
                        emptied = nil
                        ClearSlot(stem, i)
                        EllesmereUI._NotifySettingWrite(rgn)
                        Rebuild()
                    end
                end,
                summaryLabel = function() return ValueLabel(SlotRaw(stem, i)) or EllesmereUI.L("None") end,
            })
        local p1, rel, p2, ax, ay
        if ctrl then
            p1, rel, p2, ax, ay = ctrl:GetPoint(1)
            ctrl:Hide()
        end
        if p1 then cbDD:SetPoint(p1, rel, p2, ax, ay)
        else EllesmereUI.PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0) end
        rgn._control = cbDD
        rgn._lastInline = nil
        EllesmereUI.RegisterWidgetRefresh(cbRefresh)
        -- What the text shows, on the list while it is closed (the name above
        -- it is the position button, with its own tooltip).
        cbDD:HookScript("OnEnter", function(self)
            if self._ddMenu and self._ddMenu:IsShown() then return end
            EllesmereUI.ShowWidgetTooltip(self, SLOT_TIP)
        end)
        cbDD:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        cbDD:HookScript("OnClick", function() EllesmereUI.HideWidgetTooltip() end)
        -- The list has no disabled state of its own: grey it and block clicks;
        -- the row's disabled overlay explains the lock.
        local function SyncLock()
            local off = EntryLocked(e)
            cbDD:SetAlpha(off and 0.3 or 1)
            cbDD:EnableMouse(not off)
        end
        SyncLock()
        EllesmereUI.RegisterWidgetRefresh(SyncLock)
    end
    -- A text's cog (all but the bar text): its Size, offsets and Show Rested.
    local function SlotCog(rgn, e)
        local stem, i = e.pos.stem, e.i
        local key = SlotKey(stem, i)
        local sizeKey, xKey, yKey = key .. "Size", key .. "XOffset", key .. "YOffset"
        local rows = {
            { type="slider", label="Size", min=6, max=24, step=1,
              get=function() return S()[sizeKey] or S().textSize or 9 end,
              set=function(v)
                  S()[sizeKey] = v
                  ns.ApplyDataBarLayout(XP)
              end },
            { type="slider", label="X Offset", min=-150, max=150, step=1,
              get=function() return S()[xKey] or 0 end,
              set=function(v)
                  S()[xKey] = v
                  ns.ApplyDataBarLayout(XP)
              end },
            { type="slider", label="Y Offset", min=-150, max=150, step=1,
              get=function() return S()[yKey] or 0 end,
              set=function(v)
                  S()[yKey] = v
                  ns.ApplyDataBarLayout(XP)
              end },
        }
        rows[#rows + 1] = RestedRow(stem, i)
        EllesmereUI.BuildInlineCog(rgn, {
            title = EntryLabel(e),
            icon = EllesmereUI.DIRECTIONS_ICON,
            anchorTo = rgn._control,
            captureRegion = rgn,
            disabled = function() return EntryLocked(e) end,
            disabledTooltip = SlotLockTip,
            rawTooltip = _blizzDis,
            rows = rows,
        })
    end
    -- The text's name with a white chevron (the accent while hovered or open;
    -- a darker white when the accent itself is white): the standard dropdown
    -- list of the positions it can move to, built on first open (the one it
    -- is in selected, a full one greyed, all but Center on a vertical bar).
    local CHEVRON = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-down3.png"
    local POS_VALUES, POS_ORDER = {}, {}
    for _, p in ipairs(POSITIONS) do
        POS_VALUES[p.stem] = p.name
        POS_ORDER[#POS_ORDER + 1] = p.stem
    end
    local function ChevronHoverColor()
        local ac = EllesmereUI.ELLESMERE_GREEN
        if ac.r > 0.9 and ac.g > 0.9 and ac.b > 0.9 then return 0.72, 0.72, 0.72 end
        return ac.r, ac.g, ac.b
    end
    local NO_PAINT = { SetColor = function() end, SetColorTexture = function() end }
    local function PositionPicker(rgn, e)
        local label = rgn._label
        local btn = CreateFrame("Button", nil, rgn)
        btn:SetFrameLevel(rgn:GetFrameLevel() + 12)
        local arrow = btn:CreateTexture(nil, "ARTWORK")
        arrow:SetTexture(CHEVRON)
        arrow:SetSize(17, 17)
        arrow:SetPoint("LEFT", label, "LEFT", math.ceil(label:GetStringWidth()) + 6, -1)
        btn:SetPoint("TOPLEFT", label, "TOPLEFT", -4, 5)
        btn:SetPoint("BOTTOMRIGHT", arrow, "BOTTOMRIGHT", 2, -2)
        local menu
        -- The name takes the chevron's colour while lit (its own white back).
        local function Lit(on)
            if on then
                local r, g, b = ChevronHoverColor()
                arrow:SetVertexColor(r, g, b)
                label:SetTextColor(r, g, b)
            else
                arrow:SetVertexColor(1, 1, 1)
                label:SetTextColor(EllesmereUI.TEXT_WHITE_R, EllesmereUI.TEXT_WHITE_G, EllesmereUI.TEXT_WHITE_B)
            end
        end
        Lit(false)
        local function OnEnter()
            if EntryLocked(e) then
                local tip = SlotLockTip()
                EllesmereUI.ShowWidgetTooltip(btn, _blizzDis() and tip or EllesmereUI.DisabledTooltip(tip))
                return
            end
            Lit(true)
            if not (menu and menu:IsShown()) then EllesmereUI.ShowWidgetTooltip(btn, MOVE_TIP) end
        end
        local function OnLeave()
            if not (menu and menu:IsShown()) then Lit(false) end
            EllesmereUI.HideWidgetTooltip()
        end
        btn:SetScript("OnEnter", OnEnter)
        btn:SetScript("OnLeave", OnLeave)
        -- The list's label stand-in: the menu writes the picked name there,
        -- never over the text's own name.
        local proxyLbl = EllesmereUI.MakeFont(btn, 12, nil, 1, 1, 1)
        proxyLbl:Hide()
        local function EnsureMenu()
            if menu then return menu end
            local refresh
            menu, _, refresh = EllesmereUI.BuildDropdownMenu(btn, 170, POS_ORDER, POS_VALUES,
                function() return e.pos.stem end,
                function(v) MoveSlot(e.pos.stem, e.i, v) end,
                proxyLbl, "regular",
                function(v)
                    if v == e.pos.stem then return nil end
                    if v ~= "Center" and Vertical() then return EllesmereUI.DisabledTooltip("Horizontal Orientation") end
                    if not FreeIndex(v) then return true end
                end)
            -- The standard open/close behaviour (scale, click-away, scroll-away);
            -- the button keeps its own look and clicks.
            EllesmereUI.WireDropdownScripts(btn, proxyLbl, NO_PAINT, NO_PAINT, menu, refresh, EllesmereUI.RD_DD_COLOURS, true)
            btn:HookScript("OnEnter", OnEnter)
            btn:HookScript("OnLeave", OnLeave)
            menu:HookScript("OnShow", function() Lit(true) end)
            menu:HookScript("OnHide", function() Lit(btn:IsMouseOver()) end)
            return menu
        end
        btn:SetScript("OnClick", function()
            if EntryLocked(e) then return end
            EllesmereUI.HideWidgetTooltip()
            local m = EnsureMenu()
            if m:IsShown() then m:Hide() else m:Show() end
        end)
        btn:HookScript("OnHide", function() if menu then menu:Hide() end end)
        local function SyncLock() arrow:SetShown(not EntryLocked(e)) end
        EllesmereUI.RegisterWidgetRefresh(SyncLock)
        SyncLock()
    end

    -- Add Text Slot opens the list of positions (the standard dropdown menu,
    -- as wide as the button, built on first open; a full position greyed,
    -- and on a vertical bar every position but the bar text's own): the
    -- player picks where the new text goes.
    local ADD_W = 220
    local addOpen   -- the button's click, once its row is built
    local function AddPicker(rgn)
        local btn = rgn._control
        -- Its own hover look, kept past the menu wiring (which takes the scripts).
        local enter, leave = btn:GetScript("OnEnter"), btn:GetScript("OnLeave")
        local proxyLbl = EllesmereUI.MakeFont(btn, 12, nil, 1, 1, 1)
        proxyLbl:Hide()
        local menu
        local function EnsureMenu()
            if menu then return menu end
            local refresh
            menu, _, refresh = EllesmereUI.BuildDropdownMenu(btn, ADD_W, POS_ORDER, POS_VALUES,
                function() return nil end,
                function(v) AddAt(v) end,
                proxyLbl, "regular",
                function(v)
                    if Vertical() then
                        if v ~= "Center" then return EllesmereUI.DisabledTooltip("Horizontal Orientation") end
                        if Shows("Center", 1) then return true end
                        return nil
                    end
                    if not FreeIndex(v) then return true end
                end)
            EllesmereUI.WireDropdownScripts(btn, proxyLbl, NO_PAINT, NO_PAINT, menu, refresh, EllesmereUI.RD_DD_COLOURS, true)
            btn:HookScript("OnEnter", enter)
            btn:HookScript("OnLeave", function(self) if not menu:IsShown() then leave(self) end end)
            menu:HookScript("OnHide", function() if not btn:IsMouseOver() then leave(btn) end end)
            return menu
        end
        addOpen = function()
            local m = EnsureMenu()
            if m:IsShown() then m:Hide() else m:Show() end
        end
        btn:HookScript("OnHide", function() if menu then menu:Hide() end end)
    end

    -- The texts two to a row, Add Text Slot in the slot after the last.
    local addCfg = { type="button", text="+ Add Text Slot", width=ADD_W,
          onClick=function() if addOpen then addOpen() end end,
          disabled=function() return _blizzDis() or not AddRoom() end,
          disabledTooltip=function()
              if _blizzDis() then return BLIZZ_DIS_TIP end
              if Vertical() then return "Horizontal Orientation" end
              return "Every text position is full."
          end,
          rawTooltip=function() return _blizzDis() or not Vertical() end }
    local cells = {}
    for k = 1, #entries do cells[k] = entries[k] end
    cells[#cells + 1] = addCfg
    local function CellCfg(c)
        if c == nil then return EllesmereUI.BlankRowCfg() end
        if c == addCfg then return addCfg end
        return EntryCfg(c)
    end
    local function CellChrome(rgn, c)
        if not chrome or c == nil then return end
        if c == addCfg then
            AddPicker(rgn)
            return
        end
        PositionPicker(rgn, c)
        ItemsDropdown(rgn, c)
        if IsBarText(c.pos.stem, c.i) then
            K.TextCog(rgn, XP, { RestedRow(c.pos.stem, c.i) })
        else
            SlotCog(rgn, c)
        end
        -- The text Add Text Slot just made: its own row takes the write.
        if addedKey and addedKey == SlotKey(c.pos.stem, c.i) then
            addedKey = nil
            EllesmereUI._NotifySettingWrite(rgn)
        end
    end
    for k = 1, #cells, 2 do
        local l, r = cells[k], cells[k + 1]
        local row
        row, h = W:DualRow(parent, y, CellCfg(l), CellCfg(r));  y = y - h
        CellChrome(row._leftRegion, l)
        CellChrome(row._rightRegion, r)
    end

    _, h = W:Spacer(parent, y, 12);  y = y - h

    -------------------------------------------------------------------
    --  DISPLAY
    -------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "DISPLAY", y);  y = y - h

    -- Text Size (the bar text's, and every other text's until its own is
    -- set) | Text Background (its colour and opacity inline): a box behind
    -- every text shown.
    local textBgRow
    textBgRow, h = W:DualRow(parent, y, K.TextSizeCfg(XP),
        { type="toggle", text="Text Background",
          disabled=_blizzDis, disabledTooltip=BLIZZ_DIS_TIP, rawTooltip=true,
          getValue=function() return S().showTextBg end,
          setValue=function(v)
              S().showTextBg = v
              ns.ApplyDataBarLayout(XP)
              EllesmereUI:RefreshPage()
          end });  y = y - h
    if chrome then
        EllesmereUI.BuildInlineSwatches(textBgRow._rightRegion, {
            { tooltip = "Background Color", hasAlpha = true,
              getValue = function()
                  local c = S().textBgColor
                  if c then return c.r or 0.06, c.g or 0.06, c.b or 0.08, c.a or 0.9 end
                  return 0.06, 0.06, 0.08, 0.9
              end,
              setValue = function(r, g, b, a)
                  S().textBgColor = { r = r, g = g, b = b, a = a or 0.9 }
                  ns.ApplyDataBarLayout(XP)
              end },
        }, { size = 20,
            disabled = function() return _blizzDis() or not S().showTextBg end,
            disabledTooltip = function()
                if _blizzDis() then return BLIZZ_DIS_TIP end
                return "Text Background"
            end,
            rawTooltip = _blizzDis })
    end

    -- Border Style | Border Size, no Custom Border toggle: the plain line
    -- shows as Solid 1px until the first edit turns the border on.
    y = K.BorderRows(y, XP, true)

    -- Fill Style: Custom Color (the fill colour swatches inline: Custom,
    -- Accent, Reactive), Horizontal / Vertical Gradient (s.fillGradient; its
    -- Gradient Start and End colours inline, s.fillGradStart / fillGradEnd,
    -- defaults in ns.XPBarGradient) or a profession skill-bar animation (its
    -- cog inline: Animate on XP Gain, on by default -- nil plays, false stops
    -- it -- and Loop Animation, off by default, one turning the other off;
    -- Stretch to Bar draws one copy across the bar instead of tiles at the
    -- art's proportions). Only the flipbooks this client has are offered, and
    -- none on a vertical bar (the art is horizontal). Switching to another
    -- kind rebuilds the page for its inline control.
    local fillVals = { custom = "Custom Color", gradH = "Horizontal Gradient", gradV = "Vertical Gradient" }
    local fillOrder = { "custom", "gradH", "gradV" }
    if not Vertical() then
        for _, c in ipairs(FLIP_CANDS) do
            if C_Texture.GetAtlasInfo(c[1]) then
                if #fillOrder == 3 then fillOrder[4] = "---" end
                fillVals[c[1]] = c[2]; fillOrder[#fillOrder + 1] = c[1]
            end
        end
    end
    local GRAD_KEY = { HORIZONTAL = "gradH", VERTICAL = "gradV" }
    local GRAD_DIR = { gradH = "HORIZONTAL", gradV = "VERTICAL" }
    local function FillKey()
        local f = S().fvFill
        if f and fillVals[f] then return f end
        return GRAD_KEY[S().fillGradient] or "custom"
    end
    local function FillKind()
        local k = FillKey()
        if k == "custom" then return "custom" end
        return GRAD_DIR[k] and "gradient" or "flip"
    end
    local function Custom() return FillKind() == "custom" end
    -- Rested Color: the rested XP shown ahead of the fill (dark blue at half
    -- opacity until set).
    local fillRow
    fillRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Fill Style", values=fillVals, order=fillOrder,
          disabled=_blizzDis, disabledTooltip=BLIZZ_DIS_TIP, rawTooltip=true,
          getValue=FillKey,
          setValue=function(v)
              local was = FillKind()
              local s = S()
              s.fillGradient = GRAD_DIR[v]
              s.fvFill = (v ~= "custom" and not GRAD_DIR[v]) and v or nil
              ns.ApplyDataBarLayout(XP)
              -- Another kind needs its own inline control: rebuild.
              if FillKind() ~= was then EllesmereUI:RefreshPage(true) else EllesmereUI:RefreshPage() end
          end },
        { type="colorpicker", text="Rested Color", hasAlpha=true,
          disabled=_blizzDis, disabledTooltip=BLIZZ_DIS_TIP, rawTooltip=true,
          getValue=function()
              local c = S().restedColor
              if c then return c.r or 0.15, c.g or 0.30, c.b or 0.60, c.a or 0.5 end
              return 0.15, 0.30, 0.60, 0.5
          end,
          setValue=function(r, g, b, a)
              S().restedColor = { r = r, g = g, b = b, a = a or 0.5 }
              ns.ApplyDataBarLayout(XP)
          end });  y = y - h
    if chrome then
        local rgn = fillRow._leftRegion
        if Custom() then
            EllesmereUI.BuildInlineSwatches(rgn, K.ColorSwatches(XP),
                { size = 20, disabled = _blizzDis, disabledTooltip = BLIZZ_DIS_TIP, rawTooltip = true })
        elseif FillKind() == "gradient" then
            EllesmereUI.BuildInlineSwatches(rgn, {
                { tooltip = "Gradient Start Color", hasAlpha = true,
                  getValue = function()
                      local _, r, g, b, a = ns.XPBarGradient(S())
                      return r, g, b, a
                  end,
                  setValue = function(r, g, b, a)
                      S().fillGradStart = { r = r, g = g, b = b, a = a or 1 }
                      ns.ApplyDataBarLayout(XP)
                  end },
                { tooltip = "Gradient End Color", hasAlpha = true,
                  getValue = function()
                      local _, _, _, _, _, r, g, b, a = ns.XPBarGradient(S())
                      return r, g, b, a
                  end,
                  setValue = function(r, g, b, a)
                      S().fillGradEnd = { r = r, g = g, b = b, a = a or 1 }
                      ns.ApplyDataBarLayout(XP)
                  end },
            }, { size = 20, disabled = _blizzDis, disabledTooltip = BLIZZ_DIS_TIP, rawTooltip = true })
        else
            EllesmereUI.BuildInlineCog(rgn, {
                title = "Fill Animation",
                anchorTo = rgn._control,
                captureRegion = rgn,
                disabled = _blizzDis, disabledTooltip = BLIZZ_DIS_TIP, rawTooltip = true,
                rows = {
                    { type="toggle", label="Animate on XP Gain",
                      tooltip="Plays the animation once each time you gain XP.",
                      get=function() return S().fvFillSmart ~= false and not S().fvFillAnim end,
                      set=function(on)
                          if on then
                              S().fvFillSmart = nil; S().fvFillAnim = nil
                          else
                              S().fvFillSmart = false
                          end
                          ns.ApplyDataBarLayout(XP)
                      end },
                    { type="toggle", label="Loop Animation",
                      tooltip="Plays the animation continuously.",
                      get=function() return S().fvFillAnim == true end,
                      set=function(on)
                          if on then
                              S().fvFillAnim = true; S().fvFillSmart = false
                          else
                              S().fvFillAnim = nil
                          end
                          ns.ApplyDataBarLayout(XP)
                      end },
                    { type="toggle", label="Stretch to Bar",
                      tooltip="Stretches the animation across the whole bar.",
                      get=function() return S().fvFillStretch end,
                      set=function(on) S().fvFillStretch = on or nil; ns.ApplyDataBarLayout(XP) end },
                },
            })
        end
    end

    -- Background: its opacity (the slider, "Background Opacity" on hover) and
    -- its colour inline, locked at 0%; both fall back to the style's own
    -- background until set, ns.XPBarBackground) | Bar Texture.
    local bgRow
    bgRow, h = W:DualRow(parent, y,
        { type="slider", text="Background", min=0, max=100, step=1,
          tooltipOnControl="Background Opacity",
          disabled=_blizzDis, disabledTooltip=BLIZZ_DIS_TIP, rawTooltip=true,
          getValue=function()
              local _, _, _, op = ns.XPBarBackground(S())
              return op
          end,
          setValue=function(v)
              local _, _, _, was = ns.XPBarBackground(S())
              S().barBgOpacity = v
              ns.ApplyDataBarLayout(XP)
              -- The colour swatch locks at 0%: refresh only on that edge.
              if (was <= 0) ~= (v <= 0) then EllesmereUI:RefreshPage() end
          end },
        K.TexCfg(XP));  y = y - h
    if chrome then
        EllesmereUI.BuildInlineSwatches(bgRow._leftRegion, {
            { tooltip = "Background Color",
              getValue = function()
                  local r, g, b = ns.XPBarBackground(S())
                  return r, g, b
              end,
              setValue = function(r, g, b)
                  S().barBgColor = { r = r, g = g, b = b }
                  ns.ApplyDataBarLayout(XP)
              end },
        }, { size = 20,
            disabled = function()
                if _blizzDis() then return true end
                local _, _, _, op = ns.XPBarBackground(S())
                return op <= 0
            end,
            disabledTooltip = function()
                if _blizzDis() then return BLIZZ_DIS_TIP end
                return "This option requires Background above 0%"
            end,
            rawTooltip = _blizzDis })
    end

    -- Quest XP Overlay: the completed / incomplete colours as inline swatches
    -- (green / gold at 60% until set, ns.XPQuestColor), the filters in its cog.
    local questRow
    questRow, h = W:DualRow(parent, y,
        { type="toggle", text="Quest XP Overlay",
          tooltip="Shows the XP from quests in your quest log ahead of the fill.",
          disabled=_blizzDis, disabledTooltip=BLIZZ_DIS_TIP, rawTooltip=true,
          getValue=function() return S().questOverlay end,
          setValue=function(v)
              S().questOverlay = v
              ns.ApplyDataBarLayout(XP)
              EllesmereUI:RefreshPage()
          end },
        EllesmereUI.BlankRowCfg());  y = y - h
    if chrome then
        local rgn = questRow._leftRegion
        local function overlayOff() return _blizzDis() or not S().questOverlay end
        EllesmereUI.BuildInlineSwatches(rgn, {
            { tooltip = "Completed Color", hasAlpha = true,
              getValue = function() return ns.XPQuestColor(S(), true) end,
              setValue = function(r, g, b, a)
                  S().questOverlayDoneColor = { r = r, g = g, b = b, a = a or 0.6 }
                  ns.ApplyDataBarLayout(XP)
              end },
            { tooltip = "Incomplete Color", hasAlpha = true,
              disabled = function() return S().questOverlayCompleted end,
              disabledTooltip = function()
                  if _blizzDis() then return BLIZZ_DIS_TIP end
                  if not S().questOverlay then return "Quest XP Overlay" end
                  return "Completed Quests Only"
              end,
              requireState = function()
                  if S().questOverlay and not _blizzDis() then return "disabled" end
              end,
              rawTooltip = _blizzDis,
              getValue = function() return ns.XPQuestColor(S(), false) end,
              setValue = function(r, g, b, a)
                  S().questOverlayColor = { r = r, g = g, b = b, a = a or 0.6 }
                  ns.ApplyDataBarLayout(XP)
              end },
        }, { size = 20, disabled = overlayOff,
            disabledTooltip = function()
                if _blizzDis() then return BLIZZ_DIS_TIP end
                return "Quest XP Overlay"
            end,
            rawTooltip = _blizzDis })
        EllesmereUI.BuildInlineCog(rgn, {
            title = "Quest XP Overlay",
            captureRegion = rgn,
            disabled = overlayOff,
            disabledTooltip = function()
                if _blizzDis() then return BLIZZ_DIS_TIP end
                return "Quest XP Overlay"
            end,
            rawTooltip = _blizzDis,
            rows = {
                { type="toggle", label="Completed Quests Only",
                  tooltip="Only counts quests that are ready to turn in.",
                  get=function() return S().questOverlayCompleted end,
                  set=function(v)
                      S().questOverlayCompleted = v or nil
                      ns.ApplyDataBarLayout(XP)
                      EllesmereUI:RefreshPage()
                  end },
                { type="toggle", label="Current Zone Only",
                  tooltip="Only counts quests in your current zone.",
                  get=function() return S().questOverlayZone end,
                  set=function(v)
                      S().questOverlayZone = v or nil
                      ns.ApplyDataBarLayout(XP)
                  end },
            },
        })
    end

    return math.abs(y)
end

-- Used by EUI_ActionBars_Options.lua
ns.ABO_BuildXPBarPage = BuildXPBarPage
