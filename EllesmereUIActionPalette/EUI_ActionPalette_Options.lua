-------------------------------------------------------------------------------
--  EUI_ActionPalette_Options.lua  --  Settings page for the Action Palette
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local PAGE_DISPLAY = "Action Palette"
local BINDING_PREFIX = "EUI_RADIAL"
-- Palettes past MAX_BOUND_PALETTES have no <Binding> entry, so they cannot be
-- opened by a key at all: they exist to be nested inside another palette. Read
-- from the module rather than restated, so the two can never disagree about
-- which of them the keybind row applies to.
local MAX_PALETTES = ns.MAX_PALETTES or 16
local MAX_BOUND_PALETTES = ns.MAX_BOUND_PALETTES or 6
local MAX_SLOTS = ns.MAX_SLOTS or 12

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if not EllesmereUI or not EllesmereUI.RegisterModule then return end

    local db
    C_Timer.After(0, function() db = _G._EAP_AceDB end)

    -- Through ns.Profile, not db.profile: the module converts a profile's
    -- retired key names on first touch, and reading the table directly here
    -- would skip that whenever the panel is the first to see a profile the user
    -- has just switched to. The db local is still kept for the reset handler.
    local function DB()
        if not db then db = _G._EAP_AceDB end
        if ns.Profile then return ns.Profile() end
        return db and db.profile
    end

    local function Cfg(key)
        local p = DB()
        return p and p[key]
    end

    local function Set(key, val)
        local p = DB()
        if p then p[key] = val end
    end

    local function Refresh()
        if _G._EAP_Apply then _G._EAP_Apply() end
        if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage() end
    end

    local function RebuildPage()
        if _G._EAP_Apply then _G._EAP_Apply() end
        if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage(true) end
    end

    -- Which palette the PALETTE SETUP section is editing. Transient: the editor
    -- is a panel-session concept, not a saved setting.
    local editPalette = 1

    local function PaletteCount()
        return math.min(MAX_PALETTES, math.max(1, Cfg("paletteCount") or 1))
    end

    local function Palette(index)
        return ns.EnsurePalette and ns.EnsurePalette(index or editPalette)
    end

    -- From the module, so the name an emptied box reverts to is the same string
    -- the module hands a fresh palette.
    local function AutoName(index)
        if ns.AutoPaletteName then return ns.AutoPaletteName(index) end
        return "Palette " .. index
    end

    -- A palette icon is stored as a plain icon file ID, so it needs no lookup at
    -- draw time. The box takes whatever number the user has to hand: a spell ID
    -- and an item ID are both far easier to find than an icon's own ID, so each
    -- is tried first and only an unrecognised number is taken literally.
    local function ResolveIconInput(text)
        local id = tonumber(strtrim(text or ""))
        if not id then return nil end
        local spellIcon = C_Spell.GetSpellTexture(id)
        if spellIcon then return spellIcon end
        local itemIcon = C_Item.GetItemIconByID(id)
        if itemIcon then return itemIcon end
        return id
    end

    ---------------------------------------------------------------------------
    --  Inline keybind picker
    --
    --  Binds the real EUI_RADIAL<n> action declared in Bindings.xml via
    --  SetBinding/SaveBindings, rather than storing a key of our own and
    --  routing it separately. That keeps ONE source of truth: this picker and
    --  Blizzard's Keybindings page edit the same binding, GetBindingKey keeps
    --  driving ns.UpdateBindings, and the SaveBindings call fires
    --  UPDATE_BINDINGS so the palette re-routes its override binding by itself.
    ---------------------------------------------------------------------------
    local listenPalette = nil
    local captureFrame = nil

    -- Combat-safe teardown. SetPropagateKeyboardInput carries restrictions and
    -- is pcall'd elsewhere in the suite for exactly this reason
    -- (EllesmereUIChat.lua:2552) -- and this runs in combat by construction,
    -- because EllesmereUI hides its options window on PLAYER_REGEN_DISABLED
    -- and that OnHide calls us.
    local function StopListening()
        local wasListening = listenPalette ~= nil
        listenPalette = nil
        if captureFrame then
            pcall(captureFrame.SetPropagateKeyboardInput, captureFrame, true)
            captureFrame:EnableKeyboard(false)
            captureFrame:Hide()
        end
        return wasListening
    end

    -- The combat rejections below are the one case where EllesmereUI.Print is
    -- the wrong channel: it deliberately stays silent in raid combat and in an
    -- active M+ (EllesmereUI.lua:1519), which is precisely when a user would
    -- hit them and see nothing happen.
    local function Complain(msg)
        if _G.UIErrorsFrame then
            UIErrorsFrame:AddMessage(msg, 1.0, 0.3, 0.3, 1.0)
        else
            EllesmereUI.Print("|cff0cd29fAction Palette:|r " .. msg)
        end
    end

    -- chord = a binding string to assign, or nil to leave the palette unbound.
    local function CommitKey(chord)
        local palette = listenPalette
        StopListening()
        if not palette then return end

        -- SaveBindings raises "can't be done in combat" and SetBinding would
        -- then be half-applied, so nothing is touched until combat drops.
        if InCombatLockdown() then
            Complain("Action Palette: keybinds can't be changed in combat.")
            RebuildPage()
            return
        end

        local action = BINDING_PREFIX .. palette
        local stolenFrom = chord and GetBindingAction(chord) or nil
        local oldK1, oldK2 = GetBindingKey(action)

        if chord then
            -- Replace the PRIMARY key only and leave a secondary binding
            -- alone. Blizzard's own panel allows two keys per action, and
            -- clearing both here silently destroyed the second one with no
            -- message (and no way to see it, since the label shows key1).
            if oldK1 then SetBinding(oldK1, nil) end
            if not SetBinding(chord, action) then
                -- Put the primary back. oldK2 was never cleared, so there is
                -- nothing to restore for it.
                if oldK1 then SetBinding(oldK1, action) end
                Complain("Action Palette: " .. (GetBindingText(chord) or chord)
                    .. " could not be bound.")
            elseif stolenFrom and stolenFrom ~= "" and stolenFrom ~= action then
                -- SetBinding steals the key silently; say so, because the
                -- displaced binding is often something the user cares about.
                local label = _G["BINDING_NAME_" .. stolenFrom] or stolenFrom
                EllesmereUI.Print("|cff0cd29fAction Palette:|r took "
                    .. (GetBindingText(chord) or chord) .. " from |cffffd100"
                    .. label .. "|r.")
            end
        else
            -- Unbind: this one clears every key the palette holds, which is what
            -- "unbind" means.
            if oldK1 then SetBinding(oldK1, nil) end
            if oldK2 then SetBinding(oldK2, nil) end
        end

        SaveBindings(GetCurrentBindingSet())
        RebuildPage()
    end

    local function EnsureCaptureFrame()
        if captureFrame then return captureFrame end

        local f = CreateFrame("Frame", nil, UIParent)
        f:SetAllPoints(UIParent)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        -- Explicit high level: the suite has other FULLSCREEN_DIALOG frames
        -- (EllesmereUI.lua:1008, :6139, :11113) that would otherwise cover the
        -- prompt text.
        f:SetFrameLevel(1000)
        f:EnableMouse(true)
        f:EnableMouseWheel(true)
        f:Hide()

        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.45)

        f.msg = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.msg:SetPoint("CENTER")
        f.msg:SetJustifyH("CENTER")

        f:SetScript("OnKeyDown", function(self, key)
            -- Re-asserted per event: propagation is reset by the engine on
            -- some paths, and if it leaks through, Escape closes the options
            -- window out from under the picker.
            self:SetPropagateKeyboardInput(false)
            key = GetConvertedKeyOrButton(key)
            if key == "ESCAPE" then
                StopListening()
                RebuildPage()
            elseif key == "DELETE" or key == "BACKSPACE" then
                CommitKey(nil)
            elseif not IsKeyPressIgnoredForBinding(key) then
                CommitKey(CreateKeyChordStringUsingMetaKeyState(key))
            end
        end)

        f:SetScript("OnMouseDown", function(self, button)
            local key = GetConvertedKeyOrButton(button)
            -- A BARE left/right click cancels -- those two are needed to
            -- operate the UI at all, and it doubles as
            -- click-outside-to-dismiss. Held with a modifier they are
            -- ordinary bindable chords (ALT-BUTTON1 and friends), so the
            -- cancel only applies when no modifier is down.
            local modified = IsAltKeyDown() or IsControlKeyDown()
                or IsShiftKeyDown() or (IsMetaKeyDown and IsMetaKeyDown())
            if (key == "BUTTON1" or key == "BUTTON2") and not modified then
                StopListening()
                RebuildPage()
            else
                CommitKey(CreateKeyChordStringUsingMetaKeyState(key))
            end
        end)

        f:SetScript("OnMouseWheel", function(self, delta)
            CommitKey(CreateKeyChordStringUsingMetaKeyState(
                delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"))
        end)

        captureFrame = f
        return f
    end

    local function StartListening(palette)
        if InCombatLockdown() then
            Complain("Action Palette: keybinds can't be changed in combat.")
            return
        end
        listenPalette = palette

        local f = EnsureCaptureFrame()
        f.msg:SetText("Press a key or mouse button for |cff0cd29fAction Palette "
            .. palette .. "|r\n|cff888888Modifiers work with any button "
            .. "(Alt + Left Click, Shift + Wheel, ...)\n"
            .. "Esc cancels  \194\183  Delete unbinds"
            .. "  \194\183  plain left/right click cancels|r")
        f:EnableKeyboard(true)
        f:SetPropagateKeyboardInput(false)
        f:Show()
        RebuildPage()
    end

    -- The picker holds a modal overlay, so it has to come down when the user
    -- closes the options window -- a /reload never fires OnHide, and the listen
    -- state is not persisted.
    local function _installPickerAutoOff()
        local mf = _G.EllesmereUIFrame
        if not mf or mf._eRWEditorHook then return end
        mf._eRWEditorHook = true
        mf:HookScript("OnHide", function()
            -- The page's "Press a key..." label is a literal baked in at build
            -- time, and reopening the window re-shows the CACHED page without
            -- rebuilding -- so aborting a listen this way has to drop the
            -- cache, or the button reads "Press a key..." forever. This path is
            -- not hypothetical: EllesmereUI hides the window on
            -- PLAYER_REGEN_DISABLED, so entering combat mid-listen lands here.
            if StopListening() and EllesmereUI.InvalidatePageCache then
                EllesmereUI:InvalidatePageCache()
            end
        end)
    end

    -- Keys can also change from Blizzard's Keybindings page or another addon.
    -- The label is built from GetBindingKey, so without this the cached page
    -- keeps showing the old key -- which would make the "one source of truth"
    -- design only half-true in practice.
    --
    -- Signature-guarded, and that guard is not an optimisation: UPDATE_BINDINGS
    -- fires on every override-binding registration anywhere in the suite (the
    -- palette's own UpdateBindings included), and dropping the whole options
    -- page cache on each of those would rebuild the visible page over and
    -- over. Only a change to OUR six keys is of any interest here.
    local lastKeySig = nil
    local function PaletteKeySignature()
        local sig = ""
        for i = 1, MAX_BOUND_PALETTES do
            local k1, k2 = GetBindingKey(BINDING_PREFIX .. i)
            sig = sig .. "|" .. (k1 or "") .. "/" .. (k2 or "")
        end
        return sig
    end
    lastKeySig = PaletteKeySignature()

    local bindWatcher = CreateFrame("Frame")
    bindWatcher:RegisterEvent("UPDATE_BINDINGS")
    bindWatcher:SetScript("OnEvent", function()
        local sig = PaletteKeySignature()
        if sig == lastKeySig then return end
        lastKeySig = sig
        if EllesmereUI.InvalidatePageCache then EllesmereUI:InvalidatePageCache() end
        if EllesmereUI.IsShown and EllesmereUI:IsShown() and EllesmereUI.RefreshPage then
            EllesmereUI:RefreshPage(true)
        end
    end)

    ---------------------------------------------------------------------------
    --  Palette preview
    --
    --  The live palette's own renderer (ns.CreatePaletteView), scaled down to fit the
    --  panel and made interactive: drop an action on the trailing "+" to append
    --  it, drag icons between entries to reorder, right-click to remove. Because
    --  it is the same renderer, the arrangement here is literally the one the
    --  user steers at in play.
    --
    --  Cached, not rebuilt. BuildPage runs on every RebuildPage and WoW frames
    --  are never collected, so re-creating thirteen of them per rebuild would
    --  leak. The page WRAPPER is discarded on rebuild though, so the block is
    --  re-parented and re-anchored on every build.
    ---------------------------------------------------------------------------
    local PREVIEW_H    = 280   -- height the block claims in the page layout
    -- Largest radius + iconSize the block can hold. Half of PREVIEW_H less a
    -- margin: the preview turns slot labels off, so the palette only has to clear
    -- the block's own edges rather than leave room for captions under it.
    local PREVIEW_SPAN = 124
    local previewBlock, previewView

    -- Half-extent the block can give a layout on one axis. The block is as wide
    -- as the panel's content and only PREVIEW_H tall, so the two budgets differ
    -- by a wide margin and every layout has to be measured against both.
    local function BlockSpan(vertical)
        if vertical then return PREVIEW_H * 0.5 - 24 end
        local w = previewBlock and previewBlock:GetWidth() or 0
        -- The block is anchored on both sides, so its width is unresolved on
        -- the very first build. Layout re-runs on every Refresh, so a fallback
        -- here corrects itself rather than sticking.
        if w < 100 then w = 460 end
        return w * 0.5 - 24
    end

    -- How far the preview may magnify a layout that does not fill the block on
    -- its own. Fitting used to be a shrink-only rule, which left a short strip
    -- or a small grid as a row of thumbnails in the middle of a 280px block
    -- while the arc -- whose radius alone nearly fills it -- previewed at very
    -- nearly its real size. Growing is capped rather than free: this is still a
    -- preview of a palette the user steers at some other size, and a two-entry
    -- strip blown up to fill the block would misrepresent it.
    local PREVIEW_MAX_ZOOM = 2.0

    -- Fit to the block, don't crop: the live radius reaches 220, which is wider
    -- than the panel, and a two-entry strip is far narrower than it. Scaling
    -- radius, icon and dead zone by one factor keeps the proportions the user
    -- chose, so a tight arc still previews as a tight one.
    local function PreviewGeom()
        local radius   = Cfg("radius") or 96
        local iconSize = Cfg("iconSize") or 44
        local deadZone = Cfg("deadZone") or 24
        local layout = Cfg("layout") or "ARC"
        -- Half the width a selected entry reaches, which every budget has to
        -- leave room for: the preview magnifies whatever the cursor is over.
        local zoom = Cfg("selectedZoom") or 1.15
        local k
        if layout == "GRID" then
            -- The grid is bounded on BOTH axes, so both budgets have to be met:
            -- the block's width across the columns, and its height down the rows.
            local palette = Palette(editPalette)
            local n = (palette and #palette.slots or 0) + 1
            local cols, rows
            if previewView then cols, rows = previewView:GridDims() end
            -- The view answers from its last Layout, so it has nothing to say
            -- until the first one has run.
            if not cols or rows < 1 then
                cols = math.min(Cfg("gridColumns") or 4, n)
                rows = math.ceil(n / cols)
            end
            local pitch = iconSize + (Cfg("fanGap") or 10)
            k = math.min(PREVIEW_MAX_ZOOM,
                BlockSpan(false) / (cols * pitch * 0.5 + iconSize * (zoom - 1) * 0.5),
                BlockSpan(true) / (rows * pitch * 0.5 + iconSize * (zoom - 1) * 0.5))
        elseif layout ~= "ARC" then
            -- A fan's extent is the length of the strip rather than a radius, so
            -- that is what has to be fitted. The preview draws EVERY slot -- an
            -- editor cannot leave one unreachable -- plus the trailing "+", and
            -- nothing is culled, so the reach is measured over that whole count.
            local palette = Palette(editPalette)
            local n = (palette and #palette.slots or 0) + 1
            local reach
            if (Cfg("fanInput") or "SCROLL") == "CURSOR" then
                -- A pointer-steered fan is evenly spaced at full pitch, so its
                -- reach grows much faster than a coverflow strip's.
                reach = ns.FanHoverReach(n, iconSize, Cfg("fanGap") or 10)
            else
                -- Through the module rather than off the key: with the falloff
                -- switched off the strip spreads out to full pitch, and a fit
                -- measured at the stored decay would run it out of the block.
                reach = ns.FanReach(n, iconSize, Cfg("fanGap") or 10,
                                    (ns.FalloffRatios()))
            end
            local vertical = Cfg("fanOrientation") == "VERTICAL"
            -- Both axes, not just the one the strip runs along: a short strip
            -- fits its own length several times over, and without the crossways
            -- budget it would grow until the icons ran out of the block.
            k = math.min(PREVIEW_MAX_ZOOM,
                BlockSpan(vertical) / reach,
                BlockSpan(not vertical) / (iconSize * 0.5 * zoom))
        else
            k = math.min(PREVIEW_MAX_ZOOM, PREVIEW_SPAN / (radius + iconSize))
        end
        return radius * k, iconSize * k, deadZone * k
    end

    -- Manual drag, threshold-based -- the same shape as the Widgets reorder row
    -- (EllesmereUI_Widgets.lua:5391), because WoW's built-in RegisterForDrag
    -- threshold is far too large for icons this size.
    local DRAG_THRESHOLD = 4
    local dragFrom, dragStartX, dragStartY, dragging, dragTarget

    local function PreviewTooltip(widget)
        local palette = Palette(editPalette)
        local slot = palette and palette.slots[widget.index]
        GameTooltip:SetOwner(widget, "ANCHOR_RIGHT")
        if slot then
            local _, name = ns.SlotDisplay(slot)
            GameTooltip:AddLine(name or slot.kind, 1, 1, 1)
            if slot.kind == "palette" then
                local kids = ns.ChildSlots and ns.ChildSlots(ns.ChildIndex(slot))
                GameTooltip:AddLine(("nested palette, %d %s"):format(
                    kids and #kids or 0,
                    (kids and #kids == 1) and "entry" or "entries"), 0.6, 0.6, 0.6)
            else
                -- The stored kind strings are one word each; only the marker
                -- kinds read better with the space put back.
                local caption = (slot.kind == "raidtarget" and "target marker")
                    or (slot.kind == "worldmarker" and "world marker")
                    or (slot.kind == "clearmarkers" and "target markers")
                    or slot.kind
                GameTooltip:AddLine(caption, 0.6, 0.6, 0.6)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Drag to reorder.", 0.4, 0.8, 1, true)
            GameTooltip:AddLine("Right-click to remove.", 0.4, 0.8, 1, true)
            GameTooltip:AddLine("Drop an action here to replace it.", 0.4, 0.8, 1, true)
        else
            GameTooltip:AddLine("Add an action", 1, 1, 1)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Left-click to pick a spell, mount, item, toy, macro, "
                .. "battle pet or marker from a list.", 0.4, 0.8, 1, true)
            GameTooltip:AddLine("You can also drop an action from the cursor here.",
                0.4, 0.8, 1, true)
        end
        GameTooltip:Show()
    end

    -- Place whatever is on the cursor. An empty cursor is not an error: a bare
    -- left-click on a slot should do nothing at all, cursor untouched.
    local function PreviewPlace(widget)
        local palette = Palette(editPalette)
        local slot = palette and ns.SlotFromCursor()
        if not slot then return end
        if widget.isPlaceholder then
            if not ns.AddSlot(palette, slot) then return end
        else
            palette.slots[widget.index] = slot
        end
        ClearCursor()
        Refresh()
    end

    ---------------------------------------------------------------------------
    --  Action picker
    --
    --  Left-clicking the "+" entry with an empty cursor opens a category menu,
    --  then that category's actions; choosing one appends a slot to the palette
    --  being edited. Dropping an action from the cursor still works, but it
    --  cannot be the only route: opening the spellbook closes the options
    --  window, so there is no way to get a spell onto the cursor while the
    --  preview is on screen.
    --
    --  Shaped after the Cooldown Manager's bar-glow spell picker
    --  (EUI_CooldownManager_Options.lua:518): one cached anchored menu on
    --  FULLSCREEN_DIALOG, the dropdown palette, pooled rows inside a capped
    --  scroll frame, dismissed by a click outside itself.
    ---------------------------------------------------------------------------
    local PICK_W        = 250
    local PICK_ROW_H    = 26
    local PICK_MAX_LIST = 286  -- visible list height; a longer list scrolls
    local PICK_HEAD_H   = 24   -- title strip
    local PICK_NAV_H    = 56   -- back row + search box, category views only
    local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"

    local pickerMenu, pickerAnchor

    -- Category key -> entry array, built on first use of that category and kept.
    -- The spell and mount lists run to hundreds of rows, so the search box
    -- filters this cache instead of re-enumerating on every keystroke.
    local pickerLists = {}

    ---------------------------------------------------------------------------
    --  Enumeration
    --
    --  Strictly read-only, every list. The journals' filter setters
    --  (C_MountJournal.SetSearch/SetCollectedFilterSetting,
    --  C_ToyBox.SetFilterString, C_PetJournal.SetSearchFilter, ...) rewrite the
    --  user's saved Collections filters as a side effect and several are
    --  protected, so the filtering happens in Lua here. That is also why the
    --  ID-based getters are preferred: the index-based ones walk the journals'
    --  currently FILTERED lists, so what the palette offers would otherwise
    --  depend on what the user last typed in the Collections search box.
    ---------------------------------------------------------------------------
    local function SpellEntries()
        local out, seen = {}, {}
        local bank = Enum.SpellBookSpellBank.Player

        local function Add(spellID, name, icon)
            if type(spellID) ~= "number" or seen[spellID] or not name then return end
            seen[spellID] = true
            out[#out + 1] = { icon = icon, name = name,
                              slot = { kind = "spell", id = spellID } }
        end

        -- There is no C_SpellBook.GetNumSpellBookItems in this client. The book
        -- is described by its skill lines instead, each carrying an offset into
        -- the item indices and a count -- which is how Blizzard's own spellbook
        -- walks it (Blizzard_SpellBookCategory.lua:180-218).
        for line = 1, (C_SpellBook.GetNumSpellBookSkillLines() or 0) do
            local li = C_SpellBook.GetSpellBookSkillLineInfo(line)
            -- offSpecID is set on the other specialisation's tabs; those spells
            -- are listed in the book but cannot be cast.
            if li and not li.shouldHide and not li.offSpecID then
                for i = li.itemIndexOffset + 1, li.itemIndexOffset + li.numSpellBookItems do
                    local info = C_SpellBook.GetSpellBookItemInfo(i, bank)
                    -- FutureSpell (a rank not learned yet) falls out here too:
                    -- only Spell and Flyout are handled.
                    if info and not info.isPassive and not info.isOffSpec then
                        if info.itemType == Enum.SpellBookItemType.Spell then
                            -- actionID, not spellID: for a spell actionID is the
                            -- BASE id while spellID is whatever override is up
                            -- right now, and the base is what the game resolves
                            -- overrides from when the button fires.
                            Add(info.actionID, info.name, info.iconID)
                        elseif info.itemType == Enum.SpellBookItemType.Flyout then
                            -- A flyout is not castable itself, so its known
                            -- slots are offered as individual spells.
                            local numSlots = select(3, GetFlyoutInfo(info.actionID))
                            for s = 1, (numSlots or 0) do
                                local spellID, _, isKnown, spellName =
                                    GetFlyoutSlotInfo(info.actionID, s)
                                if isKnown then
                                    Add(spellID, spellName, C_Spell.GetSpellTexture(spellID))
                                end
                            end
                        end
                    end
                end
            end
        end
        return out
    end

    local function MountEntries()
        local out = {}
        for _, mountID in ipairs(C_MountJournal.GetMountIDs()) do
            local name, spellID, icon, _, isUsable, _, _, _, _, hideOnChar, isCollected =
                C_MountJournal.GetMountInfoByID(mountID)
            -- isUsable here is a character capability (riding skill, faction,
            -- class), not a "can you mount right now" -- that one is
            -- GetMountUsabilityByID. So an unusable mount is one this character
            -- can never summon, and offering it would be a dead slot.
            if name and isCollected and isUsable and not hideOnChar then
                out[#out + 1] = { icon = icon, name = name,
                    -- spellID is banked at pickup time because ResolveAction
                    -- needs the summon spell and it is already in hand here.
                    slot = { kind = "mount", id = mountID, spellID = spellID, name = name } }
            end
        end
        return out
    end

    local function ItemEntries()
        local out, seen = {}, {}
        local function ScanBag(bag)
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                local itemID = info and info.itemID
                -- Only items with a use effect. The palette fires "/use item:<id>",
                -- so an item without one is a slot that can never do anything.
                if itemID and not seen[itemID] and info.itemName
                   and C_Item.GetItemSpell(itemID) then
                    seen[itemID] = true
                    out[#out + 1] = { icon = info.iconFileID, name = info.itemName,
                        slot = { kind = "item", id = itemID, name = info.itemName } }
                end
            end
        end
        for bag = Enum.BagIndex.Backpack, NUM_BAG_SLOTS do ScanBag(bag) end
        -- The reagent bag is outside that range and easy to forget, but it is
        -- where a lot of players keep their potions and phials -- exactly the
        -- items someone puts on a palette.
        ScanBag(Enum.BagIndex.ReagentBag)
        return out
    end

    local function ToyEntries()
        local out = {}
        -- The toy box has no ID-based enumeration, only this filtered walk, so
        -- this one list does follow the user's Collections filters. Narrowing it
        -- back out would mean calling C_ToyBox.SetFilterString/SetCollectedShown,
        -- which changes what they see in Collections -- not worth it.
        for i = 1, (C_ToyBox.GetNumFilteredToys() or 0) do
            local itemID = C_ToyBox.GetToyFromIndex(i)
            if itemID and itemID > 0 and PlayerHasToy(itemID) then
                local _, name, icon = C_ToyBox.GetToyInfo(itemID)
                if name then
                    out[#out + 1] = { icon = icon, name = name,
                        slot = { kind = "toy", id = itemID, name = name } }
                end
            end
        end
        return out
    end

    local function MacroEntries()
        local out = {}
        local numAccount, numChar = GetNumMacros()
        -- Two separate blocks: the per-character macros start at a fixed offset
        -- rather than continuing from the account ones
        -- (Blizzard_MacroUI.lua:155).
        local function AddBlock(first, count)
            for i = first, first + (count or 0) - 1 do
                local name, icon = GetMacroInfo(i)
                if name then
                    -- Stored by name, matching SlotFromCursor: the index moves
                    -- when the macro list is reordered, the name does not.
                    out[#out + 1] = { icon = icon, name = name,
                        slot = { kind = "macro", name = name } }
                end
            end
        end
        AddBlock(1, numAccount)
        AddBlock(MAX_ACCOUNT_MACROS + 1, numChar)
        return out
    end

    local function PetEntries()
        local out = {}
        for _, guid in ipairs(C_PetJournal.GetOwnedPetIDs()) do
            local info = C_PetJournal.GetPetInfoTableByPetID(guid)
            local name = info and (info.customName or info.name)
            if name then
                out[#out + 1] = { icon = info.icon, name = name,
                    slot = { kind = "battlepet", guid = guid, name = name } }
            end
        end
        return out
    end

    -- The markers need no enumeration at all: the slot kinds carry the icon
    -- and the name, so a candidate slot handed to SlotDisplay IS the entry.
    -- Both marker sets are offered in one category -- nineteen rows do not
    -- earn two menu levels.
    local function MarkerEntries()
        local out = {}
        local function Add(kind, id)
            local slot = { kind = kind, id = id }
            local icon, name = ns.SlotDisplay(slot)
            out[#out + 1] = { icon = icon, name = name, slot = slot }
        end
        for i = 1, 8 do Add("raidtarget", i) end
        Add("raidtarget", 0)
        -- The all-units counterpart of the /tm 0 row above; the world markers
        -- need none because their 0 row already clears them all.
        Add("clearmarkers")
        for i = 1, 8 do Add("worldmarker", i) end
        Add("worldmarker", 0)
        return out
    end

    -- Every palette this one may open. Not a list of things the game owns, so
    -- it is rebuilt on each use rather than cached: adding a palette or filling
    -- one in has to show up here without reopening the picker.
    --
    -- ns.CanNest does the refusing, and refuses more than the obvious: a palette
    -- inside itself, and any chain that would close a loop -- A holding B
    -- holding A -- which would send every push and every draw round until the
    -- client gave out.
    local function PaletteEntries()
        local out = {}
        for i = 1, PaletteCount() do
            if i ~= editPalette and ns.CanNest and ns.CanNest(editPalette, i) then
                local palette = Palette(i)
                local name = (palette and palette.name) or AutoName(i)
                local count = palette and #palette.slots or 0
                -- Same order SlotDisplay uses: the palette's own icon, then its
                -- first entry so it looks like what it holds.
                local icon = palette and palette.icon
                local first = palette and palette.slots[1]
                if not icon and first and first.kind ~= "palette" then
                    icon = ns.SlotDisplay(first)
                end
                out[#out + 1] = {
                    icon = icon or "Interface\\Icons\\INV_Misc_Bag_08",
                    name = (count > 0) and (name .. "  |cff808080(" .. count .. ")|r")
                        or (name .. "  |cff808080(empty)|r"),
                    -- No name on the slot: SlotDisplay reads the palette's own,
                    -- so renaming the palette renames the entry that opens it.
                    slot = { kind = "palette", palette = i },
                }
            end
        end
        return out
    end

    -- custom = the typed-macro pane rather than a list of things to enumerate.
    local PICKER_CATEGORIES = {
        { key = "spell",     label = "Spells",       build = SpellEntries },
        { key = "mount",     label = "Mounts",       build = MountEntries },
        { key = "item",      label = "Items",        build = ItemEntries },
        { key = "toy",       label = "Toys",         build = ToyEntries },
        { key = "macro",     label = "Macros",       build = MacroEntries },
        { key = "battlepet", label = "Battle Pets",  build = PetEntries },
        { key = "marker",    label = "Markers",      build = MarkerEntries,
          keepOrder = true },
        { key = "palette",   label = "Palettes",     build = PaletteEntries },
        { key = "macrotext", label = "Custom Macro...", custom = true },
    }

    local ShowPickerCategories, ShowPickerCategory, ShowPickerCustom

    local function HidePicker()
        if pickerMenu then pickerMenu:Hide() end
    end

    -- Returns true when a slot was actually appended.
    local function AssignEntry(entry)
        local palette = Palette(editPalette)
        -- The stored slot is a COPY: the entry belongs to the cached list, and
        -- handing that one table to two entries would alias a single saved slot
        -- into both of them.
        local slot = {}
        for k, v in pairs(entry.slot) do slot[k] = v end
        -- ns.AddSlot refuses a full palette. Unreachable from here -- a full palette
        -- draws no "+" to click -- but the refusal must not fall through into a
        -- Refresh that has nothing to show.
        if not (palette and ns.AddSlot(palette, slot)) then return false end
        HidePicker()
        Refresh()
        return true
    end

    local function EnsurePickerMenu()
        if pickerMenu then return pickerMenu end

        local FONT = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath())
            or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
        local bgR  = EllesmereUI.DD_BG_R or 0.075
        local bgG  = EllesmereUI.DD_BG_G or 0.113
        local bgB  = EllesmereUI.DD_BG_B or 0.141
        local bgA  = EllesmereUI.DD_BG_HA or 0.98
        local brdA = EllesmereUI.DD_BRD_A or 0.20
        local hlA  = EllesmereUI.DD_ITEM_HL_A or 0.08
        local tR   = EllesmereUI.TEXT_DIM_R or 0.7
        local tG   = EllesmereUI.TEXT_DIM_G or 0.7
        local tB   = EllesmereUI.TEXT_DIM_B or 0.7
        local tA   = EllesmereUI.TEXT_DIM_A or 0.85
        local ACCENT = EllesmereUI.ELLESMERE_GREEN or { r = 0.047, g = 0.824, b = 0.624 }

        local menu = CreateFrame("Frame", nil, UIParent)
        -- The options window is on DIALOG (EllesmereUI.lua:7126), so the menu
        -- has to sit a strata above it or the panel draws over it.
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(300)
        menu:SetClampedToScreen(true)
        menu:SetSize(PICK_W, 10)
        menu:EnableMouse(true)
        menu:Hide()

        local mbg = menu:CreateTexture(nil, "BACKGROUND")
        mbg:SetAllPoints()
        mbg:SetColorTexture(bgR, bgG, bgB, bgA)
        EllesmereUI.MakeBorder(menu, 1, 1, 1, brdA, EllesmereUI.PP)

        menu.title = EllesmereUI.MakeFont(menu, 12, nil, 1, 1, 1, 0.9)
        menu.title:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, -7)

        menu.back = CreateFrame("Button", nil, menu)
        menu.back:SetHeight(PICK_ROW_H)
        menu.back:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -PICK_HEAD_H)
        menu.back:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, -PICK_HEAD_H)
        menu.back:SetFrameLevel(menu:GetFrameLevel() + 2)
        local bHl = menu.back:CreateTexture(nil, "ARTWORK")
        bHl:SetAllPoints()
        bHl:SetColorTexture(1, 1, 1, 0)
        local bTx = EllesmereUI.MakeFont(menu.back, 11, nil, tR, tG, tB, tA)
        bTx:SetPoint("LEFT", menu.back, "LEFT", 8, 0)
        bTx:SetText("\194\171 Categories")
        menu.back:SetScript("OnEnter", function()
            bHl:SetColorTexture(1, 1, 1, hlA); bTx:SetTextColor(1, 1, 1, 1)
        end)
        menu.back:SetScript("OnLeave", function()
            bHl:SetColorTexture(1, 1, 1, 0); bTx:SetTextColor(tR, tG, tB, tA)
        end)
        menu.back:SetScript("OnClick", function() ShowPickerCategories() end)

        menu.search = CreateFrame("EditBox", nil, menu)
        menu.search:SetHeight(22)
        menu.search:SetPoint("TOPLEFT", menu.back, "BOTTOMLEFT", 7, -4)
        menu.search:SetPoint("TOPRIGHT", menu.back, "BOTTOMRIGHT", -7, -4)
        menu.search:SetFrameLevel(menu:GetFrameLevel() + 2)
        menu.search:SetFont(FONT, 11, "")
        menu.search:SetTextColor(1, 1, 1, 0.9)
        menu.search:SetAutoFocus(false)
        menu.search:SetMaxLetters(40)
        menu.search:SetTextInsets(6, 6, 0, 0)
        local sBg = menu.search:CreateTexture(nil, "BACKGROUND")
        sBg:SetAllPoints()
        sBg:SetColorTexture(0, 0, 0, 0.4)
        EllesmereUI.MakeBorder(menu.search, 1, 1, 1, 0.10, EllesmereUI.PP)
        menu.searchPH = menu.search:CreateFontString(nil, "OVERLAY")
        menu.searchPH:SetFont(FONT, 11, "")
        menu.searchPH:SetTextColor(0.5, 0.5, 0.5, 0.6)
        menu.searchPH:SetPoint("LEFT", menu.search, "LEFT", 6, 0)
        menu.searchPH:SetText("Search...")
        menu.search:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
        menu.search:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
        menu.search:SetScript("OnTextChanged", function(s)
            menu.searchPH:SetShown((s:GetText() or "") == "")
            -- Re-filters the cached list; ShowPickerCategory never clears the box.
            if menu.cat then ShowPickerCategory(menu.cat) end
        end)

        menu.scroll = CreateFrame("ScrollFrame", nil, menu)
        menu.scroll:SetFrameLevel(menu:GetFrameLevel() + 1)
        menu.scroll:EnableMouseWheel(true)
        menu.list = CreateFrame("Frame", nil, menu.scroll)
        menu.list:SetWidth(PICK_W - 2)
        menu.scroll:SetScrollChild(menu.list)
        -- Thin track and thumb, as on the CDM source picker
        -- (EUI_CooldownManager_Options.lua:16016): a capped 250px menu holding a
        -- few hundred mounts gives no other sign that it scrolls.
        menu.track = menu.scroll:CreateTexture(nil, "ARTWORK")
        menu.track:SetWidth(3)
        menu.track:SetColorTexture(1, 1, 1, 0.06)
        menu.track:SetPoint("TOPRIGHT", menu.scroll, "TOPRIGHT", -1, 0)
        menu.track:SetPoint("BOTTOMRIGHT", menu.scroll, "BOTTOMRIGHT", -1, 0)
        menu.track:Hide()
        menu.thumb = menu.scroll:CreateTexture(nil, "OVERLAY")
        menu.thumb:SetWidth(3)
        menu.thumb:SetColorTexture(1, 1, 1, 0.25)
        menu.thumb:Hide()

        function menu:UpdateThumb()
            local visH, fullH = self.scroll:GetHeight(), self.list:GetHeight()
            local maxScroll = math.max(0, fullH - visH)
            if maxScroll <= 0 then
                self.track:Hide()
                self.thumb:Hide()
                return
            end
            self.track:Show()
            self.thumb:Show()
            local thumbH = math.max(20, visH * visH / fullH)
            self.thumb:SetHeight(thumbH)
            local frac = (self.scroll:GetVerticalScroll() or 0) / maxScroll
            self.thumb:ClearAllPoints()
            self.thumb:SetPoint("TOPRIGHT", self.track, "TOPRIGHT", 0,
                -frac * (visH - thumbH))
        end

        menu.scroll:SetScript("OnMouseWheel", function(self, delta)
            local maxScroll = math.max(0, menu.list:GetHeight() - self:GetHeight())
            if maxScroll <= 0 then return end
            self:SetVerticalScroll(math.max(0, math.min(maxScroll,
                (self:GetVerticalScroll() or 0) - delta * PICK_ROW_H * 2)))
            menu:UpdateThumb()
        end)

        -- Pooled rows, re-labelled per view: switching category and every
        -- keystroke in the search box re-runs the populate.
        menu.rows = {}
        function menu:GetRow(i)
            local r = self.rows[i]
            if r then return r end
            r = CreateFrame("Button", nil, self.list)
            r:SetHeight(PICK_ROW_H)
            r:SetPoint("TOPLEFT", self.list, "TOPLEFT", 0, -(i - 1) * PICK_ROW_H)
            r:SetPoint("TOPRIGHT", self.list, "TOPRIGHT", 0, -(i - 1) * PICK_ROW_H)
            r:SetFrameLevel(self:GetFrameLevel() + 2)
            r.hl = r:CreateTexture(nil, "ARTWORK")
            r.hl:SetAllPoints()
            r.hl:SetColorTexture(1, 1, 1, 0)
            r.icon = r:CreateTexture(nil, "ARTWORK")
            r.icon:SetSize(PICK_ROW_H - 6, PICK_ROW_H - 6)
            r.icon:SetPoint("LEFT", r, "LEFT", 6, 0)
            r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            r.label = EllesmereUI.MakeFont(r, 11, nil, tR, tG, tB, tA)
            r.label:SetJustifyH("LEFT")
            r.label:SetWordWrap(false)
            r.label:SetMaxLines(1)
            r:SetScript("OnEnter", function(s)
                s.hl:SetColorTexture(1, 1, 1, hlA); s.label:SetTextColor(1, 1, 1, 1)
            end)
            r:SetScript("OnLeave", function(s)
                s.hl:SetColorTexture(1, 1, 1, 0); s.label:SetTextColor(tR, tG, tB, tA)
            end)
            self.rows[i] = r
            return r
        end

        -----------------------------------------------------------------------
        --  Custom Macro pane. Typed macro text, stored as a macrotext slot --
        --  the one kind that has nothing to enumerate.
        -----------------------------------------------------------------------
        local custom = CreateFrame("Frame", nil, menu)
        custom:SetPoint("TOPLEFT", menu.back, "BOTTOMLEFT", 7, -6)
        custom:SetPoint("TOPRIGHT", menu.back, "BOTTOMRIGHT", -7, -6)
        custom:SetHeight(150)
        custom:SetFrameLevel(menu:GetFrameLevel() + 2)
        custom:Hide()
        menu.custom = custom

        local function MakeInput(parent, height, multiline)
            local box = CreateFrame("EditBox", nil, parent)
            box:SetHeight(height)
            box:SetFrameLevel(parent:GetFrameLevel() + 1)
            box:SetFont(FONT, 11, "")
            box:SetTextColor(1, 1, 1, 0.9)
            box:SetAutoFocus(false)
            box:SetTextInsets(5, 5, 3, 3)
            box:SetMultiLine(multiline == true)
            -- Newlines are part of a macro, so a multiline box must not treat
            -- Enter as "commit"; the Add button is the only commit.
            if not multiline then
                box:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
            end
            box:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
            local bg = box:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0, 0, 0, 0.4)
            EllesmereUI.MakeBorder(box, 1, 1, 1, 0.10, EllesmereUI.PP)
            return box
        end

        local nameLbl = EllesmereUI.MakeFont(custom, 10, nil, tR, tG, tB, tA)
        nameLbl:SetPoint("TOPLEFT", custom, "TOPLEFT", 1, 0)
        nameLbl:SetText("Label")
        local nameBox = MakeInput(custom, 22, false)
        nameBox:SetPoint("TOPLEFT", nameLbl, "BOTTOMLEFT", 0, -3)
        nameBox:SetPoint("RIGHT", custom, "RIGHT", -1, 0)
        nameBox:SetMaxLetters(24)

        local textLbl = EllesmereUI.MakeFont(custom, 10, nil, tR, tG, tB, tA)
        textLbl:SetPoint("TOPLEFT", nameBox, "BOTTOMLEFT", 0, -8)
        textLbl:SetText("Macro Text")
        local textBox = MakeInput(custom, 62, true)
        textBox:SetPoint("TOPLEFT", textLbl, "BOTTOMLEFT", 0, -3)
        textBox:SetPoint("RIGHT", custom, "RIGHT", -1, 0)
        textBox:SetMaxLetters(255)

        local addBtn = CreateFrame("Button", nil, custom)
        addBtn:SetSize(70, 22)
        addBtn:SetPoint("TOPRIGHT", textBox, "BOTTOMRIGHT", 0, -8)
        addBtn:SetFrameLevel(custom:GetFrameLevel() + 1)
        local aBg = addBtn:CreateTexture(nil, "BACKGROUND")
        aBg:SetAllPoints()
        aBg:SetColorTexture(ACCENT.r, ACCENT.g, ACCENT.b, 0.20)
        EllesmereUI.MakeBorder(addBtn, ACCENT.r, ACCENT.g, ACCENT.b, 0.7, EllesmereUI.PP)
        local aTx = EllesmereUI.MakeFont(addBtn, 11, nil, 1, 1, 1, 0.9)
        aTx:SetPoint("CENTER")
        aTx:SetText("Add")
        addBtn:SetScript("OnEnter", function()
            aBg:SetColorTexture(ACCENT.r, ACCENT.g, ACCENT.b, 0.35)
        end)
        addBtn:SetScript("OnLeave", function()
            aBg:SetColorTexture(ACCENT.r, ACCENT.g, ACCENT.b, 0.20)
        end)
        addBtn:SetScript("OnClick", function()
            local body = strtrim(textBox:GetText() or "")
            if body == "" then return end
            local label = strtrim(nameBox:GetText() or "")
            if label == "" then label = "Macro" end
            -- No icon is stored: SlotDisplay falls back to the question mark,
            -- which is what an unnamed custom macro looks like on an action bar
            -- too.
            if AssignEntry({ slot = { kind = "macrotext", macrotext = body, name = label } }) then
                nameBox:SetText("")
                textBox:SetText("")
            end
        end)
        menu:SetScript("OnHide", function(m)
            m.search:ClearFocus()
            nameBox:ClearFocus()
            textBox:ClearFocus()
        end)

        -- Click-outside dismissal, same test the CDM picker uses. The anchor is
        -- excluded so the "+" click that toggles the menu shut is not also read
        -- as a click outside it.
        menu:SetScript("OnUpdate", function(m)
            if IsMouseButtonDown("LeftButton") and not m:IsMouseOver()
               and not (pickerAnchor and pickerAnchor:IsMouseOver()) then
                m:Hide()
            end
        end)

        pickerMenu = menu
        return menu
    end

    -- Anchors the list under whichever header rows the current view shows and
    -- sizes the menu to its content.
    local function PickerFit(menu, count)
        local top = PICK_HEAD_H + (menu.cat and PICK_NAV_H or 0)
        menu.scroll:ClearAllPoints()
        menu.scroll:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -top)
        menu.scroll:SetPoint("RIGHT", menu, "RIGHT", -1, 0)
        local listH = math.max(PICK_ROW_H, count * PICK_ROW_H)
        menu.list:SetHeight(listH)
        local visH = math.min(listH, PICK_MAX_LIST)
        menu.scroll:SetHeight(visH)
        menu:SetHeight(top + visH + 4)
        menu.scroll:SetVerticalScroll(0)
        menu:UpdateThumb()
    end

    ShowPickerCategories = function()
        local menu = EnsurePickerMenu()
        menu.cat = nil
        menu.title:SetText("Add Action")
        menu.back:Hide()
        -- Focus first: hiding a focused edit box leaves the keyboard captured by
        -- a box that is no longer on screen.
        menu.search:ClearFocus()
        menu.search:Hide()
        menu.custom:Hide()
        menu.scroll:Show()

        for i, cat in ipairs(PICKER_CATEGORIES) do
            local r = menu:GetRow(i)
            r.icon:Hide()
            -- Rows are shared with the entry views, which anchor the label to
            -- the icon -- so both views re-anchor it every time.
            r.label:ClearAllPoints()
            r.label:SetPoint("LEFT", r, "LEFT", 8, 0)
            r.label:SetPoint("RIGHT", r, "RIGHT", -6, 0)
            r.label:SetText(cat.label)
            r:SetScript("OnClick", function()
                if cat.custom then
                    ShowPickerCustom()
                else
                    menu.search:SetText("")
                    ShowPickerCategory(cat)
                end
            end)
            r:Show()
        end
        for i = #PICKER_CATEGORIES + 1, #menu.rows do menu.rows[i]:Hide() end

        PickerFit(menu, #PICKER_CATEGORIES)
        menu:Show()
    end

    ShowPickerCategory = function(cat)
        local menu = EnsurePickerMenu()
        menu.cat = cat
        menu.title:SetText(cat.label)
        menu.back:Show()
        menu.search:Show()
        menu.searchPH:SetShown((menu.search:GetText() or "") == "")
        menu.custom:Hide()
        menu.scroll:Show()

        local list = pickerLists[cat.key]
        if not list then
            list = cat.build()
            -- Alphabetical rather than in enumeration order: the spellbook's own
            -- grouping means nothing once the tabs are gone, and a name is what
            -- the user is scanning for. A category can opt out for a list whose
            -- own order IS the one the user knows -- the markers run star to
            -- skull, the order every marker menu in the game shows.
            if not cat.keepOrder then
                table.sort(list, function(a, b) return a.name < b.name end)
            end
            pickerLists[cat.key] = list
        end

        local filter = (menu.search:GetText() or ""):lower()
        local n = 0
        for _, entry in ipairs(list) do
            if filter == "" or entry.name:lower():find(filter, 1, true) then
                n = n + 1
                local r = menu:GetRow(n)
                r.icon:SetTexture(entry.icon or QUESTION_MARK)
                r.icon:Show()
                r.label:ClearAllPoints()
                r.label:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
                r.label:SetPoint("RIGHT", r, "RIGHT", -6, 0)
                r.label:SetText(entry.name)
                r:SetScript("OnClick", function() AssignEntry(entry) end)
                r:Show()
            end
        end

        local shown = n
        if n == 0 then
            -- An empty menu reads as broken, so say why it is empty.
            local r = menu:GetRow(1)
            r.icon:Hide()
            r.label:ClearAllPoints()
            r.label:SetPoint("LEFT", r, "LEFT", 8, 0)
            r.label:SetPoint("RIGHT", r, "RIGHT", -6, 0)
            r.label:SetText(filter == "" and "Nothing to add" or "No matches")
            r:SetScript("OnClick", nil)
            r:Show()
            shown = 1
        end
        for i = shown + 1, #menu.rows do menu.rows[i]:Hide() end

        PickerFit(menu, shown)
        menu:Show()
    end

    ShowPickerCustom = function()
        local menu = EnsurePickerMenu()
        -- No cat recorded: menu.cat means "a list view is up, re-filter it on a
        -- keystroke", and there is no list here.
        menu.cat = nil
        menu.title:SetText("Custom Macro")
        menu.back:Show()
        menu.search:ClearFocus()
        menu.search:Hide()
        -- Hiding the scroll frame takes the pooled rows with it: they are its
        -- scroll child's children.
        menu.scroll:Hide()
        menu.custom:Show()
        menu:SetHeight(PICK_HEAD_H + PICK_ROW_H + 6 + menu.custom:GetHeight() + 4)
        menu:Show()
    end

    local function TogglePicker(widget)
        local menu = EnsurePickerMenu()
        if menu:IsShown() and pickerAnchor == widget then
            HidePicker()
            return
        end
        -- Dropped per open, not per category view: bags, macros and collections
        -- all change while the game is running, and one open is the coarsest
        -- point at which a rebuild is still free (the keystroke filtering is
        -- what the cache is there to protect).
        wipe(pickerLists)
        pickerAnchor = widget
        menu:ClearAllPoints()
        menu:SetPoint("TOP", widget, "BOTTOM", 0, -4)
        -- Cleared before the SetText below, which fires OnTextChanged: with the
        -- previous open's category still recorded, that would re-enumerate and
        -- briefly show the wrong view.
        menu.cat = nil
        menu.search:SetText("")
        ShowPickerCategories()
    end

    ---------------------------------------------------------------------------
    --  Palette presets
    --
    --  Each builder returns the slots a new palette starts with, worked out
    --  from what THIS character knows or carries at the moment the chooser
    --  opens -- a preset must never seed a slot that cannot fire. A preset
    --  whose builder comes back empty is left out of the chooser, which is
    --  also how the class-specific ones gate themselves: IsPlayerSpell answers
    --  no to every spell on the wrong class.
    ---------------------------------------------------------------------------
    local function TargetMarkerSlots()
        local out = {}
        for i = 1, 8 do out[#out + 1] = { kind = "raidtarget", id = i } end
        out[#out + 1] = { kind = "raidtarget", id = 0 }
        return out
    end

    local function WorldMarkerSlots()
        local out = {}
        for i = 1, 8 do out[#out + 1] = { kind = "worldmarker", id = i } end
        out[#out + 1] = { kind = "worldmarker", id = 0 }
        return out
    end

    -- The base item plus its two expansion siblings, then the toy variants.
    -- The toys all share one cooldown and one destination, so past MAX_SLOTS
    -- the tail is interchangeable with what already made it in.
    local HEARTH_ITEMS = { 6948, 140192, 110560 }   -- Hearthstone, Dalaran, Garrison
    local HEARTH_TOYS = {
        54452,  64488,  93672,  142542, 162973, 163045, 165669, 165670,
        165802, 166746, 166747, 168907, 172179, 180290, 182773, 183716,
        184353, 188952, 190196, 190237, 193588, 200630, 206195, 208704,
        209035, 212337, 228940,
    }
    local function HearthstoneSlots()
        local out = {}
        for _, itemID in ipairs(HEARTH_ITEMS) do
            if C_Item.GetItemCount(itemID) > 0 then
                out[#out + 1] = { kind = "item", id = itemID }
            end
        end
        for _, toyID in ipairs(HEARTH_TOYS) do
            if #out >= MAX_SLOTS then break end
            if PlayerHasToy(toyID) then
                out[#out + 1] = { kind = "toy", id = toyID }
            end
        end
        return out
    end

    -- Self-teleports only, keyed by class. Mage portals are deliberately not
    -- here: a palette entry fires for its owner, and the teleport is the spell
    -- an owner wants.
    local TELEPORT_SPELLS = {
        DEATHKNIGHT = { 50977 },     -- Death Gate
        DRUID       = { 193753 },    -- Dreamwalk
        MONK        = { 126892 },    -- Zen Pilgrimage
        SHAMAN      = { 556 },       -- Astral Recall
        MAGE = {
            3561, 3562, 3563, 3565, 3566, 3567,        -- the classic capitals
            32271, 32272, 33690, 35715, 49358, 49359,  -- Outland-era cities
            53140, 88342, 88344, 132621, 132627,       -- Dalaran, Tol Barad, Vale
            176248, 176242, 224869, 281403, 281404,    -- Warspear era through Boralus
            344587, 395277, 446540,                    -- Oribos, Valdrakken, Dornogal
        },
    }
    local function TeleportSlots()
        local out = {}
        local list = TELEPORT_SPELLS[select(2, UnitClass("player"))]
        for _, spellID in ipairs(list or {}) do
            if #out >= MAX_SLOTS then break end
            if IsPlayerSpell(spellID) then
                out[#out + 1] = { kind = "spell", id = spellID }
            end
        end
        return out
    end

    -- The same bag walk ItemEntries does, narrowed to drinkable consumables.
    -- Numeric subclasses: Enum.ItemConsumableSubclass stops at Other, the
    -- finer rows exist only as these constants (ItemDocumentation.lua).
    local function PotionSlots()
        local out, seen = {}, {}
        local function ScanBag(bag)
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                local itemID = info and info.itemID
                if itemID and not seen[itemID] and #out < MAX_SLOTS
                   and C_Item.GetItemSpell(itemID) then
                    seen[itemID] = true
                    local classID, subClassID = select(6, C_Item.GetItemInfoInstant(itemID))
                    if classID == Enum.ItemClass.Consumable
                       and (subClassID == 1 or subClassID == 2 or subClassID == 3) then
                        out[#out + 1] = { kind = "item", id = itemID }
                    end
                end
            end
        end
        for bag = Enum.BagIndex.Backpack, NUM_BAG_SLOTS do ScanBag(bag) end
        ScanBag(Enum.BagIndex.ReagentBag)
        return out
    end

    local FORM_SPELLS = { 5487, 768, 783, 24858, 114282 }  -- Bear, Cat, Travel, Moonkin, Treant
    local function FormSlots()
        local out = {}
        for _, spellID in ipairs(FORM_SPELLS) do
            if IsPlayerSpell(spellID) then
                out[#out + 1] = { kind = "spell", id = spellID }
            end
        end
        return out
    end

    local PALETTE_PRESETS = {
        { label = "Target Markers", build = TargetMarkerSlots },
        { label = "World Markers",  build = WorldMarkerSlots },
        { label = "Hearthstones",   build = HearthstoneSlots },
        { label = "Teleports",      build = TeleportSlots },
        { label = "Potions",        build = PotionSlots },
        { label = "Druid Forms",    build = FormSlots },
    }

    ---------------------------------------------------------------------------
    --  Adding and deleting palettes
    --
    --  The palette count used to be a slider. A slider says nothing about what
    --  the new palette will hold; the Add button opens a chooser instead --
    --  empty, or seeded from one of the presets above.
    ---------------------------------------------------------------------------

    -- slots comes in already built (the chooser built it to decide whether to
    -- offer the preset at all), and each table in it is fresh from the
    -- builder, so nothing here needs copying.
    local function AddPalette(preset, slots)
        local count = PaletteCount()
        if count >= MAX_PALETTES then return end
        Set("paletteCount", count + 1)
        local palette = Palette(count + 1)
        if palette then
            -- The index may have been used and abandoned by the retired
            -- palette-count slider, whose decrease hid palettes without
            -- clearing them. A palette added on purpose starts empty.
            palette.slots = {}
            palette.icon = nil
            palette.name = (preset and preset.label) or AutoName(count + 1)
            for _, s in ipairs(slots or {}) do
                if not ns.AddSlot(palette, s) then break end
            end
        end
        editPalette = count + 1
        HidePicker()
        RebuildPage()
    end

    -- A view on the same anchored menu the action picker uses, so the add
    -- button and the "+" entry cannot both have one open: whichever opens
    -- second takes the menu over.
    local function ShowAddPaletteMenu(anchor)
        if not anchor then return end
        local menu = EnsurePickerMenu()
        if menu:IsShown() and pickerAnchor == anchor then
            HidePicker()
            return
        end
        pickerAnchor = anchor
        menu:ClearAllPoints()
        menu:SetPoint("TOP", anchor, "BOTTOM", 0, -4)
        menu.cat = nil
        menu.title:SetText("Add Palette")
        menu.back:Hide()
        menu.search:ClearFocus()
        menu.search:Hide()
        menu.custom:Hide()
        menu.scroll:Show()

        local function FillRow(i, icon, label, onClick)
            local r = menu:GetRow(i)
            if icon then
                r.icon:SetTexture(icon)
                r.icon:Show()
                r.label:ClearAllPoints()
                r.label:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
            else
                r.icon:Hide()
                r.label:ClearAllPoints()
                r.label:SetPoint("LEFT", r, "LEFT", 8, 0)
            end
            r.label:SetPoint("RIGHT", r, "RIGHT", -6, 0)
            r.label:SetText(label)
            r:SetScript("OnClick", onClick)
            r:Show()
        end

        FillRow(1, nil, "Empty Palette", function() AddPalette(nil) end)
        local n = 1
        for _, preset in ipairs(PALETTE_PRESETS) do
            local slots = preset.build()
            if #slots > 0 then
                n = n + 1
                local icon = ns.SlotDisplay(slots[1])
                FillRow(n, icon or QUESTION_MARK,
                    preset.label .. "  |cff808080(" .. #slots .. ")|r",
                    function() AddPalette(preset, slots) end)
            end
        end
        for i = n + 1, #menu.rows do menu.rows[i]:Hide() end

        PickerFit(menu, n)
        menu:Show()
    end

    -- Deletion really removes the palette rather than hiding it the way the
    -- slider's decrease did: the palettes above it close ranks, and everything
    -- that pointed at them follows -- nested entries repoint to the shifted
    -- index, entries that opened the deleted palette are removed, and each
    -- shifted palette's keybind moves with it.
    local function DeletePalette(index)
        local p = DB()
        local count = PaletteCount()
        if not p or count <= 1 or index < 1 or index > count then return end

        -- The keybind shift below runs SetBinding, so the same combat wall the
        -- keybind picker documents applies to the whole operation.
        if InCombatLockdown() then
            Complain("Action Palette: palettes can't be deleted in combat.")
            return
        end

        -- Materialize every live palette first: the shift walks 1 .. count and
        -- table.remove stops at the first hole.
        for i = 1, count do Palette(i) end

        table.remove(p.palettes, index)
        Set("paletteCount", count - 1)

        for i = 1, count - 1 do
            local palette = Palette(i)
            for j = #palette.slots, 1, -1 do
                local s = palette.slots[j]
                if s.kind == "palette" then
                    local target = tonumber(s.palette)
                    if target == index then
                        table.remove(palette.slots, j)
                    elseif target and target > index then
                        s.palette = target - 1
                    end
                end
            end
        end

        -- Each action can hold TWO keys (see CommitKey), so the whole set is
        -- snapshotted, everything from the deleted index up is unbound, and
        -- then each successor's keys are rebound one action lower. Interleaving
        -- the two passes would unbind keys the previous step just moved.
        local keys, any = {}, false
        for n = 1, MAX_BOUND_PALETTES do
            keys[n] = { GetBindingKey(BINDING_PREFIX .. n) }
            if n >= index and keys[n][1] then any = true end
        end
        for n = index, MAX_BOUND_PALETTES do
            for _, k in ipairs(keys[n]) do SetBinding(k) end
        end
        for n = index, MAX_BOUND_PALETTES - 1 do
            for _, k in ipairs(keys[n + 1] or {}) do
                SetBinding(k, BINDING_PREFIX .. n)
            end
        end
        if any then SaveBindings(GetCurrentBindingSet()) end

        -- Keep the editor pointed at the palette it was on, which now sits one
        -- index lower; deleting the edited palette itself falls to whichever
        -- palette took its number.
        if editPalette > index then editPalette = editPalette - 1 end
        if editPalette > count - 1 then editPalette = count - 1 end
        RebuildPage()
    end

    -- Which slot the cursor is over, for the reorder drag. The live palette's own
    -- HitTest answers this from the angle to the hub, which only means anything
    -- on a circle -- in a fan it would report a entry the user is nowhere near.
    -- Nearest widget CENTRE is the layout-agnostic form of the same question,
    -- and it also follows the strip while it slides.
    local function PreviewDropTarget()
        if not previewView:IsFan() then return previewView:HitTest() end

        local shown = previewView:ShownCount()
        if shown < 1 then return nil end

        local mx, my = GetCursorPosition()
        local best, bestDist
        for i = 1, shown do
            local w = previewView:GetSlotWidget(i)
            -- Not folded into an `and`: that truncates to one value and would
            -- drop cy on the floor.
            local cx, cy
            if w:IsShown() then cx, cy = w:GetCenter() end
            if cx then
                -- GetCenter is in the widget's own scaled space; the cursor is
                -- in screen units, so the scale has to be applied to compare.
                local es = w:GetEffectiveScale()
                local dx, dy = mx - cx * es, my - cy * es
                local d = dx * dx + dy * dy
                if not bestDist or d < bestDist then best, bestDist = i, d end
            end
        end
        return best
    end

    local function EndPreviewDrag()
        if dragFrom then
            local w = previewView:GetSlotWidget(dragFrom)
            w:SetAlpha(1)
            w:SetFrameLevel(previewView:GetFrame():GetFrameLevel() + 1)
        end
        dragFrom, dragging = nil, false
        previewView:SetSelection(nil)
    end

    local function InstallPreviewScripts()
        for i = 1, (ns.MAX_SLOTS or 12) do
            local w = previewView:GetSlotWidget(i)
            w:RegisterForClicks("LeftButtonUp", "RightButtonUp")

            w:SetScript("OnEnter", function(self)
                if dragging then return end
                -- Reuse the selection paint: hovering an entry in the panel looks
                -- exactly like steering onto it in play.
                previewView:SetSelection(self.index)
                PreviewTooltip(self)
            end)
            w:SetScript("OnLeave", function()
                if dragging then return end
                previewView:SetSelection(nil)
                GameTooltip:Hide()
            end)

            w:SetScript("OnClick", function(self, button)
                if button == "RightButton" then
                    if self.isPlaceholder then return end
                    local palette = Palette(editPalette)
                    if palette and ns.RemoveSlot(palette, self.index) then Refresh() end
                    return
                end
                -- A loaded cursor still means "place this here" on every entry;
                -- the picker is the empty-cursor path on the "+" only.
                if self.isPlaceholder and not GetCursorInfo() then
                    TogglePicker(self)
                    return
                end
                PreviewPlace(self)
            end)
            w:SetScript("OnReceiveDrag", function(self) PreviewPlace(self) end)

            w:SetScript("OnMouseDown", function(self, button)
                if button ~= "LeftButton" or self.isPlaceholder then return end
                -- A loaded cursor means "place this here", not "reorder".
                if GetCursorInfo() then return end
                local es = previewView:GetFrame():GetEffectiveScale()
                local x, y = GetCursorPosition()
                dragStartX, dragStartY = x / es, y / es
                dragFrom, dragTarget = self.index, nil
            end)

            -- OnMouseUp is delivered to the frame that got OnMouseDown even when
            -- the cursor has left it, which is what makes the drop work at all.
            w:SetScript("OnMouseUp", function(self, button)
                if button ~= "LeftButton" or dragFrom ~= self.index then return end
                local from, to, moved = dragFrom, dragTarget, dragging
                EndPreviewDrag()
                if not moved or not to then return end
                local palette = Palette(editPalette)
                if palette and ns.MoveSlot(palette, from, to) then Refresh() end
            end)
        end
    end

    -- yPos is the running page offset; returns the height consumed.
    local function BuildPreview(parent, yPos)
        -- PanelPP, not PP: panel-context geometry snaps to the options window's
        -- own pixel grid, which is what every other options page uses.
        local PP = EllesmereUI.PanelPP
        local CONTENT_PAD = EllesmereUI.CONTENT_PAD or 45

        -- A rebuild re-fans the palette, so the entry the picker is anchored to may
        -- not be the "+" any more -- and an already-open menu would then be
        -- pointing at an unrelated slot.
        HidePicker()

        if not previewBlock then
            previewBlock = CreateFrame("Frame", nil, parent)

            local bg = previewBlock:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0, 0, 0, 0.18)

            previewView = ns.CreatePaletteView(previewBlock, {
                interactive = true,
                geom        = PreviewGeom,
                -- Labels would collide at the fitted scale, and the hub plus the
                -- tooltip already name whatever the cursor is over.
                showLabels  = false,
                -- Arrangement is what this preview is for; a live cooldown swipe
                -- on a settings page is only noise.
                showCooldowns = false,
                -- Kept short on purpose: the hub line is drawn centered inside a
                -- an arc only ~75px in radius, and anything longer runs under the
                -- entries at 3 and 9 o'clock. The rest is in the slot tooltips.
                hintText    = function(n)
                    if n == 0 then return "click + to add an action" end
                    return "drag to reorder"
                end,
            })
            previewView:GetFrame():SetPoint("CENTER", previewBlock, "CENTER", 0, 0)
            InstallPreviewScripts()

            previewBlock:SetScript("OnUpdate", function()
                if not dragFrom then return end
                local es = previewView:GetFrame():GetEffectiveScale()
                local x, y = GetCursorPosition()
                x, y = x / es, y / es
                if not dragging then
                    if math.abs(x - dragStartX) < DRAG_THRESHOLD
                       and math.abs(y - dragStartY) < DRAG_THRESHOLD then return end
                    dragging = true
                    local w = previewView:GetSlotWidget(dragFrom)
                    w:SetAlpha(0.4)
                    w:SetFrameLevel(previewView:GetFrame():GetFrameLevel() + 20)
                    GameTooltip:Hide()
                end
                -- The entry under the cursor. The "+" entry resolves to the
                -- last real slot, so dropping there means "move to the end".
                local hit = PreviewDropTarget()
                -- n can reach 0 mid-drag -- right-click removes while the left
                -- button is still held -- and min(hit, 0) is 0, which is TRUTHY
                -- in Lua and would index widget 0.
                local n = previewView:SlotCount()
                dragTarget = (hit and n > 0) and math.min(hit, n) or nil
                previewView:SetSelection(dragTarget)
            end)

            -- A press held while the panel closes under it (Esc, or the combat
            -- auto-hide) would otherwise resume as a phantom drag on reshow.
            previewBlock:SetScript("OnHide", function()
                if dragFrom then EndPreviewDrag() end
                -- The picker is parented to UIParent, so it does not follow the
                -- panel down by itself. OnHide propagates from the wrapper, so
                -- this covers closing the window and switching page alike.
                HidePicker()
            end)

            -- Blocks the preview outright while the module is off, matching the
            -- disabled overlay the standard rows draw over themselves.
            local dim = CreateFrame("Frame", nil, previewBlock)
            dim:SetAllPoints()
            dim:EnableMouse(true)
            local dimTex = dim:CreateTexture(nil, "OVERLAY")
            dimTex:SetAllPoints()
            dimTex:SetColorTexture(0.06, 0.08, 0.10, 0.70)
            dim:SetScript("OnEnter", function(self)
                if EllesmereUI.ShowWidgetTooltip then
                    EllesmereUI.ShowWidgetTooltip(self, "Enable the module to edit palettes.")
                end
            end)
            dim:SetScript("OnLeave", function()
                if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
            end)
            previewBlock._dim = dim
        end

        previewBlock:SetParent(parent)
        previewBlock:ClearAllPoints()
        -- Anchored on both sides rather than sized from parent:GetWidth(): the
        -- wrapper's own width is not resolved yet on the first build, and this
        -- block is cached, so a zero read would stick for the panel's lifetime.
        PP.Point(previewBlock, "TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, yPos)
        PP.Point(previewBlock, "TOPRIGHT", parent, "TOPRIGHT", -CONTENT_PAD, yPos)
        PP.Height(previewBlock, PREVIEW_H)
        -- Re-asserted per build: an explicit frame level is absolute, and the
        -- block's own level moves when it is re-parented to a fresh wrapper.
        previewBlock._dim:SetFrameLevel(previewBlock:GetFrameLevel() + 30)
        previewBlock._dim:SetShown(Cfg("enabled") == false)
        previewBlock:Show()
        previewView:Layout(editPalette)
        -- A freshly laid out strip sits at its default centre, which is a
        -- position between entries rather than on one. Park it on the first
        -- slot so the preview opens looking like the strip in play does. Only a
        -- SCROLLED strip has a centre at all: the grid and the pointer-steered
        -- fan draw every entry at a fixed position and select by proximity.
        if previewView:IsFan() and not previewView:IsGrid()
           and not previewView:IsHoverFan() then
            previewView:SetFanCenter(1)
        end

        return PREVIEW_H
    end

    ---------------------------------------------------------------------------
    --  Build Page
    ---------------------------------------------------------------------------
    local function BuildPage(pageName, parent, yOffset)
        _installPickerAutoOff()

        local W = EllesmereUI.Widgets
        local y = yOffset
        local row, h

        if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end
        parent._showRowDivider = true

        local function Disabled() return Cfg("enabled") == false end

        local centerValues = { CURSOR = "At Cursor", SCREEN = "Fixed Position" }
        local centerOrder  = { "CURSOR", "SCREEN" }

        local layoutValues = { ARC = "Arc", FAN = "Fan", GRID = "Grid" }
        local layoutOrder  = { "GRID", "FAN", "ARC" }

        local orientValues = { HORIZONTAL = "Horizontal", VERTICAL = "Vertical" }
        local orientOrder  = { "HORIZONTAL", "VERTICAL" }

        local fanInputValues = { SCROLL = "Mouse Wheel", CURSOR = "Pointer" }
        local fanInputOrder  = { "SCROLL", "CURSOR" }

        -- ── GENERAL ──────────────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "GENERAL", y); y = y - h

        local addPaletteBtn
        row, h = W:DualRow(parent, y,
            { type="toggle", text="Enable Action Palette",
              getValue=function() return Cfg("enabled") ~= false end,
              setValue=function(v) Set("enabled", v); RebuildPage() end },
            -- The chooser it opens offers an empty palette or a preset. Past
            -- MAX_BOUND_PALETTES a new palette has no key of its own and is
            -- reachable only by being nested in another palette, which is what
            -- the keybind row in PALETTE SETUP explains.
            { type="labeledButton", text="Add Palette",
              disabled=function()
                  return Disabled() or PaletteCount() >= MAX_PALETTES
              end,
              disabledTooltip=(PaletteCount() >= MAX_PALETTES)
                  and ("this profile already holds " .. MAX_PALETTES
                       .. " palettes")
                  or "the module",
              buttonText="Empty or Preset...",
              -- An upvalue filled in below, not an onClick parameter: the
              -- styled button invokes its handler with no arguments
              -- (EllesmereUI_Widgets.lua:399), so the chooser has to reach the
              -- frame it anchors under some other way.
              onClick=function() ShowAddPaletteMenu(addPaletteBtn) end })
        addPaletteBtn = row._rightRegion and row._rightRegion._control
        y = y - h

        -- ── PALETTE SETUP ───────────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "PALETTE SETUP", y); y = y - h

        local paletteValues, paletteOrder = {}, {}
        for i = 1, PaletteCount() do
            local r = Palette(i)
            paletteValues[i] = (r and r.name) or AutoName(i)
            paletteOrder[#paletteOrder + 1] = i
        end

        local keyForEditPalette = GetBindingKey(BINDING_PREFIX .. editPalette)

        row, h = W:DualRow(parent, y,
            -- noCapture: which palette the preview is pointed at is panel-session
            -- state, not a setting, so it must not be banked as a per-spec
            -- override by the Spec Overrides capture pass.
            { type="dropdown", text="Editing Palette", noCapture=true,
              disabled=Disabled, disabledTooltip="the module",
              values=paletteValues, order=paletteOrder,
              getValue=function() return editPalette end,
              setValue=function(v)
                  editPalette = v
                  -- Full rebuild, not a preview relayout: the keybind button's
                  -- label is baked in at build time from THIS palette's key.
                  RebuildPage()
              end },
            -- buttonText is consumed as a literal string, so the label is
            -- resolved at build time. Both things that can change it --
            -- committing a key and switching the edited palette -- rebuild the
            -- page, so it cannot go stale while the panel is open.
            { type="labeledButton", text="Palette Keybind",
              disabled=function()
                  return Disabled() or editPalette > MAX_BOUND_PALETTES
              end,
              disabledTooltip=(editPalette > MAX_BOUND_PALETTES)
                  and ("only the first " .. MAX_BOUND_PALETTES .. " palettes can "
                       .. "take a key -- open this one by nesting it inside "
                       .. "another palette")
                  or "the module",
              buttonText=(editPalette > MAX_BOUND_PALETTES) and "Nested Only"
                  or (listenPalette == editPalette) and "Press a key..."
                  or (keyForEditPalette and (GetBindingText(keyForEditPalette) or keyForEditPalette)
                      or "Click to Bind"),
              onClick=function() StartListening(editPalette) end })
        y = y - h

        -- Name and icon of the palette the dropdown above is pointed at, so they
        -- sit with the selector rather than in APPEARANCE: everything else in
        -- that section describes every palette at once.
        --
        -- noCapture on both, for the same reason the selector opts out: these
        -- live inside p.palettes[n] rather than under a flat key, and a per-spec
        -- override banked against whichever palette was on screen at capture
        -- time would rename a palette the user was not looking at.
        local editedPalette = Palette(editPalette)
        row, h = W:DualRow(parent, y,
            { type="input", text="Palette Name", noCapture=true,
              inputStyle="popup", inputWidth=170, placeholder=AutoName(editPalette),
              disabled=Disabled, disabledTooltip="the module",
              tooltip="Shown in the center of this palette, and on the entry that "
                  .. "opens it from another palette. Clear the box for "
                  .. AutoName(editPalette) .. ".",
              -- The auto name shows as an EMPTY box: the placeholder then says
              -- what an empty box means, and the user never has to delete a
              -- name they did not type.
              getValue=function()
                  local pal = Palette(editPalette)
                  local nm = pal and pal.name
                  if not nm or nm == AutoName(editPalette) then return "" end
                  return nm
              end,
              setValue=function(txt)
                  local pal = Palette(editPalette)
                  if not pal then return end
                  local nm = strtrim(txt or "")
                  nm = (nm ~= "") and nm or AutoName(editPalette)
                  -- Only on a real change. Every commit fires on focus loss too,
                  -- including the one where the user simply clicked away, and
                  -- rebuilding the page under that click would swallow it.
                  if nm == pal.name then return end
                  pal.name = nm
                  -- Rebuild: the selector's own labels are baked in above, so a
                  -- plain refresh would leave the dropdown naming the old one.
                  RebuildPage()
              end },
            { type="input", text="Palette Icon", noCapture=true,
              inputStyle="popup", inputWidth=100, placeholder="spell ID",
              disabled=Disabled, disabledTooltip="the module",
              tooltip="Icon for the entry that opens this palette from another "
                  .. "palette. Enter a spell, item, or icon ID. Clear the box to "
                  .. "go back to the first action's icon.",
              getValue=function()
                  local pal = Palette(editPalette)
                  return (pal and pal.icon) and tostring(pal.icon) or ""
              end,
              setValue=function(txt)
                  local pal = Palette(editPalette)
                  if not pal then return end
                  -- Compared as TEXT, before resolving. Once committed the box
                  -- shows the resolved icon ID, and running that number back
                  -- through the lookup could land on an unrelated spell that
                  -- happens to share it -- so an untouched box is a no-op
                  -- rather than a second lookup. This also swallows the commit
                  -- that every focus loss fires, which would otherwise rebuild
                  -- the page under the click that caused it.
                  local raw = strtrim(txt or "")
                  if raw == ((pal.icon and tostring(pal.icon)) or "") then return end
                  pal.icon = ResolveIconInput(raw)
                  RebuildPage()
              end })
        -- Live preview beside the box, anchored to the box itself rather than to
        -- a measured offset from the row's edge. Nothing refreshes it in place:
        -- both things that change it -- a commit here, and switching palette --
        -- rebuild the page.
        local iconBox = row._rightRegion and row._rightRegion._control
        if iconBox then
            iconBox:SetMaxLetters(10)
            local tex = row._rightRegion:CreateTexture(nil, "ARTWORK")
            tex:SetSize(24, 24)
            tex:SetPoint("RIGHT", iconBox, "LEFT", -8, 0)
            tex:SetTexture(editedPalette and editedPalette.icon or nil)
            tex:SetShown(editedPalette ~= nil and editedPalette.icon ~= nil)
        end
        local nameBox = row._leftRegion and row._leftRegion._control
        -- The hub caption is drawn inside a small arc, so a name longer than
        -- this runs out under the entries either side of it.
        if nameBox then nameBox:SetMaxLetters(24) end
        y = y - h

        -- Baked at build time like the keybind label above: the name it shows
        -- and the count that disables it both rebuild the page when they
        -- change.
        local editedName = (editedPalette and editedPalette.name)
            or AutoName(editPalette)
        row, h = W:DualRow(parent, y,
            { type="labeledButton", text="Delete Palette",
              disabled=function()
                  return Disabled() or PaletteCount() <= 1
              end,
              disabledTooltip=(PaletteCount() <= 1)
                  and "the last palette can't be deleted"
                  or "the module",
              buttonText="Delete " .. editedName,
              onClick=function()
                  EllesmereUI:ShowConfirmPopup({
                      title = "Delete Palette",
                      message = "Delete " .. editedName .. " and its "
                          .. "contents? Entries in other palettes that open "
                          .. "it are removed too, and the palettes after it "
                          .. "move up one place.",
                      confirmText = "Delete",
                      cancelText = "Cancel",
                      onConfirm = function() DeletePalette(editPalette) end,
                  })
              end })
        y = y - h

        y = y - BuildPreview(parent, y)

        -- ── PLACEMENT & SIZE ─────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "PLACEMENT & SIZE", y); y = y - h

        -- The X/Y offsets ride along with the mode dropdown because they only
        -- mean anything in Fixed Position mode -- in cursor mode the palette
        -- opens wherever the mouse is. They are also the ONLY way to place the
        -- palette: the on-screen drag editor is gone, and this module is not yet
        -- registered with Unlock Mode.
        local fixedOnly = function()
            return Disabled() or (Cfg("centerMode") or "CURSOR") ~= "SCREEN"
        end

        -- A fan has no radius, no angle and no centre to steer away from, so the
        -- settings that describe those are dead in it -- and the arc has no
        -- strip, so the fan's own settings are dead in turn. Every set stays
        -- visible and disabled rather than disappearing: a control that
        -- vanishes when a dropdown moves reads as a bug.
        --
        -- Four predicates, because the layouts do not partition cleanly: the
        -- grid shares the strip's spacing but steers like nothing else, a
        -- pointer-steered fan has no scrolling to describe, and the falloffs
        -- belong to all three and so are gated by none of them.
        local function LayoutMode() return Cfg("layout") or "ARC" end
        local function IsFanLayout() return LayoutMode() == "FAN" end

        local arcOnly = function()
            return Disabled() or LayoutMode() ~= "ARC"
        end
        -- Anything laid out as icons at a fixed pitch: both fans and the grid.
        -- The arc spaces by angle, so a pitch says nothing about it.
        local stripOnly = function()
            return Disabled() or LayoutMode() == "ARC"
        end
        local fanOnly = function()
            return Disabled() or not IsFanLayout()
        end
        -- The window-and-scroll settings: a pointer-steered fan draws the whole
        -- palette at fixed positions, so it culls nothing, animates nothing and
        -- has no wheel direction to invert.
        local scrollFanOnly = function()
            return Disabled() or not IsFanLayout()
                or (Cfg("fanInput") or "SCROLL") ~= "SCROLL"
        end
        local gridOnly = function()
            return Disabled() or LayoutMode() ~= "GRID"
        end
        -- The two falloff ratios say how steep the depth cue is, which is not a
        -- question at all once it has been switched off.
        local falloffOff = function()
            return Disabled() or Cfg("falloff") == false
        end
        -- Every layout nests. Kept as a predicate of its own because the reason
        -- a control is dead is worth saying separately from what it is dead for.
        local nestless = function()   -- true when the control is DEAD, as with arcOnly above
            return Disabled()
        end
        -- Where a nest sits is only a question when the sides are equidistant --
        -- which is every strip, both of whose long sides are. On a grid the side
        -- NEAREST the entry wins, except under Popout, where a middle entry has
        -- no nearest side and this answers for it. The arc has no sides at all.
        local nestSideDead = function()
            if nestless() then return true end
            if LayoutMode() == "ARC" then return true end
            return false
        end
        -- Only a grid has an interior and corners to arrange around; a strip
        -- ignores the setting outright.
        local gridNestDead = function()
            return nestless() or LayoutMode() ~= "GRID"
        end

        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Layout",
              disabled=Disabled, disabledTooltip="the module",
              values=layoutValues, order=layoutOrder,
              getValue=function() return Cfg("layout") or "ARC" end,
              -- Rebuild, not Refresh: this is what decides which of the two
              -- sets of controls below is live.
              setValue=function(v) Set("layout", v); RebuildPage() end },
            { type="dropdown", text="Fan Direction",
              disabled=fanOnly, disabledTooltip="a Fan layout",
              values=orientValues, order=orientOrder,
              getValue=function() return Cfg("fanOrientation") or "HORIZONTAL" end,
              setValue=function(v) Set("fanOrientation", v); Refresh() end })
        y = y - h

        row, h = W:DropdownWithOffsets(parent, y,
            { type="dropdown", text="Opens",
              disabled=Disabled, disabledTooltip="the module",
              values=centerValues, order=centerOrder,
              getValue=function() return Cfg("centerMode") or "CURSOR" end,
              setValue=function(v) Set("centerMode", v); RebuildPage() end },
            { type="slider", text="X",
              disabled=fixedOnly, disabledTooltip="Fixed Position mode",
              min=-800, max=800, step=1,
              getValue=function() return Cfg("posX") or 0 end,
              setValue=function(v) Set("posX", v); Refresh() end },
            { type="slider", text="Y",
              disabled=fixedOnly, disabledTooltip="Fixed Position mode",
              min=-600, max=600, step=1,
              getValue=function() return Cfg("posY") or 0 end,
              setValue=function(v) Set("posY", v); Refresh() end })
        y = y - h

        -- Two per row, not three: at a third of the row width a label like
        -- "Background Opacity" is truncated, so the setting stops being readable.
        row, h = W:DualRow(parent, y,
            { type="slider", text="Arc Radius",
              disabled=arcOnly, disabledTooltip="the Arc layout",
              min=50, max=220, step=1,
              getValue=function() return Cfg("radius") or 96 end,
              setValue=function(v) Set("radius", v); Refresh() end },
            { type="slider", text="Icon Size",
              disabled=Disabled, disabledTooltip="the module",
              min=24, max=72, step=1,
              getValue=function() return Cfg("iconSize") or 44 end,
              setValue=function(v) Set("iconSize", v); Refresh() end })
        y = y - h

        -- 360 is a full turn, and a rotation of a full circle is a no-op --
        -- so the rotation only becomes live once the span has been narrowed to
        -- an arc that has somewhere to point.
        row, h = W:DualRow(parent, y,
            { type="slider", text="Arc Span",
              disabled=arcOnly, disabledTooltip="the Arc layout",
              min=30, max=360, step=5,
              getValue=function() return Cfg("arcSpan") or 360 end,
              setValue=function(v) Set("arcSpan", v); Refresh() end },
            { type="slider", text="Arc Rotation",
              disabled=function()
                  return arcOnly() or (Cfg("arcSpan") or 360) >= 360
              end,
              disabledTooltip="an Arc Span below 360",
              min=-180, max=180, step=5,
              getValue=function() return Cfg("arcRotation") or 0 end,
              setValue=function(v) Set("arcRotation", v); Refresh() end })
        y = y - h

        row, h = W:DualRow(parent, y,
            -- Floor of 8, not 0: the dead zone is what makes "release without
            -- steering" a cancel, and at 0 there is no cancel region at all.
            { type="slider", text="Dead Zone",
              disabled=arcOnly, disabledTooltip="the Arc layout",
              min=8, max=80, step=1,
              getValue=function() return Cfg("deadZone") or 24 end,
              setValue=function(v) Set("deadZone", v); Refresh() end },
            { type="slider", text="Scale",
              disabled=Disabled, disabledTooltip="the module",
              min=0.5, max=2.0, step=0.01,
              getValue=function() return Cfg("scale") or 1.0 end,
              setValue=function(v) Set("scale", v); Refresh() end })
        y = y - h

        -- ── FAN & GRID ───────────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "NESTED PALETTES", y); y = y - h

        -- Distance and icon size are common to every layout. The two below them
        -- are the arc's alone: it is the only layout that carves its nests out
        -- of angles rather than setting them down in boxes.
        row, h = W:DualRow(parent, y,
            -- The gap between the two rings' icons, not a radius, so what the
            -- number says is what the eye measures. The Lane style reads it as
            -- clearance ON TOP of the gap it already hugs the block by: at the
            -- default and anywhere below it that style holds its children
            -- against the grid, and only the travel above the default pushes
            -- them off it.
            { type="slider", text="Nest Distance",
              disabled=nestless, disabledTooltip="the module",
              min=0, max=160, step=1,
              getValue=function() return Cfg("nestBand") or 40 end,
              setValue=function(v) Set("nestBand", v); Refresh() end },
            -- Both spread a nest along the arc as far as Max Nest Span, so its
            -- children stay on one ring for as long as they fit. Contained
            -- stops at the midpoint with the next NEST either side, so two of
            -- them are never drawn over one another; Overflowing spends the
            -- whole span whatever is out there. Either way the plain entries
            -- under a nest give up their angles only while it is open, so a
            -- flick that goes nowhere near a nest still fires what it points
            -- at.
            { type="dropdown", text="Nest Width",
              disabled=arcOnly, disabledTooltip="the Arc layout",
              tooltip="How far along the arc a nest may spread its entries."
                      .." Contained keeps it clear of the next nest either side,"
                      .." so two of them are never drawn on top of one another."
                      .." Overflowing lets it use the whole of Max Nest Span."
                      .." A nest reaches over the plain entries it passes, and"
                      .." they only give up their angles while it is open.",
              values={ NONE = "Contained", MIDPOINT = "Overflowing" },
              order={ "NONE", "MIDPOINT" },
              getValue=function() return Cfg("arcChildOverflow") or "NONE" end,
              setValue=function(v) Set("arcChildOverflow", v); Refresh() end })
        y = y - h

        row, h = W:DualRow(parent, y,
            -- The widest a nest may spread along the arc, at BOTH nest widths:
            -- children past what it buys go onto a second ring further out.
            { type="slider", text="Max Nest Span",
              disabled=arcOnly, disabledTooltip="the Arc layout",
              tooltip="The widest angle a nest's entries may spread over."
                      .." They stay on one ring for as long as they fit inside"
                      .." it; the rest go onto a second ring further out.",
              min=30, max=180, step=5,
              getValue=function() return Cfg("arcChildMaxSpan") or 90 end,
              setValue=function(v) Set("arcChildMaxSpan", v); Refresh() end },
            -- Smaller than the palette's own entries, so a nest reads as
            -- subordinate to the entry it opens from. Drawing only: the sectors
            -- are angular, so this changes nothing about what a release picks.
            { type="slider", text="Nest Icon Size",
              disabled=nestless, disabledTooltip="the module",
              min=0.4, max=1.0, step=0.05,
              getValue=function() return Cfg("nestScale") or 0.8 end,
              setValue=function(v) Set("nestScale", v); Refresh() end })
        y = y - h

        -- Named for the axis in front of the user rather than for the sign it
        -- stores: "above" and "right" are the same choice to the code and two
        -- quite different sentences to read.
        local vertical = IsFanLayout() and Cfg("fanOrientation") == "VERTICAL"
        local sideValues = vertical
            and { POSITIVE = "Right", NEGATIVE = "Left" }
            or  { POSITIVE = "Above", NEGATIVE = "Below" }

        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Nest Side",
              disabled=nestSideDead,
              disabledTooltip="the Grid or a Fan layout",
              values=sideValues, order={ "POSITIVE", "NEGATIVE" },
              getValue=function() return Cfg("nestSide") or "POSITIVE" end,
              setValue=function(v) Set("nestSide", v); Refresh() end },
            -- Grid only. A strip is one entry deep, so it has only ever the one
            -- answer -- break out across itself -- and offering it three would
            -- be offering the same thing three times.
            --
            --   Lane     a halo hugging the block, centered on the point of it
            --            nearest the entry that opens it -- across the edge
            --            beside that entry, or around the corner it sits on --
            --            and wrapping the corners when the run is long
            --   Halo     the eight positions around the entry itself, the block
            --            faded behind them
            --   Popout   the nested palette as a block of its own, alongside
            { type="dropdown", text="Grid Nest Style",
              disabled=gridNestDead, disabledTooltip="the Grid layout",
              values={ PERIMETER = "Lane", HALO = "Halo", POPOUT = "Popout" },
              order={ "PERIMETER", "HALO", "POPOUT" },
              getValue=function() return Cfg("gridNestStyle") or "PERIMETER" end,
              setValue=function(v) Set("gridNestStyle", v); Refresh() end })
        y = y - h

        _, h = W:SectionHeader(parent, "FAN & GRID", y); y = y - h

        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Steering",
              disabled=fanOnly, disabledTooltip="a Fan layout",
              values=fanInputValues, order=fanInputOrder,
              getValue=function() return Cfg("fanInput") or "SCROLL" end,
              -- Rebuild, not Refresh: pointer steering retires three of the
              -- sliders below, so the row states are built from this.
              setValue=function(v) Set("fanInput", v); RebuildPage() end },
            { type="toggle", text="Auto Columns",
              disabled=gridOnly, disabledTooltip="the Grid layout",
              getValue=function() return Cfg("gridAutoColumns") ~= false end,
              -- Rebuild, not Refresh: this is what decides whether the column
              -- slider below means anything.
              setValue=function(v) Set("gridAutoColumns", v); RebuildPage() end })
        y = y - h

        row, h = W:DualRow(parent, y,
            { type="slider", text="Grid Columns",
              disabled=function()
                  return gridOnly() or Cfg("gridAutoColumns") ~= false
              end,
              disabledTooltip="Auto Columns to be off",
              -- The top of the travel is the slot cap, not an arbitrary 8. A
              -- grid never draws more columns than it has entries, so asking
              -- for the most a palette can ever hold is how you say "one row",
              -- and it stays one row as entries are added. Column 1 is already
              -- the transpose of that, so both single-file layouts are on the
              -- one slider and neither needs a sentinel value.
              tooltip="How many entries a row of the grid holds. 1 stacks them into a single column; "
                      ..(ns.MAX_SLOTS or 12).." -- the most slots a palette can hold -- lays them out in a single row.",
              min=1, max=(ns.MAX_SLOTS or 12), step=1,
              getValue=function() return Cfg("gridColumns") or 4 end,
              setValue=function(v) Set("gridColumns", v); Refresh() end },
            { type="spacer" })
        y = y - h

        row, h = W:DualRow(parent, y,
            -- How much of the strip is drawn at all. Neighbours past this many
            -- steps are hidden rather than shrunk further.
            { type="slider", text="Visible Each Side",
              disabled=scrollFanOnly, disabledTooltip="a scroll-steered Fan layout",
              min=1, max=6, step=1,
              getValue=function() return Cfg("fanVisible") or 3 end,
              setValue=function(v) Set("fanVisible", v); Refresh() end },
            -- The gap describes the spacing between entries laid out at a fixed
            -- pitch, which the grid does as much as a fan. The arc spaces its
            -- entries by angle instead and has nothing to say here.
            { type="slider", text="Entry Gap",
              disabled=stripOnly, disabledTooltip="a Fan or Grid layout",
              min=0, max=40, step=1,
              getValue=function() return Cfg("fanGap") or 10 end,
              setValue=function(v) Set("fanGap", v); Refresh() end })
        y = y - h

        row, h = W:DualRow(parent, y,
            -- One switch for every layout: the entry under the cursor is drawn
            -- at full size and full strength and its neighbours draw back, which
            -- is a step round the ring, along the strip or across the grid
            -- depending on which one is open.
            { type="toggle", text="Proximity Falloff",
              disabled=Disabled, disabledTooltip="the module",
              tooltip="Draw entries smaller and fainter the further they are from the one under the cursor. "
                      .."Off draws every entry at full size, and spreads a Fan out to even spacing.",
              getValue=function() return Cfg("falloff") ~= false end,
              -- Rebuild, not Refresh: this is what decides whether the two
              -- falloff sliders below mean anything.
              setValue=function(v) Set("falloff", v); RebuildPage() end },
            { type="spacer" })
        y = y - h

        -- The two falloffs are per-STEP ratios, not absolutes: 0.72 means each
        -- entry out from the centre is 72% of the one before it. Every layout
        -- reads them -- a step is a cell on the grid, a place along the strip
        -- and an entry round the ring -- so the depth cue is the same wherever
        -- the palette is drawn. Near the top of the travel they flatten out.
        row, h = W:DualRow(parent, y,
            { type="slider", text="Size Falloff",
              disabled=falloffOff, disabledTooltip="Proximity Falloff",
              min=0.40, max=0.95, step=0.01,
              getValue=function() return Cfg("fanScaleDecay") or 0.72 end,
              setValue=function(v) Set("fanScaleDecay", v); Refresh() end },
            { type="slider", text="Fade Falloff",
              disabled=falloffOff, disabledTooltip="Proximity Falloff",
              min=0.20, max=0.95, step=0.01,
              getValue=function() return Cfg("fanAlphaDecay") or 0.62 end,
              setValue=function(v) Set("fanAlphaDecay", v); Refresh() end })
        y = y - h

        row, h = W:DualRow(parent, y,
            -- How long the strip takes to slide to the entry that was scrolled
            -- to. 0 snaps; the selection itself moves on the tick either way.
            { type="slider", text="Settle Time",
              disabled=scrollFanOnly, disabledTooltip="a scroll-steered Fan layout",
              min=0, max=0.40, step=0.01,
              getValue=function() return Cfg("fanAnimTime") or 0.10 end,
              setValue=function(v) Set("fanAnimTime", v); Refresh() end },
            { type="toggle", text="Invert Scroll",
              disabled=scrollFanOnly, disabledTooltip="a scroll-steered Fan layout",
              getValue=function() return Cfg("fanInvert") == true end,
              setValue=function(v) Set("fanInvert", v); Refresh() end })
        y = y - h

        -- ── APPEARANCE ───────────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "APPEARANCE", y); y = y - h

        row, h = W:DualRow(parent, y,
            -- Arc only, and not merely because it would look cramped: the
            -- fan never draws per-slot labels at all. == true, not ~= false:
            -- labels are off by default, so an untouched key reads as off.
            { type="toggle", text="Show Slot Labels",
              disabled=arcOnly, disabledTooltip="the Arc layout",
              getValue=function() return Cfg("showLabels") == true end,
              setValue=function(v) Set("showLabels", v); Refresh() end },
            { type="toggle", text="Show Center Text",
              disabled=Disabled, disabledTooltip="the module",
              getValue=function() return Cfg("showHubText") ~= false end,
              setValue=function(v) Set("showHubText", v); Refresh() end })
        y = y - h

        row, h = W:DualRow(parent, y,
            { type="toggle", text="Show Direction Needle",
              disabled=arcOnly, disabledTooltip="the Arc layout",
              getValue=function() return Cfg("showNeedle") ~= false end,
              setValue=function(v) Set("showNeedle", v); Refresh() end },
            { type="toggle", text="Show Cooldowns",
              disabled=Disabled, disabledTooltip="the module",
              getValue=function() return Cfg("showCooldowns") ~= false end,
              setValue=function(v) Set("showCooldowns", v); Refresh() end })
        y = y - h

        -- Hub art is arc-only: the fan and grid layouts put a real entry at
        -- the centre, so there is nothing for it to sit in.
        -- Both tests read the key against its DEFAULT rather than against
        -- true/false flatly: the logo is on unless the user has turned it off,
        -- so a profile that has never touched the key must read as on.
        local hubIconOff = function()
            return arcOnly() or Cfg("hubIcon") == false
        end
        row, h = W:DualRow(parent, y,
            { type="toggle", text="Logo In Center",
              disabled=arcOnly, disabledTooltip="the Arc layout",
              getValue=function() return Cfg("hubIcon") ~= false end,
              -- Rebuild, not Refresh: this gates the two sliders below it.
              setValue=function(v) Set("hubIcon", v); RebuildPage() end },
            { type="slider", text="Logo Size",
              disabled=hubIconOff, disabledTooltip="Logo In Center",
              min=16, max=120, step=1,
              getValue=function() return Cfg("hubIconSize") or 46 end,
              setValue=function(v) Set("hubIconSize", v); Refresh() end })
        y = y - h

        row, h = W:DualRow(parent, y,
            -- The centre text draws over the logo, so this is the control that
            -- keeps the name readable rather than pure decoration.
            { type="slider", text="Logo Opacity",
              disabled=hubIconOff, disabledTooltip="Logo In Center",
              min=0.05, max=1.0, step=0.01,
              getValue=function() return Cfg("hubIconAlpha") or 0.55 end,
              setValue=function(v) Set("hubIconAlpha", v); Refresh() end },
            { type="spacer" })
        y = y - h

        -- Swatch and the toggle that overrides it share a row, in that order --
        -- the ActionBars interactions row does the same (EUI_ActionBars_Options
        -- .lua:5569). A lone colorpicker cfg makes DualRow build a full-width
        -- half, which is both wrong here and where the swatch went unclickable.
        row, h = W:DualRow(parent, y,
            { type="colorpicker", text="Selection Color",
              disabled=function() return Disabled() or Cfg("useClassColor") == true end,
              disabledTooltip=function()
                  if Cfg("useClassColor") == true then
                      return "This option requires Use Class Color to be disabled"
                  end
                  return "This option requires the module to be enabled"
              end,
              rawTooltip=true,
              getValue=function()
                  local c = Cfg("selectColor") or {}
                  return c[1] or 0.047, c[2] or 0.824, c[3] or 0.624
              end,
              setValue=function(r, g, b)
                  Set("selectColor", { r, g, b })
                  Refresh()
              end },
            { type="toggle", text="Use Class Color",
              disabled=Disabled, disabledTooltip="the module",
              getValue=function() return Cfg("useClassColor") == true end,
              setValue=function(v) Set("useClassColor", v); RebuildPage() end })
        y = y - h

        row, h = W:DualRow(parent, y,
            { type="slider", text="Background Opacity",
              disabled=Disabled, disabledTooltip="the module",
              min=0, max=100, step=5,
              -- Stored 0..1 internally; displayed 0..100 to the user.
              getValue=function() return (Cfg("bgAlpha") or 0.65) * 100 end,
              setValue=function(v) Set("bgAlpha", v / 100); Refresh() end },
            { type="slider", text="Selected Slot Zoom",
              disabled=Disabled, disabledTooltip="the module",
              min=1.0, max=1.6, step=0.01,
              getValue=function() return Cfg("selectedZoom") or 1.15 end,
              setValue=function(v) Set("selectedZoom", v); Refresh() end })
        y = y - h

        -- ── FLICK-AHEAD ──────────────────────────────────────────────────
        -- Its own section rather than another APPEARANCE row: this is about
        -- WHEN the palette is drawn, not what it looks like, and the delay is the
        -- one setting on the page a user has to be told the purpose of.
        _, h = W:SectionHeader(parent, "FLICK-AHEAD", y); y = y - h

        row, h = W:DualRow(parent, y,
            -- Holding the palette back for a moment lets an expert finish a
            -- gesture before anything appears. Selection is live the whole
            -- time, so nothing is lost by waiting.
            { type="toggle", text="Flick-Ahead",
              disabled=arcOnly, disabledTooltip="the Arc layout",
              getValue=function() return Cfg("flickAhead") ~= false end,
              -- Rebuild: the toggle gates the delay slider beside it.
              setValue=function(v) Set("flickAhead", v); RebuildPage() end },
            { type="slider", text="Flick Delay",
              disabled=function()
                  return arcOnly() or Cfg("flickAhead") == false
              end,
              disabledTooltip="Flick-Ahead",
              min=0, max=0.40, step=0.01,
              getValue=function() return Cfg("flickDelay") or 0.12 end,
              setValue=function(v) Set("flickDelay", v); Refresh() end })
        y = y - h

        _, h = W:Spacer(parent, y, 10); y = y - h

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Register the module
    ---------------------------------------------------------------------------
    EllesmereUI:RegisterModule("EllesmereUIActionPalette", {
        title       = "Action Palette",
        description = "Hold a keybind to open a palette of actions; point or scroll to choose, release to fire.",
        pages       = { PAGE_DISPLAY },
        buildPage   = BuildPage,
        onReset     = function()
            -- Lite DB stores data at
            -- EllesmereUIDB.profiles[X].addons.EllesmereUIActionPalette
            if EllesmereUIDB and EllesmereUIDB.profiles then
                local profile = EllesmereUIDB.activeProfile or "Default"
                local p = EllesmereUIDB.profiles[profile]
                if p and p.addons and p.addons.EllesmereUIActionPalette then
                    wipe(p.addons.EllesmereUIActionPalette)
                end
            end
            local target = _G._EAP_AceDB
            if target and target.profile and ns.DB_DEFAULTS then
                EllesmereUI.Lite.DeepMergeDefaults(target.profile, ns.DB_DEFAULTS.profile)
            end
            if _G._EAP_Apply then _G._EAP_Apply() end
        end,
    })
end)
