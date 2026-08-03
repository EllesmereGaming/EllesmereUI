-------------------------------------------------------------------------------
--  EUI_ActionPalette_Options.lua  --  Settings page for the Action Palette
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local PAGE_DISPLAY = "Action Palette"
local BINDING_PREFIX = "EUI_RADIAL"
local MAX_RINGS = 6

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if not EllesmereUI or not EllesmereUI.RegisterModule then return end

    local db
    C_Timer.After(0, function() db = _G._EAP_AceDB end)

    local function DB()
        if not db then db = _G._EAP_AceDB end
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

    -- Which ring the RING SETUP section is editing. Transient: the editor is a
    -- panel-session concept, not a saved setting.
    local editRing = 1

    local function RingCount()
        return math.min(MAX_RINGS, math.max(1, Cfg("ringCount") or 1))
    end

    local function Ring(index)
        return ns.EnsureRing and ns.EnsureRing(index or editRing)
    end

    ---------------------------------------------------------------------------
    --  Inline keybind picker
    --
    --  Binds the real EUI_RADIAL<n> action declared in Bindings.xml via
    --  SetBinding/SaveBindings, rather than storing a key of our own and
    --  routing it separately. That keeps ONE source of truth: this picker and
    --  Blizzard's Keybindings page edit the same binding, GetBindingKey keeps
    --  driving ns.UpdateBindings, and the SaveBindings call fires
    --  UPDATE_BINDINGS so the wheel re-routes its override binding by itself.
    ---------------------------------------------------------------------------
    local listenRing = nil
    local captureFrame = nil

    -- Combat-safe teardown. SetPropagateKeyboardInput carries restrictions and
    -- is pcall'd elsewhere in the suite for exactly this reason
    -- (EllesmereUIChat.lua:2552) -- and this runs in combat by construction,
    -- because EllesmereUI hides its options window on PLAYER_REGEN_DISABLED
    -- and that OnHide calls us.
    local function StopListening()
        local wasListening = listenRing ~= nil
        listenRing = nil
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

    -- chord = a binding string to assign, or nil to leave the ring unbound.
    local function CommitKey(chord)
        local ring = listenRing
        StopListening()
        if not ring then return end

        -- SaveBindings raises "can't be done in combat" and SetBinding would
        -- then be half-applied, so nothing is touched until combat drops.
        if InCombatLockdown() then
            Complain("Action Palette: keybinds can't be changed in combat.")
            RebuildPage()
            return
        end

        local action = BINDING_PREFIX .. ring
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
            -- Unbind: this one clears every key the ring holds, which is what
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

    local function StartListening(ring)
        if InCombatLockdown() then
            Complain("Action Palette: keybinds can't be changed in combat.")
            return
        end
        listenRing = ring

        local f = EnsureCaptureFrame()
        f.msg:SetText("Press a key or mouse button for |cff0cd29fAction Palette "
            .. ring .. "|r\n|cff888888Modifiers work with any button "
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
    -- wheel's own UpdateBindings included), and dropping the whole options
    -- page cache on each of those would rebuild the visible page over and
    -- over. Only a change to OUR six keys is of any interest here.
    local lastKeySig = nil
    local function RingKeySignature()
        local sig = ""
        for i = 1, MAX_RINGS do
            local k1, k2 = GetBindingKey(BINDING_PREFIX .. i)
            sig = sig .. "|" .. (k1 or "") .. "/" .. (k2 or "")
        end
        return sig
    end
    lastKeySig = RingKeySignature()

    local bindWatcher = CreateFrame("Frame")
    bindWatcher:RegisterEvent("UPDATE_BINDINGS")
    bindWatcher:SetScript("OnEvent", function()
        local sig = RingKeySignature()
        if sig == lastKeySig then return end
        lastKeySig = sig
        if EllesmereUI.InvalidatePageCache then EllesmereUI:InvalidatePageCache() end
        if EllesmereUI.IsShown and EllesmereUI:IsShown() and EllesmereUI.RefreshPage then
            EllesmereUI:RefreshPage(true)
        end
    end)

    ---------------------------------------------------------------------------
    --  Ring preview
    --
    --  The live wheel's own renderer (ns.CreateWheelView), scaled down to fit the
    --  panel and made interactive: drop an action on the trailing "+" to append
    --  it, drag icons between wedges to reorder, right-click to remove. Because
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
    -- margin: the preview turns slot labels off, so the ring only has to clear
    -- the block's own edges rather than leave room for captions under it.
    local PREVIEW_SPAN = 124
    local previewBlock, previewView

    -- Half-extent the block can give a fan, along the axis that fan runs on.
    -- A horizontal strip gets the block's width, which is the panel's content
    -- width and much larger than any radius; a vertical one is bounded by
    -- PREVIEW_H and is the tighter of the two by a wide margin.
    local function FanSpan(layout)
        if layout == "FAN_V" then return PREVIEW_H * 0.5 - 24 end
        local w = previewBlock and previewBlock:GetWidth() or 0
        -- The block is anchored on both sides, so its width is unresolved on
        -- the very first build. Layout re-runs on every Refresh, so a fallback
        -- here corrects itself rather than sticking.
        if w < 100 then w = 460 end
        return w * 0.5 - 24
    end

    -- Fit, don't crop: the live radius reaches 220, which is wider than the
    -- panel. Scaling radius, icon and dead zone by one factor keeps the
    -- proportions the user chose, so a tight ring still previews as a tight one.
    local function PreviewGeom()
        local radius   = Cfg("radius") or 96
        local iconSize = Cfg("iconSize") or 44
        local deadZone = Cfg("deadZone") or 24
        local layout = Cfg("layout") or "RADIAL"
        local k
        if layout == "GRID" then
            -- The grid is the one layout bounded on BOTH axes, so both budgets
            -- have to be met: the block's width across the columns, and its
            -- height down the rows.
            local ring = Ring(editRing)
            local n = (ring and #ring.slots or 0) + 1
            local cols, rows
            if previewView then cols, rows = previewView:GridDims() end
            -- The view answers from its last Layout, so it has nothing to say
            -- until the first one has run.
            if not cols or rows < 1 then
                cols = math.min(Cfg("gridColumns") or 4, n)
                rows = math.ceil(n / cols)
            end
            local pitch = iconSize + (Cfg("fanGap") or 10)
            k = math.min(1,
                FanSpan("FAN_H") / (cols * pitch * 0.5),
                (PREVIEW_H * 0.5 - 24) / (rows * pitch * 0.5))
        elseif layout ~= "RADIAL" then
            -- A fan's extent is the length of the strip, not the radius of a
            -- ring, so that is what has to be fitted. The preview draws EVERY
            -- slot -- an editor cannot leave one unreachable -- plus the
            -- trailing "+", and nothing is culled, so the reach is measured
            -- over that whole count.
            local ring = Ring(editRing)
            local n = (ring and #ring.slots or 0) + 1
            local reach
            if (Cfg("fanInput") or "SCROLL") == "CURSOR" then
                -- A pointer-steered fan is evenly spaced at full pitch, so its
                -- reach grows much faster than a coverflow strip's.
                reach = ns.FanHoverReach(n, iconSize, Cfg("fanGap") or 10)
            else
                reach = ns.FanReach(n, iconSize, Cfg("fanGap") or 10,
                                    Cfg("fanScaleDecay") or 0.72)
            end
            -- Against the budget of the axis the strip actually runs along, NOT
            -- PREVIEW_SPAN: that is a RADIUS budget, and measuring a strip's
            -- half-LENGTH against it shrank the icons to about a third of the
            -- size the block had room for.
            k = math.min(1, FanSpan(layout) / reach)
        else
            k = math.min(1, PREVIEW_SPAN / (radius + iconSize))
        end
        return radius * k, iconSize * k, deadZone * k
    end

    -- Manual drag, threshold-based -- the same shape as the Widgets reorder row
    -- (EllesmereUI_Widgets.lua:5391), because WoW's built-in RegisterForDrag
    -- threshold is far too large for icons this size.
    local DRAG_THRESHOLD = 4
    local dragFrom, dragStartX, dragStartY, dragging, dragTarget

    local function PreviewTooltip(widget)
        local ring = Ring(editRing)
        local slot = ring and ring.slots[widget.index]
        GameTooltip:SetOwner(widget, "ANCHOR_RIGHT")
        if slot then
            local _, name = ns.SlotDisplay(slot)
            GameTooltip:AddLine(name or slot.kind, 1, 1, 1)
            GameTooltip:AddLine(slot.kind, 0.6, 0.6, 0.6)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Drag to reorder.", 0.4, 0.8, 1, true)
            GameTooltip:AddLine("Right-click to remove.", 0.4, 0.8, 1, true)
            GameTooltip:AddLine("Drop an action here to replace it.", 0.4, 0.8, 1, true)
        else
            GameTooltip:AddLine("Add an action", 1, 1, 1)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Left-click to pick a spell, mount, item, toy, macro or "
                .. "battle pet from a list.", 0.4, 0.8, 1, true)
            GameTooltip:AddLine("You can also drop an action from the cursor here.",
                0.4, 0.8, 1, true)
        end
        GameTooltip:Show()
    end

    -- Place whatever is on the cursor. An empty cursor is not an error: a bare
    -- left-click on a slot should do nothing at all, cursor untouched.
    local function PreviewPlace(widget)
        local ring = Ring(editRing)
        local slot = ring and ns.SlotFromCursor()
        if not slot then return end
        if widget.isPlaceholder then
            if not ns.AddSlot(ring, slot) then return end
        else
            ring.slots[widget.index] = slot
        end
        ClearCursor()
        Refresh()
    end

    ---------------------------------------------------------------------------
    --  Action picker
    --
    --  Left-clicking the "+" wedge with an empty cursor opens a category menu,
    --  then that category's actions; choosing one appends a slot to the ring
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
    --  currently FILTERED lists, so what the wheel offers would otherwise
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
                -- Only items with a use effect. The wheel fires "/use item:<id>",
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
        -- items someone puts on a wheel.
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

    -- custom = the typed-macro pane rather than a list of things to enumerate.
    local PICKER_CATEGORIES = {
        { key = "spell",     label = "Spells",       build = SpellEntries },
        { key = "mount",     label = "Mounts",       build = MountEntries },
        { key = "item",      label = "Items",        build = ItemEntries },
        { key = "toy",       label = "Toys",         build = ToyEntries },
        { key = "macro",     label = "Macros",       build = MacroEntries },
        { key = "battlepet", label = "Battle Pets",  build = PetEntries },
        { key = "macrotext", label = "Custom Macro...", custom = true },
    }

    local ShowPickerCategories, ShowPickerCategory, ShowPickerCustom

    local function HidePicker()
        if pickerMenu then pickerMenu:Hide() end
    end

    -- Returns true when a slot was actually appended.
    local function AssignEntry(entry)
        local ring = Ring(editRing)
        -- The stored slot is a COPY: the entry belongs to the cached list, and
        -- handing that one table to two wedges would alias a single saved slot
        -- into both of them.
        local slot = {}
        for k, v in pairs(entry.slot) do slot[k] = v end
        -- ns.AddSlot refuses a full ring. Unreachable from here -- a full ring
        -- draws no "+" to click -- but the refusal must not fall through into a
        -- Refresh that has nothing to show.
        if not (ring and ns.AddSlot(ring, slot)) then return false end
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
            -- the user is scanning for.
            table.sort(list, function(a, b) return a.name < b.name end)
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

    -- Which slot the cursor is over, for the reorder drag. The live wheel's own
    -- HitTest answers this from the angle to the hub, which only means anything
    -- on a circle -- in a fan it would report a wedge the user is nowhere near.
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
                -- Reuse the selection paint: hovering a wedge in the panel looks
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
                    local ring = Ring(editRing)
                    if ring and ns.RemoveSlot(ring, self.index) then Refresh() end
                    return
                end
                -- A loaded cursor still means "place this here" on every wedge;
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
                local ring = Ring(editRing)
                if ring and ns.MoveSlot(ring, from, to) then Refresh() end
            end)
        end
    end

    -- yPos is the running page offset; returns the height consumed.
    local function BuildPreview(parent, yPos)
        -- PanelPP, not PP: panel-context geometry snaps to the options window's
        -- own pixel grid, which is what every other options page uses.
        local PP = EllesmereUI.PanelPP
        local CONTENT_PAD = EllesmereUI.CONTENT_PAD or 45

        -- A rebuild re-fans the ring, so the wedge the picker is anchored to may
        -- not be the "+" any more -- and an already-open menu would then be
        -- pointing at an unrelated slot.
        HidePicker()

        if not previewBlock then
            previewBlock = CreateFrame("Frame", nil, parent)

            local bg = previewBlock:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0, 0, 0, 0.18)

            previewView = ns.CreateWheelView(previewBlock, {
                interactive = true,
                geom        = PreviewGeom,
                -- Labels would collide at the fitted scale, and the hub plus the
                -- tooltip already name whatever the cursor is over.
                showLabels  = false,
                -- Arrangement is what this preview is for; a live cooldown swipe
                -- on a settings page is only noise.
                showCooldowns = false,
                -- Kept short on purpose: the hub line is drawn centered inside a
                -- ring only ~75px in radius, and anything longer runs under the
                -- wedges at 3 and 9 o'clock. The rest is in the slot tooltips.
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
                -- The wedge under the cursor. The "+" wedge resolves to the
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
                    EllesmereUI.ShowWidgetTooltip(self, "Enable the module to edit rings.")
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
        previewView:Layout(editRing)
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

        local layoutValues = { RADIAL = "Radial", FAN_H = "Fan (Horizontal)",
                               FAN_V = "Fan (Vertical)", GRID = "Grid" }
        local layoutOrder  = { "RADIAL", "FAN_H", "FAN_V", "GRID" }

        local fanInputValues = { SCROLL = "Mouse Wheel", CURSOR = "Pointer" }
        local fanInputOrder  = { "SCROLL", "CURSOR" }

        -- ── GENERAL ──────────────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "GENERAL", y); y = y - h

        row, h = W:DualRow(parent, y,
            { type="toggle", text="Enable Action Palette",
              getValue=function() return Cfg("enabled") ~= false end,
              setValue=function(v) Set("enabled", v); RebuildPage() end },
            { type="slider", text="Number of Rings",
              disabled=Disabled, disabledTooltip="the module",
              min=1, max=MAX_RINGS, step=1,
              getValue=function() return RingCount() end,
              setValue=function(v)
                  Set("ringCount", v)
                  if editRing > v then editRing = v end
                  for i = 1, v do Ring(i) end
                  RebuildPage()
              end })
        y = y - h

        -- ── RING SETUP ───────────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "RING SETUP", y); y = y - h

        local ringValues, ringOrder = {}, {}
        for i = 1, RingCount() do
            local r = Ring(i)
            ringValues[i] = (r and r.name) or ("Ring " .. i)
            ringOrder[#ringOrder + 1] = i
        end

        local keyForEditRing = GetBindingKey(BINDING_PREFIX .. editRing)

        row, h = W:DualRow(parent, y,
            -- noCapture: which ring the preview is pointed at is panel-session
            -- state, not a setting, so it must not be banked as a per-spec
            -- override by the Spec Overrides capture pass.
            { type="dropdown", text="Editing Ring", noCapture=true,
              disabled=Disabled, disabledTooltip="the module",
              values=ringValues, order=ringOrder,
              getValue=function() return editRing end,
              setValue=function(v)
                  editRing = v
                  -- Full rebuild, not a preview relayout: the keybind button's
                  -- label is baked in at build time from THIS ring's key.
                  RebuildPage()
              end },
            -- buttonText is consumed as a literal string, so the label is
            -- resolved at build time. Both things that can change it --
            -- committing a key and switching the edited ring -- rebuild the
            -- page, so it cannot go stale while the panel is open.
            { type="labeledButton", text="Ring Keybind",
              disabled=Disabled, disabledTooltip="the module",
              buttonText=(listenRing == editRing) and "Press a key..."
                  or (keyForEditRing and (GetBindingText(keyForEditRing) or keyForEditRing)
                      or "Click to Bind"),
              onClick=function() StartListening(editRing) end })
        y = y - h

        y = y - BuildPreview(parent, y)

        -- ── PLACEMENT & SIZE ─────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "PLACEMENT & SIZE", y); y = y - h

        -- The X/Y offsets ride along with the mode dropdown because they only
        -- mean anything in Fixed Position mode -- in cursor mode the wheel
        -- opens wherever the mouse is. They are also the ONLY way to place the
        -- wheel: the on-screen drag editor is gone, and this module is not yet
        -- registered with Unlock Mode.
        local fixedOnly = function()
            return Disabled() or (Cfg("centerMode") or "CURSOR") ~= "SCREEN"
        end

        -- A fan has no ring, no angle and no centre to steer away from, so the
        -- settings that describe those are dead in it -- and the radial has no
        -- strip, so the fan's own settings are dead in turn. Every set stays
        -- visible and disabled rather than disappearing: a control that
        -- vanishes when a dropdown moves reads as a bug.
        --
        -- Four predicates, because the layouts do not partition cleanly: the
        -- grid shares the strip's spacing and falloff settings but steers like
        -- nothing else, and a pointer-steered fan has no scrolling to describe.
        local function LayoutMode() return Cfg("layout") or "RADIAL" end
        local function IsFanLayout()
            local l = LayoutMode()
            return l == "FAN_H" or l == "FAN_V"
        end

        local radialOnly = function()
            return Disabled() or LayoutMode() ~= "RADIAL"
        end
        -- Anything laid out as icons at a fixed pitch: both fans and the grid.
        local stripOnly = function()
            return Disabled() or LayoutMode() == "RADIAL"
        end
        local fanOnly = function()
            return Disabled() or not IsFanLayout()
        end
        -- The window-and-scroll settings: a pointer-steered fan draws the whole
        -- ring at fixed positions, so it culls nothing, animates nothing and
        -- has no wheel direction to invert.
        local scrollFanOnly = function()
            return Disabled() or not IsFanLayout()
                or (Cfg("fanInput") or "SCROLL") ~= "SCROLL"
        end
        local gridOnly = function()
            return Disabled() or LayoutMode() ~= "GRID"
        end

        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Layout",
              disabled=Disabled, disabledTooltip="the module",
              values=layoutValues, order=layoutOrder,
              getValue=function() return Cfg("layout") or "RADIAL" end,
              -- Rebuild, not Refresh: this is what decides which of the two
              -- sets of controls below is live.
              setValue=function(v) Set("layout", v); RebuildPage() end },
            { type="spacer" })
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
        -- "Ring Radius" is truncated, so the setting stops being readable.
        row, h = W:DualRow(parent, y,
            { type="slider", text="Ring Radius",
              disabled=radialOnly, disabledTooltip="the Radial layout",
              min=50, max=220, step=1,
              getValue=function() return Cfg("radius") or 96 end,
              setValue=function(v) Set("radius", v); Refresh() end },
            { type="slider", text="Icon Size",
              disabled=Disabled, disabledTooltip="the module",
              min=24, max=72, step=1,
              getValue=function() return Cfg("iconSize") or 44 end,
              setValue=function(v) Set("iconSize", v); Refresh() end })
        y = y - h

        -- 360 is the full wheel, and a rotation of a full circle is a no-op --
        -- so the rotation only becomes live once the span has been narrowed to
        -- an arc that has somewhere to point.
        row, h = W:DualRow(parent, y,
            { type="slider", text="Arc Span",
              disabled=radialOnly, disabledTooltip="the Radial layout",
              min=30, max=360, step=5,
              getValue=function() return Cfg("arcSpan") or 360 end,
              setValue=function(v) Set("arcSpan", v); Refresh() end },
            { type="slider", text="Arc Rotation",
              disabled=function()
                  return radialOnly() or (Cfg("arcSpan") or 360) >= 360
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
              disabled=radialOnly, disabledTooltip="the Radial layout",
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
        _, h = W:SectionHeader(parent, "FAN & GRID", y); y = y - h

        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Steering",
              disabled=fanOnly, disabledTooltip="a Fan layout",
              values=fanInputValues, order=fanInputOrder,
              getValue=function() return Cfg("fanInput") or "SCROLL" end,
              -- Rebuild, not Refresh: pointer steering retires three of the
              -- sliders below, so the row states are built from this.
              setValue=function(v) Set("fanInput", v); RebuildPage() end },
            { type="slider", text="Grid Columns",
              disabled=gridOnly, disabledTooltip="the Grid layout",
              min=1, max=8, step=1,
              getValue=function() return Cfg("gridColumns") or 4 end,
              setValue=function(v) Set("gridColumns", v); Refresh() end })
        y = y - h

        row, h = W:DualRow(parent, y,
            -- How much of the strip is drawn at all. Neighbours past this many
            -- steps are hidden rather than shrunk further.
            { type="slider", text="Visible Each Side",
              disabled=scrollFanOnly, disabledTooltip="a scroll-steered Fan layout",
              min=1, max=6, step=1,
              getValue=function() return Cfg("fanVisible") or 3 end,
              setValue=function(v) Set("fanVisible", v); Refresh() end },
            -- Gap and both falloffs describe the spacing between entries laid
            -- out at a fixed pitch, which the grid does as much as a fan.
            { type="slider", text="Entry Gap",
              disabled=stripOnly, disabledTooltip="a Fan or Grid layout",
              min=0, max=40, step=1,
              getValue=function() return Cfg("fanGap") or 10 end,
              setValue=function(v) Set("fanGap", v); Refresh() end })
        y = y - h

        -- The two falloffs are per-STEP ratios, not absolutes: 0.72 means each
        -- entry out from the centre is 72% of the one before it.
        row, h = W:DualRow(parent, y,
            { type="slider", text="Size Falloff",
              disabled=stripOnly, disabledTooltip="a Fan or Grid layout",
              min=0.40, max=0.95, step=0.01,
              getValue=function() return Cfg("fanScaleDecay") or 0.72 end,
              setValue=function(v) Set("fanScaleDecay", v); Refresh() end },
            { type="slider", text="Fade Falloff",
              disabled=stripOnly, disabledTooltip="a Fan or Grid layout",
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
            -- Radial only, and not merely because it would look cramped: the
            -- fan never draws per-slot labels at all.
            { type="toggle", text="Show Slot Labels",
              disabled=radialOnly, disabledTooltip="the Radial layout",
              getValue=function() return Cfg("showLabels") ~= false end,
              setValue=function(v) Set("showLabels", v); Refresh() end },
            { type="toggle", text="Show Center Text",
              disabled=Disabled, disabledTooltip="the module",
              getValue=function() return Cfg("showHubText") ~= false end,
              setValue=function(v) Set("showHubText", v); Refresh() end })
        y = y - h

        row, h = W:DualRow(parent, y,
            { type="toggle", text="Show Direction Needle",
              disabled=radialOnly, disabledTooltip="the Radial layout",
              getValue=function() return Cfg("showNeedle") ~= false end,
              setValue=function(v) Set("showNeedle", v); Refresh() end },
            { type="toggle", text="Show Cooldowns",
              disabled=Disabled, disabledTooltip="the module",
              getValue=function() return Cfg("showCooldowns") ~= false end,
              setValue=function(v) Set("showCooldowns", v); Refresh() end })
        y = y - h

        -- Hub art is radial-only: the fan and grid layouts put a real entry at
        -- the centre, so there is nothing for it to sit in.
        local hubIconOff = function()
            return radialOnly() or Cfg("hubIcon") ~= true
        end
        row, h = W:DualRow(parent, y,
            { type="toggle", text="Logo In Center",
              disabled=radialOnly, disabledTooltip="the Radial layout",
              getValue=function() return Cfg("hubIcon") == true end,
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
        -- WHEN the ring is drawn, not what it looks like, and the delay is the
        -- one setting on the page a user has to be told the purpose of.
        _, h = W:SectionHeader(parent, "FLICK-AHEAD", y); y = y - h

        row, h = W:DualRow(parent, y,
            -- Holding the ring back for a moment lets an expert finish a
            -- gesture before anything appears. Selection is live the whole
            -- time, so nothing is lost by waiting.
            { type="toggle", text="Flick-Ahead",
              disabled=radialOnly, disabledTooltip="the Radial layout",
              getValue=function() return Cfg("flickAhead") ~= false end,
              -- Rebuild: the toggle gates the delay slider beside it.
              setValue=function(v) Set("flickAhead", v); RebuildPage() end },
            { type="slider", text="Flick Delay",
              disabled=function()
                  return radialOnly() or Cfg("flickAhead") == false
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
