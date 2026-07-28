-------------------------------------------------------------------------------
--  EUI_Friends_Groups_121.lua
--  Friend Grouping for the 12.1 Social UI friends list.
--
--  This is a complete, self-contained rebuild of the friend-grouping feature
--  that was removed in v7.4.3. It targets ONLY the new Blizzard Social UI
--  (SocialUIFrame.FriendsList, added in 12.1). On a 12.0 client, and on a
--  12.1 client where Blizzard is still serving the legacy FriendsFrame, this
--  entire file is inert -- nothing is created, hooked, or registered.
--
--  Architecture (taint-safe by construction):
--    * We NEVER call SetDataProvider, RegisterCallback, CreateTexture, or any
--      scroll method on Blizzard's ScrollBox, and we never anchor to it.
--      The only things we do to it are SetAlpha / EnableMouse / EnableMouseWheel
--      on the top-level frame, which is the sanctioned suppression pattern.
--    * We build our OWN WowScrollBoxList + MinimalScrollBar parented to
--      UIParent and overlay it on the list area. All data provider work
--      happens on our frame.
--    * Friend cards are Blizzard's own FriendsListSocialCardTemplate driven by
--      Blizzard's own Initialize(node), so card visuals stay native. Only the
--      group headers are ours.
--    * No custom keys are ever written onto a Blizzard frame table -- all
--      per-frame state lives in the external weak-keyed FFD table.
--
--  Group membership is stored inside the Blizzard friend note as ||EUI:Name||
--  (identical to the original implementation), so it travels with the BNet
--  account and survives reinstalls. The tag is stripped from every display
--  path and from the Set Note popup, so the user never sees it.
-------------------------------------------------------------------------------
local ADDON_NAME = ...

-- 12.1 ONLY. On a 12.0 client the Social UI does not exist and the legacy
-- friends list is the one that ships; running any of this there would create
-- an orphan scroll box over the old frame.
if not (EllesmereUI and EllesmereUI.IS_121) then return end

local EG = EllesmereUI.ELLESMERE_GREEN

-- External weak-keyed lookup table for frame state. Never write custom keys
-- onto a frame table we did not create.
local FFD = setmetatable({}, { __mode = "k" })
local function GetFFD(frame)
    local d = FFD[frame]
    if not d then d = {}; FFD[frame] = d end
    return d
end

local MEDIA = "Interface\\AddOns\\EllesmereUI\\media\\"

-------------------------------------------------------------------------------
--  Global storage (account-wide, deliberately outside the profile system so
--  group layout is never carried by profile import/export)
-------------------------------------------------------------------------------
local ORDER_FAVORITES = "_favorites"
local ORDER_UNGROUPED = "_ungrouped"
local FAVORITES_KEY   = "Favorites"   -- internal bucket key, never displayed

local function GetFriendGroupsGlobal()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.global then EllesmereUIDB.global = {} end
    local g = EllesmereUIDB.global
    if not g.friendGroups then g.friendGroups = {} end
    -- Membership: battleTag -> group name. Keyed by battleTag because it is
    -- stable across sessions (bnetAccountID is not) and readable while the
    -- friend is offline.
    if not g.friendGroupsByTag then g.friendGroupsByTag = {} end
    if g.friendFavCollapsed == nil then g.friendFavCollapsed = false end
    if g.friendUngroupedCollapsed == nil then g.friendUngroupedCollapsed = false end
    if not g.friendGroupColors then g.friendGroupColors = {} end
    if not g.friendGroupOrder then g.friendGroupOrder = {} end
    return g
end

-- Validate/rebuild the full group order so it contains every group exactly
-- once. Preserves the user's existing order, drops stale entries, appends
-- anything missing (Favorites first, custom groups next, ungrouped last).
local function GetValidGroupOrder()
    local fg = GetFriendGroupsGlobal()
    local order = fg.friendGroupOrder

    local needed = {}
    needed[ORDER_FAVORITES] = true
    needed[ORDER_UNGROUPED] = true
    for _, g in ipairs(fg.friendGroups) do
        needed[g.name] = true
    end

    local clean, seen = {}, {}
    for _, key in ipairs(order) do
        if needed[key] and not seen[key] then
            clean[#clean + 1] = key
            seen[key] = true
        end
    end

    if not seen[ORDER_FAVORITES] then
        table.insert(clean, 1, ORDER_FAVORITES)
        seen[ORDER_FAVORITES] = true
    end
    for _, g in ipairs(fg.friendGroups) do
        if not seen[g.name] then
            local ungroupedIdx
            for i, k in ipairs(clean) do
                if k == ORDER_UNGROUPED then ungroupedIdx = i; break end
            end
            if ungroupedIdx then
                table.insert(clean, ungroupedIdx, g.name)
            else
                clean[#clean + 1] = g.name
            end
            seen[g.name] = true
        end
    end
    if not seen[ORDER_UNGROUPED] then
        clean[#clean + 1] = ORDER_UNGROUPED
        seen[ORDER_UNGROUPED] = true
    end

    fg.friendGroupOrder = clean
    return clean
end

-------------------------------------------------------------------------------
--  Profile settings bridge
-------------------------------------------------------------------------------
local function FriendsDB()
    local db = _G._EFR_DB
    return db and db.profile and db.profile.friends
end

-- TEMPORARY BISECT FLAGS. Confirmed so far: with the overlay off entirely,
-- whispers are clean -- so the cause is inside the overlay. But turning the
-- overlay off also removes the tile decoration, so that test could not tell
-- ROW CREATION/POPULATION apart from DECORATION.
--
-- FORCE_PLAIN_TILES keeps the grouped list but skips every decoration pass:
-- rows are created and populated by FriendsFrame_UpdateFriendButton and then
-- left completely stock. No CreateTexture, no HookScript, no writes to
-- Blizzard's FontStrings.
--
--   still tainted -> creating/populating the row is the cause (row.id written
--                    from our execution), and only the node-move rewrite fixes it
--   clean         -> a decoration call is the cause, the architecture is fine,
--                    and we bisect which one
--
-- BOTH SHOULD BE false FOR NORMAL OPERATION.
-- Left OFF deliberately. Every renderer we can build taints BNet whispers on
-- 12.1 (see the bisect table below); until that is solved this module must not
-- render. Flip to false to resume experimenting.
local FORCE_GROUPS_OFF  = true
local FORCE_PLAIN_TILES = true

-- Renderer selection. OVERLAY is the original design (our ScrollBox, our rows)
-- and is PROVEN to break BNet whispers on 12.1 -- kept only so the two can be
-- compared, never for shipping. REGROUP re-parents Blizzard's own nodes and
-- leaves every row to Blizzard.
local USE_OVERLAY_RENDERER = false

local function GroupsEnabled()
    if FORCE_GROUPS_OFF then return false end
    local f = FriendsDB()
    if not f then return false end
    if f.enabled == false then return false end
    return f.groupsEnabled ~= false
end

local function ShowUngrouped()
    local f = FriendsDB()
    return not f or f.showUngrouped ~= false
end

local function UseAccentColors()
    local f = FriendsDB()
    return not f or f.accentColors ~= false
end

local function AccentRGB()
    if UseAccentColors() and EllesmereUI.GetAccentColor then
        local r, g, b = EllesmereUI.GetAccentColor()
        if r then return r, g, b end
    end
    return EG.r, EG.g, EG.b
end

local function FontPath()
    return (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("friends")) or STANDARD_TEXT_FONT
end

-------------------------------------------------------------------------------
--  Legacy note tag:  ||EUI:GroupName||
--
--  READ ONLY. The pre-7.4.3 implementation stored group membership inside the
--  Blizzard friend note, which meant re-appending the tag whenever the user
--  edited a note -- and the only way to catch that was to overwrite the global
--  BNSetFriendNote and to write into StaticPopupDialogs. Both are permanent
--  variable taints: every secure Blizzard read of them marks that execution as
--  ours, and the chat pipeline (SetTellTarget on a secret whisper target) is
--  what breaks. Membership now lives in our own SavedVariables; this parser
--  survives only to strip stale tags out of notes we DISPLAY, and to migrate
--  anyone who still has them.
-------------------------------------------------------------------------------
local EUI_NOTE_TAG = "||EUI:"
local EUI_NOTE_END = "||"

local function ParseGroupFromNote(note)
    if not note or note == "" then return nil, note end
    local tagStart = note:find(EUI_NOTE_TAG, 1, true)
    if not tagStart then return nil, note end
    local groupStart = tagStart + #EUI_NOTE_TAG
    local tagEnd = note:find(EUI_NOTE_END, groupStart, true)
    if not tagEnd then return nil, note end
    local group = note:sub(groupStart, tagEnd - 1)
    local clean = note:sub(1, tagStart - 1)
    clean = clean:match("^(.-)%s*$") or clean
    if group == "" then return nil, clean end
    return group, clean
end

-- Exposed so the main Friends module can strip the tag out of any note it
-- renders on a card without duplicating the parser.
EllesmereUI.FriendsParseGroupNote = ParseGroupFromNote

-------------------------------------------------------------------------------
--  Group mutation helpers
-------------------------------------------------------------------------------
local RebuildGroups  -- forward declaration

-- Set to a bnetAccountID to flash that friend briefly after the next rebuild
-- (used after a group assignment). Flash only -- we never move the scroll.
local flashBnetID = nil

-- Membership read/write. Pure SavedVariables: we never call BNSetFriendNote,
-- so no Blizzard global or table is written and the chat pipeline stays clean.
-- Empty-string guard, not just nil: "" would be a single shared key, so two
-- tag-less accounts would end up in each other's group. Bailing means such a
-- friend simply stays ungrouped, which fails visibly instead of silently.
local function GetFriendGroup(accountInfo)
    local tag = accountInfo and accountInfo.battleTag
    if not tag or tag == "" then return nil end
    return GetFriendGroupsGlobal().friendGroupsByTag[tag]
end

local function SetFriendGroupByTag(battleTag, groupName)
    if not battleTag or battleTag == "" then return end
    GetFriendGroupsGlobal().friendGroupsByTag[battleTag] = groupName
end

-- One-time lift of the legacy in-note tags into our own store, so anyone who
-- used the pre-7.4.3 feature keeps their groups. Read-only on Blizzard's side:
-- the stale tag stays in the note text and is stripped at display time.
local function MigrateLegacyNoteTags()
    local g = GetFriendGroupsGlobal()
    if g.friendGroupsTagMigrated then return end
    g.friendGroupsTagMigrated = true

    local known = {}
    for _, grp in ipairs(g.friendGroups) do known[grp.name] = true end

    local total = BNGetNumFriends and BNGetNumFriends() or 0
    for i = 1, total do
        local info = C_BattleNet and C_BattleNet.GetFriendAccountInfo(i)
        if info and info.battleTag and info.note then
            local grp = ParseGroupFromNote(info.note)
            if grp and known[grp] and not g.friendGroupsByTag[info.battleTag] then
                g.friendGroupsByTag[info.battleTag] = grp
            end
        end
    end
end

local function GroupExists(name)
    local fg = GetFriendGroupsGlobal()
    for _, g in ipairs(fg.friendGroups) do
        if g.name == name then return true end
    end
    return false
end

local function CreateGroup(name, assignTag, assignBnetID)
    if not name or name == "" then return end
    if GroupExists(name) then return end
    local fg = GetFriendGroupsGlobal()
    fg.friendGroups[#fg.friendGroups + 1] = { name = name, collapsed = false }
    if assignTag then
        SetFriendGroupByTag(assignTag, name)
        flashBnetID = assignBnetID
    end
    RebuildGroups("direct")
end

local function RenameGroup(oldName, newName)
    if not oldName or not newName or newName == "" or newName == oldName then return end
    if GroupExists(newName) then return end
    local fg = GetFriendGroupsGlobal()
    for _, g in ipairs(fg.friendGroups) do
        if g.name == oldName then g.name = newName; break end
    end
    -- Carry the group color and the position in the order list across.
    if fg.friendGroupColors[oldName] then
        fg.friendGroupColors[newName] = fg.friendGroupColors[oldName]
        fg.friendGroupColors[oldName] = nil
    end
    for i, key in ipairs(fg.friendGroupOrder) do
        if key == oldName then fg.friendGroupOrder[i] = newName; break end
    end
    -- Repoint every member. Pure table work -- no Blizzard call at all.
    for tag, grp in pairs(fg.friendGroupsByTag) do
        if grp == oldName then fg.friendGroupsByTag[tag] = newName end
    end
    RebuildGroups("direct")
end

local function DeleteGroup(name)
    if not name then return end
    local fg = GetFriendGroupsGlobal()
    for i = #fg.friendGroups, 1, -1 do
        if fg.friendGroups[i].name == name then
            table.remove(fg.friendGroups, i)
            break
        end
    end
    -- Members fall back to ungrouped.
    for tag, grp in pairs(fg.friendGroupsByTag) do
        if grp == name then fg.friendGroupsByTag[tag] = nil end
    end
    fg.friendGroupColors[name] = nil
    for i = #fg.friendGroupOrder, 1, -1 do
        if fg.friendGroupOrder[i] == name then table.remove(fg.friendGroupOrder, i) end
    end
    RebuildGroups("direct")
end

-------------------------------------------------------------------------------
--  Popups (EllesmereUI native -- never Blizzard StaticPopup)
-------------------------------------------------------------------------------
local function PromptNewGroup(assignTag, assignBnetID)
    if not EllesmereUI.ShowInputPopup then return end
    EllesmereUI:ShowInputPopup({
        title       = "New Friend Group",
        message     = "Enter a name for the new group:",
        placeholder = "Enter name...",
        confirmText = "Create",
        cancelText  = "Cancel",
        onConfirm   = function(text)
            local name = text and strtrim(text) or ""
            if name == "" then return end
            CreateGroup(name, assignTag, assignBnetID)
        end,
    })
end

local function PromptRenameGroup(oldName)
    if not EllesmereUI.ShowInputPopup then return end
    EllesmereUI:ShowInputPopup({
        title       = "Rename Friend Group",
        message     = "Enter a new name for this group:",
        initialText = oldName,
        placeholder = oldName,
        confirmText = "Rename",
        cancelText  = "Cancel",
        onConfirm   = function(text)
            local name = text and strtrim(text) or ""
            if name == "" then return end
            RenameGroup(oldName, name)
        end,
    })
end

local function PromptDeleteGroup(name)
    if not EllesmereUI.ShowConfirmPopup then return end
    EllesmereUI:ShowConfirmPopup({
        title       = "Delete Friend Group",
        message     = format("Delete group \"%s\"?\nFriends in this group will be moved to the default list.", name),
        confirmText = "Delete",
        cancelText  = "Cancel",
        onConfirm   = function() DeleteGroup(name) end,
    })
end

-------------------------------------------------------------------------------
--  Group assignment menu (OURS -- never Blizzard's unit popup)
--
--  We deliberately do NOT use Menu.ModifyMenu on MENU_UNIT_BN_FRIEND. That menu
--  carries Whisper, and in 12.1 the whisper target is a secret value: opening
--  it from, or extending it with, addon code makes SetTellTarget fail. This is
--  a self-contained context menu raised from our own tile, containing only our
--  own insecure actions, so it can never sit on the chat path.
-------------------------------------------------------------------------------
local function OpenGroupMenu(anchorFrame, accountInfo)
    if not (accountInfo and accountInfo.battleTag) then return end
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    if not GroupsEnabled() then return end

    local tag     = accountInfo.battleTag
    local bnetID  = accountInfo.bnetAccountID
    local current = GetFriendGroup(accountInfo)
    local fg      = GetFriendGroupsGlobal()

    MenuUtil.CreateContextMenu(anchorFrame, function(_owner, root)
        local ar, ag, ab = AccentRGB()
        root:CreateTitle(format("|cff%02x%02x%02x%s|r", ar * 255, ag * 255, ab * 255,
            "EUI Friend Groups"))

        -- Favorites are Blizzard's own bucket and always render there.
        if accountInfo.isFavorite then
            root:CreateTitle("Favorites are managed by Battle.net")
            return
        end

        local addLabel = current and "Move to Group" or "Add to Group"
        local addTo = root:CreateButton(addLabel)
        addTo:CreateButton("|cff00ff00+|r Add New Group", function()
            PromptNewGroup(tag, bnetID)
        end)
        if #fg.friendGroups > 0 then
            addTo:CreateDivider()
            for _, gName in ipairs(GetValidGroupOrder()) do
                if gName ~= ORDER_FAVORITES and gName ~= ORDER_UNGROUPED and gName ~= current then
                    addTo:CreateButton(gName, function()
                        SetFriendGroupByTag(tag, gName)
                        flashBnetID = bnetID
                        RebuildGroups("direct")
                    end)
                end
            end
        end

        local removeBtn = root:CreateButton("Remove from Group", function()
            SetFriendGroupByTag(tag, nil)
            RebuildGroups("direct")
        end)
        if not current then removeBtn:SetEnabled(false) end
    end)
end

-------------------------------------------------------------------------------
--  Group header row (the EUI divider)
--
--  Layout, colors and sizes are a 1:1 match of the original implementation:
--     Favorites / Friends:  up ---- Label ---- down
--     Custom group:         up edit ---- Label ---- close down
-------------------------------------------------------------------------------
local DIV_H           = 24
local DIV_LABEL_SIZE  = 12
local DIV_ICON_SZ     = 14
-- Header bar fill: white at 8%, so it lifts off the panel instead of sitting
-- as an opaque slab the way the live divider did.
local DIV_BG_R, DIV_BG_G, DIV_BG_B, DIV_BG_A = 1, 1, 1, 0.04
local DIV_ICON_ALPHA  = 0.35
local DIV_ICON_HOVER  = 0.7
local DIV_ICON_OFF    = 0.06

-- One physical pixel in a frame's OWN coordinate space. SetHeight(1) is one UI
-- unit, not one pixel, so the divider lines render fat or blurry depending on
-- resolution and UI scale. PanelPP.mult is the wrong multiplier here: that is
-- options-panel units, and these frames run at UIParent scale, where it lands
-- between 1 and 2 physical pixels. PP.perfect (1 physical px at scale 1)
-- divided by the frame's effective scale is exact at any scale.
local function PhysPx(frame)
    local PP = EllesmereUI.PP
    local es = frame and frame.GetEffectiveScale and frame:GetEffectiveScale()
    if PP and PP.perfect and es and es > 0 then
        return PP.perfect / es
    end
    return (PP and PP.mult) or 1
end

local function MakeDividerIcon(parent, texture)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(DIV_ICON_SZ, DIV_ICON_SZ)
    btn:SetFrameLevel(parent:GetFrameLevel() + 2)
    local icon = btn:CreateTexture(nil, "OVERLAY")
    icon:SetAllPoints()
    icon:SetTexture(MEDIA .. "icons\\" .. texture)
    btn:SetAlpha(DIV_ICON_ALPHA)
    btn:SetScript("OnEnter", function(s) s:SetAlpha(DIV_ICON_HOVER) end)
    btn:SetScript("OnLeave", function(s) s:SetAlpha(DIV_ICON_ALPHA) end)
    return btn
end

local function BuildDivider(btn)
    local d = GetFFD(btn)
    if d.divSetup then return d end
    d.divSetup = true

    local hl = btn:GetHighlightTexture()
    if hl then hl:SetAlpha(0) end

    d.bg = btn:CreateTexture(nil, "BACKGROUND")
    d.bg:SetAllPoints()
    d.bg:SetColorTexture(DIV_BG_R, DIV_BG_G, DIV_BG_B, DIV_BG_A)

    d.label = btn:CreateFontString(nil, "OVERLAY")
    if EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(d.label, true) end
    d.label:SetFont(FontPath(), DIV_LABEL_SIZE, "")
    d.label:SetPoint("CENTER", btn, "CENTER", 0, 0)

    d.up   = MakeDividerIcon(btn, "eui-arrow-up3.png")
    d.down = MakeDividerIcon(btn, "eui-arrow-down3.png")
    d.x    = MakeDividerIcon(btn, "eui-close.png")
    d.edit = MakeDividerIcon(btn, "eui-edit.png")

    d.lineL = btn:CreateTexture(nil, "OVERLAY")
    d.lineL:SetColorTexture(1, 1, 1, 0.1)
    d.lineR = btn:CreateTexture(nil, "OVERLAY")
    d.lineR:SetColorTexture(1, 1, 1, 0.1)
    -- Height comes from PhysPx, re-applied per init so a UI-scale change is
    -- picked up on the next rebuild.

    d.hover = btn:CreateTexture(nil, "ARTWORK", nil, -5)
    d.hover:SetAllPoints()
    d.hover:SetColorTexture(1, 1, 1, 0.06)
    d.hover:Hide()

    btn:EnableMouse(true)
    btn:SetScript("OnEnter", function() d.hover:Show() end)
    btn:SetScript("OnLeave", function() d.hover:Hide() end)

    -- Transparent hit area over the label so a click there opens the color
    -- picker instead of toggling collapse.
    d.labelBtn = CreateFrame("Button", nil, btn)
    d.labelBtn:SetHeight(DIV_H)
    d.labelBtn:SetFrameLevel(btn:GetFrameLevel() + 3)

    return d
end

-- Read the saved collapsed state for a bucket key.
local function IsGroupCollapsed(groupKey)
    local fg = GetFriendGroupsGlobal()
    if groupKey == FAVORITES_KEY then
        return fg.friendFavCollapsed and true or false
    elseif groupKey == false then
        return fg.friendUngroupedCollapsed and true or false
    end
    for _, g in ipairs(fg.friendGroups) do
        if g.name == groupKey then return g.collapsed and true or false end
    end
    return false
end

local function ToggleGroupCollapsed(groupKey)
    local fg = GetFriendGroupsGlobal()
    if groupKey == FAVORITES_KEY then
        fg.friendFavCollapsed = not fg.friendFavCollapsed
    elseif groupKey == false then
        fg.friendUngroupedCollapsed = not fg.friendUngroupedCollapsed
    else
        for _, g in ipairs(fg.friendGroups) do
            if g.name == groupKey then g.collapsed = not g.collapsed; break end
        end
    end
end

-- Map a bucket key to the key used for color storage and order lookups.
local function ColorKeyFor(groupKey)
    if groupKey == FAVORITES_KEY then return ORDER_FAVORITES end
    if groupKey == false then return ORDER_UNGROUPED end
    return groupKey
end

local function InitDividerButton(btn, node)
    local ed = node:GetData()
    local groupKey    = ed._groupKey
    local displayName = ed._displayName or ""
    local isFavorites = (groupKey == FAVORITES_KEY)
    local isDefault   = (groupKey == false)
    local isCustom    = not isFavorites and not isDefault

    local d = BuildDivider(btn)
    btn:SetHeight(DIV_H)

    d.label:SetFont(FontPath(), DIV_LABEL_SIZE, "")
    d.label:SetText(displayName)

    local colorKey = ColorKeyFor(groupKey)
    d.colorKey = colorKey
    local fg = GetFriendGroupsGlobal()
    local gc = fg.friendGroupColors[colorKey]
    if gc then
        d.label:SetTextColor(gc.r, gc.g, gc.b, 1)
    else
        local ar, ag, ab = AccentRGB()
        d.label:SetTextColor(ar, ag, ab, 1)
    end

    -- Label click: EllesmereUI color picker for this group's header color.
    d.labelBtn:ClearAllPoints()
    d.labelBtn:SetPoint("CENTER", d.label, "CENTER", 0, 0)
    d.labelBtn:SetWidth((d.label:GetStringWidth() or 40) + 8)
    d.labelBtn:SetScript("OnClick", function()
        local ck = d.colorKey
        if not ck then return end
        -- The widgets file is deferred; make sure the picker exists.
        if EllesmereUI.EnsureLoaded then EllesmereUI:EnsureLoaded() end
        local store = GetFriendGroupsGlobal()
        local cur = store.friendGroupColors[ck]
        local cr, cg, cb
        if cur then
            cr, cg, cb = cur.r, cur.g, cur.b
        else
            cr, cg, cb = AccentRGB()
        end
        local snapR, snapG, snapB = cr, cg, cb
        EllesmereUI:ShowColorPicker({
            r = cr, g = cg, b = cb,
            hasOpacity = false,
            swatchFunc = function()
                local popup = EllesmereUI._colorPickerPopup
                if not popup then return end
                local nr, ng, nb = popup:GetColorRGB()
                store.friendGroupColors[ck] = { r = nr, g = ng, b = nb }
                RebuildGroups("direct")
            end,
            cancelFunc = function()
                store.friendGroupColors[ck] = { r = snapR, g = snapG, b = snapB }
                RebuildGroups("direct")
            end,
        }, d.labelBtn)
    end)

    -- Layout
    d.up:ClearAllPoints()
    d.down:ClearAllPoints()
    d.edit:ClearAllPoints()
    d.x:ClearAllPoints()
    d.lineL:ClearAllPoints()
    d.lineR:ClearAllPoints()

    -- Re-resolve every init: the header is pooled and the user can change UI
    -- scale between rebuilds.
    local hairline = PhysPx(btn)
    d.lineL:SetHeight(hairline)
    d.lineR:SetHeight(hairline)

    d.up:Show()
    d.down:Show()

    if isCustom then
        -- up edit ---- Label ---- close down
        d.x:Show()
        d.edit:Show()
        d.up:SetPoint("LEFT", btn, "LEFT", 8, 0)
        d.edit:SetPoint("LEFT", d.up, "RIGHT", 4, 0)
        d.down:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
        d.x:SetPoint("RIGHT", d.down, "LEFT", -4, 0)
        d.lineL:SetPoint("LEFT", d.edit, "RIGHT", 6, 0)
        d.lineL:SetPoint("RIGHT", d.label, "LEFT", -6, 0)
        d.lineR:SetPoint("LEFT", d.label, "RIGHT", 6, 0)
        d.lineR:SetPoint("RIGHT", d.x, "LEFT", -6, 0)
    else
        -- up ---- Label ---- down
        d.x:Hide()
        d.edit:Hide()
        d.up:SetPoint("LEFT", btn, "LEFT", 8, 0)
        d.down:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
        d.lineL:SetPoint("LEFT", d.up, "RIGHT", 6, 0)
        d.lineL:SetPoint("RIGHT", d.label, "LEFT", -6, 0)
        d.lineR:SetPoint("LEFT", d.label, "RIGHT", 6, 0)
        d.lineR:SetPoint("RIGHT", d.down, "LEFT", -6, 0)
    end

    -- Click the bar to collapse/expand.
    btn:SetScript("OnClick", function()
        ToggleGroupCollapsed(groupKey)
        RebuildGroups("direct")
    end)

    if isCustom then
        d.x:SetScript("OnClick", function() PromptDeleteGroup(groupKey) end)
        d.edit:SetScript("OnClick", function() PromptRenameGroup(groupKey) end)
    else
        d.x:SetScript("OnClick", nil)
        d.edit:SetScript("OnClick", nil)
    end

    -- Reordering. Arrows at the boundary of the order are dimmed and inert,
    -- but keep mouse enabled so they still swallow the click instead of
    -- falling through to the collapse toggle underneath.
    local orderKey = ColorKeyFor(groupKey)
    local isFirst  = ed._isFirstGroup
    local isLast   = ed._isLastGroup

    if isFirst then
        d.up:SetAlpha(DIV_ICON_OFF)
        d.up:SetScript("OnEnter", nil)
        d.up:SetScript("OnLeave", nil)
    else
        d.up:SetAlpha(DIV_ICON_ALPHA)
        d.up:EnableMouse(true)
        d.up:SetScript("OnEnter", function(s) s:SetAlpha(DIV_ICON_HOVER) end)
        d.up:SetScript("OnLeave", function(s) s:SetAlpha(DIV_ICON_ALPHA) end)
    end
    if isLast then
        d.down:SetAlpha(DIV_ICON_OFF)
        d.down:SetScript("OnEnter", nil)
        d.down:SetScript("OnLeave", nil)
    else
        d.down:SetAlpha(DIV_ICON_ALPHA)
        d.down:EnableMouse(true)
        d.down:SetScript("OnEnter", function(s) s:SetAlpha(DIV_ICON_HOVER) end)
        d.down:SetScript("OnLeave", function(s) s:SetAlpha(DIV_ICON_ALPHA) end)
    end

    d.up:SetScript("OnClick", function()
        if isFirst then return end
        local order = GetValidGroupOrder()
        for idx, k in ipairs(order) do
            if k == orderKey and idx > 1 then
                order[idx], order[idx - 1] = order[idx - 1], order[idx]
                RebuildGroups("direct")
                break
            end
        end
    end)
    d.down:SetScript("OnClick", function()
        if isLast then return end
        local order = GetValidGroupOrder()
        for idx, k in ipairs(order) do
            if k == orderKey and idx < #order then
                order[idx], order[idx + 1] = order[idx + 1], order[idx]
                RebuildGroups("direct")
                break
            end
        end
    end)
end

-------------------------------------------------------------------------------
--  Friend tile skin
--
--  Renders the live (v8.6.4) EllesmereUI tile look on top of Blizzard's 12.1
--  social card. We keep their card as the container so the right-hand action
--  buttons (Party / RAF Summon), the context menu and the tooltip stay fully
--  native -- that is the one intentional visual change from live. Everything
--  else (tile background, faction wash, class icon, two-line text, status orb,
--  region icon, hover and selection bars) is drawn by us and matches live
--  colour for colour.
-------------------------------------------------------------------------------
-- Row height. Live is 34 (Blizzard's FRIENDS_BUTTON_NORMAL_HEIGHT); we run a
-- little taller so the two text lines breathe on the 12.1 card. Tune here --
-- the class icon, region icon and faction wash all derive from this.
local TILE_H = 42

-- Text block geometry. The info line and the status orb are both anchored off
-- the name, so TILE_TEXT_X shifts all three together and is the only knob
-- needed to move the block horizontally. Live runs 12/9 at x=34.
local TILE_TEXT_X    = TILE_H + 4   -- left inset of the name (clears the class icon)
local TILE_TEXT_Y    = -4   -- top inset of the name
local TILE_NAME_SIZE = 13
local TILE_INFO_SIZE = 10
local TILE_LINE_GAP  = -3   -- name baseline to info line

-- modern_blizz is the same atlas the EUI window shells use; MB_* is its
-- standard crop. It backs two effects here, each masked by a different fade
-- so they read differently: the online backdrop and the hover bar.
local MODERN_BLIZZ_TEX = "Interface\\AddOns\\EllesmereUI\\media\\modern_blizz.png"
local TEX_BASE         = "Interface\\AddOns\\EllesmereUI\\media\\textures\\"
local MB_L, MB_R, MB_T, MB_B = 0.25, 1, 0, 0.75

-- Online-only gradient backdrop. Swap the mask to gradient-rl.tga to run the
-- fade the other way.
local TILE_ONLINE_BG_TEX   = MODERN_BLIZZ_TEX
local TILE_ONLINE_MASK_TEX = TEX_BASE .. "gradient-light.tga"
local TILE_ONLINE_BG_ALPHA = 0.3

-- Hover bar. Same atlas, masked by fade-right so the highlight falls away
-- across the tile rather than filling it edge to edge.
local TILE_HOVER_TEX      = MODERN_BLIZZ_TEX
local TILE_HOVER_MASK_TEX = TEX_BASE .. "fade-right.tga"
local TILE_HOVER_ALPHA    = 0.2

local OFFLINE_ICON = "Interface\\AddOns\\EllesmereUIFriends\\Media\\offline.png"
local FACTION_TEX_ALLIANCE = "Interface\\AddOns\\EllesmereUIFriends\\Media\\alliance.png"
local FACTION_TEX_HORDE    = "Interface\\AddOns\\EllesmereUIFriends\\Media\\horde.png"
local FACTION_TEX_NEUTRAL  = "Interface\\AddOns\\EllesmereUIFriends\\Media\\neutral.png"

local CLASS_ICON_SPRITE_BASE = "Interface\\AddOns\\EllesmereUI\\media\\icons\\class-full\\"
local CLASS_ICON_SPRITE_TEX = {}
for _, style in ipairs({ "modern", "dark", "light", "clean" }) do
    CLASS_ICON_SPRITE_TEX[style] = CLASS_ICON_SPRITE_BASE .. style .. ".tga"
end
local CLASS_SPRITE_COORDS = {
    WARRIOR     = { 0,     0.125, 0,     0.125 },
    MAGE        = { 0.125, 0.25,  0,     0.125 },
    ROGUE       = { 0.25,  0.375, 0,     0.125 },
    DRUID       = { 0.375, 0.5,   0,     0.125 },
    EVOKER      = { 0.5,   0.625, 0,     0.125 },
    HUNTER      = { 0,     0.125, 0.125, 0.25  },
    SHAMAN      = { 0.125, 0.25,  0.125, 0.25  },
    PRIEST      = { 0.25,  0.375, 0.125, 0.25  },
    WARLOCK     = { 0.375, 0.5,   0.125, 0.25  },
    PALADIN     = { 0,     0.125, 0.25,  0.375 },
    DEATHKNIGHT = { 0.125, 0.25,  0.25,  0.375 },
    MONK        = { 0.25,  0.375, 0.25,  0.375 },
    DEMONHUNTER = { 0.375, 0.5,   0.25,  0.375 },
}

local MINI_DISPLAY = {
    namerica = "North America", samerica = "South America",
    australia = "Australia", europe = "Europe",
    russia = "Russia", korea = "Korea",
    taiwan = "Taiwan", china = "China",
}

-- Status orb: first cell of the loot-roll reveal sheet, same crop as live.
local _orbFile, _orbL, _orbR, _orbT, _orbB
do
    local orbInfo = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("lootroll-animreveal-a")
    if orbInfo and orbInfo.file then
        _orbFile = orbInfo.file
        local aL = orbInfo.leftTexCoord or 0
        local aR = orbInfo.rightTexCoord or 1
        local aT = orbInfo.topTexCoord or 0
        local aB = orbInfo.bottomTexCoord or 1
        local aW, aH = aR - aL, aB - aT
        _orbL, _orbR, _orbT, _orbB = aL, aL + aW / 6, aT, aT + aH / 2
    end
end

local classFileByLocalName = {}
local function BuildClassNameLookup()
    if next(classFileByLocalName) then return end
    if LOCALIZED_CLASS_NAMES_MALE then
        for token, name in pairs(LOCALIZED_CLASS_NAMES_MALE) do
            classFileByLocalName[name] = token
        end
    end
    if LOCALIZED_CLASS_NAMES_FEMALE then
        for token, name in pairs(LOCALIZED_CLASS_NAMES_FEMALE) do
            classFileByLocalName[name] = token
        end
    end
end

local function GetClassFile(accountInfo)
    local gi = accountInfo and accountInfo.gameAccountInfo
    if not gi then return nil end
    if gi.classID and gi.classID > 0 then
        local _, classFile = GetClassInfo(gi.classID)
        if classFile then return classFile end
    end
    if gi.className then
        BuildClassNameLookup()
        return classFileByLocalName[gi.className]
    end
    return nil
end

local _classColorCodes = {}
local function ClassColorCode(classFile)
    local code = _classColorCodes[classFile]
    if code then return code end
    local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if not cc then return nil end
    code = format("|cff%02x%02x%02x", cc.r * 255, cc.g * 255, cc.b * 255)
    _classColorCodes[classFile] = code
    return code
end

-- Playing this WoW project right now (drives class icon, faction wash).
local function IsSameProjectOnline(gi)
    if not (gi and gi.isOnline) then return false end
    if gi.clientProgram ~= BNET_CLIENT_WOW then return false end
    return gi.wowProjectID == WOW_PROJECT_ID or gi.wowProjectID == nil
end

local function TileState(accountInfo)
    local gi = accountInfo and accountInfo.gameAccountInfo
    if not (gi and gi.isOnline) then return "offline" end
    if IsSameProjectOnline(gi) then return "retail" end
    return "other_game"
end

-- Line 1: account name, plus the character name in parentheses class-coloured,
-- exactly as live renders it.
local function BuildTileName(accountInfo)
    local base
    if FriendsListUtil and FriendsListUtil.BuildFriendNameDisplayText then
        base = FriendsListUtil.BuildFriendNameDisplayText(accountInfo)
    else
        base = accountInfo.accountName or ""
    end

    local gi = accountInfo.gameAccountInfo
    local charName = gi and gi.characterName
    if IsSameProjectOnline(gi) and charName and charName ~= "" then
        local shown = charName
        local p = FriendsDB()
        if p and p.classColorNames then
            local classFile = GetClassFile(accountInfo)
            local code = classFile and ClassColorCode(classFile)
            if code then shown = code .. charName .. "|r" end
        end
        base = base .. " (" .. shown .. ")"
    end
    return base
end

-- Line 2: Blizzard's own location/last-online string, with the user's friend
-- note appended in grey (legacy group tag stripped) -- same as live.
local function BuildTileInfo(accountInfo)
    local text = ""
    if FriendsListUtil and FriendsListUtil.BuildLocationDisplayText then
        text = FriendsListUtil.BuildLocationDisplayText(accountInfo) or ""
    end

    -- Battle.net app users have no location string; live fills it in.
    if text == "" then
        local gi = accountInfo.gameAccountInfo
        local cp = gi and gi.clientProgram
        if gi and gi.isOnline and (cp == "App" or cp == "BSAp") then
            local locale = GetLocale()
            if locale == "enUS" or locale == "enGB" then
                text = "In App"
            else
                text = "Battle.Net"
            end
        end
    end

    local _, clean = ParseGroupFromNote(accountInfo.note)
    if clean and clean ~= "" then
        if text ~= "" then
            text = text .. "  |cff888888|  " .. clean .. "|r"
        else
            text = "|cff888888" .. clean .. "|r"
        end
    end
    return text
end

-- One-time structural build. Everything lives in FFD, never on the frame.
local function SkinCardStructure(card)
    local d = GetFFD(card)
    if d.tileSkinned then return d end
    d.tileSkinned = true

    -- Tile background, then the online gradient, then the faction wash.
    -- Sublevels 2/3/4 keep that stack explicit.
    d.tileBg = card:CreateTexture(nil, "BACKGROUND", nil, 2)
    d.tileBg:SetAllPoints()
    d.tileBg:SetColorTexture(0, 0, 0, 0.10)

    -- Online backdrop: the modern_blizz atlas faded out along gradient-lr, so
    -- it reads strongest at one edge and dissolves across the tile. The mask
    -- is attached once here -- AddMaskTexture is additive, and re-adding on
    -- every recycle would stack masks on the pooled frame.
    d.onlineBg = card:CreateTexture(nil, "BACKGROUND", nil, 3)
    d.onlineBg:SetTexture(TILE_ONLINE_BG_TEX)
    d.onlineBg:SetTexCoord(MB_L, MB_R, MB_T, MB_B)
    d.onlineBg:SetAllPoints()
    d.onlineBg:SetAlpha(TILE_ONLINE_BG_ALPHA)
    d.onlineBg:Hide()

    d.onlineMask = card:CreateMaskTexture()
    d.onlineMask:SetTexture(TILE_ONLINE_MASK_TEX, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    d.onlineMask:SetAllPoints(d.onlineBg)
    d.onlineBg:AddMaskTexture(d.onlineMask)

    d.factionBg = card:CreateTexture(nil, "BACKGROUND", nil, 4)

    -- The 2% additive wash sits under both states.
    local function MakeFill(sub)
        local fill = card:CreateTexture(nil, "ARTWORK", nil, sub)
        fill:SetAllPoints()
        fill:SetColorTexture(1, 1, 1, 0.02)
        fill:SetBlendMode("ADD")
        fill:Hide()
        return fill
    end

    -- Hover: modern_blizz atlas masked by fade-right, matching the treatment
    -- used for the online backdrop. Mask attached once -- AddMaskTexture is
    -- additive and these frames are pooled.
    d.hoverBar = card:CreateTexture(nil, "ARTWORK", nil, -7)
    d.hoverBar:SetAllPoints()
    d.hoverBar:SetTexture(TILE_HOVER_TEX)
    d.hoverBar:SetTexCoord(MB_L, MB_R, MB_T, MB_B)
    d.hoverBar:SetAlpha(TILE_HOVER_ALPHA)
    d.hoverBar:Hide()

    d.hoverMask = card:CreateMaskTexture()
    d.hoverMask:SetTexture(TILE_HOVER_MASK_TEX, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    d.hoverMask:SetAllPoints(d.hoverBar)
    d.hoverBar:AddMaskTexture(d.hoverMask)

    d.hoverFill = MakeFill(-8)

    -- Selection keeps the live group-finder bar so the two states stay
    -- visually distinct from each other.
    d.selBar = card:CreateTexture(nil, "ARTWORK", nil, -5)
    d.selBar:SetAllPoints()
    d.selBar:SetAtlas("groupfinder-highlightbar-green")
    d.selBar:SetDesaturated(true)
    d.selBar:SetVertexColor(0.4, 0.7, 1.0)
    d.selBar:SetAlpha(1)
    d.selBar:Hide()

    d.selFill = MakeFill(-6)

    card:HookScript("OnEnter", function()
        d.hoverBar:Show(); d.hoverFill:Show()
    end)
    card:HookScript("OnLeave", function()
        d.hoverBar:Hide(); d.hoverFill:Hide()
    end)

    d.classIcon = card:CreateTexture(nil, "ARTWORK", nil, 2)

    -- Text is Blizzard's own name/info FontStrings on the legacy row, restyled
    -- in place. We do NOT create our own: Blizzard's updater owns their
    -- content (status colour, level/class formatting, offline greying), and
    -- reusing them is exactly how the live module renders this same template.
    d.name = card.name or card.Name
    d.info = card.info or card.Info

    local fontPath = FontPath()
    if d.name then
        if EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(d.name, true) end
        d.name:SetFont(fontPath, TILE_NAME_SIZE, "")
        d.name:SetJustifyH("LEFT")
        d.name:SetWordWrap(false)
        d.name:ClearAllPoints()
        d.name:SetPoint("TOPLEFT", card, "TOPLEFT", TILE_TEXT_X, TILE_TEXT_Y)
    end
    if d.info then
        if EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(d.info, true) end
        d.info:SetFont(fontPath, TILE_INFO_SIZE, "")
        d.info:SetJustifyH("LEFT")
        d.info:SetWordWrap(false)
        d.info:ClearAllPoints()
        if d.name then
            d.info:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, TILE_LINE_GAP)
        end
    end

    d.orb = card:CreateTexture(nil, "OVERLAY", nil, 3)
    d.orb:SetSize(18, 18)
    if _orbFile then
        d.orb:SetTexture(_orbFile)
        d.orb:SetTexCoord(_orbL, _orbR, _orbT, _orbB)
    else
        d.orb:SetAtlas("lootroll-animreveal-a")
        d.orb:SetTexCoord(0, 1 / 6, 0, 0.5)
    end

    return d
end

-- Blizzard repopulates the legacy row on every recycle, so this runs per
-- populate rather than once. Same set the live module hides on this template.
--
-- gameIcon is faded, never hidden: UpdateTileClassIcon reads its resolved
-- texture for the "playing something else" state.
local function SuppressCardArt(card)
    if card.background then card.background:SetAlpha(0) end

    local fav = card.Favorite
    if fav then fav:SetAlpha(0) end

    local statusIcon = card.statusIcon or card.StatusIcon
    if statusIcon then statusIcon:SetAlpha(0) end

    local statusTex = card.status
    if statusTex and statusTex.IsObjectType and statusTex:IsObjectType("Texture") then
        statusTex:SetAlpha(0)
    end

    if card.gameIcon then card.gameIcon:SetAlpha(0) end

    -- Blizzard's own highlight; we draw our own hover/selection bars.
    local hl = card.GetHighlightTexture and card:GetHighlightTexture()
    if hl then hl:SetVertexColor(0, 0, 0, 0) end
end

local function UpdateTileClassIcon(card, d, accountInfo)
    local p = FriendsDB()
    if not (p and p.showClassIcons ~= false) then
        d.classIcon:Hide()
        return
    end

    local h = (card:GetHeight() or TILE_H) - 4
    if h <= 0 then d.classIcon:Hide(); return end

    local icon = d.classIcon
    local state = TileState(accountInfo)
    icon:ClearAllPoints()

    if state == "retail" then
        local inset = math.floor(h * 0.025 + 0.5)
        icon:SetPoint("LEFT", card, "LEFT", 4, 0)
        icon:SetPoint("TOP", card, "TOP", 0, -(2 + inset))
        icon:SetPoint("BOTTOM", card, "BOTTOM", 0, 2 + inset)
        local iconH = h - inset * 2
        if iconH > 0 then icon:SetWidth(iconH) end

        local classFile = GetClassFile(accountInfo)
        if not classFile then icon:Hide(); return end

        local style = p.iconStyle or "modern"
        if style == "blizzard" then
            icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
            local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
            if coords then icon:SetTexCoord(unpack(coords)) end
        else
            local coords = CLASS_SPRITE_COORDS[classFile]
            if coords then
                icon:SetTexture(CLASS_ICON_SPRITE_TEX[style] or (CLASS_ICON_SPRITE_BASE .. style .. ".tga"))
                icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
            end
        end
        icon:SetDesaturated(false)
        icon:SetAlpha(1)

    elseif state == "other_game" then
        local smallH = math.floor(h * 0.75)
        icon:SetSize(smallH, smallH)
        icon:SetPoint("LEFT", card, "LEFT", 4 + math.floor((h - smallH) / 2), 0)
        -- Blizzard resolves the per-game art onto the card's game icon.
        local src = card.GameIconHolder and card.GameIconHolder.Icon
        local tex = src and src:GetTexture()
        if tex then
            icon:SetTexture(tex)
            icon:SetTexCoord(0, 1, 0, 1)
        end
        icon:SetDesaturated(false)
        icon:SetAlpha(1)

    else
        local smallH = math.floor(h * 0.75)
        icon:SetSize(smallH, smallH)
        icon:SetPoint("LEFT", card, "LEFT", 4 + math.floor((h - smallH) / 2), 0)
        icon:SetTexture(OFFLINE_ICON)
        icon:SetTexCoord(0, 1, 0, 1)
        icon:SetDesaturated(false)
        icon:SetAlpha(0.5)
    end

    icon:Show()
end

-- Online friends get the gradient backdrop; offline tiles stay flat so the
-- list still reads at a glance.
local function UpdateTileOnlineBg(d, accountInfo)
    local gi = accountInfo.gameAccountInfo
    d.onlineBg:SetShown(gi ~= nil and gi.isOnline == true)
end

local function UpdateTileFaction(card, d, accountInfo)
    local gi = accountInfo.gameAccountInfo
    local isRetail = IsSameProjectOnline(gi)
    local factionName = gi and gi.factionName

    local p = FriendsDB()
    local showFaction = not p or p.factionBanners ~= false

    local texPath = FACTION_TEX_NEUTRAL
    if showFaction and isRetail and factionName == "Alliance" then
        texPath = FACTION_TEX_ALLIANCE
    elseif showFaction and isRetail and factionName == "Horde" then
        texPath = FACTION_TEX_HORDE
    end

    local tex = d.factionBg
    tex:SetTexture(texPath)
    tex:SetTexCoord(0, 1, 0, 1)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
    tex:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", 0, 0)
    tex:SetAlpha(0.2)
    tex:Show()
end

local function UpdateTileOrb(d, accountInfo)
    local gi = accountInfo.gameAccountInfo
    local isOnline = gi and gi.isOnline

    -- AFK/DND can arrive as secret values; never branch on them directly.
    local _isv = issecretvalue
    local rawAFK, rawDND = accountInfo.isAFK, accountInfo.isDND
    local isAFK = (not _isv or not _isv(rawAFK)) and rawAFK or false
    local isDND = (not _isv or not _isv(rawDND)) and rawDND or false

    local orb = d.orb
    orb:ClearAllPoints()
    local textW = d.name:GetStringWidth() or 0
    orb:SetPoint("TOPLEFT", d.name, "TOPLEFT", textW - 1, 2)

    if isOnline then
        if isDND then
            orb:SetVertexColor(1, 0.2, 0.2, 1)
        elseif isAFK then
            orb:SetVertexColor(1, 0.8, 0, 1)
        else
            orb:SetVertexColor(0.2, 1, 0.2, 1)
        end
    else
        orb:SetVertexColor(0.4, 0.4, 0.4, 0.6)
    end
    orb:Show()
end

local function UpdateTileRegion(card, d, accountInfo)
    local p = FriendsDB()
    if p and p.showRegionIcons == false then
        if d.regionBtn then d.regionBtn:Hide() end
        return
    end

    local myFull = EllesmereUI.GetMyFullRegion and EllesmereUI.GetMyFullRegion()
    local friendMini
    if accountInfo.gameAccountInfo and EllesmereUI.GetFriendMiniRegion then
        friendMini = EllesmereUI.GetFriendMiniRegion(accountInfo.gameAccountInfo)
    end
    local friendFull = friendMini and EllesmereUI.GetFullRegion and EllesmereUI.GetFullRegion(friendMini)

    if not (friendMini and friendFull and friendFull ~= myFull) then
        if d.regionBtn then d.regionBtn:Hide() end
        return
    end

    if not d.regionBtn then
        local rb = CreateFrame("Button", nil, card)
        rb:SetFrameLevel(card:GetFrameLevel() + 5)
        rb._tex = rb:CreateTexture(nil, "OVERLAY", nil, 7)
        rb._tex:SetAllPoints()
        rb._tex:SetAlpha(0.25)
        rb:SetScript("OnEnter", function(self)
            if EllesmereUI.ShowWidgetTooltip then
                EllesmereUI.ShowWidgetTooltip(self, self._regionLabel or "")
            end
        end)
        rb:SetScript("OnLeave", function()
            if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
        end)
        local iconH = math.floor((card:GetHeight() or TILE_H) * 0.8)
        rb:SetSize(iconH, iconH)
        -- Sits left of the native action button, mirroring how live anchors it
        -- against Blizzard's travel pass button.
        if card.PartyButton then
            rb:SetPoint("RIGHT", card.PartyButton, "LEFT", -2, 0)
        else
            rb:SetPoint("RIGHT", card, "RIGHT", -30, 0)
        end
        d.regionBtn = rb
    end

    local rb = d.regionBtn
    if rb._lastMini ~= friendMini then
        rb._lastMini = friendMini
        rb._tex:SetTexture(EllesmereUI.GetRegionIcon and EllesmereUI.GetRegionIcon(friendMini))
        rb._tex:SetTexCoord(0, 1, 0, 1)
        rb._regionLabel = MINI_DISPLAY[friendMini] or friendMini
    end
    rb:Show()
end

-- Selection uses our own bar rather than Blizzard's card-selected atlas, so
-- the highlight matches live. Declared before PaintTile, which calls it.
local function SetTileSelected(card, selected)
    local d = FFD[card]
    if not d or not d.selBar then return end
    d.selBar:SetShown(selected and true or false)
    d.selFill:SetShown(selected and true or false)
end

-- Full per-recycle paint.
--
-- Blizzard's own updater runs FIRST: it stamps buttonType/id onto the row (the
-- two fields its secure OnClick reads) and fills the name/info strings, the
-- status texture and the travel-pass button. We only decorate afterwards. We
-- never set a click handler -- the template's XML one is the whole point of
-- using this template.
local function PaintTile(card, node)
    local ed = node:GetData()
    if not ed then return end

    if FriendsFrame_UpdateFriendButton then
        FriendsFrame_UpdateFriendButton(card, ed)
    end

    -- Bisect: stop here and leave the row completely stock. The list is still
    -- grouped, so if whispers taint in this state the cause is row
    -- creation/population, not anything below.
    if FORCE_PLAIN_TILES then return end

    local accountInfo = ed.accountInfo
    if not accountInfo then return end

    local d = SkinCardStructure(card)
    SuppressCardArt(card)

    -- Blizzard populated the strings; append the friend note to the info line
    -- the way live does, from the original text so recycling cannot stack it.
    if d.info then
        -- Strip any note we appended on a previous use of this pooled row, so
        -- recycling cannot stack suffixes.
        local orig = d.info:GetText() or ""
        orig = orig:match("^(.-)  |cff888888|") or orig
        local _, clean = ParseGroupFromNote(accountInfo.note)
        if clean and clean ~= "" then
            if orig ~= "" then
                d.info:SetText(orig .. "  |cff888888|  " .. clean .. "|r")
            else
                d.info:SetText("|cff888888" .. clean .. "|r")
            end
        end
    end

    UpdateTileClassIcon(card, d, accountInfo)
    UpdateTileOnlineBg(d, accountInfo)
    UpdateTileFaction(card, d, accountInfo)
    UpdateTileOrb(d, accountInfo)
    UpdateTileRegion(card, d, accountInfo)

    -- Recycled frames can carry a stale hover. Selection follows Blizzard's
    -- own selectedFriend state, which its secure OnClick maintains.
    d.hoverBar:Hide(); d.hoverFill:Hide()
    local sel = FriendsFrame and FriendsFrame.selectedFriend == card.id
    SetTileSelected(card, sel)
end

-------------------------------------------------------------------------------
--  Friend sort priority (mirrors the original ordering rules)
--    1 = online, same WoW project      2 = online, other WoW project
--    3 = online, other Blizzard game   4 = online, Battle.net app
--    5 = offline
-------------------------------------------------------------------------------
local function GetBNetPriority(info)
    if info and info.gameAccountInfo then
        local gi = info.gameAccountInfo
        if gi.isOnline then
            if gi.clientProgram == BNET_CLIENT_WOW then
                return (gi.wowProjectID == WOW_PROJECT_ID or gi.wowProjectID == nil) and 1 or 2
            end
            local cp = gi.clientProgram
            if not cp or cp == "" or cp == "BSAp" or cp == "App" then
                return 4
            end
            return 3
        end
    end
    return 5
end

-------------------------------------------------------------------------------
--  Our own ScrollBox
--
--  Parented to UIParent and anchored to the friends view frame (never to
--  Blizzard's ScrollBox). Blizzard's list is suppressed top-level only.
-------------------------------------------------------------------------------
-- Blizzard's LEGACY friend row, not the 12.1 social card. This is a hard
-- taint requirement, not a style choice.
--
-- FriendsListSocialCardTemplate has no OnClick in XML: Blizzard wires it inside
-- a local function in their own element factory. Building the list ourselves
-- meant we had to supply the handler, ours runs tainted, and opening the
-- BN_FRIEND menu from it wrote a tainted value into the global
-- LAST_ACTIVE_CHAT_EDIT_BOX (SendBNetTell -> OpenChat -> ActivateChat ->
-- SetLastActiveWindow), which is what broke SetTellTarget on a secret whisper
-- target. Proven from a taint log, not guessed.
--
-- FriendsListButtonTemplate binds <OnClick method="OnClick"/> in XML to
-- FriendsListButtonMixin:OnClick. That is Blizzard code and stays secure no
-- matter who instantiates the frame, so the menu it opens is secure too. It
-- needs exactly two fields from us -- buttonType and id -- which is why the
-- provider seeds them. NEVER SetScript("OnClick") on these rows.
local CARD_TEMPLATE   = "FriendsListButtonTemplate"
local SPACER_TEMPLATE = "SocialUIScrollableSpacerTemplate"

local ourScrollBox, ourScrollBar, selectionBehavior
local extents  -- extent previewer instance (plain table, mixin needs no frame)

local function GetView()
    return SocialUIFrame and SocialUIFrame.FriendsList
end

local function IsSocialUIAvailable()
    return SocialUIFrame ~= nil
       and GetView() ~= nil
       and C_SocialUI ~= nil
       and C_SocialUI.IsSystemEnabled ~= nil
end

-- Fixed at the live row height. Blizzard's 12.1 card is 70-85px because it
-- shows name/level/class/location on separate lines; our tile packs the same
-- information into two lines, so it keeps the compact live proportions.
local function CardExtent()
    return TILE_H
end

local function SpacerExtent()
    if extents then
        local e = extents:GetTemplateExtent(SPACER_TEMPLATE)
        if e and e > 0 then return e end
    end
    return 2
end

local function IsHeaderNode(node)
    local data = node:GetData()
    return data ~= nil and data._euiHeader == true
end

local function IsSpacerNode(node)
    local data = node:GetData()
    return data ~= nil and data.isSpacer == true
end

-- Our overlay lives on UIParent, so it has to be lifted clear of the Social UI
-- panel. Sharing the panel's strata and relying on frame level does NOT work:
-- the pooled card frames are parented to our ScrollTarget and keep the levels
-- they were created with, so a later SetFrameLevel on the ScrollBox leaves them
-- underneath the panel's opaque background. Take the next strata up instead --
-- a strata win is absolute and needs no level arithmetic.
local STRATA_ABOVE = {
    BACKGROUND        = "LOW",
    LOW               = "MEDIUM",
    MEDIUM            = "HIGH",
    HIGH              = "DIALOG",
    DIALOG            = "FULLSCREEN",
    FULLSCREEN        = "FULLSCREEN_DIALOG",
    FULLSCREEN_DIALOG = "TOOLTIP",
    TOOLTIP           = "TOOLTIP",
}

local function TargetStrata()
    local view = GetView()
    local base = view and view:GetFrameStrata() or "MEDIUM"
    return STRATA_ABOVE[base] or "HIGH"
end

-- Strata must be settled BEFORE the scroll view acquires any frames, so this
-- runs once at creation and afterwards only when the panel actually moves.
local function SyncOverlayLayer()
    if not ourScrollBox then return end
    local want = TargetStrata()
    if ourScrollBox:GetFrameStrata() == want then return false end
    ourScrollBox:SetFrameStrata(want)
    ourScrollBar:SetFrameStrata(want)
    return true
end

local function EnsureScrollBox()
    if ourScrollBox then return true end
    local view = GetView()
    if not view then return false end
    if not (ScrollUtil and CreateScrollBoxListTreeListView and CreateTreeDataProvider) then return false end

    -- Extent previewer: Blizzard's own helper, mixed onto a plain table of
    -- ours so card heights track the user's text-size setting exactly.
    if SocialUIScrollableElementExtentPreviewerMixin then
        extents = CreateFromMixins(SocialUIScrollableElementExtentPreviewerMixin)
        extents:OnLoad()
        extents:RegisterScrollableTemplatesForExtentPreview({
            { template = CARD_TEMPLATE,
              baseHeightCalculator = FriendsListSocialCardMixin and FriendsListSocialCardMixin.GetActiveBaseHeight },
            SPACER_TEMPLATE,
        })
    end

    ourScrollBox = CreateFrame("Frame", nil, UIParent, "WowScrollBoxList")
    ourScrollBar = CreateFrame("EventFrame", nil, UIParent, "MinimalScrollBar")
    ourScrollBox:Hide()
    ourScrollBar:Hide()

    -- Settle the strata now, before the view exists and before any pooled card
    -- frame is created underneath it.
    local strata = TargetStrata()
    ourScrollBox:SetFrameStrata(strata)
    ourScrollBar:SetFrameStrata(strata)
    ourScrollBox:SetFrameLevel(10)
    ourScrollBar:SetFrameLevel(11)

    -- Anchor to the dividers that bracket the list area. These are plain
    -- textures on the view frame, so placement stays exact across text-scale
    -- changes without ever referencing Blizzard's ScrollBox.
    ourScrollBox:ClearAllPoints()
    if view.TopDivider and view.BottomDivider then
        ourScrollBox:SetPoint("TOPLEFT", view.TopDivider, "TOPLEFT", 0, -5)
        ourScrollBox:SetPoint("BOTTOM", view.BottomDivider, "TOP", 0, 1)
        ourScrollBox:SetPoint("RIGHT", view, "RIGHT", -23, 0)
    else
        -- Fallback offsets derived from the Social UI template geometry.
        ourScrollBox:SetPoint("TOPLEFT", view, "TOPLEFT", 5, -58)
        ourScrollBox:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -23, 58)
    end
    ourScrollBar:ClearAllPoints()
    ourScrollBar:SetPoint("TOPLEFT", ourScrollBox, "TOPRIGHT", 5, -7)
    ourScrollBar:SetPoint("BOTTOMLEFT", ourScrollBox, "BOTTOMRIGHT", 5, 4)

    -- Live proportions, not Blizzard's: rows butt straight up against each
    -- other and against the group header, with no element spacing.
    local topPad, bottomPad, leftPad, rightPad = 2, 2, 0, 0
    local childIndent, spacing = 0, 0
    local scrollView = CreateScrollBoxListTreeListView(childIndent, topPad, bottomPad, leftPad, rightPad, spacing)

    scrollView:SetElementExtentCalculator(function(_dataIndex, node)
        if IsSpacerNode(node) then return SpacerExtent() end
        if IsHeaderNode(node) then return DIV_H end
        return CardExtent()
    end)

    scrollView:SetElementFactory(function(factory, node)
        if IsSpacerNode(node) then
            factory(SPACER_TEMPLATE)
        elseif IsHeaderNode(node) then
            factory("Button", InitDividerButton)
        else
            -- NOTE THE ABSENCE OF SetScript("OnClick"). The template binds it
            -- in XML to FriendsListButtonMixin:OnClick, which is Blizzard code
            -- and therefore secure: left-click selects, right-click opens the
            -- BN_FRIEND menu from an untainted context so Whisper still works.
            -- Setting our own handler here is exactly what broke whispers.
            -- Group assignment lives on shift-right-click via a post-hook
            -- below, which cannot retroactively taint a menu Blizzard has
            -- already built.
            factory(CARD_TEMPLATE, PaintTile)
        end
    end)

    ScrollUtil.InitScrollBoxListWithScrollBar(ourScrollBox, ourScrollBar, scrollView)

    selectionBehavior = ScrollUtil.AddSelectionBehavior(ourScrollBox,
        SelectionBehaviorFlags.Deselectable, SelectionBehaviorFlags.Intrusive)
    selectionBehavior:RegisterCallback(SelectionBehaviorMixin.Event.OnSelectionChanged,
        function(_o, elementData, selected)
            local card = ourScrollBox:FindFrame(elementData)
            if card then SetTileSelected(card, selected) end
        end, ourScrollBox)

    return true
end

-------------------------------------------------------------------------------
--  Suppression of Blizzard's list
--
--  Top-level frame only. We never touch children, and we only ever restore
--  what we ourselves disabled.
-------------------------------------------------------------------------------
local blizSuppressed = false
local savedPoints = nil   -- captured anchor set for Blizzard's ScrollBox

-- SetAlpha(0) hides a frame's children, but EnableMouse(false) does NOT
-- disable theirs -- Blizzard's invisible friend cards would keep answering
-- mouseover and firing tooltips through the gaps in our list. Moving the
-- ScrollBox off-screen kills the whole subtree's rendering and hit-testing in
-- one call, and ClearAllPoints/SetPoint on the ScrollBox itself is the one
-- category of interaction with it that is known-safe.
local function CapturePoints(frame)
    local n = frame:GetNumPoints()
    if not n or n < 1 then return nil end
    local pts = {}
    for i = 1, n do
        local point, relativeTo, relativePoint, x, y = frame:GetPoint(i)
        if not point then return nil end
        pts[#pts + 1] = { point, relativeTo, relativePoint, x, y }
    end
    return pts
end

local function RestorePoints(frame, pts)
    if not pts then return false end
    frame:ClearAllPoints()
    for _, p in ipairs(pts) do
        frame:SetPoint(p[1], p[2], p[3], p[4], p[5])
    end
    return true
end

local function SuppressBlizzardList(suppress)
    local view = GetView()
    if not view then return end
    local sb, bar = view.ScrollBox, view.ScrollBar

    if suppress then
        if blizSuppressed then return end
        blizSuppressed = true
        if sb then
            savedPoints = CapturePoints(sb)
            if savedPoints then
                sb:ClearAllPoints()
                sb:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, 10000)
            end
            -- Alpha stays as a belt-and-braces fallback for the case where
            -- the anchor capture failed and the frame is still in place.
            sb:SetAlpha(0)
            sb:EnableMouse(false)
            if sb.EnableMouseWheel then sb:EnableMouseWheel(false) end
        end
        if bar then
            bar:SetAlpha(0)
            bar:EnableMouse(false)
        end
    else
        if not blizSuppressed then return end
        blizSuppressed = false
        if sb then
            RestorePoints(sb, savedPoints)
            savedPoints = nil
            sb:SetAlpha(1)
            sb:EnableMouse(true)
            if sb.EnableMouseWheel then sb:EnableMouseWheel(true) end
        end
        if bar then
            bar:SetAlpha(1)
            bar:EnableMouse(true)
        end
    end
end

-------------------------------------------------------------------------------
--  Search / filter parity
--
--  Blizzard's own search bar and filter dropdown stay fully functional. We
--  rebuild the same allow-list they would by reading the filter state they
--  store on the view and calling the same public API.
-------------------------------------------------------------------------------
local function BuildActiveSearchInfo(view, searchText)
    local info = {
        searchText = searchText or "",
        isOnline = false, isOffline = false,
        isDND = false, isAFK = false,
        isInQueue = false, isAvailableForQueue = false,
        tags = {},
    }
    for filterOption, isChecked in pairs(view.selectedSearchFilterOptions or {}) do
        if isChecked and type(filterOption) == "table" and filterOption.searchInfo then
            local si = filterOption.searchInfo
            if si.tags then
                for _, tag in ipairs(si.tags) do
                    table.insert(info.tags, tag)
                end
            else
                for field, value in pairs(si) do
                    info[field] = info[field] or value
                end
            end
        end
    end
    return info
end

local function HasActiveFilter(view, searchText)
    if searchText and searchText ~= "" then return true end
    for _, isChecked in pairs(view.selectedSearchFilterOptions or {}) do
        if isChecked then return true end
    end
    return false
end

local function GetSearchText(view)
    local bar = view.FilterBar and view.FilterBar.SearchBar
    if not bar or not bar.GetText then return "" end
    local ok, text = pcall(bar.GetText, bar)
    if not ok then return "" end
    return text or ""
end

-------------------------------------------------------------------------------
--  Data provider build
-------------------------------------------------------------------------------
local rebuilding = false

local function BuildProvider()
    local view = GetView()
    if not view then return nil end

    MigrateLegacyNoteTags()

    local fg = GetFriendGroupsGlobal()
    local searchText = GetSearchText(view)

    -- Allow-list from Blizzard's own search API when a filter is active.
    local allowed
    if HasActiveFilter(view, searchText) and C_BattleNet and C_BattleNet.SearchFriends then
        local ok, result = pcall(C_BattleNet.SearchFriends, BuildActiveSearchInfo(view, searchText))
        if ok and type(result) == "table" then
            allowed = {}
            for _, idx in ipairs(result) do allowed[idx] = true end
        end
    end

    -- Collect and bucket.
    local total = BNGetNumFriends and BNGetNumFriends() or 0
    local friends = {}
    for i = 1, total do
        local info = C_BattleNet and C_BattleNet.GetFriendAccountInfo(i)
        if info and (not allowed or allowed[i]) then
            local group
            if info.isFavorite then
                group = FAVORITES_KEY
            else
                group = GetFriendGroup(info)
            end
            local btag = (info.battleTag or ""):lower()
            local sortName = btag:match("^(.-)#") or btag
            if sortName == "" then sortName = (info.accountName or ""):lower() end
            friends[#friends + 1] = {
                friendIndex = i,
                accountInfo = info,
                priority    = GetBNetPriority(info),
                sortName    = sortName,
                group       = group,
            }
        end
    end

    table.sort(friends, function(a, b)
        if a.priority ~= b.priority then return a.priority < b.priority end
        return a.sortName < b.sortName
    end)

    -- Any friend still pointing at a deleted group falls back to ungrouped
    -- rather than vanishing into a bucket no header renders.
    local validGroups = { [FAVORITES_KEY] = true }
    for _, g in ipairs(fg.friendGroups) do validGroups[g.name] = true end

    local buckets = {}
    for _, f in ipairs(friends) do
        local key = f.group or false
        if key and not validGroups[key] then key = false end
        if not buckets[key] then buckets[key] = {} end
        buckets[key][#buckets[key] + 1] = f
    end

    -- Ordered list of bucket keys from the saved order.
    local groupOrder = {}
    for _, key in ipairs(GetValidGroupOrder()) do
        if key == ORDER_FAVORITES then
            groupOrder[#groupOrder + 1] = FAVORITES_KEY
        elseif key == ORDER_UNGROUPED then
            groupOrder[#groupOrder + 1] = false
        else
            groupOrder[#groupOrder + 1] = key
        end
    end

    local showUngrouped = ShowUngrouped()

    -- Which groups actually render, for first/last arrow state.
    local activeGroups, activeCount = {}, 0
    for _, gKey in ipairs(groupOrder) do
        local renderable = buckets[gKey] and #buckets[gKey] > 0
        if gKey == false and not showUngrouped then renderable = false end
        if renderable then
            activeCount = activeCount + 1
            activeGroups[activeCount] = gKey
        end
    end

    local provider = CreateTreeDataProvider()

    for _, gKey in ipairs(groupOrder) do
        local bucket = buckets[gKey]
        local renderable = bucket and #bucket > 0
        if gKey == false and not showUngrouped then renderable = false end

        if renderable then
            local displayName
            if gKey == FAVORITES_KEY then
                displayName = FAVORITES or "Favorites"
            elseif gKey == false then
                displayName = FRIENDS or "Friends"
            else
                displayName = gKey
            end

            -- No spacer rows: live runs the header straight into its first
            -- tile, and one group straight into the next header.
            local subTree = provider:Insert({
                _euiHeader    = true,
                _groupKey     = gKey,
                _displayName  = displayName,
                _isFirstGroup = (activeGroups[1] == gKey),
                _isLastGroup  = (activeGroups[activeCount] == gKey),
            })

            for _, f in ipairs(bucket) do
                -- buttonType/id are the legacy row's contract with
                -- FriendsFrame_UpdateFriendButton and with its secure
                -- OnClick; accountInfo is ours, for the decoration pass.
                subTree:Insert({
                    buttonType  = FRIENDS_BUTTON_TYPE_BNET,
                    id          = f.friendIndex,
                    accountInfo = f.accountInfo,
                })
            end

            subTree:SetCollapsed(IsGroupCollapsed(gKey))
        end
    end

    return provider
end

-------------------------------------------------------------------------------
--  Regroup Blizzard's provider (the taint-safe renderer)
--
--  Established by bisect: with our overlay off, whispers are clean; with the
--  overlay on and every decoration disabled -- rows created and populated by us
--  but otherwise completely stock -- whispers still taint. So the cause is not
--  styling, it is that WE create the row and write its data. Blizzard's secure
--  OnClick reads row.id, and reading a value we wrote taints the execution that
--  opens the BN_FRIEND menu.
--
--  So we never author a row or an element table again. Blizzard's own Refresh
--  builds its provider; we only RE-PARENT the nodes it already created into
--  group sub-trees. Their data tables are untouched, their rows are created by
--  Blizzard's factory, in Blizzard's ScrollBox, with Blizzard's click handler.
--  The only tables we contribute are the header nodes, and headers never open
--  a menu.
-------------------------------------------------------------------------------
local regrouping = false

local function RegroupBlizzardProvider()
    if regrouping then return end
    if not GroupsEnabled() then return end

    local view = GetView()
    local sb = view and view.ScrollBox
    local dp = sb and sb.GetDataProvider and sb:GetDataProvider()
    if not (dp and dp.EnumerateEntireRange and dp.Insert) then return end

    regrouping = true

    -- Collect Blizzard's own friend nodes, and the sub-trees they sit in.
    local friendNodes, blizzSubTrees = {}, {}
    for _, node in dp:EnumerateEntireRange() do
        local d = node:GetData()
        if d then
            if d.accountInfo then
                friendNodes[#friendNodes + 1] = node
            elseif d.headerText and not d._euiHeader then
                blizzSubTrees[#blizzSubTrees + 1] = node
            end
        end
    end

    if #friendNodes == 0 then
        regrouping = false
        return
    end

    -- Bucket by our stored membership. Favorites stay Blizzard's bucket.
    local buckets = {}
    for _, node in ipairs(friendNodes) do
        local info = node:GetData().accountInfo
        local key
        if info.isFavorite then
            key = FAVORITES_KEY
        else
            key = GetFriendGroup(info) or false
        end
        if not buckets[key] then buckets[key] = {} end
        local b = buckets[key]
        b[#b + 1] = node
    end

    local showUngrouped = ShowUngrouped()
    local fg = GetFriendGroupsGlobal()
    local validGroups = { [FAVORITES_KEY] = true }
    for _, g in ipairs(fg.friendGroups) do validGroups[g.name] = true end

    -- Ordered bucket keys from the saved order.
    local groupOrder = {}
    for _, key in ipairs(GetValidGroupOrder()) do
        if key == ORDER_FAVORITES then
            groupOrder[#groupOrder + 1] = FAVORITES_KEY
        elseif key == ORDER_UNGROUPED then
            groupOrder[#groupOrder + 1] = false
        else
            groupOrder[#groupOrder + 1] = key
        end
    end

    -- Build our headers and move Blizzard's nodes under them.
    for _, gKey in ipairs(groupOrder) do
        local bucket = buckets[gKey]
        local renderable = bucket and #bucket > 0
        if gKey == false and not showUngrouped then renderable = false end
        if gKey and gKey ~= FAVORITES_KEY and not validGroups[gKey] then renderable = false end

        if renderable then
            local displayName
            if gKey == FAVORITES_KEY then
                displayName = FAVORITES or "Favorites"
            elseif gKey == false then
                displayName = FRIENDS or "Friends"
            else
                displayName = gKey
            end

            -- headerText is Blizzard's own key: their element factory renders
            -- it with SocialUIScrollableHeaderTemplate and wires the collapse
            -- toggle for us. _euiGroupKey is ours, read only by our decorator.
            local header = dp:Insert({
                headerText   = displayName,
                _euiHeader   = true,
                _euiGroupKey = gKey,
            })

            for _, node in ipairs(bucket) do
                header:MoveNode(node)
            end

            header:SetCollapsed(IsGroupCollapsed(gKey))
        end
    end

    -- Drop Blizzard's now-empty Favorites/Friends sub-trees and their spacers.
    for _, node in ipairs(blizzSubTrees) do
        dp:Remove(node)
    end

    regrouping = false
end

-------------------------------------------------------------------------------
--  Rebuild scheduling
--
--  Direct user actions (collapse, reorder, group edits) apply immediately.
--  Event-driven rebuilds are coalesced, because Blizzard fires several friend
--  events back-to-back during the show sequence.
-------------------------------------------------------------------------------
local rebuildScheduled = false

local function IsActive()
    if not GroupsEnabled() then return false end
    if not IsSocialUIAvailable() then return false end
    local view = GetView()
    return view ~= nil and view:IsShown()
end

-- Flash the friend that was just assigned to a group, in place. No scrolling:
-- the rebuild already retains scroll position, and forcing a second scroll on
-- top of that in the same frame produced a visible double-jump.
local function FlashPendingFriend()
    local targetID = flashBnetID
    flashBnetID = nil
    if not targetID or not ourScrollBox then return end

    C_Timer.After(0.05, function()
        if not ourScrollBox then return end
        for _, card in ourScrollBox:EnumerateFrames() do
            local ed = card.elementData
            if ed and ed.accountInfo and ed.accountInfo.bnetAccountID == targetID then
                local cd = GetFFD(card)
                if not cd.flashHL then
                    cd.flashHL = card:CreateTexture(nil, "ARTWORK", nil, -5)
                    cd.flashHL:SetAllPoints()
                    cd.flashHL:SetColorTexture(1, 1, 1, 0.12)
                end
                cd.flashHL:Show()
                C_Timer.After(1.5, function()
                    if cd.flashHL then cd.flashHL:Hide() end
                end)
                break
            end
        end
    end)
end

local function RebuildImpl()
    if rebuilding then return end
    if not IsActive() then return end

    -- Regroup renderer: Blizzard owns the ScrollBox and every row. Ask their
    -- view to rebuild and our Refresh post-hook re-parents the result. Nothing
    -- below this line runs -- no overlay, no suppression, no rows of ours.
    if not USE_OVERLAY_RENDERER then
        local view = GetView()
        if view and view.Refresh then
            view:Refresh(ScrollBoxConstants.RetainScrollPosition)
        end
        return
    end

    if not EnsureScrollBox() then return end

    -- Card extents follow the user's text-size setting; drop the cache so a
    -- scale change is picked up on the next build.
    if extents then extents:ClearTemplateExtentCache() end
    -- Only re-strata if the panel actually moved; changing strata re-bases
    -- every pooled child, so it must not happen on every routine rebuild.
    local strataChanged = SyncOverlayLayer()
    SuppressBlizzardList(true)

    -- ORDER MATTERS: show BEFORE handing over the data provider. A hidden
    -- ScrollBox has no resolved rect, so the view calculates that zero
    -- elements fit and acquires no frames -- the list renders completely
    -- blank and a later Show() does not re-acquire on its own.
    ourScrollBox:Show()
    ourScrollBar:Show()

    rebuilding = true
    local provider = BuildProvider()
    if provider then
        ourScrollBox:SetDataProvider(provider, ScrollBoxConstants.RetainScrollPosition)
    end
    rebuilding = false

    -- On the very first build the anchor rect can still be unresolved in this
    -- frame. If we ended up with no height, re-run the layout once the frame
    -- has been through a display pass.
    if strataChanged or (ourScrollBox:GetHeight() or 0) < 1 then
        C_Timer.After(0, function()
            if ourScrollBox and ourScrollBox:IsShown() then
                ourScrollBox:FullUpdate(ScrollBoxConstants.UpdateImmediately)
            end
        end)
    end

    if flashBnetID then FlashPendingFriend() end
end

RebuildGroups = function(source)
    if not IsActive() then return end
    if source == "direct" then
        RebuildImpl()
        return
    end
    if rebuildScheduled then return end
    rebuildScheduled = true
    C_Timer.After(0.05, function()
        rebuildScheduled = false
        RebuildImpl()
    end)
end

local function Teardown()
    if ourScrollBox then
        ourScrollBox:Hide()
        ourScrollBar:Hide()
    end
    SuppressBlizzardList(false)
end

-- Called when the groups toggle changes, or the module is reset.
local function ApplyGroups()
    if IsActive() then
        RebuildGroups("direct")
    else
        Teardown()
    end
end

-------------------------------------------------------------------------------
--  Wiring
-------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local FRIEND_EVENTS = {
    "BN_FRIEND_LIST_SIZE_CHANGED",
    "BN_FRIEND_INFO_CHANGED",
    "BATTLE_NET_FRIEND_TAG_ENABLED_STATUS_UPDATED",
    "SOCIAL_UI_SYSTEM_STATUS_UPDATED",
    "SOCIAL_UI_FRIENDS_LIST_SYSTEM_STATUS_UPDATED",
}

-- Blizzard gates the Social UI behind a server-side switch, so the view can
-- appear after login. Hooking is idempotent and retried on the status event.
local viewHooked = false

local function TryHookView()
    if viewHooked then return end
    local view = GetView()
    if not view then return end
    viewHooked = true

    -- Show/hide follow the view itself. HookScript is a post-hook and never
    -- replaces Blizzard's handler.
    view:HookScript("OnShow", function()
        if IsActive() then
            RebuildGroups("direct")
        else
            Teardown()
        end
    end)
    view:HookScript("OnHide", function()
        Teardown()
    end)

    -- Regroup renderer: post-hook Blizzard's own Refresh. Their provider is
    -- fully built by the time this fires, so we only ever re-parent nodes they
    -- authored. hooksecurefunc, never a replacement -- Refresh must stay
    -- Blizzard's or every row it builds becomes ours again.
    if not USE_OVERLAY_RENDERER and view.Refresh then
        hooksecurefunc(view, "Refresh", function()
            RegroupBlizzardProvider()
        end)
    end

    -- Group menu + selection sync, as a POST-hook on Blizzard's own row
    -- handler. By the time this fires Blizzard's secure OnClick has already
    -- run and already opened its menu, so nothing here can taint it -- the
    -- same mechanism FriendGroups uses on live. hooksecurefunc, never
    -- SetScript: replacing the handler would destroy the secure click that
    -- makes whispering work at all.
    --
    -- Shift-LEFT-click, not shift-right: Blizzard's handler opens its menu on
    -- any right-click regardless of modifiers, so hanging ours off right-click
    -- would open two menus at once. Left-click only selects, so it is free.
    if FriendsListButtonMixin then
        hooksecurefunc(FriendsListButtonMixin, "OnClick", function(btn, mouseButton)
            if not (ourScrollBox and ourScrollBox:IsShown()) then return end
            if mouseButton ~= "LeftButton" then return end

            if IsShiftKeyDown() then
                local node = btn.GetElementData and btn:GetElementData()
                local data = node and node.GetData and node:GetData()
                OpenGroupMenu(btn, data and data.accountInfo)
                return
            end

            -- Blizzard just moved selectedFriend; resync our bars.
            for _, row in ourScrollBox:EnumerateFrames() do
                if row.id then
                    SetTileSelected(row, FriendsFrame and FriendsFrame.selectedFriend == row.id)
                end
            end
        end)
    end

    -- Blizzard funnels BOTH the search box and every filter checkbox through
    -- OnSearchEnterPressed: the status/tag dropdown's SetSelected callback
    -- calls it directly after flipping selectedSearchFilterOptions. Hooking it
    -- is the only way to see a filter change -- the checkboxes never touch the
    -- search text, so a text hook alone misses them entirely and the list is
    -- left showing whatever the previous filter produced.
    if view.OnSearchEnterPressed then
        hooksecurefunc(view, "OnSearchEnterPressed", function()
            RebuildGroups("search")
        end)
    end

    -- Live search on top of Blizzard's enter-to-search box.
    local bar = view.FilterBar and view.FilterBar.SearchBar
    if bar and bar.HookScript then
        pcall(bar.HookScript, bar, "OnTextChanged", function()
            RebuildGroups("search")
        end)
    end

    if view:IsShown() then ApplyGroups() end
end

eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        eventFrame:UnregisterEvent("PLAYER_LOGIN")
        TryHookView()
        return
    end

    if event == "SOCIAL_UI_SYSTEM_STATUS_UPDATED"
    or event == "SOCIAL_UI_FRIENDS_LIST_SYSTEM_STATUS_UPDATED" then
        -- The friends system was turned on or off underneath us.
        TryHookView()
        ApplyGroups()
        return
    end

    -- Friend data changed; only meaningful while our list is up.
    RebuildGroups("event")
end)
eventFrame:RegisterEvent("PLAYER_LOGIN")
for _, e in ipairs(FRIEND_EVENTS) do
    -- Guarded: these events are 12.1-only and may not all exist on an older
    -- 12.1 PTR build. A missing event must not abort the whole file.
    pcall(eventFrame.RegisterEvent, eventFrame, e)
end

-- Exposed for the options page and for the module reset path.
_G._EFR_ApplyGroups   = ApplyGroups
_G._EFR_RebuildGroups = RebuildGroups

-------------------------------------------------------------------------------
--  /euifg -- diagnostic dump for the 12.1 grouping overlay
-------------------------------------------------------------------------------
SLASH_EUIFG1 = "/euifg"
SlashCmdList.EUIFG = function()
    local function say(fmt, ...)
        print("|cff0cd29fEUI Groups|r " .. string.format(fmt, ...))
    end

    local view = GetView()
    say("SocialUIFrame=%s  view=%s  viewShown=%s  hooked=%s",
        tostring(SocialUIFrame ~= nil), tostring(view ~= nil),
        tostring(view and view:IsShown()), tostring(viewHooked))
    say("groupsEnabled=%s  socialAvailable=%s  IsActive=%s",
        tostring(GroupsEnabled()), tostring(IsSocialUIAvailable()), tostring(IsActive()))

    if not ourScrollBox then
        say("our ScrollBox: NOT CREATED")
    else
        say("our ScrollBox: shown=%s  w=%.1f h=%.1f  strata=%s level=%d",
            tostring(ourScrollBox:IsShown()),
            ourScrollBox:GetWidth() or -1, ourScrollBox:GetHeight() or -1,
            tostring(ourScrollBox:GetFrameStrata()), ourScrollBox:GetFrameLevel() or -1)
        local dp = ourScrollBox:GetDataProvider()
        -- Long-form on purpose: a size of 0 is the interesting answer here and
        -- an `and/or` chain would report it as the "missing" sentinel instead.
        local size = -1
        if dp and dp.GetSize then
            size = dp:GetSize(TreeDataProviderConstants.ExcludeCollapsed)
        end
        local frames = 0
        for _ in ourScrollBox:EnumerateFrames() do frames = frames + 1 end
        say("provider nodes(visible)=%s  acquired frames=%d", tostring(size), frames)

        local st = ourScrollBox.ScrollTarget or (ourScrollBox.GetScrollTarget and ourScrollBox:GetScrollTarget())
        if st then
            say("ScrollTarget: shown=%s alpha=%.2f w=%.1f h=%.1f strata=%s level=%d",
                tostring(st:IsShown()), st:GetAlpha() or -1,
                st:GetWidth() or -1, st:GetHeight() or -1,
                tostring(st:GetFrameStrata()), st:GetFrameLevel() or -1)
        else
            say("ScrollTarget: NOT FOUND")
        end

        -- Dump the first acquired element: if the list is populated but blank,
        -- the answer is in this line.
        for _, f in ourScrollBox:EnumerateFrames() do
            local top = f:GetTop()
            say("card1: shown=%s alpha=%.2f w=%.1f h=%.1f strata=%s level=%d top=%s",
                tostring(f:IsShown()), f:GetAlpha() or -1,
                f:GetWidth() or -1, f:GetHeight() or -1,
                tostring(f:GetFrameStrata()), f:GetFrameLevel() or -1,
                top and string.format("%.1f", top) or "nil")
            local bg = f.Background
            if bg then
                say("card1.Background(blizz): shown=%s alpha=%.2f",
                    tostring(bg:IsShown()), bg:GetAlpha() or -1)
            end
            local td = FFD[f]
            if td and td.tileSkinned then
                say("card1 tile: name=%q info=%q",
                    (td.name:GetText() or ""):sub(1, 40),
                    (td.info:GetText() or ""):sub(1, 40))
                say("card1 tile: tileBg=%s faction=%s icon=%s orb=%s partyBtn=%s",
                    tostring(td.tileBg:IsShown()), tostring(td.factionBg:IsShown()),
                    tostring(td.classIcon:IsShown()), tostring(td.orb:IsShown()),
                    tostring(f.PartyButton ~= nil and f.PartyButton:IsShown()))
            else
                say("card1 tile: NOT SKINNED")
            end
            break
        end
    end

    if view then
        say("view: strata=%s level=%d", tostring(view:GetFrameStrata()), view:GetFrameLevel() or -1)
        local sb = view.ScrollBox
        if sb then
            say("blizz ScrollBox: alpha=%.2f points=%d suppressed=%s",
                sb:GetAlpha() or -1, sb:GetNumPoints() or -1, tostring(blizSuppressed))
        end
        say("TopDivider=%s BottomDivider=%s",
            tostring(view.TopDivider ~= nil), tostring(view.BottomDivider ~= nil))
    end

    local fg = GetFriendGroupsGlobal()
    say("groups=%d  order=%d  BNGetNumFriends=%d",
        #fg.friendGroups, #fg.friendGroupOrder, BNGetNumFriends and BNGetNumFriends() or -1)
end

-------------------------------------------------------------------------------
--  Options section (12.1 only; the Friends page calls this if it exists)
--
--  Returns the height consumed so the caller can continue its own layout.
-------------------------------------------------------------------------------
_G._EFR_BuildGroupsOptions = function(W, parent, yOffset)
    local y = yOffset
    local _, h

    parent._showRowDivider = true

    _, h = W:SectionHeader(parent, "FRIEND GROUPS", y);  y = y - h

    _, h = W:DualRow(parent, y,
        { type="toggle", text="Enable Friend Groups",
          tooltip="Organizes your friends list into collapsible custom groups.",
          getValue=function() local f = FriendsDB(); return f and (f.groupsEnabled ~= false) end,
          setValue=function(v)
            local f = FriendsDB(); if not f then return end
            f.groupsEnabled = v
            ApplyGroups()
            EllesmereUI:RefreshPage()
          end },
        { type="toggle", text="Show Ungrouped Section",
          tooltip="Shows the default Friends section for friends not in a custom group.",
          disabled=function()
            local f = FriendsDB()
            return not f or f.groupsEnabled == false
          end,
          disabledTooltip="Enable Friend Groups", rawTooltip=true,
          getValue=function() local f = FriendsDB(); return f and (f.showUngrouped ~= false) end,
          setValue=function(v)
            local f = FriendsDB(); if not f then return end
            f.showUngrouped = v
            RebuildGroups("direct")
          end }
    );  y = y - h

    return math.abs(y - yOffset)
end
