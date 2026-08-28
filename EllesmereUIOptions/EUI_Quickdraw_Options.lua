if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Quickdraw_Options.lua  --  Settings page for the Quickdraw
-------------------------------------------------------------------------------
local ADDON_NAME = "EllesmereUIQuickdraw"
local ns = EllesmereUI._ModuleNS[ADDON_NAME]  -- module namespace (published by the module at its load)
if not ns then return end  -- module disabled: no options page

local PAGE_DISPLAY = "Quickdraw"
local BINDING_PREFIX = "EUI_RADIAL"
-- Every palette has a <Binding> entry of its own, so the keybind row below
-- applies to all of them. Read from the module rather than restated, so the two
-- can never disagree about how far the binding actions run.
local MAX_PALETTES = ns.MAX_PALETTES or 16
local MAX_SLOTS = ns.MAX_SLOTS or 12

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if not EllesmereUI or not EllesmereUI.RegisterModule then return end

    local db

    -- Through ns.Profile, not db.profile: the module converts a profile's
    -- retired key names on first touch, and reading the table directly here
    -- would skip that whenever the panel is the first to see a profile the user
    -- has just switched to. The db local is still kept for the reset handler.
    local function DB()
        if not db then db = _G._EQD_AceDB end
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

    -- Whether the page was BUILT with the nest-geometry row on it (some menu
    -- holds a nested entry). Rows are structural, so when nest presence flips
    -- under a plain Refresh -- the first nested entry added, the last one
    -- removed -- the refresh escalates to a rebuild and the row appears or
    -- goes with it. HasAnyNest is assigned below PaletteCount.
    local builtWithNest = false
    local HasAnyNest

    local function Refresh()
        if _G._EQD_Apply then _G._EQD_Apply() end
        if HasAnyNest and HasAnyNest() ~= builtWithNest and EllesmereUI.RefreshPage then
            EllesmereUI:RefreshPage(true)
            return
        end
        if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage() end
    end

    local function RebuildPage()
        if _G._EQD_Apply then _G._EQD_Apply() end
        if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage(true) end
    end

    -- Which palette the ACTION MENU SETUP section is editing. Transient: the editor
    -- is a panel-session concept, not a saved setting.
    local editPalette = 1

    local function PaletteCount()
        return math.min(MAX_PALETTES, math.max(1, Cfg("paletteCount") or 1))
    end

    local function Palette(index)
        return ns.EnsurePalette and ns.EnsurePalette(index or editPalette)
    end

    -- Does ANY menu hold a nested entry? Read-only walk over the stored
    -- tables (never through EnsurePalette, which compacts and allocates):
    -- this runs on every Refresh to notice presence flipping.
    HasAnyNest = function()
        local prof = DB()
        local palettes = prof and prof.palettes
        if type(palettes) ~= "table" then return false end
        for i = 1, PaletteCount() do
            local pal = palettes[i]
            local slots = type(pal) == "table" and pal.slots
            for j = 1, (type(slots) == "table" and #slots or 0) do
                local s = slots[j]
                if type(s) == "table" and s.kind == "palette" then return true end
            end
        end
        return false
    end

    ---------------------------------------------------------------------------
    --  Per-palette appearance
    --
    --  EVERY setting on the page is read and written against the palette the
    --  Editing Action Menu selector is pointed at. The module holds the list
    --  (ns.APPEARANCE_KEYS) and the fallback: a palette with no override of its
    --  own reads the profile's value, so a profile written before any of this
    --  existed draws exactly as it did. Only the module's enable switch and
    --  the menu list itself are profile state through Cfg/Set; the "Apply All
    --  Settings To" row below the preview is the bridge between menus.
    --
    --  Every row that writes through ASet carries noCapture: these live
    --  inside p.palettes[n] rather than under a flat key, and a per-spec
    --  override banked against
    --  whichever palette happened to be on screen at capture time would rewrite
    --  a palette the user was not looking at.
    ---------------------------------------------------------------------------
    local function ACfg(key)
        local pal = ns.EnsurePalette and ns.EnsurePalette(editPalette)
        local a = pal and pal.appearance
        local v = a and a[key]
        if v ~= nil then return v end
        return Cfg(key)
    end

    local function ASet(key, val)
        local pal = ns.EnsurePalette and ns.EnsurePalette(editPalette)
        if not pal then return end
        pal.appearance = pal.appearance or {}
        pal.appearance[key] = val
    end

    -- From the module, so the name an emptied box reverts to is the same string
    -- the module hands a fresh palette.
    local function AutoName(index)
        if ns.AutoPaletteName then return ns.AutoPaletteName(index) end
        return "Action Menu " .. index
    end

    -- The icon a menu is listed BY, everywhere one is listed: its first entry,
    -- so a "Mounts" menu looks like a mount without anyone having to pick an
    -- icon for it. Same rule the module's SlotDisplay applies to nested
    -- entries, including the one-level stop: a first entry that is itself a
    -- menu would send this round its own loop. An empty menu shows the bag.
    local function PaletteListIcon(palette)
        local first = palette and palette.slots and palette.slots[1]
        if first and first.kind ~= "palette" and ns.SlotDisplay then
            local icon = ns.SlotDisplay(first)
            if icon then return icon end
        end
        return "Interface\\Icons\\INV_Misc_Bag_08"
    end

    ---------------------------------------------------------------------------
    --  Inline keybind button
    --
    --  Binds the real EUI_RADIAL<n> action declared in Bindings.xml via
    --  SetBinding/SaveBindings, rather than storing a key of our own and
    --  routing it separately. That keeps ONE source of truth: this button and
    --  Blizzard's Keybindings page edit the same binding, GetBindingKey keeps
    --  driving ns.UpdateBindings, and the SaveBindings call fires
    --  UPDATE_BINDINGS so the palette re-routes its override binding by itself.
    --
    --  The button is the Action Bars "Toggle Action Bar" keybind button: it
    --  does its own listening -- left-click arms it, the next key press binds,
    --  right-click unbinds, Escape cancels -- with no overlay of any kind.
    --  The build lives in BuildKeybindButton below the page's selector.
    ---------------------------------------------------------------------------

    -- The combat rejections below are the one case where EllesmereUI.Print is
    -- the wrong channel: it deliberately stays silent in raid combat and in an
    -- active M+ (EllesmereUI.lua:1519), which is precisely when a user would
    -- hit them and see nothing happen.
    local function Complain(msg)
        msg = EllesmereUI.L(msg)
        if _G.UIErrorsFrame then
            UIErrorsFrame:AddMessage(msg, 1.0, 0.3, 0.3, 1.0)
        else
            EllesmereUI.Print("|cff0cd29fQuickdraw:|r " .. msg)
        end
    end

    -- What the user calls the action a chord is currently bound to. The binding
    -- system stores an action string; BINDING_NAME_<action> is the label every
    -- keybind UI shows, and our own palettes declare one each.
    local function BindingLabel(action)
        return _G["BINDING_NAME_" .. action] or action
    end

    -- Both halves of a commit, past the point of asking. Split out so the
    -- confirmation below can defer exactly this and nothing else. stolenFrom is
    -- the action the chord was taken from, for the record it leaves in chat --
    -- which is what the no-dialog fallback below relies on, and is still worth
    -- having once the dialog has been agreed to.
    local function ApplyKey(palette, chord, stolenFrom)
        local action = BINDING_PREFIX .. palette
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
                Complain("Quickdraw: " .. (GetBindingText(chord) or chord)
                    .. " could not be bound.")
            elseif stolenFrom then
                EllesmereUI.Print("|cff0cd29fQuickdraw:|r took "
                    .. (GetBindingText(chord) or chord) .. " from |cffffd100"
                    .. BindingLabel(stolenFrom) .. "|r.")
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

    -- chord = a binding string to assign, or nil to leave the palette unbound.
    -- The button has already put the bound key back on its own label by the
    -- time this runs, so the rejection paths below leave nothing to restore.
    local function CommitKey(palette, chord)
        -- SaveBindings raises "can't be done in combat" and SetBinding would
        -- then be half-applied, so nothing is touched until combat drops.
        if InCombatLockdown() then
            Complain("Quickdraw: keybinds can't be changed in combat.")
            return
        end

        local action = BINDING_PREFIX .. palette
        -- Only a real theft is worth either a dialog or a notice: an unbound
        -- chord takes nothing, and rebinding a palette to the key it already
        -- holds takes it from itself. A key held by ANOTHER palette of ours
        -- does count -- that one would be left with no way to open at all.
        local stolenFrom = chord and GetBindingAction(chord) or nil
        if stolenFrom == "" or stolenFrom == action then stolenFrom = nil end

        -- SetBinding takes a key from whatever holds it without a word, and the
        -- displaced binding is often something the user cares about and will
        -- not miss until they reach for it mid-fight. Asking first is the only
        -- point at which they can still say no -- a message after the fact
        -- tells them what to go and put back, which is not the same thing.
        if stolenFrom and EllesmereUI.ShowConfirmPopup then
            local keyText = GetBindingText(chord) or chord
            EllesmereUI:ShowConfirmPopup({
                title       = "Key Already Bound",
                message     = EllesmereUI.Lf("%1$s is bound to \"%2$s\". Binding it to \"%3$s\" will leave that unbound.",
                    keyText, BindingLabel(stolenFrom), BindingLabel(action)),
                confirmText = "Rebind",
                cancelText  = "Keep",
                -- Re-checked rather than trusted: the dialog sits open for as
                -- long as the user leaves it, and a fight can start under it.
                onConfirm   = function()
                    if InCombatLockdown() then
                        Complain("Quickdraw: keybinds can't be changed in combat.")
                        RebuildPage()
                        return
                    end
                    ApplyKey(palette, chord, stolenFrom)
                end,
            })
            return
        end

        ApplyKey(palette, chord, stolenFrom)
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
    -- over. Only a change to one of OUR keys is of any interest here.
    --
    -- The watcher serves the page's keybind rows and nothing else, so it is
    -- created the first time the page is built rather than at login: a session
    -- that never opens this page pays no frame and no event.
    local lastKeySig = nil
    local bindWatcher = nil
    local function PaletteKeySignature()
        local sig = ""
        for i = 1, MAX_PALETTES do
            local k1, k2 = GetBindingKey(BINDING_PREFIX .. i)
            sig = sig .. "|" .. (k1 or "") .. "/" .. (k2 or "")
        end
        return sig
    end

    local function EnsureBindWatcher()
        if bindWatcher then return end
        lastKeySig = PaletteKeySignature()
        bindWatcher = CreateFrame("Frame")
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
    end

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
    -- nearly its real size. Growing is capped at REAL size, never past it:
    -- the fit below only ever shrinks a palette into the block, and a short
    -- strip drawn larger than the user actually steers at would misrepresent
    -- the one thing the preview exists to show.
    local PREVIEW_MAX_ZOOM = 1.0

    -- How many entries the preview will actually place, which is what the fit
    -- has to be measured over. The trailing "+" counts only while the palette
    -- has room for another action -- the view stops drawing it at MAX_SLOTS
    -- (see the shownCount it works out in Layout) -- and counting it anyway
    -- fitted a full palette for one entry more than it shows, which drew it
    -- smaller than the block allows.
    local function PreviewEntryCount(palette)
        local n = palette and #palette.slots or 0
        if n < MAX_SLOTS then n = n + 1 end
        return n
    end

    -- Fit to the block, don't crop: the live radius reaches 220, which is wider
    -- than the panel, and a two-entry strip is far narrower than it. Scaling
    -- radius, icon and dead zone by one factor keeps the proportions the user
    -- chose, so a tight arc still previews as a tight one.
    local function PreviewGeom()
        local radius   = ACfg("radius") or 100
        local iconSize = ACfg("iconSize") or 40
        -- Fixed, not a setting: the module hardcodes the dead zone (see
        -- DefaultGeom). Still scaled by the fit below like the rest.
        local deadZone = 24
        local layout = ACfg("layout") or "ARC"
        -- No selection zoom (hardcoded off in the module), so the fit
        -- budgets no growth headroom.
        local zoom = 1
        local k
        if layout == "GRID" then
            -- The grid is bounded on BOTH axes, so both budgets have to be met:
            -- the block's width across the columns, and its height down the rows.
            local palette = Palette(editPalette)
            local n = PreviewEntryCount(palette)
            local cols, rows
            if previewView then cols, rows = previewView:GridDims() end
            -- The view answers from its last Layout, so it has nothing to say
            -- until the first one has run.
            if not cols or rows < 1 then
                cols = math.min(ACfg("gridColumns") or 4, n)
                rows = math.ceil(n / cols)
            end
            local pitch = iconSize + (ACfg("fanGap") or 10)
            k = math.min(PREVIEW_MAX_ZOOM,
                BlockSpan(false) / (cols * pitch * 0.5 + iconSize * (zoom - 1) * 0.5),
                BlockSpan(true) / (rows * pitch * 0.5 + iconSize * (zoom - 1) * 0.5))
        elseif layout ~= "ARC" then
            -- A fan's extent is the length of the strip rather than a radius,
            -- so that is what has to be fitted. The preview windows exactly
            -- like play now -- the centre plus the window each way (Visible
            -- Icons), the wheel scrolling the rest into view -- so the fit is
            -- measured over the drawn window, not the whole palette. The "+"
            -- sits off the strip's own line and costs the length nothing.
            local palette = Palette(editPalette)
            local nReal = palette and #palette.slots or 0
            local window = ACfg("fanVisible") or 2
            local drawn = math.min(math.max(nReal, 1), window * 2 + 1)
            -- Through the module rather than off the key: with the falloff
            -- switched off the strip spreads out to full pitch, and a fit
            -- measured at the stored decay would run it out of the block.
            -- One branch only -- a fan is always wheel-steered now.
            local reach = ns.FanReach(drawn, iconSize, ACfg("fanGap") or 10,
                                      (ns.FalloffRatios(editPalette)))
            local vertical = ACfg("fanOrientation") == "VERTICAL"
            -- Both axes, not just the one the strip runs along: a short strip
            -- fits its own length several times over, and without the crossways
            -- budget it would grow until the icons ran out of the block.
            k = math.min(PREVIEW_MAX_ZOOM,
                BlockSpan(vertical) / reach,
                BlockSpan(not vertical) / (iconSize * 0.5 * zoom))
        else
            -- A CONSTANT miniaturisation, not a fit to the current radius:
            -- the arc previews at a flat 75% of live size, so moving Distance
            -- from Center slides the ring in and out of the block exactly as
            -- it does in play and the icons never change size. Past a radius
            -- of roughly 140 the ring outgrows the block and draws past its
            -- edges -- the accepted price of the fixed scale.
            k = 0.75
        end
        return radius * k, iconSize * k, deadZone * k
    end

    -- Manual drag, threshold-based -- the same shape as the Widgets reorder row
    -- (EllesmereUI_Widgets.lua:5391), because WoW's built-in RegisterForDrag
    -- threshold is far too large for icons this size.
    local DRAG_THRESHOLD = 4
    local dragFrom, dragStartX, dragStartY, dragging, dragTarget

    -- One escape-coded string, not tooltip lines: the panel helper takes a
    -- single block of text, so the caption and the hints carry their own color
    -- codes. Gray for what the entry IS, blue for what the mouse can do to it.
    local function PreviewTooltip(widget)
        local palette = Palette(editPalette)
        local slot = palette and palette.slots[widget.index]
        local text
        if slot then
            local _, name = ns.SlotDisplay(slot)
            local caption
            if slot.kind == "palette" then
                -- Capped at what the palette being edited can seat, which is
                -- the whole nested menu everywhere but the halo -- eight fixed
                -- positions round a cell, and no ninth to put a child in. See
                -- NestChildCap.
                local cap = ns.NestChildCap and ns.NestChildCap(editPalette)
                local child = ns.ChildIndex(slot)
                local kids = ns.ChildSlots and ns.ChildSlots(child, cap)
                caption = (kids and #kids == 1)
                    and EllesmereUI.Lf("nested action menu, %1$d entry", 1)
                    or  EllesmereUI.Lf("nested action menu, %1$d entries", kids and #kids or 0)
                -- Said where the user meets it, rather than left to be
                -- discovered by counting the entries that turned up: a menu
                -- holding more than the halo can show looks broken otherwise.
                local all = ns.ChildSlots and ns.ChildSlots(child, MAX_SLOTS)
                if all and kids and #all > #kids then
                    -- The literal stays on the Lf line: the locale extractor
                    -- reads one line at a time, and a string wrapped onto the
                    -- next one is a key it never learns about.
                    caption = caption
                        .. EllesmereUI.Lf(", %1$d not shown in this layout",
                                          #all - #kids)
                end
            else
                -- The stored kind strings are one word each; only the marker
                -- kinds read better with the space put back.
                caption = (slot.kind == "raidtarget" and "target marker")
                    or (slot.kind == "worldmarker" and "world marker")
                    or (slot.kind == "clearmarkers" and "target markers")
                    or (slot.kind == "cycleraidtarget"
                        and "target marker, next on each press")
                    or (slot.kind == "cycleworldmarker"
                        and "world marker, next on each press")
                    or (slot.kind == "randommount" and "mount")
                    or (slot.kind == "panel" and "interface panel")
                    or (slot.kind == "spec" and "specialization")
                    -- Same icon and same name as a fixed spec entry on the
                    -- character that made it, so the caption is the only place
                    -- the difference between the two can be said.
                    or (slot.kind == "dynamicspec"
                        and "specialization, by position on this character")
                    -- Checked before the plain profession caption below,
                    -- since slot.extra would otherwise still match it.
                    or (slot.kind == "dynamicprofession" and slot.specialization
                        and "profession specialization ability, by position on this character")
                    or (slot.kind == "dynamicprofession" and slot.extra
                        and "profession's second ability, by position on this character")
                    -- Same icon and same name as a fixed profession entry on
                    -- the character that made it, just as with dynamicspec.
                    or (slot.kind == "dynamicprofession"
                        and "profession, by position on this character")
                    -- The name above is already the spell this character would
                    -- cast, so the caption says what picked it rather than
                    -- repeating it.
                    or (slot.kind == "dynamicrez"
                        and "resurrection, chosen for this character")
                    or slot.kind
            end
            text = EllesmereUI.L(name or slot.kind)
                .. "\n|cff999999" .. EllesmereUI.L(caption) .. "|r"
                .. EllesmereUI.L("\n|cff66ccffDrag to reorder."
                    .. "\nRight-click to change action."
                    .. "\nMiddle-click to remove."
                    .. "\nDrop an action here to replace it.|r")
        else
            text = EllesmereUI.L("Add an action"
                .. "\n|cff66ccffLeft-click to pick an action from a list."
                .. "\nYou can also drop an action from the cursor here.|r")
        end
        if EllesmereUI.ShowWidgetTooltip then
            EllesmereUI.ShowWidgetTooltip(widget, text)
        end
    end

    local function HidePreviewTooltip()
        if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
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

    -- pickerReplaceIndex: set while the picker was opened by a right-click on
    -- an existing entry -- the pick then replaces that slot instead of
    -- appending. nil on the "+" path.
    local pickerMenu, pickerAnchor, pickerReplaceIndex

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

        -- Dynamic Rez ahead of the spellbook itself, the way the Mount Journal's
        -- random roll leads the mounts: it is one entry that is whichever
        -- resurrection spell the character holding the palette has, so a palette
        -- shared between characters carries the rez once instead of once per
        -- class with all but one of them dead. pin is what holds it at the top
        -- past the sort. Left out entirely for a class with no rez at all.
        if ns.HasRezKit and ns.HasRezKit() then
            local slot = { kind = "dynamicrez" }
            local icon = ns.SlotDisplay(slot)
            -- Named for what the ENTRY is, not for the spell it happens to
            -- resolve to today: this row is picked from a list, and "Rebirth"
            -- sitting above the real Rebirth would read as a duplicate.
            out[1] = { icon = icon, name = "Dynamic Rez", slot = slot, pin = true }
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

    -- The words a collection entry can be searched by besides its own name,
    -- lowercase and space separated, matched by the same plain substring find
    -- the name gets -- so "vend" finds a vendor mount the way "sea" finds a
    -- seahorse.
    --
    -- The source label is the client's own BATTLE_PET_SOURCE_n string, which is
    -- what the Mount Journal and the Toy Box label their own source filters
    -- with, so a localized client searches in its own words. Nothing is
    -- invented here: only what the collection API actually hands back is
    -- indexed.
    local function SourceKeywords(sourceType, isFavorite)
        local out = isFavorite and (EllesmereUI.L("favorite"):lower() .. " ") or ""
        local label = sourceType and _G["BATTLE_PET_SOURCE_" .. sourceType]
        if label then out = out .. label:lower() end
        return out ~= "" and out or nil
    end

    local function MountEntries()
        local out = {}
        -- The roll the Mount Journal's own button makes, offered ahead of the
        -- collection itself: it is the entry most palettes want, and hunting
        -- for it among several hundred mounts sorted by name is not a search
        -- anyone can make. pin is what holds it there past the sort.
        do
            local slot = { kind = "randommount" }
            local icon, name = ns.SlotDisplay(slot)
            out[1] = { icon = icon, name = name, slot = slot, pin = true }
        end
        -- Beside it, and pinned for the same reason: an entry that summons
        -- whatever the player rode last. Its target changes on its own, so it
        -- is a kind rather than a mount -- there is nothing here to pick.
        do
            local slot = { kind = "lastmount" }
            local icon = ns.SlotDisplay(slot)
            out[#out + 1] = { icon = icon, name = "Last Used Mount",
                              slot = slot, pin = true }
        end
        for _, mountID in ipairs(C_MountJournal.GetMountIDs()) do
            local name, spellID, icon, _, _, sourceType, isFavorite, _, _,
                  hideOnChar, isCollected = C_MountJournal.GetMountInfoByID(mountID)
            -- isUsable is deliberately not read here. It moves with where the
            -- player stands -- the Mount Journal rebuilds its list on
            -- MOUNT_JOURNAL_USABILITY_CHANGED -- so filtering on it hides an
            -- aquatic mount from anyone picking on dry ground. Whether a mount
            -- can be summoned is a run-time question, not a pick-time one.
            if name and isCollected and not hideOnChar then
                out[#out + 1] = { icon = icon, name = name,
                    -- Where it came from, and whether it is a favorite, so both
                    -- are things the search box can be asked for.
                    keywords = SourceKeywords(sourceType, isFavorite),
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

    -- The toy box has no ID-based enumeration, only a walk over the list the
    -- Collections filters leave standing, so the picker used to show whatever
    -- the player last set there -- with "Not Collected" ticked it came up
    -- empty, which reads as a broken picker rather than as a filter. So the
    -- filters are widened for the length of the walk and every one of them is
    -- put back afterwards. Restoring is the whole cost of this: the scan runs
    -- inside pcall so an error still hands the player their own filters back.
    local function ScanToysUnfiltered(scan)
        local saved = {
            collected = C_ToyBox.GetCollectedShown(),
            uncollected = C_ToyBox.GetUncollectedShown(),
            unusable = C_ToyBox.GetUnusableShown(),
            sources = {},
            expansions = {},
        }
        local numSources = C_PetJournal.GetNumPetSources()
        for i = 1, numSources do
            saved.sources[i] = C_ToyBox.IsSourceTypeFilterChecked(i)
        end
        local numExpansions = GetNumExpansions()
        for i = 1, numExpansions do
            saved.expansions[i] = C_ToyBox.IsExpansionTypeFilterChecked(i)
        end
        -- There is no getter for the search string. It only ever comes from the
        -- Toy Box's own box, which banks it here, and it does not survive a
        -- reload -- so an empty string is the right restore when that is absent.
        local searchString = (ToyBox and ToyBox.searchString) or ""

        -- Uncollected toys are dropped rather than shown: PlayerHasToy rejects
        -- them anyway, so widening that one would only lengthen the walk.
        C_ToyBox.SetCollectedShown(true)
        C_ToyBox.SetUncollectedShown(false)
        C_ToyBox.SetUnusableShown(true)
        C_ToyBox.SetAllSourceTypeFilters(true)
        C_ToyBox.SetAllExpansionTypeFilters(true)
        C_ToyBox.SetFilterString("")
        C_ToyBox.ForceToyRefilter()

        local ok, err = pcall(scan)

        C_ToyBox.SetCollectedShown(saved.collected)
        C_ToyBox.SetUncollectedShown(saved.uncollected)
        C_ToyBox.SetUnusableShown(saved.unusable)
        for i = 1, numSources do
            C_ToyBox.SetSourceTypeFilter(i, saved.sources[i])
        end
        for i = 1, numExpansions do
            C_ToyBox.SetExpansionTypeFilter(i, saved.expansions[i])
        end
        C_ToyBox.SetFilterString(searchString)
        C_ToyBox.ForceToyRefilter()
        -- An open Toy Box drew its page from the widened list, so it has to be
        -- told to draw it again -- the same pair its own filter menu calls.
        if ToyBox and ToyBox:IsVisible() then
            if ToyBox_UpdatePages then ToyBox_UpdatePages() end
            if ToyBox_UpdateButtons then ToyBox_UpdateButtons() end
        end

        if not ok then error(err, 0) end
    end

    local function ToyEntries()
        local out = {}
        ScanToysUnfiltered(function()
            for i = 1, (C_ToyBox.GetNumFilteredToys() or 0) do
                local itemID = C_ToyBox.GetToyFromIndex(i)
                if itemID and itemID > 0 and PlayerHasToy(itemID) then
                    local _, name, icon, isFavorite = C_ToyBox.GetToyInfo(itemID)
                    if name then
                        -- Favorite only: the toy API hands back no source for
                        -- an individual toy, and a source guessed from anywhere
                        -- else would be a made-up answer in a search box.
                        out[#out + 1] = { icon = icon, name = name,
                            keywords = SourceKeywords(nil, isFavorite),
                            slot = { kind = "toy", id = itemID, name = name } }
                    end
                end
            end
        end)
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
        -- The global is nil on this client; 120 is the account block's size,
        -- the same fallback the ClickCast macro list uses
        -- (EUI_RaidFrames_ClickCast.lua:36).
        AddBlock((MAX_ACCOUNT_MACROS or 120) + 1, numChar)
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

    -- This character's own specializations, in the order the game lists them.
    -- The slot banks the specID rather than the index -- the module resolves
    -- the index back at fire time, so the same palette carried to an alt
    -- points at nothing instead of at somebody else's spec.
    local function SpecEntries()
        local out = {}
        local classID = select(3, UnitClass("player"))
        if not classID or not C_SpecializationInfo then return out end
        for i = 1, (C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0) do
            local specID, name, _, icon = C_SpecializationInfo.GetSpecializationInfo(i)
            if specID and name then
                out[#out + 1] = { icon = icon, name = name,
                    slot = { kind = "spec", specID = specID, name = name } }
            end
        end
        return out
    end

    -- The most specializations any class has -- four, the druid's alone.
    -- Walked rather than written down so a class that gains a fourth is picked
    -- up without a code change.
    local function MaxSpecCount()
        if not C_SpecializationInfo or not GetNumClasses then return 0 end
        local most = 0
        for classID = 1, GetNumClasses() do
            local n = C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0
            if n > most then most = n end
        end
        return most
    end

    -- The same list by POSITION rather than by identity, offered beside the
    -- fixed entries rather than instead of them: "go Restoration" is not "go
    -- to the third one", and only the second survives being carried to
    -- another class.
    --
    -- Every position ANY class has, not only this character's -- a paladin
    -- offered three could not put a druid's fourth on a palette built FOR the
    -- druid. The usability filter hides the extras until an alt has them.
    local function DynamicSpecEntries()
        local out = {}
        -- Named by the module that also RESOLVES the kind, so an older
        -- EllesmereUIQuickdraw beside a newer options page offers nothing
        -- rather than a kind that module could not fire.
        if not ns.SpecPositionName then return out end
        for i = 1, MaxSpecCount() do
            local slot = { kind = "dynamicspec", index = i }
            local icon = ns.SlotDisplay(slot)
            out[#out + 1] = { icon = icon, name = ns.SpecPositionName(i), slot = slot }
        end
        return out
    end

    -- Both lists, fixed first: naming a spec is what a player picking one on
    -- their main usually means, and the by-position block reads as the
    -- alternative to it rather than as the lead.
    local function AllSpecEntries()
        local out = SpecEntries()
        for _, entry in ipairs(DynamicSpecEntries()) do out[#out + 1] = entry end
        return out
    end

    -- Profession POSITIONS (DynamicSpecEntries counterpart): the five
    -- GetProfessions slots as openers, then the same five as second abilities,
    -- then the two primary slots as gathering specialization abilities.
    -- Unlearned or inapplicable positions resolve to nothing and go dark under
    -- Hide Unusable Entries (see Dynamic Profession in EllesmereUIQuickdraw).
    local function DynamicProfessionEntries()
        local out = {}
        if not ns.ProfessionPositionName then return out end
        for i = 1, 5 do
            local slot = { kind = "dynamicprofession", index = i }
            local icon = ns.SlotDisplay(slot)
            out[#out + 1] = { icon = icon, name = ns.ProfessionPositionName(i), slot = slot }
        end
        for i = 1, 5 do
            local slot = { kind = "dynamicprofession", index = i, extra = true }
            local icon = ns.SlotDisplay(slot)
            out[#out + 1] = { icon = icon, name = ns.ProfessionPositionName(i, true), slot = slot }
        end
        for i = 1, 2 do
            local slot = { kind = "dynamicprofession", index = i, specialization = true }
            local icon = ns.SlotDisplay(slot)
            out[#out + 1] = {
                icon = icon,
                name = ns.ProfessionPositionName(i, false, true),
                slot = slot,
            }
        end
        return out
    end

    -- The markers need no enumeration at all: the slot kinds carry the icon
    -- and the name, so a candidate slot handed to SlotDisplay IS the entry.
    --
    -- One row per marker per set is twenty-one rows, and the two sets are the
    -- one thing a user has already decided between before opening the menu --
    -- so Markers holds two lists rather than one, and neither is long enough to
    -- scroll. See the subs field on its category below.
    local function MarkerAdder(out)
        return function(kind, id, name)
            local slot = { kind = kind, id = id }
            local icon, drawn = ns.SlotDisplay(slot)
            out[#out + 1] = { icon = icon, name = name or drawn, slot = slot }
        end
    end

    -- The cyclers lead each list: one entry that steps through all eight is the
    -- reason to come here at all on a palette with no room for nine, and
    -- burying it under the eight it replaces hides it from exactly the person
    -- who wants it. Deliberately NOT in the two marker presets -- a preset that
    -- lays out all eight has nothing to cycle.
    --
    -- Each is named without the marker SlotDisplay appends. On a placed entry
    -- that suffix says which one is up next, which is the point of it; on a
    -- menu row it would read as the one marker this row places.
    local function TargetMarkerEntries()
        local out = {}
        local Add = MarkerAdder(out)
        Add("cycleraidtarget", nil, "Cycle Target Markers")
        for i = 1, 8 do Add("raidtarget", i) end
        Add("raidtarget", 0)
        -- The all-units counterpart of the /tm 0 row above; the world markers
        -- need none because their 0 row already clears them all.
        Add("clearmarkers")
        return out
    end

    local function WorldMarkerEntries()
        local out = {}
        local Add = MarkerAdder(out)
        Add("cycleworldmarker", nil, "Cycle World Markers")
        for i = 1, 8 do Add("worldmarker", i) end
        Add("worldmarker", 0)
        return out
    end

    -- The interface panels this client has, in micro-menu order. The module
    -- owns the list -- which panel is clicked how, and which of them this
    -- client even has -- so the picker only draws what it is handed. Panels
    -- missing from this build (Housing before 12.0, the Shop in a region whose
    -- client has none) never reach the list, so a row here always opens
    -- something.
    local function PanelEntries()
        local out = {}
        for _, slot in ipairs(ns.PanelSlots and ns.PanelSlots(true) or {}) do
            local icon, name = ns.SlotDisplay(slot)
            out[#out + 1] = { icon = icon, name = name, slot = slot }
        end
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
                out[#out + 1] = {
                    -- Same icon SlotDisplay draws it by: its first entry.
                    icon = PaletteListIcon(palette),
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
    -- subs = the row opens a second list of categories rather than a list of
    -- entries, for a category whose contents divide the way the user already
    -- has in their head before they open it.
    local PICKER_CATEGORIES = {
        -- First, above the divider the root list draws under it: nesting is
        -- the one row that is about the menus themselves rather than about
        -- something the game owns.
        { key = "palette",   label = "Nest Another Action Menu", build = PaletteEntries },
        { key = "spell",     label = "Spells",       build = SpellEntries },
        { key = "mount",     label = "Mounts",       build = MountEntries,
          keywordHint = true },
        { key = "item",      label = "Items",        build = ItemEntries },
        { key = "toy",       label = "Toys",         build = ToyEntries,
          keywordHint = true },
        { key = "macro",     label = "Macros",       build = MacroEntries },
        { key = "battlepet", label = "Battle Pets",  build = PetEntries },
        -- keepOrder on both: the markers run star to skull, the order every
        -- marker menu in the game shows. noSearch on both too -- a fixed
        -- handful of rows has nothing worth filtering, and the nav strip
        -- collapses to the Back row alone.
        { key = "marker",    label = "Markers", subs = {
            { key = "marker_target", label = "Target Markers",
              build = TargetMarkerEntries, keepOrder = true, noSearch = true },
            { key = "marker_world",  label = "World Markers",
              build = WorldMarkerEntries,  keepOrder = true, noSearch = true },
        } },
        -- keepOrder: the game lists a class's specs in one fixed order that
        -- every character sheet shows, and alphabetising them would be the
        -- one place in the interface they are not in it. It also keeps the
        -- by-position block below the fixed one, which is the whole of how the
        -- two tell themselves apart. noSearch: at most eight rows.
        { key = "spec",      label = "Specializations", build = AllSpecEntries,
          keepOrder = true, noSearch = true },
        -- keepOrder: Profession 1, Profession 2, Cooking, Fishing and
        -- Archaeology in the fixed order the game lists them, then the same
        -- five positions' second abilities. noSearch: ten rows.
        { key = "profession", label = "Professions", build = DynamicProfessionEntries,
          keepOrder = true, noSearch = true },
        -- keepOrder: the panels run in the order the micro menu draws them,
        -- which is the row the player already reads left to right. noSearch:
        -- the whole interface is under twenty rows, and a search box over a
        -- list the user is scanning by ICON buys nothing.
        { key = "panel",     label = "Interface Panels", build = PanelEntries,
          keepOrder = true, noSearch = true },
        { key = "macrotext", label = "Custom Macro...", custom = true },
    }

    -- Which list the Back row goes home to, filled in here because a table
    -- literal cannot name itself. A category with no parent is at the root.
    for _, cat in ipairs(PICKER_CATEGORIES) do
        for _, sub in ipairs(cat.subs or {}) do sub.parent = cat end
    end

    local ShowPickerCategories, ShowPickerCategory, ShowPickerCustom

    local function HidePicker()
        if pickerMenu then pickerMenu:Hide() end
    end

    -- Returns true when a slot was actually committed.
    local function AssignEntry(entry)
        local palette = Palette(editPalette)
        if not palette then return false end
        -- The stored slot is a COPY: the entry belongs to the cached list, and
        -- handing that one table to two entries would alias a single saved slot
        -- into both of them.
        local slot = {}
        for k, v in pairs(entry.slot) do slot[k] = v end
        if pickerReplaceIndex then
            -- Opened by a right-click on an existing entry: the pick replaces
            -- that slot, the same direct write dropping an action on it
            -- performs (PreviewPlace). Guarded in case the slot is gone --
            -- every removal path closes the picker, but a guard is cheaper
            -- than the certainty.
            if not palette.slots[pickerReplaceIndex] then return false end
            palette.slots[pickerReplaceIndex] = slot
        elseif not ns.AddSlot(palette, slot) then
            -- ns.AddSlot refuses a full palette. Unreachable from here -- a
            -- full palette draws no "+" to click -- but the refusal must not
            -- fall through into a Refresh that has nothing to show.
            return false
        end
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
        menu.title:SetPoint("TOP", menu, "TOP", 0, -7)
        menu.title:SetJustifyH("CENTER")

        menu.back = CreateFrame("Button", nil, menu)
        menu.back:SetHeight(PICK_ROW_H)
        menu.back:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -PICK_HEAD_H)
        menu.back:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, -PICK_HEAD_H)
        menu.back:SetFrameLevel(menu:GetFrameLevel() + 2)
        local bHl = menu.back:CreateTexture(nil, "ARTWORK")
        bHl:SetAllPoints()
        bHl:SetColorTexture(1, 1, 1, 0)
        local bAr = menu.back:CreateTexture(nil, "OVERLAY")
        bAr:SetSize(12, 12)
        bAr:SetPoint("LEFT", menu.back, "LEFT", 8, 0)
        bAr:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-left.png")
        bAr:SetVertexColor(tR, tG, tB, tA)
        if bAr.SetSnapToPixelGrid then bAr:SetSnapToPixelGrid(false); bAr:SetTexelSnappingBias(0) end
        local bTx = EllesmereUI.MakeFont(menu.back, 11, nil, tR, tG, tB, tA)
        bTx:SetPoint("LEFT", bAr, "RIGHT", 6, 0)
        bTx:SetText(EllesmereUI.L("Categories"))
        -- Named, because a sub-category's entries go back to the sub-list
        -- rather than to the root and the row has to say which.
        menu.backText = bTx
        menu.back:SetScript("OnEnter", function()
            bHl:SetColorTexture(1, 1, 1, hlA)
            bTx:SetTextColor(1, 1, 1, 1)
            bAr:SetVertexColor(1, 1, 1, 1)
        end)
        menu.back:SetScript("OnLeave", function()
            bHl:SetColorTexture(1, 1, 1, 0)
            bTx:SetTextColor(tR, tG, tB, tA)
            bAr:SetVertexColor(tR, tG, tB, tA)
        end)
        -- One step up from wherever we are: the entries of a sub-category go to
        -- its own list, everything else to the root. menu.cat is nil in both
        -- list views, so a sub-list's own Back lands at the root, which is the
        -- only place left to go.
        menu.back:SetScript("OnClick", function()
            ShowPickerCategories(menu.cat and menu.cat.parent or nil)
        end)

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
        menu.searchPH:SetText(EllesmereUI.L("Search..."))
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

        -- Hairline under the root list's first row (the nest category),
        -- separating it from the game-owned categories below. Drawn on the
        -- boundary between rows 1 and 2 so the pooled rows' fixed pitch is
        -- untouched; only ShowPickerCategories' root view shows it.
        menu.catDivider = menu.list:CreateTexture(nil, "ARTWORK")
        menu.catDivider:SetColorTexture(1, 1, 1, brdA)
        menu.catDivider:SetHeight(1)
        menu.catDivider:SetPoint("TOPLEFT", menu.list, "TOPLEFT", 6, -PICK_ROW_H)
        menu.catDivider:SetPoint("TOPRIGHT", menu.list, "TOPRIGHT", -6, -PICK_ROW_H)
        menu.catDivider:Hide()

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
        nameLbl:SetText(EllesmereUI.L("Label"))
        local nameBox = MakeInput(custom, 22, false)
        nameBox:SetPoint("TOPLEFT", nameLbl, "BOTTOMLEFT", 0, -3)
        nameBox:SetPoint("RIGHT", custom, "RIGHT", -1, 0)
        nameBox:SetMaxLetters(24)

        local textLbl = EllesmereUI.MakeFont(custom, 10, nil, tR, tG, tB, tA)
        textLbl:SetPoint("TOPLEFT", nameBox, "BOTTOMLEFT", 0, -8)
        textLbl:SetText(EllesmereUI.L("Macro Text"))
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
        aTx:SetText(EllesmereUI.L("Add"))
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
            -- Replace mode ends with the menu, however it went down --
            -- committed, dismissed, or torn down by a page rebuild.
            pickerReplaceIndex = nil
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
        -- Measured off the rows themselves rather than off menu.cat: a
        -- sub-category list shows the Back row without being an entry view,
        -- and reserving no space for it would put the first row under it.
        -- Views with no search box (category lists, noSearch categories)
        -- collapse the nav strip to the Back row alone.
        local top = PICK_HEAD_H
        if menu.back:IsShown() then
            top = top + (menu.search:IsShown() and PICK_NAV_H
                or (PICK_ROW_H + 4))
        end
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

    -- parent = nil for the root list, or the category whose sub-list to show.
    ShowPickerCategories = function(parent)
        local menu = EnsurePickerMenu()
        local cats = parent and parent.subs or PICKER_CATEGORIES
        -- No cat: this is a list of categories, and the search box has nothing
        -- to filter. The Back row is the one thing that differs between the two
        -- levels -- the root has nowhere above it.
        menu.cat = nil
        menu.title:SetText(EllesmereUI.L(parent and parent.label
            or (pickerReplaceIndex and "Change Action" or "Add Action")))
        menu.back:SetShown(parent ~= nil)
        menu.backText:SetText(EllesmereUI.L("Categories"))
        -- Focus first: hiding a focused edit box leaves the keyboard captured by
        -- a box that is no longer on screen.
        menu.search:ClearFocus()
        menu.search:Hide()
        menu.custom:Hide()
        menu.scroll:Show()
        -- Only the root list carries the nest row, so only it draws the
        -- divider under row 1.
        menu.catDivider:SetShown(parent == nil)

        for i, cat in ipairs(cats) do
            local r = menu:GetRow(i)
            r.icon:Hide()
            -- Rows are shared with the entry views, which anchor the label to
            -- the icon -- so both views re-anchor it every time.
            r.label:ClearAllPoints()
            r.label:SetPoint("LEFT", r, "LEFT", 8, 0)
            r.label:SetPoint("RIGHT", r, "RIGHT", -6, 0)
            r.label:SetText(EllesmereUI.L(cat.label))
            r:SetScript("OnClick", function()
                if cat.custom then
                    ShowPickerCustom()
                elseif cat.subs then
                    ShowPickerCategories(cat)
                else
                    menu.search:SetText("")
                    ShowPickerCategory(cat)
                end
            end)
            r:Show()
        end

        -- Replace mode's root list ends with a Remove Action row: removal
        -- otherwise lives on middle-click alone, and not every mouse has a
        -- middle button. Root only -- inside a category the list is answers
        -- to "change it to what", and Back already leads out.
        local count = #cats
        if parent == nil and pickerReplaceIndex then
            count = count + 1
            local r = menu:GetRow(count)
            r.icon:Hide()
            r.label:ClearAllPoints()
            r.label:SetPoint("LEFT", r, "LEFT", 8, 0)
            r.label:SetPoint("RIGHT", r, "RIGHT", -6, 0)
            r.label:SetText(EllesmereUI.L("Remove Action"))
            r:SetScript("OnClick", function()
                -- Before HidePicker, which clears the index on OnHide. The
                -- guard mirrors AssignEntry's: a slot already gone leaves
                -- nothing to remove and the menu stays up.
                local palette = Palette(editPalette)
                if palette and pickerReplaceIndex
                   and ns.RemoveSlot(palette, pickerReplaceIndex) then
                    HidePicker()
                    Refresh()
                end
            end)
            r:Show()
        end
        for i = count + 1, #menu.rows do menu.rows[i]:Hide() end

        PickerFit(menu, count)
        menu:Show()
    end

    ShowPickerCategory = function(cat)
        local menu = EnsurePickerMenu()
        menu.cat = cat
        menu.title:SetText(EllesmereUI.L(cat.label))
        menu.back:Show()
        menu.backText:SetText(EllesmereUI.L(cat.parent and cat.parent.label or "Categories"))
        -- Focus first when hiding: a hidden edit box keeps the keyboard.
        if cat.noSearch then
            menu.search:ClearFocus()
            menu.search:Hide()
        else
            menu.search:Show()
            -- The placeholder names what the box searches. A list that also
            -- matches source and favorite is worth nothing if the only way to
            -- find that out is to guess it.
            menu.searchPH:SetText(EllesmereUI.L(
                cat.keywordHint and "Search name, source, favorite..." or "Search..."))
            menu.searchPH:SetShown((menu.search:GetText() or "") == "")
        end
        menu.custom:Hide()
        menu.scroll:Show()
        menu.catDivider:Hide()

        local list = pickerLists[cat.key]
        if not list then
            list = cat.build()
            -- Alphabetical rather than in enumeration order: the spellbook's own
            -- grouping means nothing once the tabs are gone, and a name is what
            -- the user is scanning for. A category can opt out for a list whose
            -- own order IS the one the user knows -- the markers run star to
            -- skull, the order every marker menu in the game shows.
            -- A pinned entry sorts ahead of every plain one whatever its name.
            -- Pinning is per entry rather than per category so a list that is
            -- otherwise alphabetical can still lead with the row the user came
            -- for.
            if not cat.keepOrder then
                table.sort(list, function(a, b)
                    if (a.pin or false) ~= (b.pin or false) then return a.pin == true end
                    return a.name < b.name
                end)
            end
            pickerLists[cat.key] = list
        end

        local filter = cat.noSearch and ""
            or (menu.search:GetText() or ""):lower()
        local n = 0
        for _, entry in ipairs(list) do
            -- The name first, then whatever else the entry knows about itself.
            -- A picker holding several hundred rows that can only be searched
            -- by name can only be searched by someone who already knows the
            -- name of the thing they want, which is the opposite of what a
            -- search is for. Keywords are built once with the list and are
            -- already lowercase; this runs on every keystroke.
            if filter == ""
               or entry.name:lower():find(filter, 1, true)
               or (entry.keywords and entry.keywords:find(filter, 1, true)) then
                n = n + 1
                local r = menu:GetRow(n)
                r.icon:SetTexture(entry.icon or QUESTION_MARK)
                -- Rows are pooled across categories, and the marker textures
                -- take the full rect where action icons take the crop.
                if ns.ApplyIconCrop then ns.ApplyIconCrop(r.icon, entry.icon) end
                r.icon:Show()
                r.label:ClearAllPoints()
                r.label:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
                r.label:SetPoint("RIGHT", r, "RIGHT", -6, 0)
                r.label:SetText(EllesmereUI.L(entry.name))
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
            r.label:SetText(filter == "" and EllesmereUI.L("Nothing to add") or EllesmereUI.L("No matches"))
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
        menu.title:SetText(EllesmereUI.L("Custom Macro"))
        menu.back:Show()
        -- Restated rather than left as it was: the row is shared, and the view
        -- before this one may have been a sub-category's.
        menu.backText:SetText(EllesmereUI.L("Categories"))
        menu.search:ClearFocus()
        menu.search:Hide()
        -- Hiding the scroll frame takes the pooled rows with it: they are its
        -- scroll child's children.
        menu.scroll:Hide()
        menu.catDivider:Hide()
        menu.custom:Show()
        menu:SetHeight(PICK_HEAD_H + PICK_ROW_H + 6 + menu.custom:GetHeight() + 4)
        menu:Show()
    end

    -- replaceIndex: open in replace mode on that slot (right-click on an
    -- entry); nil is the "+" append mode.
    local function TogglePicker(widget, replaceIndex)
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
        pickerReplaceIndex = replaceIndex
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

    -- Numeric /ping aliases (1 attack, 2 warning, 3 on my way, 4 assist, 5 look):
    -- the word forms resolve through localized PING_TYPE_* globals and only match
    -- on English clients.
    local function PingSlots()
        return {
            {
                kind = "macrotext",
                name = "Look",
                macrotext = "/ping 5",
                icon = { atlas = "Ping_Marker_Icon_NonThreat" },
            },
            {
                kind = "macrotext",
                name = "Assist",
                macrotext = "/ping 4",
                icon = { atlas = "Ping_Marker_Icon_Assist" },
            },
            {
                kind = "macrotext",
                name = "Attack",
                macrotext = "/ping 1",
                icon = { atlas = "Ping_Marker_Icon_Attack" },
            },
            {
                kind = "macrotext",
                name = "Warning",
                macrotext = "/ping 2",
                icon = { atlas = "Ping_Marker_Icon_Warning" },
            },
            {
                kind = "macrotext",
                name = "On My Way",
                macrotext = "/ping 3",
                icon = { atlas = "Ping_Marker_Icon_OnMyWay" },
            },
        }
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
    -- A builder returns what it found and, second, how many it had to leave
    -- out. A preset that quietly stopped at the cap was the "it also seems to
    -- limit hearthstones" half of the report: the toys share a cooldown, so
    -- dropping the tail of THOSE costs nothing, but a hearthstone the player
    -- owns and cannot see is a destination they have lost. Counted here and
    -- said in the menu rather than fixed by raising a cap on its own -- some
    -- collections are simply larger than any menu.
    local function HearthstoneSlots()
        local out, dropped = {}, 0
        for _, itemID in ipairs(HEARTH_ITEMS) do
            if C_Item.GetItemCount(itemID) > 0 then
                out[#out + 1] = { kind = "item", id = itemID }
            end
        end
        for _, toyID in ipairs(HEARTH_TOYS) do
            if PlayerHasToy(toyID) then
                if #out < MAX_SLOTS then
                    out[#out + 1] = { kind = "toy", id = toyID }
                else
                    dropped = dropped + 1
                end
            end
        end
        return out, dropped
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
        local out, dropped = {}, 0
        local list = TELEPORT_SPELLS[select(2, UnitClass("player"))]
        for _, spellID in ipairs(list or {}) do
            if IsPlayerSpell(spellID) then
                if #out < MAX_SLOTS then
                    out[#out + 1] = { kind = "spell", id = spellID }
                else
                    dropped = dropped + 1
                end
            end
        end
        return out, dropped
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

    -- Every form a druid can be in, plus the two that are really ways of
    -- moving between them. Aquatic and Flight are listed even though Travel
    -- Form has absorbed both on most builds: IsPlayerSpell is what decides,
    -- and a spell nobody has simply does not appear.
    local FORM_SPELLS = {
        5487,    -- Bear Form
        768,     -- Cat Form
        5215,    -- Prowl
        783,     -- Travel Form
        1066,    -- Aquatic Form
        165962,  -- Flight Form
        24858,   -- Moonkin Form
        114282,  -- Treant Form
    }
    local function FormSlots()
        local out, dropped = {}, 0
        for _, spellID in ipairs(FORM_SPELLS) do
            if IsPlayerSpell(spellID) then
                if #out < MAX_SLOTS then
                    out[#out + 1] = { kind = "spell", id = spellID }
                else
                    dropped = dropped + 1
                end
            end
        end
        -- Getting OUT is the half of shapeshifting no form spell covers, and
        -- there is no spell for it at all -- /cancelform is the whole of it.
        -- Only offered once a form has been found, so the preset stays hidden
        -- on a class that has none. The clear icon the marker entries use,
        -- because it says the same thing.
        if #out > 0 and #out < MAX_SLOTS then
            out[#out + 1] = { kind = "macrotext", macrotext = "/cancelform",
                              name = "Cancel Form",
                              icon = "Interface\\Buttons\\UI-GroupLoot-Pass-Up" }
        end
        return out, dropped
    end

    -- One-of-a-set toggles that are not forms: a warrior's stances and a
    -- paladin's auras are the same choice in two costumes, and both are
    -- ordinary spells.
    local STANCE_SPELLS = {
        WARRIOR = { 386164, 386208, 386196 },   -- Battle, Defensive, Berserker
        PALADIN = { 465, 32223, 183435, 317920 },  -- Devotion, Crusader, Retribution, Concentration
    }
    local function StanceSlots()
        local out, dropped = {}, 0
        for _, spellID in ipairs(STANCE_SPELLS[select(2, UnitClass("player"))] or {}) do
            if IsPlayerSpell(spellID) then
                if #out < MAX_SLOTS then
                    out[#out + 1] = { kind = "spell", id = spellID }
                else
                    dropped = dropped + 1
                end
            end
        end
        return out, dropped
    end

    -- By position rather than by identity. A preset is the palette a player
    -- has not built by hand, so it is the one most likely to be copied to a
    -- profile an alt shares -- and the only preset here whose slots would
    -- otherwise all go dead on arrival.
    --
    -- No dropped count: four positions against a sixteen-slot menu, so unlike
    -- the collection presets this one can never be the thing that does not
    -- fit. Empty is the stale-module case, and leaves the preset unoffered.
    local function SpecSlots()
        local slots = {}
        for _, entry in ipairs(DynamicSpecEntries()) do slots[#slots + 1] = entry.slot end
        return slots
    end

    -- Quest items the character is carrying that DO something: the bag walk
    -- ItemEntries makes, narrowed to the quest item class and to items with a
    -- use effect. An item with no effect is a quest object being carried, not
    -- something an entry can fire.
    --
    -- The quest log's own special items are folded in as well. Those are the
    -- ones the objective tracker draws a button for, and they are not always
    -- in the quest item CLASS -- a trinket or a toy handed out for one quest
    -- reads as its own class and would be missed by the bag walk alone.
    -- GetQuestLogSpecialItemInfo is the same call the tracker makes
    -- (Blizzard_ObjectiveTrackerShared.lua:53).
    --
    -- A snapshot, like every preset here: it holds what the character carries
    -- at the moment the menu is built. See the note under QD-07a in the bug
    -- report for the self-refilling version and why it is not this.
    local function QuestItemSlots()
        local out, seen, dropped = {}, {}, 0
        local function Add(itemID)
            if not itemID or seen[itemID] then return end
            if not C_Item.GetItemSpell(itemID) then return end
            seen[itemID] = true
            if #out < MAX_SLOTS then
                out[#out + 1] = { kind = "item", id = itemID }
            else
                dropped = dropped + 1
            end
        end
        local function ScanBag(bag)
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                local itemID = info and info.itemID
                if itemID and not seen[itemID] then
                    local classID = select(6, C_Item.GetItemInfoInstant(itemID))
                    if classID == Enum.ItemClass.Questitem then Add(itemID) end
                end
            end
        end
        for bag = Enum.BagIndex.Backpack, NUM_BAG_SLOTS do ScanBag(bag) end
        ScanBag(Enum.BagIndex.ReagentBag)

        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader then
                -- The LINK, which is the first return; the second is the
                -- button's texture, not an id. GetItemInfoInstant takes a link
                -- and hands back the itemID first.
                local link = GetQuestLogSpecialItemInfo(i)
                if link then Add((C_Item.GetItemInfoInstant(link))) end
            end
        end
        return out, dropped
    end

    -- By position rather than by identity, the same reasoning as SpecSlots
    -- above and for the same reason: a preset is the palette most likely to
    -- be copied to an alt, and only a position survives that trip. Ten
    -- positions against a sixteen-slot menu, so no dropped count either --
    -- see DynamicProfessionEntries for what each position means.
    local function ProfessionSlots()
        local slots = {}
        for _, entry in ipairs(DynamicProfessionEntries()) do slots[#slots + 1] = entry.slot end
        return slots
    end

    -- The micro menu as a menu, which is the whole of what this preset is for:
    -- one keybind in place of the dozen the panels take between them. The
    -- module drops the panels this client has not got and holds back the two
    -- worth least in a ring -- the Shop and Customer Support -- so a full house
    -- lands on MAX_SLOTS exactly rather than reporting an overflow every time.
    -- Both are still in the picker for anyone who wants them.
    local function InterfacePanelSlots()
        return ns.PanelSlots and ns.PanelSlots(false) or {}
    end

    local PALETTE_PRESETS = {
        { label = "Interface Panels", build = InterfacePanelSlots },
        { label = "Target Markers", build = TargetMarkerSlots },
        { label = "World Markers",  build = WorldMarkerSlots },
        { label = "Pings",          build = PingSlots },
        { label = "Hearthstones",   build = HearthstoneSlots },
        { label = "Teleports",      build = TeleportSlots },
        { label = "Potions",        build = PotionSlots },
        { label = "Druid Forms",    build = FormSlots },
        { label = "Stances",        build = StanceSlots },
        { label = "Specializations", build = SpecSlots },
        { label = "Professions",    build = ProfessionSlots },
        { label = "Quest Items",    build = QuestItemSlots },
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
            palette.appearance = nil
            -- Seed the name in the player's language: it is user data from the
            -- moment it exists (renameable), so store the translated label.
            palette.name = (preset and EllesmereUI.L(preset.label)) or AutoName(count + 1)
            for _, s in ipairs(slots or {}) do
                if not ns.AddSlot(palette, s) then break end
            end
        end
        editPalette = count + 1
        HidePicker()
        RebuildPage()
    end

    -- One pooled row of the shared menu, filled in. Shared by the two views
    -- below that list something other than actions; the action views anchor
    -- their labels the same two ways inline.
    local function MenuRow(menu, i, icon, label, onClick)
        local r = menu:GetRow(i)
        if icon then
            if type(icon) == "table" and icon.atlas then
                r.icon:SetAtlas(icon.atlas)
            else
                r.icon:SetTexture(icon)
            end
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

    -- Open the shared menu as a plain list with `title` at the top, ready for
    -- MenuRow. Returns the menu, or nil when this click was the one that
    -- closes an already-open list on the same anchor.
    local function OpenListMenu(anchor, title)
        if not anchor then return nil end
        local menu = EnsurePickerMenu()
        if menu:IsShown() and pickerAnchor == anchor then
            HidePicker()
            return nil
        end
        pickerAnchor = anchor
        menu:ClearAllPoints()
        menu:SetPoint("TOP", anchor, "BOTTOM", 0, -4)
        menu.cat = nil
        menu.title:SetText(EllesmereUI.L(title))
        menu.back:Hide()
        menu.search:ClearFocus()
        menu.search:Hide()
        menu.custom:Hide()
        menu.scroll:Show()
        menu.catDivider:Hide()
        return menu
    end

    -- A view on the same anchored menu the action picker uses, so the add
    -- button and the "+" entry cannot both have one open: whichever opens
    -- second takes the menu over.
    local function ShowAddPaletteMenu(anchor)
        local menu = OpenListMenu(anchor, "Add Action Menu")
        if not menu then return end

        MenuRow(menu, 1, nil, EllesmereUI.L("Empty Action Menu"), function() AddPalette(nil) end)
        local n = 1
        for _, preset in ipairs(PALETTE_PRESETS) do
            local slots, dropped = preset.build()
            if #slots > 0 then
                n = n + 1
                local icon = ns.SlotDisplay(slots[1])
                -- The count, and what a full menu could not take. A preset that
                -- stopped at the cap and said nothing looked like a preset that
                -- had found everything there was.
                local count = "  |cff808080(" .. #slots .. ")|r"
                if dropped and dropped > 0 then
                    count = count .. " |cffd08050"
                        .. EllesmereUI.Lf("%1$d did not fit", dropped) .. "|r"
                end
                MenuRow(menu, n, icon or QUESTION_MARK,
                    EllesmereUI.L(preset.label) .. count,
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
            Complain("Quickdraw: action menus can't be deleted in combat.")
            return
        end

        -- Materialize every live palette first: the shift walks 1 .. count and
        -- table.remove stops at the first hole.
        for i = 1, count do Palette(i) end

        table.remove(p.palettes, index)
        Set("paletteCount", count - 1)

        -- The auto-names close ranks with everything else. A palette the user
        -- never renamed carries the number it was made under, so deleting
        -- "Action Menu 1" would otherwise leave "Action Menu 2" sitting at
        -- index 1 -- and Add, which names by index, would then hand out that
        -- same name a second time. Only the auto-name moves: a name the user
        -- typed is theirs, whatever it happens to look like.
        for i = index, count - 1 do
            local palette = Palette(i)
            if palette and palette.name == AutoName(i + 1) then
                palette.name = AutoName(i)
            end
        end

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
        for n = 1, MAX_PALETTES do
            keys[n] = { GetBindingKey(BINDING_PREFIX .. n) }
            if n >= index and keys[n][1] then any = true end
        end
        for n = index, MAX_PALETTES do
            for _, k in ipairs(keys[n]) do SetBinding(k) end
        end
        for n = index, MAX_PALETTES - 1 do
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

    ---------------------------------------------------------------------------
    --  Editing Action Menu selector -- the Profiles & Presets "Active
    --  Profile" dropdown re-cut for menus: every row carries the same inline
    --  rename (pencil) and delete (X) buttons, in exactly that style, and
    --  those are where renaming and deleting live now (the page rows they
    --  replace are gone). The MENU frame and its item pool are cached across
    --  page rebuilds -- only the anchor button rebuilds with the page -- so
    --  rebuilds leak nothing.
    ---------------------------------------------------------------------------
    local mmMenu
    local mmItems = {}
    local MM_W, MM_X = 170, 14

    local function EnsureMenuMenu()
        if mmMenu then return mmMenu end
        local PPQ = EllesmereUI.PanelPP
        local m = CreateFrame("Frame", nil, UIParent)
        m:SetFrameStrata("FULLSCREEN_DIALOG")
        m:SetFrameLevel(200)
        m:SetClampedToScreen(true)
        m:SetSize(MM_W, 4)
        m:Hide()
        local bg = m:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, 0.98)
        EllesmereUI.MakeBorder(m, 1, 1, 1, EllesmereUI.DD_BRD_A, PPQ)
        -- Click-outside dismissal + anchor scale matching, the profile
        -- menu's own. The anchor is re-pointed per page build (m._anchor).
        m:SetScript("OnShow", function(self)
            local anchor = self._anchor
            if anchor then
                self:SetScale(anchor:GetEffectiveScale() / UIParent:GetEffectiveScale())
            end
            self:SetScript("OnUpdate", function(mm)
                local a2 = mm._anchor
                if (not a2 or not a2:IsMouseOver()) and not mm:IsMouseOver() then
                    if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then
                        mm:Hide()
                    end
                end
            end)
        end)
        m:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
        mmMenu = m
        return m
    end

    local function RebuildMenuRows()
        local m = EnsureMenuMenu()
        local FONT = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath())
            or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
        local mH = 4
        local count = PaletteCount()
        for i = 1, count do
            local itm = mmItems[i]
            if not itm then
                itm = CreateFrame("Button", nil, m)
                itm:SetHeight(26)
                itm:SetFrameLevel(m:GetFrameLevel() + 1)
                -- The menu's icon, the class-icon-dropdown treatment (icon
                -- sized to the row less 8, label re-anchored to it) mirrored
                -- to the left because the rename and delete buttons own this
                -- row's right edge. Cropped like every action icon.
                local ico = itm:CreateTexture(nil, "ARTWORK")
                ico:SetSize(18, 18)
                ico:SetPoint("LEFT", itm, "LEFT", 8, 0)
                ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                itm._ico = ico
                local lbl = itm:CreateFontString(nil, "OVERLAY")
                lbl:SetFont(FONT, 13, EllesmereUI.GetFontOutlineFlag())
                lbl:SetPoint("LEFT", ico, "RIGHT", 6, 0)
                lbl:SetPoint("RIGHT", itm, "RIGHT", -(MM_X * 2 + 22), 0)
                lbl:SetJustifyH("LEFT")
                lbl:SetWordWrap(false)
                lbl:SetTextColor(1, 1, 1, EllesmereUI.TEXT_DIM_A)
                itm._lbl = lbl
                local hl = itm:CreateTexture(nil, "ARTWORK")
                hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 1); hl:SetAlpha(0)
                itm._hl = hl

                local xBtn = CreateFrame("Button", nil, itm)
                xBtn:SetSize(MM_X, MM_X)
                xBtn:SetPoint("RIGHT", itm, "RIGHT", -8, 0)
                xBtn:SetFrameLevel(itm:GetFrameLevel() + 2)
                local xIcon = xBtn:CreateTexture(nil, "OVERLAY")
                xIcon:SetAllPoints()
                if xIcon.SetSnapToPixelGrid then xIcon:SetSnapToPixelGrid(false); xIcon:SetTexelSnappingBias(0) end
                xIcon:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png")
                xBtn:SetAlpha(0.4)
                itm._xBtn = xBtn

                local editBtn = CreateFrame("Button", nil, itm)
                editBtn:SetSize(MM_X, MM_X)
                editBtn:SetPoint("RIGHT", xBtn, "LEFT", -4, 0)
                editBtn:SetFrameLevel(itm:GetFrameLevel() + 2)
                local editIcon = editBtn:CreateTexture(nil, "OVERLAY")
                editIcon:SetAllPoints()
                if editIcon.SetSnapToPixelGrid then editIcon:SetSnapToPixelGrid(false); editIcon:SetTexelSnappingBias(0) end
                editIcon:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-edit.png")
                editBtn:SetAlpha(0.4)
                itm._editBtn = editBtn

                local function IsOverInline()
                    return xBtn:IsMouseOver() or editBtn:IsMouseOver()
                end
                local function SetAllInlineAlpha(a2)
                    xBtn:SetAlpha(a2); editBtn:SetAlpha(a2)
                end
                itm:SetScript("OnEnter", function()
                    lbl:SetTextColor(1, 1, 1, 1)
                    hl:SetAlpha(EllesmereUI.DD_ITEM_HL_A)
                    SetAllInlineAlpha(0.8)
                end)
                itm:SetScript("OnLeave", function()
                    if IsOverInline() then return end
                    lbl:SetTextColor(1, 1, 1, EllesmereUI.TEXT_DIM_A)
                    hl:SetAlpha(itm._isSel and EllesmereUI.DD_ITEM_SEL_A or 0)
                    SetAllInlineAlpha(0.4)
                end)
                local function InlineBtnEnter(self2)
                    lbl:SetTextColor(1, 1, 1, 1)
                    hl:SetAlpha(EllesmereUI.DD_ITEM_HL_A)
                    SetAllInlineAlpha(0.8)
                    self2:SetAlpha(1)
                end
                local function InlineBtnLeave(self2)
                    if itm:IsMouseOver() or IsOverInline() then
                        self2:SetAlpha(0.8)
                        return
                    end
                    lbl:SetTextColor(1, 1, 1, EllesmereUI.TEXT_DIM_A)
                    hl:SetAlpha(itm._isSel and EllesmereUI.DD_ITEM_SEL_A or 0)
                    SetAllInlineAlpha(0.4)
                end
                xBtn:SetScript("OnEnter", function(self2)
                    InlineBtnEnter(self2)
                    EllesmereUI.ShowWidgetTooltip(self2, "Delete")
                end)
                xBtn:SetScript("OnLeave", function(self2)
                    InlineBtnLeave(self2)
                    EllesmereUI.HideWidgetTooltip()
                end)
                editBtn:SetScript("OnEnter", function(self2)
                    InlineBtnEnter(self2)
                    EllesmereUI.ShowWidgetTooltip(self2, "Rename")
                end)
                editBtn:SetScript("OnLeave", function(self2)
                    InlineBtnLeave(self2)
                    EllesmereUI.HideWidgetTooltip()
                end)
                mmItems[i] = itm
            end

            itm:SetPoint("TOPLEFT", m, "TOPLEFT", 1, -mH)
            itm:SetPoint("TOPRIGHT", m, "TOPRIGHT", -1, -mH)
            local pal = Palette(i)
            itm._ico:SetTexture(PaletteListIcon(pal))
            itm._lbl:SetText((pal and pal.name) or AutoName(i))
            itm._isSel = (i == editPalette)
            itm._hl:SetAlpha(itm._isSel and 0.04 or 0)
            itm._lbl:SetTextColor(1, 1, 1, EllesmereUI.TEXT_DIM_A)

            -- The row being edited hides its X, exactly as the active profile
            -- does -- which also means the last remaining menu never shows
            -- one. Deleting is done from any OTHER row.
            if itm._isSel then
                itm._xBtn:Hide()
                itm._editBtn:ClearAllPoints()
                itm._editBtn:SetPoint("RIGHT", itm, "RIGHT", -8, 0)
            else
                itm._xBtn:Show()
                itm._editBtn:ClearAllPoints()
                itm._editBtn:SetPoint("RIGHT", itm._xBtn, "LEFT", -4, 0)
            end

            local idx = i
            itm:SetScript("OnClick", function()
                mmMenu:Hide()
                if idx ~= editPalette then
                    editPalette = idx
                    RebuildPage()
                end
            end)
            itm._xBtn:SetScript("OnClick", function()
                mmMenu:Hide()
                local pal2 = Palette(idx)
                local nm = (pal2 and pal2.name) or AutoName(idx)
                EllesmereUI:ShowConfirmPopup({
                    title = "Delete Action Menu",
                    message = EllesmereUI.Lf("Delete %1$s and its contents? Entries "
                        .. "in other action menus that open it are removed "
                        .. "too, and the menus after it move up one place.", nm),
                    confirmText = "Delete",
                    cancelText = "Cancel",
                    onConfirm = function() DeletePalette(idx) end,
                })
            end)
            itm._editBtn:SetScript("OnClick", function()
                mmMenu:Hide()
                local pal2 = Palette(idx)
                local cur = (pal2 and pal2.name) or AutoName(idx)
                EllesmereUI:ShowInputPopup({
                    title = "Rename Action Menu",
                    message = EllesmereUI.Lf("Enter a new name for \"%1$s\":", cur),
                    placeholder = cur,
                    confirmText = "Rename",
                    cancelText = "Cancel",
                    onConfirm = function(newName)
                        local pal3 = Palette(idx)
                        if not pal3 then return end
                        newName = strtrim(newName or "")
                        -- The hub caption sits inside a small arc; longer
                        -- names run under the entries either side of it.
                        if #newName > 24 then newName = newName:sub(1, 24) end
                        if newName == "" then newName = AutoName(idx) end
                        if newName == pal3.name then return end
                        pal3.name = newName
                        RebuildPage()
                    end,
                })
            end)
            itm:Show()
            mH = mH + 26
        end
        for i = count + 1, #mmItems do mmItems[i]:Hide() end
        m:SetHeight(mH + 4)
    end

    -- The anchor button, rebuilt with every page build (the menu above is
    -- not): the Profiles page's Active Profile dropdown look, verbatim.
    local function BuildMenuSelector(rgn)
        local PPQ = EllesmereUI.PanelPP
        local btn = CreateFrame("Button", nil, rgn)
        -- 170x30, the exact face BuildDropdownControl gives every standard
        -- row dropdown, so this selector reads as one of them.
        PPQ.Size(btn, MM_W, 30)
        btn:SetFrameLevel(rgn:GetFrameLevel() + 3)
        PPQ.Point(btn, "RIGHT", rgn, "RIGHT", -20, 0)
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
        local brd = EllesmereUI.MakeBorder(btn, 1, 1, 1, EllesmereUI.DD_BRD_A, PPQ)
        local lbl = EllesmereUI.MakeFont(btn, 13, nil, 1, 1, 1)
        lbl:SetAlpha(EllesmereUI.DD_TXT_A)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(false)
        lbl:SetMaxLines(1)
        lbl:SetPoint("LEFT", btn, "LEFT", 12, 0)
        local arrow = EllesmereUI.MakeDropdownArrow(btn, 12, PPQ)
        lbl:SetPoint("RIGHT", arrow, "LEFT", -5, 0)
        local pal = Palette(editPalette)
        lbl:SetText((pal and pal.name) or AutoName(editPalette))
        local s = EllesmereUI.RD_DD_COLOURS
        btn:SetScript("OnEnter", function()
            lbl:SetTextColor(s[21], s[22], s[23], s[24])
            brd:SetColor(s[13], s[14], s[15], s[16])
            bg:SetColorTexture(s[5], s[6], s[7], s[8])
        end)
        btn:SetScript("OnLeave", function()
            lbl:SetTextColor(s[17], s[18], s[19], s[20])
            brd:SetColor(s[9], s[10], s[11], s[12])
            bg:SetColorTexture(s[1], s[2], s[3], s[4])
        end)
        if Cfg("enabled") ~= true then btn:SetAlpha(0.4) end
        btn:SetScript("OnClick", function()
            if Cfg("enabled") ~= true then return end
            local m = EnsureMenuMenu()
            if m:IsShown() and m._anchor == btn then m:Hide() return end
            m._anchor = btn
            m:ClearAllPoints()
            m:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
            RebuildMenuRows()
            m:Show()
        end)
        rgn._lastInline = btn
        return btn
    end

    -- The Action Bars "Toggle Action Bar" keybind button, on the row's right
    -- half: the button itself listens. Left-click arms it and the next key
    -- press binds; right-click unbinds; Escape cancels; hiding the page (the
    -- options window closes on entering combat) cancels too. Only the commit
    -- differs from Action Bars: this edits the real EUI_RADIAL<n> binding
    -- through CommitKey, theft dialog and all, not a saved key of our own.
    -- The palette index is baked at build time like every other row here --
    -- switching the edited menu rebuilds the page.
    -- spec is nil for the palette's own keybind, which is the button this was
    -- written for and still its default behaviour. The Select key passes one:
    --
    --   read()          the chord currently held, or nil
    --   commit(chord)   store it; nil unbinds
    --   plainMouse      allow a bare left-click to bind BUTTON1
    --
    -- plainMouse is the one real divergence, and it moves where the two
    -- gestures live rather than adding one. The palette's key refuses bare left
    -- and right clicks because they keep their widget meanings -- arm and
    -- unbind -- and the Blizzard bindings page refuses them for the same
    -- reason. A bare mouse button is precisely what a Select key is for, so
    -- there the meaning follows the STATE instead of the button:
    --
    --   resting     left arms the picker, right unbinds
    --   listening   any click is the chord, any key is the chord, Escape backs out
    --
    -- so BUTTON1 and BUTTON2 are both reachable and unbind is still one click.
    local function BuildKeybindButton(rgn, spec)
        local PPQ = EllesmereUI.PanelPP
        local kbBtn = CreateFrame("Button", nil, rgn)
        PPQ.Size(kbBtn, 126, 29)
        PPQ.Point(kbBtn, "RIGHT", rgn, "RIGHT", -20, 0)
        kbBtn:SetFrameLevel(rgn:GetFrameLevel() + 4)
        kbBtn:RegisterForClicks("AnyUp")
        local kbBg = EllesmereUI.SolidTex(kbBtn, "BACKGROUND", EllesmereUI.DD_BG_R,
            EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
        kbBg:SetAllPoints()
        kbBtn._border = EllesmereUI.MakeBorder(kbBtn, 1, 1, 1, EllesmereUI.DD_BRD_A, PPQ)
        local kbLbl = EllesmereUI.MakeFont(kbBtn, 12, nil, 1, 1, 1)
        kbLbl:SetAlpha(EllesmereUI.DD_TXT_A)
        kbLbl:SetPoint("CENTER")

        local palette = editPalette
        local action = BINDING_PREFIX .. palette
        local listening = false
        local ReadKey = spec and spec.read or function() return GetBindingKey(action) end
        local Commit = spec and spec.commit or function(chord) CommitKey(palette, chord) end
        local plainMouse = spec and spec.plainMouse
        -- What the key IS, shown above the how-to-bind instructions: the
        -- palette's own keybind row sits under a heading that already says,
        -- but a spec-driven picker (the Select Key) has only its label.
        local intro = spec and spec.intro
        -- BuildPage's own Disabled() is a local of that function and out of
        -- scope here, the same reason BuildMenuSelector reads Cfg directly.
        -- A spec may widen the gate (the Select Key: also disabled while the
        -- edited menu's Toggle Menu Open is off -- the key answers only
        -- latched menus) and name the requirement for the disabled tooltip.
        local Disabled = (spec and spec.disabled)
            or function() return Cfg("enabled") ~= true end
        local disabledReason = (spec and spec.disabledReason) or "the module"

        local function FormatKey(key)
            if not key then return EllesmereUI.L("Not Bound") end
            local parts = {}
            for mod in key:gmatch("(%u+)%-") do
                parts[#parts + 1] = mod:sub(1, 1) .. mod:sub(2):lower()
            end
            parts[#parts + 1] = key:match("[^%-]+$") or key
            return table.concat(parts, " + ")
        end

        -- Always AFTER the commit, never before it. Reading first and painting
        -- the old key was the same answer for the palette's keybind -- a
        -- CommitKey the user declines or combat refuses leaves the binding
        -- alone, and one that lands rebuilds the whole page over this button --
        -- but the Select key's commit only writes the profile, so a label
        -- painted before it stayed a whole interaction behind the value: the
        -- click that bound BUTTON1 still read "Not Bound", and the right-click
        -- that unbound it still read BUTTON1. Reading after is correct for
        -- both, because a refused commit leaves exactly what the pre-read was
        -- there to preserve.
        local function RefreshLabel()
            kbLbl:SetText(FormatKey(ReadKey()))
        end

        kbBtn:SetScript("OnClick", function(self, button)
            if Disabled() then return end
            -- Mouse chords. OnKeyDown never fires for mouse buttons, so an
            -- armed listener takes them from the click itself, through the
            -- same conversion the keyboard path uses (GetConvertedKeyOrButton
            -- maps "Button4" -> "BUTTON4" and so on). The extra buttons --
            -- middle, Button4 and up -- bind bare or modified; left and right
            -- bind only WITH a modifier held, since plain they keep their
            -- widget meanings (left arms, right unbinds) -- the same rule the
            -- Blizzard bindings page applies to mouse input. The wheel stays
            -- uncapturable on purpose: a tick cannot be HELD, and hold is the
            -- palette's whole input model -- key down opens, key up fires.
            -- plainMouse takes every bare click while LISTENING as a chord,
            -- left and right alike, which is what makes BUTTON1 and BUTTON2
            -- reachable at all. It costs nothing: unbind moves to a right-click
            -- from the resting state, which is where a user reaches for it
            -- anyway, and Escape still backs out of an armed picker. Without
            -- this the two most obvious Select keys are the two this widget
            -- cannot take.
            if listening and ((button ~= "LeftButton" and button ~= "RightButton")
                or IsModifierKeyDown()
                or plainMouse) then
                listening = false
                self:EnableKeyboard(false)
                Commit(CreateKeyChordStringUsingMetaKeyState(
                    GetConvertedKeyOrButton(button)))
                RefreshLabel()
                return
            end
            if button == "RightButton" then
                if listening then
                    listening = false
                    self:EnableKeyboard(false)
                end
                Commit(nil)
                RefreshLabel()
                return
            end
            -- The extra mouse buttons only mean something while listening.
            if button ~= "LeftButton" then return end
            if listening then return end
            if InCombatLockdown() then
                Complain("Quickdraw: keybinds can't be changed in combat.")
                return
            end
            listening = true
            kbLbl:SetText(EllesmereUI.L("Press a key..."))
            self:EnableKeyboard(true)
        end)

        kbBtn:SetScript("OnKeyDown", function(self, key)
            if not listening then self:SetPropagateKeyboardInput(true); return end
            key = GetConvertedKeyOrButton(key)
            -- Bare modifiers pass through so the user can hold them for the
            -- chord; everything the binding system ignores does too.
            if IsKeyPressIgnoredForBinding(key) then
                self:SetPropagateKeyboardInput(true); return
            end
            self:SetPropagateKeyboardInput(false)
            listening = false
            self:EnableKeyboard(false)
            if key ~= "ESCAPE" then
                Commit(CreateKeyChordStringUsingMetaKeyState(key))
            end
            RefreshLabel()
        end)

        kbBtn:SetScript("OnEnter", function(self)
            if Disabled() then
                EllesmereUI.ShowWidgetTooltip(self,
                    EllesmereUI.DisabledTooltip(disabledReason))
                return
            end
            kbBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G,
                EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_HA)
            if kbBtn._border and kbBtn._border.SetColor then
                kbBtn._border:SetColor(1, 1, 1, 0.3)
            end
            -- Right-click means two different things on a plainMouse picker
            -- depending on whether it is armed, so it has to say which.
            local tip = plainMouse
                and EllesmereUI.L("Left-click to set a keybind, then press any key or\n"
                    .. "click any mouse button to use it.\n"
                    .. "Escape cancels. Right-click here to unbind.")
                or EllesmereUI.L("Left-click to set a keybind.\nRight-click to unbind.")
            if intro then tip = EllesmereUI.L(intro) .. "\n\n" .. tip end
            EllesmereUI.ShowWidgetTooltip(self, tip)
        end)
        kbBtn:SetScript("OnLeave", function()
            if listening then return end
            kbBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G,
                EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
            if kbBtn._border and kbBtn._border.SetColor then
                kbBtn._border:SetColor(1, 1, 1, EllesmereUI.DD_BRD_A)
            end
            EllesmereUI.HideWidgetTooltip()
        end)
        kbBtn:SetScript("OnHide", function()
            -- Closing the window mid-capture must cancel the capture AND hide
            -- the tooltip: OnLeave skips the hide while listening and may not
            -- fire, so it would linger.
            if listening then
                listening = false
                kbBtn:EnableKeyboard(false)
                RefreshLabel()
            end
            EllesmereUI.HideWidgetTooltip()
        end)

        if Disabled() then kbBtn:SetAlpha(0.4) end
        RefreshLabel()
        rgn._lastInline = kbBtn
        return kbBtn
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

    -- Installed on the press and cleared on the release, so the block is idle
    -- whenever nothing is being dragged.
    local function PreviewDragUpdate()
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
            HidePreviewTooltip()
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
    end

    local function EndPreviewDrag()
        if dragFrom then
            local w = previewView:GetSlotWidget(dragFrom)
            w:SetAlpha(1)
            w:SetFrameLevel(previewView:GetFrame():GetFrameLevel() + 1)
        end
        dragFrom, dragging = nil, false
        if previewBlock then previewBlock:SetScript("OnUpdate", nil) end
        previewView:SetSelection(nil)
    end

    local function InstallPreviewScripts()
        for i = 1, (ns.MAX_SLOTS or 12) do
            local w = previewView:GetSlotWidget(i)
            w:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")

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
                HidePreviewTooltip()
            end)

            w:SetScript("OnClick", function(self, button)
                if button == "MiddleButton" then
                    if self.isPlaceholder then return end
                    local palette = Palette(editPalette)
                    if palette and ns.RemoveSlot(palette, self.index) then Refresh() end
                    return
                end
                if button == "RightButton" then
                    -- The picker in replace mode: the pick lands on THIS slot
                    -- (AssignEntry). Nothing to change on the "+" -- its
                    -- left-click already opens the append picker.
                    if self.isPlaceholder then return end
                    TogglePicker(self, self.index)
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
                previewBlock:SetScript("OnUpdate", PreviewDragUpdate)
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
            -- Opted out of the inline search (the RaidFrames overlays'
            -- _searchIgnore, same reason): the search re-anchors collected
            -- children with a single saved point against the WRAPPER it first
            -- saw them in. This block is cached across wrappers and anchored
            -- on BOTH sides with no explicit width, so that restore pins it
            -- to a dead wrapper and collapses it to zero width -- the preview
            -- then stays invisible on every cache-restore path (reopening
            -- after unlock mode, /eqd) until something rebuilds the page.
            previewBlock._searchIgnore = true

            local bg = previewBlock:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            previewBlock._bg = bg

            previewView = ns.CreatePaletteView(previewBlock, {
                interactive = true,
                geom        = PreviewGeom,
                -- Arrangement is what this preview is for; a live cooldown swipe
                -- on a settings page is only noise.
                showCooldowns = false,
                -- And so is a red icon reporting that the dummy you are not
                -- targeting is out of range of a spell you are only filing.
                showUsability = false,
            })
            previewView:GetFrame():SetPoint("CENTER", previewBlock, "CENTER", 0, 0)
            InstallPreviewScripts()

            -- The editor strip windows and scrolls exactly like play: the
            -- wheel walks the centre one entry per tick. A plain jump through
            -- SetFanCenter -- the preview is insecure, and the fold in
            -- ApplyFanGeometry does the rest. Direction matches the live
            -- wheel snippet, Invert Scroll included.
            previewBlock:EnableMouseWheel(true)
            previewBlock:SetScript("OnMouseWheel", function(_, delta)
                -- Shift is the strip's modifier: the block eats the wheel
                -- event either way, so a plain tick is handed to the panel's
                -- own scroll frame and the page keeps scrolling over the
                -- preview. Only Shift+Scroll walks the strip.
                if not IsShiftKeyDown() then
                    local sf = EllesmereUI._scrollFrame
                    local handler = sf and sf:GetScript("OnMouseWheel")
                    if handler then handler(sf, delta) end
                    return
                end
                if Cfg("enabled") ~= true then return end
                if not (previewView:IsFan() and not previewView:IsGrid()
                        and not previewView:IsHoverFan()) then return end
                local shown = previewView.shownCount or 0
                if shown < 2 then return end
                local step = (delta > 0) and -1 or 1
                if ACfg("fanInvert") == true then step = -step end
                previewView:SetFanCenter(
                    (((previewView.fanTarget or 1) - 1 + step) % shown) + 1)
            end)

            local hint = EllesmereUI.MakeFont(previewBlock, 12, nil, 0.5, 0.5, 0.5)
            hint:SetPoint("BOTTOM", previewBlock, "BOTTOM", 0, 7)
            hint:SetText(EllesmereUI.L("Shift+Scroll to see more"))
            previewBlock._scrollHint = hint

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
                    EllesmereUI.ShowWidgetTooltip(self, "Enable the module to edit action menus.")
                end
            end)
            dim:SetScript("OnLeave", function()
                if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
            end)
            previewBlock._dim = dim
        end

        previewBlock:SetParent(parent)
        -- The block reads as one row of its section's alternation: tick the
        -- same per-parent counter the widget rows use and take whatever shade
        -- this position lands on. A fixed shade only matches until the row
        -- count above changes -- which is not hypothetical, it is how the
        -- icon row's removal left this block the same color as its neighbor.
        local rc = EllesmereUI._rowCounters
        rc[parent] = (rc[parent] or 0) + 1
        previewBlock._bg:SetColorTexture(0, 0, 0,
            (rc[parent] % 2 == 0) and EllesmereUI.ROW_BG_EVEN
                or EllesmereUI.ROW_BG_ODD)
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
        previewBlock._dim:SetShown(Cfg("enabled") ~= true)
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

        -- Only when there is actually more to scroll to: a palette that fits
        -- inside the window entirely draws every entry already, and the hint
        -- would promise something the wheel cannot deliver.
        local pal = Palette(editPalette)
        previewBlock._scrollHint:SetShown((ACfg("layout") or "ARC") == "FAN"
            and (pal and #pal.slots or 0) > ((ACfg("fanVisible") or 2) * 2 + 1))

        return PREVIEW_H
    end

    ---------------------------------------------------------------------------
    --  Inline cog button beside a DualRow region, opening a BuildCogPopup.
    --  The same shape the other option pages use (EUI_AuraBuffReminders_
    --  Options.lua:588): parked left of the region's control, dim until
    --  hovered, and handing itself to showFn as the popup's anchor.
    ---------------------------------------------------------------------------
    local function MakeCogBtn(rgn, showFn, anchorTo, iconPath)
        local cogBtn = CreateFrame("Button", nil, rgn)
        cogBtn:SetSize(26, 26)
        cogBtn:SetPoint("RIGHT", anchorTo or rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = cogBtn
        cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
        cogBtn:SetAlpha(0.4)
        local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
        cogTex:SetAllPoints()
        cogTex:SetTexture(iconPath or EllesmereUI.COGS_ICON)
        cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
        cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
        cogBtn:SetScript("OnClick", function(self) showFn(self) end)
        return cogBtn
    end

    ---------------------------------------------------------------------------
    --  "Apply All Settings From" -- bulk copy between action menus, the Unit
    --  Frames main-frames row re-cut for menus.
    ---------------------------------------------------------------------------
    -- Every appearance key's EFFECTIVE value on the source menu (its own
    -- override, or the shared fallback under it) is written onto the target
    -- as an explicit override, tables deep-copied, so the target draws
    -- exactly what the source draws right now. A menu's actions, name, icon
    -- and keybind are not settings and are never touched.
    local function CopyAllMenuSettings(srcIdx, dstIdx)
        local src = ns.PaletteProfile and ns.PaletteProfile(srcIdx)
        local dst = Palette(dstIdx)
        local keys = ns.APPEARANCE_KEYS
        if not src or not dst or not keys then return end
        dst.appearance = dst.appearance or {}
        for key in pairs(keys) do
            local v = src[key]
            if type(v) == "table" then
                v = EllesmereUI.Lite.DeepCopy(v)
            end
            dst.appearance[key] = v
        end
        Refresh()
        EllesmereUI:RefreshPage(true)
    end

    -- Centered label + action dropdown below the preview: lists the other
    -- menus and copies FROM the chosen one onto the edited menu after a
    -- confirm popup. getValue always returns the placeholder so the dropdown
    -- stores nothing; the registered widget refresh snaps the label back
    -- after each pick.
    local function BuildApplyAllRow(parent, y)
        local PPQ = EllesmereUI.PanelPP
        local curIdx = editPalette
        local function NameOf(index)
            local pal = Palette(index)
            return (pal and pal.name) or AutoName(index)
        end
        local ddValues = { [""] = "Choose Menu..." }
        local ddOrder = {}
        for i = 1, PaletteCount() do
            if i ~= curIdx then
                ddValues[i] = NameOf(i)
                ddOrder[#ddOrder + 1] = i
            end
        end

        local ROW_H = 50
        local contentPad = EllesmereUI.CONTENT_PAD or 45
        local rowFrame = CreateFrame("Frame", nil, parent)
        PPQ.Size(rowFrame, parent:GetWidth() - contentPad * 2, ROW_H)
        PPQ.Point(rowFrame, "TOPLEFT", parent, "TOPLEFT", contentPad, y)

        local label = EllesmereUI.MakeFont(rowFrame, 14, nil, 1, 1, 1)
        label:SetText(EllesmereUI.L("Apply All Settings From"))
        label:SetTextColor(1, 1, 1, 0.6)

        local DD_W, GAP = 180, 12
        local ddBtn = EllesmereUI.BuildDropdownControl(
            rowFrame, DD_W, rowFrame:GetFrameLevel() + 2,
            ddValues, ddOrder,
            function() return "" end,
            function(srcIdx)
                if srcIdx == "" then return end
                EllesmereUI:ShowConfirmPopup({
                    title   = "Apply All Settings",
                    message = EllesmereUI.Lf("Copy all settings from %1$s to %2$s?",
                        NameOf(srcIdx), NameOf(curIdx)),
                    disclaimer = "This overwrites this action menu's current settings. Its actions, name, and keybind are not changed.",
                    confirmText = "Apply",
                    cancelText  = "Cancel",
                    onConfirm = function() CopyAllMenuSettings(srcIdx, curIdx) end,
                })
            end)
        ddBtn._ttText = "Copy every setting from another action menu to this one."
        EllesmereUI.RegisterWidgetRefresh(function() ddBtn._refreshLabel() end)

        -- Center the label + dropdown pair as one line
        local totalW = label:GetStringWidth() + GAP + DD_W
        label:SetPoint("LEFT", rowFrame, "CENTER", -totalW / 2, 0)
        ddBtn:SetPoint("LEFT", label, "RIGHT", GAP, 0)

        return ROW_H
    end

    ---------------------------------------------------------------------------
    --  Build Page
    ---------------------------------------------------------------------------
    local function BuildPage(pageName, parent, yOffset)
        EnsureBindWatcher()

        local W = EllesmereUI.Widgets
        local y = yOffset
        local row, h

        if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end
        parent._showRowDivider = true

        -- Not `== false`: the master switch is opt-in, so an absent key counts
        -- as off. The appearance sub-settings below stay nil-means-on.
        local function Disabled() return Cfg("enabled") ~= true end

        -- What this build assumed about nest presence; Refresh compares
        -- against it and escalates to a rebuild when it flips.
        builtWithNest = HasAnyNest()

        -- Which palette is being edited is panel-session state, but the profile
        -- under it can change without one: switching to a profile that holds
        -- fewer palettes repoints the data with no reload, and the module reset
        -- leaves a single palette behind. Clamped here rather than at each
        -- reader because Palette, ACfg and ASet all go through
        -- ns.EnsurePalette, which would CREATE the out-of-range palette and
        -- bank that junk in the profile the user has just moved to.
        local paletteCount = PaletteCount()
        if editPalette > paletteCount then editPalette = paletteCount end

        local centerValues = { CURSOR = "Cursor", SCREEN = "Fixed Position" }
        local centerOrder  = { "CURSOR", "SCREEN" }

        local layoutValues = { ARC = "Arc", FAN = "Fan", GRID = "Grid" }
        local layoutOrder  = { "ARC", "FAN", "GRID" }

        local orientValues = { HORIZONTAL = "Horizontal", VERTICAL = "Vertical" }
        local orientOrder  = { "HORIZONTAL", "VERTICAL" }


        -----------------------------------------------------------------------
        --  GENERAL
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "GENERAL", y); y = y - h

        local addPaletteBtn
        row, h = W:DualRow(parent, y,
            { type="toggle", text="Enable Quickdraw",
              getValue=function() return Cfg("enabled") == true end,
              setValue=function(v) Set("enabled", v); RebuildPage() end },
            -- The chooser it opens offers an empty palette or a preset. The new
            -- palette takes a key of its own from the keybind row in PALETTE
            -- SETUP, whatever its number.
            { type="labeledButton", text="Add Action Menu",
              disabled=function()
                  return Disabled() or PaletteCount() >= MAX_PALETTES
              end,
              disabledTooltip=function()
                  if PaletteCount() >= MAX_PALETTES then
                      return "This profile already holds " .. MAX_PALETTES
                          .. " action menus"
                  end
                  return "This option requires the module to be enabled"
              end,
              rawTooltip=true,
              buttonText="Empty or Preset...",
              -- An upvalue filled in below, not an onClick parameter: the
              -- styled button invokes its handler with no arguments
              -- (EllesmereUI_Widgets.lua:399), so the chooser has to reach the
              -- frame it anchors under some other way.
              onClick=function() ShowAddPaletteMenu(addPaletteBtn) end })
        addPaletteBtn = row._rightRegion and row._rightRegion._control
        y = y - h

        -----------------------------------------------------------------------
        --  ACTION MENU SETUP
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "ACTION MENU SETUP", y); y = y - h

        row, h = W:DualRow(parent, y,
            -- Two label halves: the selector and the keybind button are both
            -- bespoke controls attached below. The selector is the custom
            -- Profiles-style dropdown whose rows carry the inline rename and
            -- delete buttons (panel-session state, never captured); the
            -- keybind button is the Action Bars one, which does its own
            -- listening and edits the real EUI_RADIAL<n> binding.
            { type="label", text="Editing Action Menu" },
            { type="label", text="Action Menu Keybind" })
        BuildMenuSelector(row._leftRegion)
        BuildKeybindButton(row._rightRegion)
        y = y - h

        -- The Select Key, then the switch that needs it: the key is the
        -- PREREQUISITE (a latched menu nothing can answer would be a trap), so
        -- it binds first and is never gated, and Toggle Menu Open stays
        -- disabled until a key exists. Together on one row because neither
        -- does anything without the other.
        --
        -- The key is one for the profile (Set) and the switch is per menu
        -- (ASet): the gesture that picks an entry should mean the same thing
        -- whichever menu is up.
        local function HasSelectKey()
            local key = Cfg("confirmKey")
            return type(key) == "string" and key ~= ""
        end
        row, h = W:DualRow(parent, y,
            -- A label half, like the keybind row above: the control underneath
            -- is the same bespoke listening button, attached after the row.
            { type="label", text="Toggled Menu Select Action" },
            { type="toggle", text="Toggle Menu Open", noCapture=true,
              disabled=function() return Disabled() or not HasSelectKey() end,
              disabledTooltip="a Toggled Menu Select Action keybind",
              tooltip="Keep this menu open when you let go of its keybind.\n"
                  .. "Point at an entry and press the Select Action key to use it.\n"
                  .. "Press the menu's own keybind again, or Escape, to close it.",
              getValue=function() return ACfg("toggleMode") == true end,
              setValue=function(v) ASet("toggleMode", v); Refresh() end })
        BuildKeybindButton(row._leftRegion, {
            intro = "Uses the entry you are pointing at while a menu is kept "
                .. "open with Toggle Menu Open. One key shared by every menu, "
                .. "claimed only while a menu is up -- a mouse button keeps "
                .. "its normal use the rest of the time.",
            read = function()
                local key = Cfg("confirmKey")
                if type(key) ~= "string" or key == "" then return nil end
                return key
            end,
            -- "" rather than nil for an unbind: the profile default is a string,
            -- and a nil would simply be re-merged from the defaults table.
            -- RefreshPage as well as Refresh: Toggle Menu Open beside this
            -- takes its disabled state from whether a key is bound.
            commit = function(chord)
                Set("confirmKey", chord or "")
                Refresh()
                EllesmereUI:RefreshPage()
            end,
            -- A bare mouse button is the point of this one. See BuildKeybindButton.
            plainMouse = true,
        })
        y = y - h

        -- Its opposite, and on a row of its own: nothing else belongs beside a
        -- cancel key. Escape already backs out of any menu and stays that way;
        -- this is a second key for the hand that is holding the menu open and
        -- is nowhere near Escape, which is the whole of the request behind it.
        -- Shown only once the Select key exists: cancelling is a gesture of
        -- the kept-open flow that key unlocks, so before it the row is noise.
        -- The Select commit above already RefreshPage()s on bind/unbind, which
        -- is what brings this row in and out. A cancelKey bound earlier stays
        -- stored while hidden and returns with the row.
        if HasSelectKey() then
            row, h = W:DualRow(parent, y,
                { type="label", text="Menu Cancel Action" }, { type="label", text="" })
            BuildKeybindButton(row._leftRegion, {
                intro = "Closes an open menu without using anything. Escape always "
                    .. "does this as well. One key shared by every menu, claimed "
                    .. "only while a menu is up -- a mouse button keeps its normal "
                    .. "use the rest of the time.",
                read = function()
                    local key = Cfg("cancelKey")
                    if type(key) ~= "string" or key == "" then return nil end
                    return key
                end,
                commit = function(chord)
                    -- A menu's own key would be taken over for as long as that menu
                    -- was up, which is exactly the moment its release has to reach
                    -- the menu -- so the menu could be opened and never closed. The
                    -- Select key is refused for the reason the module gives at the
                    -- binding itself: one chord, two meanings, and the wrong one
                    -- wins.
                    if chord then
                        if chord == Cfg("confirmKey") then
                            Complain("Quickdraw: that key is already the Toggled Menu Select Action.")
                            return
                        end
                        for i = 1, (Cfg("paletteCount") or 1) do
                            if GetBindingKey(BINDING_PREFIX .. i) == chord then
                                Complain("Quickdraw: that key opens a menu, so it cannot also close one.")
                                return
                            end
                        end
                    end
                    Set("cancelKey", chord or "")
                    Refresh()
                end,
                -- The same reason as the Select key: a bare mouse button is what
                -- this is for.
                plainMouse = true,
            })
            y = y - h
        end

        y = y - BuildPreview(parent, y)

        -- Hidden with a single menu: nothing to copy from.
        if paletteCount > 1 then
            y = y - BuildApplyAllRow(parent, y)
        end

        -----------------------------------------------------------------------
        --  LAYOUT
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "LAYOUT", y); y = y - h

        -- The page keeps the two decisions every palette needs -- which
        -- layout it draws as and where it opens -- and the two sizes everyone
        -- reaches for. Every layout carries its primary dials on a page row
        -- of its own below: the arc's radius and span (rotation riding the
        -- span's cog), the fan's direction and window (the strip's settings
        -- riding the direction's cog), and the grid's column pair. Only the
        -- grid still builds a cog on the Layout dropdown, for the one row
        -- left over (spacing); its nest style rides Nest Distance's cog
        -- below. The Layout popup can never be open when
        -- the layout changes under it -- the dropdown click that changes it
        -- is a click outside the popup, which closes it -- so its rows cannot
        -- go stale.
        local layoutMode = ACfg("layout") or "ARC"

        local layoutCogShow
        local layoutCogTitle, layoutCogRows
        if layoutMode == "GRID" then
            layoutCogTitle = "Grid Settings"
            layoutCogRows = {
                { type="slider", label="Spacing", noCapture=true,
                  min=0, max=40, step=1,
                  disabled=Disabled, disabledTooltip="the module",
                  get=function() return ACfg("fanGap") or 10 end,
                  set=function(v) ASet("fanGap", v); Refresh() end },
            }
        end

        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Layout", noCapture=true,
              disabled=Disabled, disabledTooltip="the module",
              values=layoutValues, order=layoutOrder,
              getValue=function() return ACfg("layout") or "ARC" end,
              -- Rebuild, not Refresh: the cog beside this dropdown is loaded
              -- with the rows of the layout picked here.
              setValue=function(v) ASet("layout", v); RebuildPage() end },
            { type="dropdown", text="Open At", noCapture=true,
              disabled=Disabled, disabledTooltip="the module",
              values=centerValues, order=centerOrder,
              getValue=function() return ACfg("centerMode") or "CURSOR" end,
              setValue=function(v) ASet("centerMode", v); Refresh() end })
        do
            -- No captureRegion: every row in the popup is per-menu
            -- (noCapture), so there is nothing for Spec Overrides to bank.
            -- Only the GRID builds a layout cog.
            if layoutCogRows then
                layoutCogShow = select(2, EllesmereUI.BuildCogPopup({
                    title = layoutCogTitle,
                    rows = layoutCogRows,
                }))
                MakeCogBtn(row._leftRegion, layoutCogShow)
            end

            -- The X/Y offsets are the ONLY way to place the palette: the
            -- on-screen drag editor is gone, and this module is not yet
            -- registered with Unlock Mode. In cursor mode the palette opens
            -- wherever the mouse is, so both rows sit dead until Fixed
            -- Position is picked. No captureRegion: both rows are stored per
            -- palette, so neither may bank a per-spec override.
            local fixedOnly = function()
                return Disabled() or (ACfg("centerMode") or "CURSOR") ~= "SCREEN"
            end
            local _, posCogShow = EllesmereUI.BuildCogPopup({
                title = "Fixed Position",
                rows = {
                    { type="slider", label="X Offset", noCapture=true,
                      min=-800, max=800, step=1,
                      disabled=fixedOnly, disabledTooltip="Fixed Position mode",
                      get=function() return ACfg("posX") or 0 end,
                      set=function(v) ASet("posX", v); Refresh() end },
                    { type="slider", label="Y Offset", noCapture=true,
                      min=-600, max=600, step=1,
                      disabled=fixedOnly, disabledTooltip="Fixed Position mode",
                      get=function() return ACfg("posY") or 0 end,
                      set=function(v) ASet("posY", v); Refresh() end },
                },
            })
            local posCogBtn = MakeCogBtn(row._rightRegion, posCogShow)

            -- The offsets are dead ground in cursor mode, so the cog that
            -- opens them disables with them: the blocking-overlay pattern
            -- (clicks eaten, disabled tooltip) rather than a hidden button,
            -- so the row still says the settings exist.
            local posCogBlock = CreateFrame("Frame", nil, posCogBtn)
            posCogBlock:SetAllPoints()
            posCogBlock:SetFrameLevel(posCogBtn:GetFrameLevel() + 10)
            posCogBlock:EnableMouse(true)
            posCogBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(posCogBtn, EllesmereUI.DisabledTooltip(
                    Disabled() and "the module" or "Fixed Position mode"))
            end)
            posCogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdatePosCogDisabled()
                if fixedOnly() then
                    posCogBtn:SetAlpha(0.15); posCogBlock:Show()
                else
                    posCogBtn:SetAlpha(0.4); posCogBlock:Hide()
                end
            end
            UpdatePosCogDisabled()
            EllesmereUI.RegisterWidgetRefresh(UpdatePosCogDisabled)
        end
        y = y - h

        -----------------------------------------------------------------------
        --  Grid dials -- on the page only while the edited menu draws as a
        --  GRID, the same swap the arc and fan rows below make. Both are
        --  per-menu (noCapture); the cog on Layout keeps the rest of the
        --  grid's rows.
        -----------------------------------------------------------------------
        if layoutMode == "GRID" then
            row, h = W:DualRow(parent, y,
                { type="toggle", text="Auto Columns", noCapture=true,
                  disabled=Disabled, disabledTooltip="the module",
                  getValue=function() return ACfg("gridAutoColumns") ~= false end,
                  setValue=function(v) ASet("gridAutoColumns", v); Refresh() end },
                { type="slider", text="Grid Columns", noCapture=true,
                  -- The top of the travel is the slot cap, not an arbitrary
                  -- 8. A grid never draws more columns than it has entries,
                  -- so asking for the most a palette can ever hold is how you
                  -- say "one row", and it stays one row as entries are added.
                  -- Column 1 is already the transpose of that, so both
                  -- single-file layouts are on the one slider and neither
                  -- needs a sentinel value.
                  min=1, max=MAX_SLOTS, step=1,
                  disabled=function()
                      return Disabled() or ACfg("gridAutoColumns") ~= false
                  end,
                  requireState="disabled", disabledTooltip="Auto Columns",
                  tooltip=EllesmereUI.Lf("How many entries a row of the grid holds. 1 stacks "
                      .."them into a single column; %1$s -- the most slots an "
                      .."action menu can hold -- lays them out in a single row.", MAX_SLOTS),
                  getValue=function() return ACfg("gridColumns") or 4 end,
                  setValue=function(v) ASet("gridColumns", v); Refresh() end })
            y = y - h
        end

        -----------------------------------------------------------------------
        --  Arc dials -- on the page only while the edited menu draws as an
        --  ARC (the Layout dropdown rebuilds the page, so this row swaps
        --  with it). Both dials are per-menu; Rotation rides Span's cog
        --  because a full-circle span has nowhere to point.
        -----------------------------------------------------------------------
        if layoutMode == "ARC" then
            local arcRow
            arcRow, h = W:DualRow(parent, y,
                { type="slider", text="Distance from Center", noCapture=true,
                  min=50, max=220, step=1,
                  disabled=Disabled, disabledTooltip="the module",
                  getValue=function() return ACfg("radius") or 100 end,
                  setValue=function(v) ASet("radius", v); Refresh() end },
                { type="slider", text="Arc Span", noCapture=true,
                  min=30, max=360, step=5,
                  disabled=Disabled, disabledTooltip="the module",
                  getValue=function() return ACfg("arcSpan") or 360 end,
                  setValue=function(v) ASet("arcSpan", v); Refresh() end })
            do
                local _, rotCogShow = EllesmereUI.BuildCogPopup({
                    title = "Arc Rotation",
                    rows = {
                        -- 360 is a full turn, and rotating a full circle is
                        -- a no-op -- the row only comes live once the span
                        -- has been narrowed to an arc that has somewhere to
                        -- point. Span edits close this popup (a page click
                        -- is a click outside it), so the predicate is fresh
                        -- on every open.
                        { type="slider", label="Arc Rotation", noCapture=true,
                          min=-180, max=180, step=5,
                          disabled=function()
                              return Disabled() or (ACfg("arcSpan") or 360) >= 360
                          end,
                          disabledTooltip="an Arc Span below 360",
                          get=function() return ACfg("arcRotation") or 0 end,
                          set=function(v) ASet("arcRotation", v); Refresh() end },
                    },
                })
                MakeCogBtn(arcRow._rightRegion, rotCogShow)
            end
            y = y - h
        end

        -----------------------------------------------------------------------
        --  Fan dials -- on the page only while the edited menu draws as a
        --  FAN, the same swap the arc row above makes. Both page values are
        --  per-menu appearance, so both carry noCapture; the cog on Fan
        --  Direction holds the rest of the strip's settings.
        -----------------------------------------------------------------------
        if layoutMode == "FAN" then
            local fanRow
            fanRow, h = W:DualRow(parent, y,
                { type="dropdown", text="Fan Direction", noCapture=true,
                  disabled=Disabled, disabledTooltip="the module",
                  values=orientValues, order=orientOrder,
                  getValue=function() return ACfg("fanOrientation") or "HORIZONTAL" end,
                  setValue=function(v) ASet("fanOrientation", v); Refresh() end },
                -- How much of the strip is drawn at all. Neighbours past this
                -- many steps are hidden rather than shrunk further.
                { type="slider", text="Visible Icons", noCapture=true,
                  -- The whole strip, as the user sees it: an odd count, the
                  -- centre plus the same number each side. Stored as the
                  -- each-side WINDOW -- (total - 1) / 2 -- which is the
                  -- number every window, hover and snippet test runs on.
                  min=1, max=9, step=2,
                  disabled=Disabled, disabledTooltip="the module",
                  getValue=function() return ((ACfg("fanVisible") or 2) * 2) + 1 end,
                  setValue=function(v) ASet("fanVisible", (v - 1) * 0.5); Refresh() end })
            do
                -- No captureRegion: every row here is per-menu (noCapture),
                -- so there is nothing for Spec Overrides to bank.
                local _, fanCogShow = EllesmereUI.BuildCogPopup({
                    title = "Fan Settings",
                    rows = {
                        -- The strip's hover channel: the entry under the
                        -- pointer is the one a release fires, and pointing at
                        -- none of them selects nothing. The wheel scrolls the
                        -- strip either way.
                        { type="toggle", label="Select Action with Mouse", noCapture=true,
                          disabled=Disabled, disabledTooltip="the module",
                          get=function() return ACfg("fanMouseSelect") ~= false end,
                          set=function(v) ASet("fanMouseSelect", v); Refresh() end },
                        { type="slider", label="Spacing", noCapture=true,
                          min=0, max=40, step=1,
                          disabled=Disabled, disabledTooltip="the module",
                          get=function() return ACfg("fanGap") or 10 end,
                          set=function(v) ASet("fanGap", v); Refresh() end },
                        { type="toggle", label="Invert Scroll", noCapture=true,
                          disabled=Disabled, disabledTooltip="the module",
                          get=function() return ACfg("fanInvert") == true end,
                          set=function(v) ASet("fanInvert", v); Refresh() end },
                    },
                })
                MakeCogBtn(fanRow._leftRegion, fanCogShow)
            end
            y = y - h
        end

        -----------------------------------------------------------------------
        --  Nest geometry -- on the page only while some menu actually nests
        --  another (Refresh escalates to a rebuild when that flips). Both
        --  sliders are per-menu. The cog on Nest Distance is the edited
        --  menu's layout's: the arc's shape pair, or the grid's nest style.
        --  A fan nest has neither, so there it builds no cog at all -- the
        --  layout swap rebuilds the page, same as the dial rows above.
        -----------------------------------------------------------------------
        if builtWithNest then
            local nestRow
            nestRow, h = W:DualRow(parent, y,
                { type="slider", text="Nest Distance", noCapture=true,
                  disabled=Disabled, disabledTooltip="the module",
                  tooltip="The gap between a nested menu's icons and the entry "
                      .."that opens it.",
                  min=0, max=160, step=1,
                  getValue=function() return ACfg("nestBand") or 40 end,
                  setValue=function(v) ASet("nestBand", v); Refresh() end },
                { type="slider", text="Nest Icon Size", noCapture=true,
                  disabled=Disabled, disabledTooltip="the module",
                  min=0.4, max=1.0, step=0.05,
                  getValue=function() return ACfg("nestScale") or 0.8 end,
                  setValue=function(v) ASet("nestScale", v); Refresh() end })
            if layoutMode == "ARC" then
                local _, nestCogShow = EllesmereUI.BuildCogPopup({
                    title = "Arc Nest Shape",
                    rows = {
                        { type="dropdown", label="Nest Width", noCapture=true,
                          disabled=Disabled, disabledTooltip="the module",
                          tooltip="How far along the arc a nest may spread its entries."
                              .." Contained keeps it clear of the next nest either side,"
                              .." so two of them are never drawn on top of one another."
                              .." Overflowing lets it use the whole of Max Nest Span."
                              .." A nest reaches over the plain entries it passes, and"
                              .." they only give up their angles while it is open.",
                          values={ NONE = "Contained", MIDPOINT = "Overflowing" },
                          order={ "NONE", "MIDPOINT" },
                          get=function() return ACfg("arcChildOverflow") or "NONE" end,
                          set=function(v) ASet("arcChildOverflow", v); Refresh() end },
                        { type="slider", label="Max Nest Span", noCapture=true,
                          min=30, max=180, step=5,
                          disabled=Disabled, disabledTooltip="the module",
                          tooltip="The widest angle a nest's entries may spread over."
                              .." They stay on one ring for as long as they fit inside"
                              .." it; the rest go onto a second ring further out.",
                          get=function() return ACfg("arcChildMaxSpan") or 90 end,
                          set=function(v) ASet("arcChildMaxSpan", v); Refresh() end },
                    },
                })
                MakeCogBtn(nestRow._leftRegion, nestCogShow)
            elseif layoutMode == "GRID" then
                local _, nestCogShow = EllesmereUI.BuildCogPopup({
                    title = "Grid Nest Style",
                    rows = {
                        --   Lane     a halo hugging the block, centered on the
                        --            point of it nearest the entry that opens
                        --            it, wrapping the corners when the run is
                        --            long
                        --   Halo     the eight positions around the entry
                        --            itself, the block faded behind them
                        -- A stored value from the retired Popout style reads
                        -- as Lane, here and in the module both.
                        { type="dropdown", label="Grid Nest Style", noCapture=true,
                          disabled=Disabled, disabledTooltip="the module",
                          values={ PERIMETER = "Lane", HALO = "Halo" },
                          order={ "PERIMETER", "HALO" },
                          get=function()
                              local v = ACfg("gridNestStyle")
                              return (v == "HALO") and "HALO" or "PERIMETER"
                          end,
                          set=function(v) ASet("gridNestStyle", v); Refresh() end },
                    },
                })
                MakeCogBtn(nestRow._leftRegion, nestCogShow)
            end
            y = y - h
        end

        row, h = W:DualRow(parent, y,
            { type="slider", text="Icon Size", noCapture=true,
              disabled=Disabled, disabledTooltip="the module",
              min=24, max=72, step=1,
              getValue=function() return ACfg("iconSize") or 40 end,
              setValue=function(v) ASet("iconSize", v); Refresh() end },
            { type="slider", text="Scale", noCapture=true,
              disabled=Disabled, disabledTooltip="the module",
              min=0.5, max=2.0, step=0.01,
              getValue=function() return ACfg("scale") or 1.0 end,
              setValue=function(v) ASet("scale", v); Refresh() end })
        y = y - h

        -----------------------------------------------------------------------
        --  APPEARANCE
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "APPEARANCE", y); y = y - h

        row, h = W:DualRow(parent, y,
            { type="toggle", text="Show Cooldowns", noCapture=true,
              disabled=Disabled, disabledTooltip="the module",
              getValue=function() return ACfg("showCooldowns") ~= false end,
              setValue=function(v) ASet("showCooldowns", v); Refresh() end },
            { type="toggle", text="Dim Unusable Entries", noCapture=true,
              disabled=Disabled, disabledTooltip="the module",
              tooltip="Tint an entry that would do nothing right now: red when the "
                      .."target is out of range, blue when you are short of the "
                      .."resource, and gray when the game refuses it for any other "
                      .."reason. Spells and items only -- the game reports every "
                      .."toy as unusable, and a macro's usability depends on what "
                      .."its body resolves to.",
              getValue=function() return ACfg("showUsability") ~= false end,
              setValue=function(v) ASet("showUsability", v); Refresh() end })
        y = y - h

        -- Selection Color is the accent|custom|class swatch trio -- the
        -- standard dual-swatch treatment (AttachLookSwatches in
        -- EUI_BlizzardSkin_Options.lua) grown by one: accent by default and
        -- resolved live, the custom swatch storing its own color, the class
        -- swatch reading the player's class live. Exactly one of the three
        -- is lit, and class outranks custom -- the module's SelectColor
        -- resolves the stored pair the same way.
        -- A label half, not a colorpicker: the custom swatch IS the picker.
        row, h = W:DualRow(parent, y,
            { type="label", text="Selection Color" },
            { type="toggle", text="Show Action Text Label", noCapture=true,
              disabled=Disabled, disabledTooltip="the module",
              tooltip="Show the selected action's name next to the selected icon.",
              getValue=function() return ACfg("showActionText") == true end,
              setValue=function(v) ASet("showActionText", v); Refresh() end })
        do
            local rgn = row._leftRegion
            local PPQ = EllesmereUI.PanelPP
            -- Per-menu values: the swatches' own BuildColorSwatch capture
            -- self-registration is suppressed, the same reason every ASet
            -- row carries noCapture -- there is nothing for Spec Overrides
            -- to bank.
            rgn._noCapture = true

            local customSwatch, updateCustom = EllesmereUI.BuildColorSwatch(
                rgn, row:GetFrameLevel() + 3,
                function()
                    local c = ACfg("selectColor") or {}
                    return c[1] or 0.047, c[2] or 0.824, c[3] or 0.624
                end,
                function(r2, g2, b2)
                    ASet("selectColor", { r2, g2, b2 })
                    ASet("selectColorCustom", true)
                    ASet("useClassColor", false)
                    Refresh()
                end,
                false, 20)
            PPQ.Point(customSwatch, "RIGHT", rgn, "RIGHT", -20, 0)
            local origClick = customSwatch:GetScript("OnClick")
            customSwatch:SetScript("OnClick", function(self2, ...)
                if Disabled() then return end
                if ACfg("selectColorCustom") ~= true or ACfg("useClassColor") == true then
                    -- First click only chooses the mode; the second opens the
                    -- picker, exactly like the window-skin pairs.
                    ASet("selectColorCustom", true)
                    ASet("useClassColor", false)
                    Refresh()
                    return
                end
                if origClick then origClick(self2, ...) end
            end)
            customSwatch:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(customSwatch, "Custom Color")
            end)
            customSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            local accentSwatch, updateAccent = EllesmereUI.BuildColorSwatch(
                rgn, row:GetFrameLevel() + 3,
                function() return EllesmereUI.ResolveActiveAccent() end,
                function()
                    ASet("selectColorCustom", false)
                    ASet("useClassColor", false)
                    Refresh()
                end,
                false, 20)
            PPQ.Point(accentSwatch, "RIGHT", customSwatch, "LEFT", -8, 0)
            accentSwatch:SetScript("OnClick", function()
                if Disabled() then return end
                ASet("selectColorCustom", false)
                ASet("useClassColor", false)
                Refresh()
            end)
            accentSwatch:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(accentSwatch, "Accent Color")
            end)
            accentSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            -- The Class Color swatch: the player's own class color, resolved
            -- live like the accent. Its click chooses the mode; there is no
            -- picker behind it, the class decides the color.
            local classSwatch, updateClass = EllesmereUI.BuildColorSwatch(
                rgn, row:GetFrameLevel() + 3,
                function()
                    local c = RAID_CLASS_COLORS
                        and RAID_CLASS_COLORS[select(2, UnitClass("player"))]
                    if c then return c.r, c.g, c.b end
                    return 1, 1, 1
                end,
                function()
                    ASet("useClassColor", true)
                    Refresh()
                end,
                false, 20)
            PPQ.Point(classSwatch, "RIGHT", accentSwatch, "LEFT", -8, 0)
            classSwatch:SetScript("OnClick", function()
                if Disabled() then return end
                ASet("useClassColor", true)
                Refresh()
            end)
            classSwatch:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(classSwatch, "Class Color")
            end)
            classSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            rgn._lastInline = classSwatch

            local function refreshSwatches()
                updateCustom(); updateAccent(); updateClass()
                if Disabled() then
                    customSwatch:SetAlpha(0.3)
                    accentSwatch:SetAlpha(0.3)
                    classSwatch:SetAlpha(0.3)
                else
                    -- Exactly one of the three lit: class outranks custom,
                    -- matching the module's SelectColor resolution.
                    local class = ACfg("useClassColor") == true
                    local custom = not class and ACfg("selectColorCustom") == true
                    classSwatch:SetAlpha(class and 1 or 0.3)
                    customSwatch:SetAlpha(custom and 1 or 0.3)
                    accentSwatch:SetAlpha((class or custom) and 0.3 or 1)
                end
            end
            EllesmereUI.RegisterWidgetRefresh(refreshSwatches)
            refreshSwatches()

        end
        -- No Selection Effects cog: the zoom and both falloffs are hardcoded
        -- off in the module (FalloffRatios / SelectedZoom), pending the
        -- user's own animation pass.
        y = y - h

        local wmRow
        wmRow, h = W:DualRow(parent, y,
            { type="toggle", text="Hide Unusable Entries", noCapture=true,
              disabled=Disabled, disabledTooltip="the module",
              tooltip="Hide entries this character cannot use: another class's "
                      .."specializations and spells, and macros this character "
                      .."does not have. One shared menu then fits every "
                      .."character. The menu editor always shows every entry.",
              getValue=function() return ACfg("hideUnusable") ~= false end,
              setValue=function(v) ASet("hideUnusable", v); Refresh() end },
            -- Beside the filter rather than in ACTION MENU SETUP: both of
            -- these change what an entry does once the menu is drawn, and both
            -- are per menu. It also keeps this the last row of the section
            -- with no half of it empty.
            { type="toggle", text="Toggle World Markers", noCapture=true,
              disabled=Disabled, disabledTooltip="the module",
              tooltip="Use a world marker entry again to pick that marker "
                      .."back up. Off places the marker again, at the new "
                      .."position.\n"
                      .."This does not change the entry that clears all world "
                      .."markers, or the cycling entry.",
              getValue=function() return ACfg("worldMarkerToggle") ~= false end,
              setValue=function(v) ASet("worldMarkerToggle", v); Refresh() end })
        y = y - h

        -- Inline cog on Toggle World Markers: the placed-marker pip opt-out.
        if not EllesmereUI._prebuilding then
            local rgn = wmRow._rightRegion
            local _, wmCogShow = EllesmereUI.BuildCogPopup({
                title = "World Marker Entries",
                rows = {
                    { type="toggle", label="Show Placed-Marker Pips",
                      tooltip="Mark a world marker entry whose marker is on the ground with a small corner square, so you can see whether pressing it places or picks up.",
                      get=function() return ACfg("worldMarkerPip") ~= false end,
                      set=function(v) ASet("worldMarkerPip", v); Refresh() end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.COGS_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(self) wmCogShow(self) end)
        end

        _, h = W:Spacer(parent, y, 10); y = y - h

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Slash command
    ---------------------------------------------------------------------------
    SLASH_EUIQUICKDRAW1 = "/eqd"
    SLASH_EUIQUICKDRAW2 = "/quickdraw"
    SlashCmdList.EUIQUICKDRAW = function()
        if InCombatLockdown and InCombatLockdown() then
            print("Cannot open options in combat")
            return
        end
        EllesmereUI:ShowModule("EllesmereUIQuickdraw")
    end

    ---------------------------------------------------------------------------
    --  Register the module
    ---------------------------------------------------------------------------
    EllesmereUI:RegisterModule("EllesmereUIQuickdraw", {
        title       = "Quickdraw",
        description = "Hold a keybind to open a menu of actions; point or scroll to choose, release to fire.",
        pages       = { PAGE_DISPLAY },
        buildPage   = BuildPage,
        onReset     = function()
            -- Lite DB stores data at
            -- EllesmereUIDB.profiles[X].addons.EllesmereUIQuickdraw
            if EllesmereUIDB and EllesmereUIDB.profiles then
                local profile = EllesmereUIDB.activeProfile or "Default"
                local p = EllesmereUIDB.profiles[profile]
                if p and p.addons and p.addons.EllesmereUIQuickdraw then
                    wipe(p.addons.EllesmereUIQuickdraw)
                end
            end
            local target = _G._EQD_AceDB
            if target and target.profile and ns.DB_DEFAULTS then
                EllesmereUI.Lite.DeepMergeDefaults(target.profile, ns.DB_DEFAULTS.profile)
            end
            if _G._EQD_Apply then _G._EQD_Apply() end
            -- The reset leaves one palette, so the editor cannot stay pointed
            -- at whichever one it was on.
            editPalette = 1
        end,
    })
end)
-- LoadOnDemand: this addon loads after PLAYER_LOGIN, so the event above will never fire; run the init now.
if IsLoggedIn() then initFrame:GetScript("OnEvent")(initFrame) end
