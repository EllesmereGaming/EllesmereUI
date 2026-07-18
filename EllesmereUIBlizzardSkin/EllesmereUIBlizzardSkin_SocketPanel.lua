--------------------------------------------------------------------------------
--  Character Sheet Socket Panel
--
--  A single bare row of socket icons in the blank strip along the bottom
--  edge of the EUI-skinned character sheet, right-aligned. Each icon is one
--  socket on a currently-equipped item:
--  filled sockets paint the gem, empty sockets paint the empty-socket texture.
--  Clicking a socket opens a flyout of socketable bag gems; clicking a gem
--  socket-sequences it into that exact socket index.
--
--  Zero cost when the sheet is closed: everything is built lazily on first
--  show, and WoW events are registered only while the panel is visible.
--  Zero taint: all UI frames are ours; Blizzard frames are HookScript-only;
--  no custom keys are written onto Blizzard-owned frames.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

-- Probe-and-fallback API locals. On Midnight/PTR some socket-session calls are
-- namespaced under C_ItemSocketInfo and some remain bare globals; resolve each
-- once here so a missing API simply yields nil (the panel stays empty).
local CIS              = _G.C_ItemSocketInfo
local GetNumSockets    = (CIS and CIS.GetNumSockets)     or _G.GetNumSockets
local ClickSocketBtn   = (CIS and CIS.ClickSocketButton) or _G.ClickSocketButton
local AcceptSocketsFn  = (CIS and CIS.AcceptSockets)   or _G.AcceptSockets
local CloseSocketFn    = (CIS and CIS.CloseSocketInfo) or _G.CloseSocketInfo
local SocketInvItem    = (CIS and CIS.SocketInventoryItem) or _G.SocketInventoryItem
local GetItemNumSockets = C_Item and C_Item.GetItemNumSockets
local GetItemGemFn     = C_Item and C_Item.GetItemGem
local GetItemStatsFn   = C_Item and C_Item.GetItemStats
local GetInfoInstant   = C_Item and C_Item.GetItemInfoInstant
local GetIconByID      = C_Item and C_Item.GetItemIconByID
local GetItemCountFn   = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
local CClear           = _G.ClearCursor
local CHasItem         = _G.CursorHasItem

-- Constants
local SIZE       = 28
local PAD        = 4
local ROW_H      = 20   -- gem flyout row height
local FLYOUT_W   = 240
local MAX_FLYOUT_ROWS = 12   -- flyout caps here; extra gems scroll with the wheel
local GEM_CLASS  = (Enum and Enum.ItemClass and Enum.ItemClass.Gem) or 3
local EMPTY_SOCKET_TEX = "Interface\\ItemSocketingFrame\\UI-EmptySocket-Prismatic"

-- Inventory slots that can carry sockets (skip Body/Relic/Tabard/Shirt).
local SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }

-- State (all plain Lua tables / our own frames -- nothing lives on Blizzard frames)
local sockets   = {}      -- ordered list of { slot, socketIndex, gemLink, emptyName }
local iconPool  = {}      -- pooled socket icon buttons
local gemCache  = {}      -- deduped bag gems: { itemID, link, tex }
local relevantItems = {}  -- itemID -> true for equipped socketed items + their gems
local gemRows   = {}      -- pooled flyout rows
local pending   = nil     -- in-flight socket action
local panel               -- the panel frame
local flyout              -- the gem flyout frame
local catcher             -- full-screen click-catcher behind the flyout
local evtFrame            -- our event frame
local built    = false
local shownEvents = false
local gemDirty = true
local pendingGemLoads = {} -- itemID -> true: bag gems whose data load we requested
local socketLoadRequested = {} -- gem itemID -> true: equipped-gem data loads we requested
local activeIcon = nil    -- icon whose flyout is currently open
local flyoutScroll = 0    -- top gem index offset when the gem list overflows MAX_FLYOUT_ROWS
local flyoutHoverMode = false -- flyout opened by hovering an empty socket (auto-closes on leave)
local ourSession = false  -- a socketing session WE opened is (or may still be) live

--------------------------------------------------------------------------------
--  Helpers
--------------------------------------------------------------------------------

-- Rarity -> border color (local copy; do not reach into CharacterSheet.lua).
local function GemBorderColor(rarity)
    if (rarity or 0) >= 3 then
        return 1.00, 0.82, 0.00, 1   -- gold
    end
    return 0.75, 0.75, 0.75, 1        -- silver
end

-- Build a short "+16 Versatility & +7 Critical Strike" summary for a gem.
local function GetGemStatText(gemLink)
    if not gemLink then return "" end
    local parts
    if GetItemStatsFn then
        local stats = GetItemStatsFn(gemLink)
        if stats then
            -- Stat keys are global-string tokens ("ITEM_MOD_HASTE_RATING_SHORT",
            -- "ITEM_MOD_VERSATILITY", ...); _G[key] is the localized stat name.
            for key, val in pairs(stats) do
                if type(key) == "string" and type(val) == "number" and val > 0
                    and key:find("^ITEM_MOD_") then
                    local name = _G[key]
                    if type(name) == "string" and name ~= "" then
                        parts = parts or {}
                        parts[#parts + 1] = "+" .. val .. " " .. name
                    end
                end
            end
        end
    end
    if parts and #parts > 0 then
        table.sort(parts)
        return table.concat(parts, " & ")
    end
    -- Fallback: the gem's own name.
    if C_Item and C_Item.GetItemInfo then
        local nm = C_Item.GetItemInfo(gemLink)
        if nm then return nm end
    end
    return "Gem"
end

-- Find the first bag slot currently holding the given gem itemID.
local function FindBagSlotForItem(itemID)
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then
        return nil
    end
    local maxBag = _G.NUM_BAG_SLOTS or 4
    for bag = 0, maxBag do
        local n = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, n do
            -- GetContainerItemID reads the slot directly and works before the
            -- item's data is cached; GetContainerItemInfo returns nil for an
            -- item this client has never seen (e.g. fresh from the mailbox).
            local id = C_Container.GetContainerItemID and C_Container.GetContainerItemID(bag, slot)
            if not id then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                id = info and info.itemID
            end
            if id == itemID then
                return bag, slot
            end
        end
    end
    return nil
end

-- Scan bags for socketable gems (lazy; only when a flyout opens with dirty cache).
local function ScanBagGems()
    for i = #gemCache, 1, -1 do gemCache[i] = nil end
    if not (C_Container and C_Container.GetContainerNumSlots
        and C_Container.GetContainerItemInfo and GetInfoInstant) then
        gemDirty = false
        return
    end
    local seen = {}
    local maxBag = _G.NUM_BAG_SLOTS or 4
    for bag = 0, maxBag do
        local n = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, n do
            -- GetContainerItemID works before the item's data is cached;
            -- GetContainerItemInfo returns nil for an item this client has
            -- never seen (e.g. a gem fresh from the mailbox), which made new
            -- gems invisible until something else forced the cache.
            local itemID = C_Container.GetContainerItemID and C_Container.GetContainerItemID(bag, slot)
            if not itemID then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                itemID = info and info.itemID
            end
            if itemID and not seen[itemID] then
                local _, _, _, _, tex, classID = GetInfoInstant(itemID)
                if classID == GEM_CLASS then
                    seen[itemID] = true
                    local link = (C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bag, slot)) or nil
                    if not link then
                        -- Data not loaded yet: request it; the row upgrades
                        -- (stat label + tooltip link) when ITEM_DATA_LOAD_RESULT
                        -- lands and the handler repopulates the flyout.
                        pendingGemLoads[itemID] = true
                        if C_Item and C_Item.RequestLoadItemDataByID then
                            C_Item.RequestLoadItemDataByID(itemID)
                        end
                    end
                    gemCache[#gemCache + 1] = {
                        itemID = itemID,
                        link   = link,
                        tex    = tex,
                    }
                end
            end
        end
    end
    gemDirty = false
end

--------------------------------------------------------------------------------
--  Socket action sequence (event-driven, no timers)
--------------------------------------------------------------------------------

local function SafeCloseSession()
    if CloseSocketFn then CloseSocketFn() end
    -- Fallback for a missing/renamed close API (the probed name is a silent
    -- no-op then, which left the session window lingering open and empty
    -- after a strip replace): hide the panel; the window's own OnHide handler
    -- ends the session. The window itself stays fully visible/interactive
    -- while it exists -- an invisible live session would block gem clicks
    -- with no way for the user to close it.
    local f = _G.ItemSocketingFrame
    if f and f:IsShown() and not InCombatLockdown() and HideUIPanel then
        HideUIPanel(f)
    end
end

local RebuildSockets   -- forward declaration
local CloseFlyout      -- forward declaration
local OpenFlyout       -- forward declaration
local MaybeCloseHoverFlyout -- forward declaration

-- Triggered from a gem-row OnClick (a genuine hardware event).
local function DoSocket(targetSlot, socketIndex, gemItemID)
    if InCombatLockdown() then
        if UIErrorsFrame then
            UIErrorsFrame:AddMessage(_G.ERR_NOT_IN_COMBAT or "Can't do that in combat.", 1, 0.1, 0.1)
        end
        return
    end
    if CHasItem and CHasItem() then return end            -- don't hijack a held item
    if ItemSocketingFrame and ItemSocketingFrame:IsShown() then
        if ourSession then
            -- Leftover window from our own previous action (the accept event
            -- never closed it): end it now so socketing is not silently dead
            -- until the user closes it by hand. Never reopen in the same
            -- click -- the old session's SOCKET_INFO_CLOSE would wipe the new
            -- pending mid-flight. The flyout stays open; the next gem click
            -- goes through cleanly.
            SafeCloseSession()
        end
        return   -- manual session: never hijack
    end
    if not SocketInvItem then return end
    pending = { slot = targetSlot, socketIndex = socketIndex, gemItemID = gemItemID, acted = false }
    ourSession = true
    SocketInvItem(targetSlot)   -- opens the LoD session; we act inside SOCKET_INFO_UPDATE
    CloseFlyout()
end

-- Runs once inside SOCKET_INFO_UPDATE after the session is ready.
local function OnSocketInfoUpdate()
    if not pending then return end
    if pending.acted then
        -- Session updates keep firing after we act (notably when the picked-up
        -- gem lands in the socket UI). If the first AcceptSockets raced ahead
        -- of the gem registering, no SOCKET_INFO_ACCEPT ever comes and the
        -- window sits open waiting for a manual Socket click -- re-issue the
        -- accept (a no-op when nothing is pending in the UI), bounded so a
        -- genuinely unacceptable state cannot loop.
        local n = pending.reaccepts or 0
        if n < 3 and AcceptSocketsFn then
            pending.reaccepts = n + 1
            AcceptSocketsFn()
        end
        return
    end
    local nSock = GetNumSockets and GetNumSockets()
    if not nSock or pending.socketIndex > nSock then
        -- Session not ready / mismatch: wait for the next update. No timer.
        return
    end
    pending.acted = true

    local bag, slot = FindBagSlotForItem(pending.gemItemID)
    if not bag then
        pending = nil
        SafeCloseSession()
        return
    end

    if C_Container and C_Container.PickupContainerItem then
        C_Container.PickupContainerItem(bag, slot)
    end
    if ClickSocketBtn then ClickSocketBtn(pending.socketIndex) end
    if CClear then CClear() end
    if AcceptSocketsFn then AcceptSocketsFn() end
    -- Do not force-close: let Blizzard own success/confirmation dialogs.
end

--------------------------------------------------------------------------------
--  Icon painting
--------------------------------------------------------------------------------

local PP = EllesmereUI and EllesmereUI.PanelPP

local function PaintFilledIcon(btn, gemLink)
    local icon = btn.icon
    -- Clear atlas / color-texture mode before applying a fileID.
    if icon.SetAtlas then icon:SetAtlas(nil) end
    icon:SetColorTexture(0, 0, 0, 0)
    icon:SetTexture(nil)
    if icon.SetVertexColor then icon:SetVertexColor(1, 1, 1, 1) end

    local tex
    if GetInfoInstant then tex = select(5, GetInfoInstant(gemLink)) end
    if (not tex) and GetIconByID then
        -- GetItemIconByID wants a numeric itemID, not a link.
        local iid = tonumber(gemLink:match("item:(%d+)"))
        if iid then tex = GetIconByID(iid) end
    end
    icon:SetTexture(tex)
    btn:SetAlpha(1)

    -- Rarity border (default silver; upgrades async once item data loads).
    local rarity = 2
    if C_Item and C_Item.GetItemInfo then
        local _, _, r = C_Item.GetItemInfo(gemLink)
        if r then rarity = r end
    end
    if PP and PP.SetBorderColor then
        PP.SetBorderColor(btn, GemBorderColor(rarity))
    end
end

local function PaintEmptyIcon(btn)
    local icon = btn.icon
    if icon.SetAtlas then icon:SetAtlas(nil) end
    icon:SetColorTexture(0, 0, 0, 0)
    icon:SetTexture(nil)
    if icon.SetVertexColor then icon:SetVertexColor(1, 1, 1, 1) end
    icon:SetTexture(EMPTY_SOCKET_TEX)
    btn:SetAlpha(0.85)
    if PP and PP.SetBorderColor then
        PP.SetBorderColor(btn, 1, 1, 1, 0.4)
    end
end

--------------------------------------------------------------------------------
--  Hovered-gem slot glow
--  Hovering a socket icon plays the standard proc glow over the equipment
--  slot button holding that gem. Modern WoW Glow is a FlipBook style: the
--  animation is a C-side AnimationGroup, so no Lua runs while it plays, and
--  the wrapper is created lazily on first hover and fully stopped + hidden
--  on leave / sheet close -- zero cost while not hovering. Taint-safe: the
--  wrapper is OUR frame (parented to CharacterFrame, like the panel); the
--  Blizzard slot button is only ever read (GetID, size, level) and used as
--  an anchor target -- never written to, reparented, or hooked.
--------------------------------------------------------------------------------
local slotGlow          -- our lazy wrapper frame
local slotButtons       -- lazy [invSlotID] = Blizzard slot button

local SLOT_BUTTON_NAMES = {
    "Head", "Neck", "Shoulder", "Chest", "Waist", "Legs", "Feet", "Wrist",
    "Hands", "Finger0", "Finger1", "Trinket0", "Trinket1", "Back",
    "MainHand", "SecondaryHand",
}

local function SlotButtonFor(slotID)
    if not slotButtons then
        slotButtons = {}
        for _, n in ipairs(SLOT_BUTTON_NAMES) do
            local b = _G["Character" .. n .. "Slot"]
            -- Keyed by the button's own inventory ID, never a hardcoded pairing.
            if b and b.GetID then slotButtons[b:GetID()] = b end
        end
    end
    return slotButtons[slotID]
end

local function StopSlotGlow()
    if not slotGlow then return end
    local G = EllesmereUI and EllesmereUI.Glows
    if G and G.StopGlow then G.StopGlow(slotGlow) end
    slotGlow:Hide()
end

local function StartSlotGlow(slotID)
    local G = EllesmereUI and EllesmereUI.Glows
    if not (G and G.StartGlow) then return end
    local slotBtn = SlotButtonFor(slotID)
    if not slotBtn then return end
    if not slotGlow then
        slotGlow = CreateFrame("Frame", nil, CharacterFrame)
    end
    slotGlow:ClearAllPoints()
    slotGlow:SetAllPoints(slotBtn)
    slotGlow:SetFrameStrata(slotBtn:GetFrameStrata())
    slotGlow:SetFrameLevel(slotBtn:GetFrameLevel() + 5)
    slotGlow:Show()
    local w, h = slotBtn:GetWidth(), slotBtn:GetHeight()
    if not w or w < 1 then w = 37 end
    if not h or h < 1 then h = w end
    -- Style 6 = Modern WoW Glow (proc-loop FlipBook).
    G.StartGlow(slotGlow, 6, w, 1, 1, 1, nil, h)
end

local function AcquireIcon(i)
    local btn = iconPool[i]
    if btn then return btn end

    btn = CreateFrame("Button", nil, panel)
    btn:SetSize(SIZE, SIZE)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(btn)
    -- Standard icon zoom: crop the baked-in dark edge ring off icon art.
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    btn.icon = icon

    if PP and PP.CreateBorder then
        PP.CreateBorder(btn, 1, 1, 1, 0.4, 1, "OVERLAY", 7)
    end

    -- Hover wash
    local hov = btn:CreateTexture(nil, "HIGHLIGHT")
    hov:SetAllPoints(btn)
    hov:SetColorTexture(1, 1, 1, 0.1)

    btn:SetScript("OnEnter", function(self)
        local rec = self.euiSock
        if not rec then return end
        -- Slot locator glow first: independent of tooltip suppression.
        StartSlotGlow(rec.slot)
        -- Hover-to-suggest: an EMPTY socket opens the gem flyout on hover so a
        -- single click on a gem sockets it (click-socket-then-click-gem doubles
        -- the clicks across a many-socket session). Filled sockets keep the
        -- explicit click -- replacing destroys the old gem. Never hijack a
        -- sticky (click-opened) flyout; re-hovering the open icon is a no-op.
        if not rec.gemLink and not InCombatLockdown() then
            local open = flyout and flyout:IsShown()
            if not (open and (activeIcon == self or not flyoutHoverMode)) then
                OpenFlyout(self, rec.slot, rec.socketIndex, true)
            end
        end
        if EllesmereUI and EllesmereUI._tooltipSuppressedByMode
            and EllesmereUI._tooltipSuppressedByMode(GameTooltip) then
            return
        end
        if rec.gemLink then
            -- Filled socket: real item tooltip (sanctioned item-tooltip surface).
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(rec.gemLink)
            GameTooltip:Show()
        else
            -- Empty socket: plain-text hint uses the EUI widget tooltip.
            if EllesmereUI and EllesmereUI.ShowWidgetTooltip then
                EllesmereUI.ShowWidgetTooltip(self,
                    (rec.emptyName or "Empty Socket") .. "\nPick a gem from the list to socket it.",
                    { anchor = "right" })
            end
        end
    end)
    btn:SetScript("OnLeave", function()
        StopSlotGlow()
        MaybeCloseHoverFlyout()
        GameTooltip:Hide()
        if EllesmereUI and EllesmereUI.HideWidgetTooltip then
            EllesmereUI.HideWidgetTooltip()
        end
    end)
    btn:SetScript("OnClick", function(self)
        local rec = self.euiSock
        if not rec then return end
        if InCombatLockdown() then
            if UIErrorsFrame then
                UIErrorsFrame:AddMessage(_G.ERR_NOT_IN_COMBAT or "Can't do that in combat.", 1, 0.1, 0.1)
            end
            return
        end
        -- Toggle: clicking the open icon again closes its flyout. A
        -- hover-opened flyout is pinned sticky instead (the natural read of
        -- clicking the socket whose suggestions are already showing).
        if activeIcon == self and flyout and flyout:IsShown() then
            if flyoutHoverMode then
                flyoutHoverMode = false
                if catcher then catcher:Show() end
                return
            end
            CloseFlyout()
            return
        end
        OpenFlyout(self, rec.slot, rec.socketIndex)
    end)

    iconPool[i] = btn
    return btn
end

--------------------------------------------------------------------------------
--  Rebuild + layout
--------------------------------------------------------------------------------

-- Best-effort empty-socket type name for an equipped item (cosmetic tooltip line).
local function ItemEmptySocketName(link)
    if not GetItemStatsFn then return nil end
    local stats = GetItemStatsFn(link)
    if not stats then return nil end
    local found
    for key in pairs(stats) do
        if type(key) == "string" and key:find("EMPTY_SOCKET") then
            if found then return nil end   -- more than one type -> ambiguous
            found = key
        end
    end
    if found then
        return _G[found] or "Empty Socket"
    end
    return nil
end

-- Read the gem itemID for a socket index straight out of the equipped item's
-- link (gem IDs are fields 3-6 of the item string). This needs no item-data
-- cache, unlike C_Item.GetItemGem, which returns nil until the GEM's own item
-- is cached and so painted filled sockets as empty on the first open after
-- login. The extra parens around select() are required: it returns every field
-- from that position onward, and a second value would become tonumber's base.
local function GemIDFromLink(link, idx)
    local itemString = link:match("item:([%-%d:]+)")
    if not itemString then return nil end
    local gid = tonumber((select(idx + 2, strsplit(":", itemString))))
    if gid and gid > 0 then return gid end
    return nil
end

RebuildSockets = function()
    for i = #sockets, 1, -1 do sockets[i] = nil end
    for k in pairs(relevantItems) do relevantItems[k] = nil end

    if GetItemNumSockets and GetItemGemFn then
        for _, slot in ipairs(SLOTS) do
            local link = GetInventoryItemLink("player", slot)
            if link then
                local num = GetItemNumSockets(link) or 0
                if num > 0 then
                    local emptyName = ItemEmptySocketName(link)
                    -- Track the equipped item's itemID so a late data-load for it
                    -- (rarity/stats) can trigger a targeted refresh.
                    if GetInfoInstant then
                        local iid = GetInfoInstant(link)
                        if iid then relevantItems[iid] = true end
                    end
                    for idx = 1, num do
                        local _, gemLink = GetItemGemFn(link, idx)
                        if not gemLink then
                            -- Uncached gem: build a bare link from the ID in the
                            -- equipped link (the icon still resolves instantly
                            -- via GetItemInfoInstant) and request the real data;
                            -- the ITEM_DATA_LOAD_RESULT rebuild then upgrades
                            -- the rarity border and tooltip. Requested at most
                            -- once per sheet-open so a failed load cannot chain
                            -- request -> result -> rebuild -> request forever.
                            local gid = GemIDFromLink(link, idx)
                            if gid then
                                gemLink = "item:" .. gid
                                if not socketLoadRequested[gid]
                                    and C_Item and C_Item.RequestLoadItemDataByID then
                                    socketLoadRequested[gid] = true
                                    C_Item.RequestLoadItemDataByID(gid)
                                end
                            end
                        end
                        if gemLink and GetInfoInstant then
                            local giid = GetInfoInstant(gemLink)
                            if giid then relevantItems[giid] = true end
                        end
                        sockets[#sockets + 1] = {
                            slot = slot,
                            socketIndex = idx,
                            gemLink = gemLink,
                            emptyName = emptyName or "Empty Socket",
                        }
                    end
                end
            end
        end
    end

    if not panel then return end

    -- Hide all pooled icons first.
    for _, btn in ipairs(iconPool) do
        btn:Hide()
        btn.euiSock = nil
    end

    local count = #sockets
    if count == 0 then
        panel:Hide()
        return
    end

    -- One row, never wraps; the panel's right edge stays pinned so the row
    -- grows leftward into the strip.
    for i, rec in ipairs(sockets) do
        local btn = AcquireIcon(i)
        btn.euiSock = rec
        if rec.gemLink then
            PaintFilledIcon(btn, rec.gemLink)
        else
            PaintEmptyIcon(btn)
        end
        btn:ClearAllPoints()
        btn:SetPoint("LEFT", panel, "LEFT", (i - 1) * (SIZE + PAD), 0)
        btn:Show()
    end

    panel:SetWidth(count * (SIZE + PAD) - PAD)
    panel:Show()
end

--------------------------------------------------------------------------------
--  Flyout
--------------------------------------------------------------------------------

local function AcquireGemRow(i)
    local row = gemRows[i]
    if row then return row end

    row = CreateFrame("Button", nil, flyout)
    row:SetHeight(ROW_H)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ROW_H - 2, ROW_H - 2)
    icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.icon = icon

    local fontPath = (EllesmereUI and EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("blizzardSkin")) or STANDARD_TEXT_FONT
    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetFont(fontPath, 11, "")
    label:SetPoint("LEFT", icon, "RIGHT", 5, 0)
    label:SetJustifyH("LEFT")
    row.label = label

    local count = row:CreateFontString(nil, "OVERLAY")
    count:SetFont(fontPath, 11, "")
    count:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    count:SetJustifyH("RIGHT")
    count:SetTextColor(0.7, 0.7, 0.7)
    row.count = count

    local hov = row:CreateTexture(nil, "HIGHLIGHT")
    hov:SetAllPoints(row)
    hov:SetColorTexture(1, 1, 1, 0.1)

    row:SetScript("OnEnter", function(self)
        if not self.gemLink then return end
        if EllesmereUI and EllesmereUI._tooltipSuppressedByMode
            and EllesmereUI._tooltipSuppressedByMode(GameTooltip) then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.gemLink)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
        MaybeCloseHoverFlyout()
    end)
    row:SetScript("OnClick", function(self)
        if not self.gemItemID then return end
        DoSocket(flyout.targetSlot, flyout.targetSocketIndex, self.gemItemID)
    end)

    gemRows[i] = row
    return row
end

local function PopulateFlyout()
    if gemDirty then ScanBagGems() end

    for _, row in ipairs(gemRows) do
        row:Hide()
        row.gemItemID = nil
        row.gemLink = nil
    end

    local n = #gemCache
    local shown = 0
    if n == 0 then
        -- Single greyed "no gems" row.
        local row = AcquireGemRow(1)
        row.icon:SetTexture(nil)
        row.icon:SetColorTexture(0, 0, 0, 0)
        row.label:SetText("No gems in bags.")
        row.label:SetTextColor(0.5, 0.5, 0.5)
        row.count:SetText("")
        row.gemItemID = nil
        row.gemLink = nil
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", flyout, "TOPLEFT", 4, -4)
        row:SetPoint("TOPRIGHT", flyout, "TOPRIGHT", -4, -4)
        row:Show()
        shown = 1
    else
        -- Render at most MAX_FLYOUT_ROWS at a time; the wheel scrolls the window
        -- so a large gem inventory never produces an off-screen, unreachable list.
        local visible = n
        if visible > MAX_FLYOUT_ROWS then visible = MAX_FLYOUT_ROWS end
        local maxScroll = n - visible
        if flyoutScroll < 0 then flyoutScroll = 0 end
        if flyoutScroll > maxScroll then flyoutScroll = maxScroll end
        for vis = 1, visible do
            local g = gemCache[flyoutScroll + vis]
            local row = AcquireGemRow(vis)
            row.icon:SetTexture(g.tex)
            row.icon:SetColorTexture(0, 0, 0, 0)
            row.icon:SetTexture(g.tex)
            row.label:SetTextColor(1, 1, 1)
            row.label:SetText(g.link and GetGemStatText(g.link) or "Loading...")
            local c = (GetItemCountFn and GetItemCountFn(g.itemID)) or 1
            row.count:SetText(c .. "x")
            row.gemItemID = g.itemID
            row.gemLink = g.link
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", flyout, "TOPLEFT", 4, -4 - (vis - 1) * ROW_H)
            row:SetPoint("TOPRIGHT", flyout, "TOPRIGHT", -4, -4 - (vis - 1) * ROW_H)
            row:Show()
            shown = vis
        end
    end

    flyout:SetHeight(8 + shown * ROW_H)
end

local function BuildFlyout()
    if flyout then return end

    -- Full-screen click-catcher (our frame), just below the flyout strata.
    catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN")
    catcher:EnableMouse(true)
    catcher:RegisterForClicks("AnyUp")
    catcher:Hide()
    catcher:SetScript("OnClick", function() CloseFlyout() end)

    flyout = CreateFrame("Frame", "EUI_CharSheet_SocketFlyout", UIParent)
    flyout:SetWidth(FLYOUT_W)
    flyout:SetHeight(ROW_H + 8)
    flyout:SetFrameStrata("FULLSCREEN_DIALOG")
    flyout:Hide()

    local bg = flyout:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(flyout)
    bg:SetColorTexture(0.06, 0.06, 0.06, 0.95)
    if PP and PP.CreateBorder then
        PP.CreateBorder(flyout, 0.2, 0.2, 0.2, 1, 1, "OVERLAY", 1)
    end

    -- Mouse-enabled so the hover-opened flyout can watch its own OnLeave; also
    -- keeps clicks on the menu background from falling through to the sheet.
    flyout:EnableMouse(true)
    flyout:SetScript("OnLeave", function() MaybeCloseHoverFlyout() end)

    flyout:EnableMouseWheel(true)
    flyout:SetScript("OnMouseWheel", function(self, delta)
        if #gemCache <= MAX_FLYOUT_ROWS then return end
        flyoutScroll = flyoutScroll - delta   -- wheel down (-1) advances the window
        PopulateFlyout()
    end)

    flyout:EnableKeyboard(true)
    flyout:SetPropagateKeyboardInput(true)
    flyout:SetScript("OnKeyDown", function(self, key)
        -- SetPropagateKeyboardInput is protected in combat; the flyout is
        -- already being closed by PLAYER_REGEN_DISABLED at that point.
        if InCombatLockdown() then return end
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            CloseFlyout()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
end

OpenFlyout = function(iconBtn, targetSlot, targetSocketIndex, hoverMode)
    BuildFlyout()
    -- Close any existing flyout first.
    CloseFlyout()

    flyoutHoverMode = hoverMode and true or false
    flyout.targetSlot = targetSlot
    flyout.targetSocketIndex = targetSocketIndex
    activeIcon = iconBtn
    flyoutScroll = 0

    PopulateFlyout()

    -- Anchor below the icon, flip upward if it would clip the screen bottom.
    flyout:ClearAllPoints()
    local h = flyout:GetHeight()
    local btnBottom = iconBtn:GetBottom() or 0
    if (btnBottom - h - 6) < 0 then
        flyout:SetPoint("BOTTOMLEFT", iconBtn, "TOPLEFT", 0, 4)
    else
        flyout:SetPoint("TOPLEFT", iconBtn, "BOTTOMLEFT", 0, -4)
    end

    -- Always start in pass-through state: an ESCAPE-close leaves propagate
    -- false on the hidden frame, which would swallow the first key next open.
    flyout:SetPropagateKeyboardInput(true)

    -- Hover mode has no click-catcher: the flyout dismisses itself when the
    -- cursor leaves it, and a stray hover must never eat an unrelated click.
    -- A click on the socket icon pins it sticky, which shows the catcher.
    if not flyoutHoverMode then catcher:Show() end
    flyout:Show()

    -- Watch for combat while the flyout is open.
    if evtFrame then evtFrame:RegisterEvent("PLAYER_REGEN_DISABLED") end
end

CloseFlyout = function()
    if flyout then flyout:Hide() end
    if catcher then catcher:Hide() end
    activeIcon = nil
    flyoutHoverMode = false
    if evtFrame then evtFrame:UnregisterEvent("PLAYER_REGEN_DISABLED") end
end

-- Hover-opened flyouts dismiss when the cursor is over neither the flyout nor
-- the socket icon that opened it. Called from the OnLeave of every surface
-- involved (icon, flyout body, gem rows) -- purely event-driven, no polling.
MaybeCloseHoverFlyout = function()
    if not flyoutHoverMode then return end
    if not (flyout and flyout:IsShown()) then return end
    -- The margin bridges the 4px anchor gap between icon and flyout so the
    -- cursor can travel across it without this check closing the menu.
    if flyout:IsMouseOver(8, -8, -8, 8) then return end
    if activeIcon and activeIcon:IsMouseOver() then return end
    CloseFlyout()
end

--------------------------------------------------------------------------------
--  Events (registered only while the panel is shown)
--------------------------------------------------------------------------------

local function EventValid(event)
    if C_EventUtils and C_EventUtils.IsEventValid then
        return C_EventUtils.IsEventValid(event)
    end
    return true
end

local SHOWN_EVENTS = {
    "PLAYER_EQUIPMENT_CHANGED",
    "ITEM_CHANGED",
    "SOCKET_INFO_UPDATE",
    "SOCKET_INFO_ACCEPT",
    "SOCKET_INFO_CLOSE",
    "BAG_UPDATE_DELAYED",
    "ITEM_DATA_LOAD_RESULT",
}

local function RegisterShownEvents()
    if shownEvents or not evtFrame then return end
    shownEvents = true
    for _, ev in ipairs(SHOWN_EVENTS) do
        if EventValid(ev) then
            pcall(evtFrame.RegisterEvent, evtFrame, ev)
        end
    end
end

local function UnregisterShownEvents()
    if not (shownEvents and evtFrame) then return end
    shownEvents = false
    for _, ev in ipairs(SHOWN_EVENTS) do
        pcall(evtFrame.UnregisterEvent, evtFrame, ev)
    end
    evtFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
end

local function OnEvent(self, event, arg1)
    if event == "PLAYER_EQUIPMENT_CHANGED" then
        RebuildSockets()
    elseif event == "ITEM_CHANGED" then
        -- Socketing modifies the equipped item's link IN PLACE (no re-equip),
        -- so PLAYER_EQUIPMENT_CHANGED stays silent and the accept-time rebuild
        -- still reads the old link; this fires once the link actually changed.
        RebuildSockets()
    elseif event == "SOCKET_INFO_UPDATE" then
        OnSocketInfoUpdate()
    elseif event == "SOCKET_INFO_ACCEPT" or event == "SOCKET_INFO_CLOSE" then
        local ours = pending ~= nil
        pending = nil
        if event == "SOCKET_INFO_CLOSE" then ourSession = false end
        gemDirty = true
        RebuildSockets()
        -- End the session we opened once the gem is applied; the socketing
        -- window hides itself in response (never touch a manual session).
        if event == "SOCKET_INFO_ACCEPT" and ours then
            SafeCloseSession()
        end
    elseif event == "BAG_UPDATE_DELAYED" then
        gemDirty = true
        -- The socketed gem just left the bags; refresh the equipped row too,
        -- as the guaranteed fallback if ITEM_CHANGED is ever unavailable.
        RebuildSockets()
        if flyout and flyout:IsShown() then PopulateFlyout() end
    elseif event == "ITEM_DATA_LOAD_RESULT" then
        -- A bag gem we listed before its data was cached: rescan so its link
        -- and stat label fill in (kept separate from relevantItems, which
        -- RebuildSockets wipes and refills on every pass).
        if arg1 and pendingGemLoads[arg1] then
            pendingGemLoads[arg1] = nil
            gemDirty = true
            if flyout and flyout:IsShown() then PopulateFlyout() end
        end
        -- This event is a global broadcast that fires for EVERY item whose data
        -- finishes loading anywhere in the UI. Only refresh when the loaded item
        -- is one of our tracked equipped/socketed items or their gems, so we do
        -- not run a full 16-slot rebuild on every unrelated bag/tooltip load.
        if panel and panel:IsShown() and (arg1 == nil or relevantItems[arg1]) then
            RebuildSockets()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        CloseFlyout()
    end
end

--------------------------------------------------------------------------------
--  Build + lifecycle
--------------------------------------------------------------------------------

local function BuildPanel()
    if built then return end

    -- Bare row of icons in the blank strip along the sheet's bottom edge,
    -- right-aligned. No header, no backdrop -- just the gems. Anchoring to
    -- CharacterFrame directly (not a skin frame) means the panel builds fine
    -- on the very first open after login, before the skin's lazy layout runs.
    panel = CreateFrame("Frame", "EUI_CharSheet_SocketPanel", CharacterFrame)
    panel:ClearAllPoints()
    panel:SetPoint("BOTTOMRIGHT", CharacterFrame, "BOTTOMRIGHT", -10, 6)
    panel:SetSize(SIZE, SIZE)
    panel:SetFrameLevel(55)

    if not evtFrame then
        evtFrame = CreateFrame("Frame")
        evtFrame:SetScript("OnEvent", OnEvent)
    end

    built = true
end

local function OnPaperDollShow()
    if EllesmereUIDB and (EllesmereUIDB.themedCharacterSheet == false or EllesmereUI.BlizzWindowSkinsKilled()) then return end
    if EllesmereUIDB and EllesmereUIDB.charSheetSocketPanel == false then
        if panel then panel:Hide() end
        return
    end
    if not built then BuildPanel() end
    if not panel then return end
    RegisterShownEvents()
    -- Events were unregistered while the sheet was closed, so any bag change
    -- in between (mail, loot, trade) never marked the gem list dirty.
    gemDirty = true
    -- Fresh open: allow one new data-load request per equipped gem, so a
    -- load that failed last time gets retried.
    for k in pairs(socketLoadRequested) do socketLoadRequested[k] = nil end
    RebuildSockets()
end

local function OnHideAll()
    -- OnLeave never fires when the sheet hides under the cursor; stop the
    -- slot glow explicitly so its FlipBook anim is not left running hidden.
    StopSlotGlow()
    CloseFlyout()
    UnregisterShownEvents()
    if panel then panel:Hide() end
end

-- Live apply from the options toggle (no reload).
local function RefreshFromOptions()
    if not (PaperDollFrame and PaperDollFrame:IsShown()) then return end
    if EllesmereUIDB and EllesmereUIDB.charSheetSocketPanel == false then
        CloseFlyout()
        UnregisterShownEvents()
        if panel then panel:Hide() end
    else
        if not built then BuildPanel() end
        if panel then
            RegisterShownEvents()
            RebuildSockets()
        end
    end
end

--------------------------------------------------------------------------------
--  Bootstrap
--------------------------------------------------------------------------------

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
    if EllesmereUI then
        EllesmereUI._refreshCharSheetSocketPanel = RefreshFromOptions
    end
    if PaperDollFrame then
        PaperDollFrame:HookScript("OnShow", OnPaperDollShow)
        PaperDollFrame:HookScript("OnHide", OnHideAll)
    end
    if CharacterFrame then
        CharacterFrame:HookScript("OnHide", OnHideAll)
    end
end)
