if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CooldownManager_TalentConditions.lua
--  Talent Conditions for the CDM per-icon menu (cooldown/utility bars): the
--  menu row opens the shared picker (EllesmereUI.ShowTalentConditionsPopup in
--  EllesmereUI_TalentConditionsPopup.lua) on the spell's own list, and the bar
--  preview marks the slots whose spells carry conditions.
--
--  Storage, evaluation and the reanchor filter live in the CDM addon
--  (EllesmereUICdmTalentConditions.lua). Conditions are stored per spec, so
--  what the picker shows (the active config's committed build) is exactly
--  what decides the icon.
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUICooldownManager"]
if not ns then return end

-- The options page pool (EllesmereUI_FramePool.lua): the corner mark on a
-- preview slot (a reused header's slot is a pool host) is handed out again
-- reset to fresh.
local CreateFrame = EllesmereUI._Pool.CreateFrame

local PP = EllesmereUI.PP
local NOT_TAKEN = EllesmereUI.TALENT_COND_NOT_TAKEN

-- The picker's texts, in the icon's words (made on the first open).
local iconTexts
local function IconTexts()
    if not iconTexts then
        iconTexts = {
            hint = EllesmereUI.L("Click a talent to require it: Taken, then Not Taken, then cleared. Every condition must hold for the icon to show."),
            none = EllesmereUI.L("No conditions: the icon always shows."),
            met = function(n)
                return EllesmereUI.Lf("%1$d condition(s), met by your current talents: the icon shows.", n)
            end,
            notMet = function(n)
                return EllesmereUI.Lf("%1$d condition(s), not met by your current talents: the icon is hidden.", n)
            end,
        }
    end
    return iconTexts
end

-------------------------------------------------------------------------------
--  Options preview helpers (called from the CDM bar preview; kept here so the
--  preview function, already near Lua 5.1's local cap, gains one local only)
-------------------------------------------------------------------------------

-- For a CD/utility bar's assigned ids: id -> "on" when its conditions hold now,
-- "off" when they do not. Includes Empty Slot markers; nil when none have conditions.
function ns.TalentCondPreviewSet(barKey, tracked)
    local store = ns.GetSpellSettingsStore(barKey)
    if not store or type(tracked) ~= "table" then return nil end
    local set
    for _, id in ipairs(tracked) do
        local entry = type(id) == "number" and (id > 0 or ns.IsEmptySlotMarker(id)) and store[id]
        local conds = type(entry) == "table" and rawget(entry, "talentConditions")
        if type(conds) == "table" and #conds > 0 then
            set = set or {}
            set[id] = ns.TalentConditionsHold(conds) and "on" or "off"
        end
    end
    return set
end

-- Small corner mark on a preview slot whose spell carries conditions: accent while
-- they hold, red while they do not. state nil hides it. Built on first use. Kept under
-- the slot's text overlay (its border strips sit one level above the fill), so keybind
-- and stack text stay readable in every icon style (the overlay's level differs per style).
function ns.PaintTalentCondMark(slot, state)
    local mark = slot._tcMark
    if not state then
        if mark then mark:Hide() end
        return
    end
    if not mark then
        mark = CreateFrame("Frame", nil, slot)
        mark:EnableMouse(false)
        mark._tex = mark:CreateTexture(nil, "ARTWORK")
        mark._tex:SetAllPoints()
        PP.CreateBorder(mark, 0, 0, 0, 1, 1, "OVERLAY", 7)
        slot._tcMark = mark
    end
    mark:SetFrameLevel(slot._pvTextOverlay:GetFrameLevel() - 2)
    local size = math.max(6, math.floor((slot:GetWidth() or 0) * 0.28 + 0.5))
    mark:SetSize(size, size)
    mark:ClearAllPoints()
    mark:SetPoint("TOPLEFT", slot, "TOPLEFT", 3, -3)
    if state == "off" then
        mark._tex:SetColorTexture(NOT_TAKEN[1], NOT_TAKEN[2], NOT_TAKEN[3], 1)
    else
        local ar, ag, ab = EllesmereUI.GetAccentColor()
        mark._tex:SetColorTexture(ar, ag, ab, 1)
    end
    mark:Show()
end

-------------------------------------------------------------------------------
--  Entry point (the per-icon menu's "Talent Conditions" row)
--  conds: the spell's saved list (read only here); confirm(newList or nil).
-------------------------------------------------------------------------------
function ns.ShowCDMTalentConditionsPopup(spellID, conds, confirm)
    local spellName = ns.IsEmptySlotMarker(spellID) and EllesmereUI.L("Empty Slot")
        or C_Spell.GetSpellName(spellID) or tostring(spellID)
    EllesmereUI.ShowTalentConditionsPopup({
        title = EllesmereUI.Lf("Talent Conditions: %1$s", spellName),
        conds = conds,
        onConfirm = confirm,
        texts = IconTexts(),
        fontKey = "cdm",
    })
end
