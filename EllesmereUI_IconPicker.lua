if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_IconPicker.lua
--  The suite's icon picker, EllesmereUI.ShowIconPicker(opts): a grid of the
--  caller's own icons first, then every icon the game offers for macros.
--  Loads right after EllesmereUI_Popups.lua (its shell and buttons).
--
--  Built on the first open and kept: one popup shell, a fixed grid of cells
--  that shows the rows the scroll bar picks, an optional Custom Icon ID row
--  under it (a file id typed in), and Cancel. Nothing is
--  registered, hooked or running while it is closed. The game's icon list is
--  read once per session (repeats allowed, as in Blizzard's own list), never
--  through Blizzard's IconDataProviderMixin: driven from here it would write
--  the file state Blizzard's macro window shares and force a full collect.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI

local PanelPP    = EllesmereUI.PanelPP
local MakeFont   = EllesmereUI.MakeFont
local MakeBorder = EllesmereUI.MakeBorder
local SolidTex   = EllesmereUI.SolidTex

local floor, ceil, max = math.floor, math.ceil, math.max
local type, tonumber = type, tonumber

local COLS, ROWS, SIZE = 10, 6, 40  -- the grid: SIZE per cell, its icon SIZE - 4
local SIDE = 20                     -- popup edge to the grid, left and right
local TOP_SUB = 70                  -- popup top to the grid under a one-line subtitle
local TOP_BARE = 50                 -- popup top to the grid with no subtitle
local BOTTOM = 62                   -- grid to the popup's bottom (Cancel sits there)
local CUSTOM_H = 37                 -- the Custom Icon ID row under the grid (opts.customID)
local CROP = 0.08                   -- icon edge trimmed off each side
local NONE = {}                     -- the lead of a caller that gives none

local picker      -- the popup and this open's values, built on the first open
local gameIcons   -- every icon the game offers, read on the first open

-- A file id is a number (the game's list may hand one over as a string of
-- digits); a texture name or path, or an atlas name, stays a string.
local function Normal(icon)
    return tonumber(icon) or icon
end

local function PaintCell(b, hover)
    if b.selected then
        local ac = EllesmereUI.ELLESMERE_GREEN
        b.brd:SetColor(ac.r, ac.g, ac.b, 1)
    elseif hover then
        b.brd:SetColor(1, 1, 1, 0.5)
    else
        b.brd:SetColor(0, 0, 0, 1)
    end
end

local function CellEnter(self) PaintCell(self, true) end
local function CellLeave(self) PaintCell(self, false) end

-- An atlas the caller names (opts.atlas) is drawn whole; any other icon is a
-- file id or a texture (a bare name lives under Interface\Icons), trimmed.
-- Returns what it drew: the atlas name, the file id or the texture path.
local function SetCellIcon(b, icon)
    local tex = b.icon
    local atlas = picker.atlas
    if atlas and atlas[icon] then
        tex:SetAtlas(icon)
        return icon
    end
    local v = Normal(icon)
    if type(v) == "string" and not v:find("\\", 1, true) then v = "Interface\\Icons\\" .. v end
    tex:SetTexture(v)
    tex:SetTexCoord(CROP, 1 - CROP, CROP, 1 - CROP)
    return v
end

-- Hides the picker and lets go of this open's values. No pick.
local function Close()
    local p = picker
    p.dimmer:Hide()
    p.customBox:ClearFocus()
    p.lead, p.nLead, p.atlas, p.onPick, p.current, p.handle = NONE, 0, nil, nil, nil, nil
end

local function CellClick(self)
    local onPick, icon = picker.onPick, self.value
    Close()
    if onPick and icon ~= nil then onPick(Normal(icon)) end
end

-- Fills the grid from the first icon the scroll bar picks. A cell under the
-- cursor keeps its hover look with its new icon.
local function Update()
    local p = picker
    local lead, nLead, current = p.lead, p.nLead, p.current
    for i = 1, COLS * ROWS do
        local b = p.cells[i]
        local k = p.offset + i
        local icon
        if k <= nLead then icon = lead[k] else icon = gameIcons[k - nLead] end
        b.value = icon
        if icon ~= nil then
            -- The current icon, as listed or as drawn (a bare name a caller
            -- saved as its path under Interface\Icons)
            local drawn = SetCellIcon(b, icon)
            b.selected = current ~= nil and (Normal(icon) == current or drawn == current)
            PaintCell(b, b:IsMouseMotionFocus())
            b:Show()
        else
            b:Hide()
        end
    end
end

-- Custom Icon ID (opts.customID): the file id typed into the row's box, or
-- nil while the box holds none.
local function CustomID()
    local id = tonumber(picker.customBox:GetText())
    return id and id > 0 and id or nil
end

-- The typed icon shows beside the box as it is typed; Apply is live only
-- while there is an id to pick.
local function CustomChanged()
    local p = picker
    local id = CustomID()
    p.customPrev:SetShown(id ~= nil)
    if id then p.customPrev:SetTexture(id) end
    p.customApply:SetAlpha(id and 1 or 0.3)
    p.customApply:EnableMouse(id ~= nil)
end

-- Apply, or Enter in the box: picks the typed id as a cell click picks an icon.
local function CustomPick()
    local id = CustomID()
    if not id then return end
    local onPick = picker.onPick
    Close()
    if onPick then onPick(id) end
end

-- The grid sits under the title and the subtitle's lines, and the popup
-- grows with them and with the Custom Icon ID row; moved only when one of
-- those heights changes.
local function Layout(hasSub)
    local p = picker
    local top = TOP_BARE
    if hasSub then
        top = TOP_SUB + max(0, floor(p.sub:GetStringHeight() - p.sub:GetLineHeight() + 0.5))
    end
    local bottom = BOTTOM + (p.custom and CUSTOM_H or 0)
    if top == p.top and bottom == p.bottom then return end
    p.top, p.bottom = top, bottom
    PanelPP.Size(p.popup, COLS * SIZE + SIDE * 2, top + ROWS * SIZE + bottom)
    p.customRow:SetPoint("TOPLEFT", p.popup, "TOPLEFT", SIDE, -top - ROWS * SIZE - 8)
    for i, b in ipairs(p.cells) do
        b:SetPoint("TOPLEFT", SIDE + ((i - 1) % COLS) * SIZE, -top - floor((i - 1) / COLS) * SIZE)
    end
    p.sf:SetPoint("TOPLEFT", p.popup, "TOPLEFT", SIDE, -top)
end

local function Build()
    local p = { offset = 0, lead = NONE, nLead = 0, cells = {} }
    picker = p
    p.dimmer, p.popup = EllesmereUI.BuildPopupShell("EUIIconPicker", {
        w = COLS * SIZE + SIDE * 2, h = TOP_SUB + ROWS * SIZE + BOTTOM, bump = 1,
        onEscape = Close, onDimmerDown = Close,
    })
    local popup = p.popup
    -- The panel's scale goes to the dimmer, the popup keeps its bump.
    EllesmereUI._popupFrames[#EllesmereUI._popupFrames + 1] = { popup = popup, dimmer = p.dimmer }
    -- Escape on every show out of combat, also after a first open in combat.
    EllesmereUI.PopupTakeKeys(popup, p.dimmer)

    p.title = MakeFont(popup, 16, "", 1, 1, 1)
    p.title:SetPoint("TOP", popup, "TOP", 0, -20)
    p.sub = MakeFont(popup, 12, nil, 1, 1, 1, EllesmereUI.TEXT_DIM_A)
    p.sub:SetPoint("TOP", p.title, "BOTTOM", 0, -8)
    p.sub:SetWidth(COLS * SIZE)
    p.sub:SetJustifyH("CENTER")
    p.sub:SetWordWrap(true)

    for i = 1, COLS * ROWS do
        local b = CreateFrame("Button", nil, popup)
        b:SetSize(SIZE - 4, SIZE - 4)
        b:SetFrameLevel(popup:GetFrameLevel() + 2)   -- above the scroll frame below
        -- Left clicks only, and no drag: a drag would swallow the click.
        b:RegisterForClicks("LeftButtonUp")
        SolidTex(b, "BACKGROUND", 0, 0, 0, 0.5):SetAllPoints()
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("TOPLEFT", 1, -1)
        b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        b.brd = MakeBorder(b, 0, 0, 0, 1, PanelPP)
        b:SetScript("OnEnter", CellEnter)
        b:SetScript("OnLeave", CellLeave)
        b:SetScript("OnClick", CellClick)
        p.cells[i] = b
    end

    -- The shared scroll bar on an empty scroll frame under the grid: its child
    -- is as tall as every icon row, and the scroll value picks the first row
    -- the grid shows (the grid itself stays put).
    local sf = CreateFrame("ScrollFrame", nil, popup)
    sf:SetFrameLevel(popup:GetFrameLevel() + 1)
    sf:SetSize(COLS * SIZE + 12, ROWS * SIZE)
    p.sf = sf
    p.child = CreateFrame("Frame", nil, sf)
    p.child:SetSize(COLS * SIZE, ROWS * SIZE)
    sf:SetScrollChild(p.child)
    p.updateThumb, p.scrollTo = EllesmereUI.AttachSmoothScrollbar(sf, {
        step = SIZE, child = p.child,
        onScroll = function(v)
            local off = floor(v / SIZE + 0.5) * COLS
            if off ~= p.offset then
                p.offset = off
                Update()
            end
        end,
    })

    p.cancel = EllesmereUI.MakePopupButton(popup, "BOTTOM", popup, "BOTTOM", 0, 18,
        1, 1, 1, 0.75, 1, 1, 1, 1, 1, 1, 1, 0.25, 1, 1, 1, 0.5)
    p.cancel._lbl:SetText(EllesmereUI.L("Cancel"))
    p.cancel:SetScript("OnClick", Close)

    -- Custom Icon ID (opts.customID): a label, a box for the file id, the
    -- typed icon beside it and Apply, in one row under the grid. Built with
    -- the picker and shown only for an open that asks for it.
    local row = CreateFrame("Frame", nil, popup)
    row:SetSize(COLS * SIZE, 27)
    row:SetFrameLevel(popup:GetFrameLevel() + 2)
    row:Hide()
    p.customRow = row
    local lbl = MakeFont(row, 12, nil, 1, 1, 1, EllesmereUI.TEXT_DIM_A)
    lbl:SetPoint("LEFT", row, "LEFT", 0, 0)
    lbl:SetText(EllesmereUI.L("Custom Icon ID:"))
    local box = CreateFrame("EditBox", nil, row)
    box:SetSize(90, 26)
    box:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetMaxLetters(9)
    box:SetFont(EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 13, "")
    box:SetTextColor(1, 1, 1, 1)
    box:SetTextInsets(8, 8, 0, 0)
    SolidTex(box, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
    EllesmereUI.MakeRoundedBorder(box, 1, 1, 1, 0.12)
    p.customBox = box
    local prev = row:CreateTexture(nil, "ARTWORK")
    prev:SetSize(26, 26)
    prev:SetPoint("LEFT", box, "RIGHT", 8, 0)
    prev:SetTexCoord(CROP, 1 - CROP, CROP, 1 - CROP)
    prev:Hide()
    p.customPrev = prev
    p.customApply = EllesmereUI.MakePopupButton(row, "RIGHT", row, "RIGHT", 0, 0,
        1, 1, 1, 0.75, 1, 1, 1, 1, 1, 1, 1, 0.25, 1, 1, 1, 0.5)
    p.customApply._lbl:SetText(EllesmereUI.L("Apply"))
    p.customApply:SetScript("OnClick", CustomPick)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", CustomPick)
    box:SetScript("OnTextChanged", CustomChanged)
end

-------------------------------------------------------------------------------
--  EllesmereUI.ShowIconPicker(opts)
--  opts: title, subtitle (both translated by the caller; subtitle optional);
--  current (the icon marked as selected); lead (an array of the caller's own
--  icons, listed first; may be empty); atlas (optional set of lead icons that
--  are atlas names, drawn whole); customID (true adds the Custom Icon ID row:
--  a file id typed in is picked by Apply or Enter and handed to onPick as a
--  number); onPick(icon) (a file id as a number, any
--  other icon as the string listed). One picker at a time: an open for
--  another caller replaces every value of the open one, whose onPick is never
--  called. Escape, a click on the dimmer and Cancel close it with no pick.
--  Returns a handle for EllesmereUI.CloseIconPicker / IconPickerShown.
-------------------------------------------------------------------------------
function EllesmereUI.ShowIconPicker(opts)
    if not picker then Build() end
    if not gameIcons then
        gameIcons = {}
        GetLooseMacroIcons(gameIcons)
        GetLooseMacroItemIcons(gameIcons)
        GetMacroIcons(gameIcons)
        GetMacroItemIcons(gameIcons)
    end
    local p = picker
    local lead = opts.lead or NONE
    local handle = {}
    p.lead, p.nLead, p.atlas, p.onPick, p.handle = lead, #lead, opts.atlas, opts.onPick, handle
    p.current = Normal(opts.current)
    p.offset = 0
    p.title:SetText(opts.title or "")
    local sub = opts.subtitle
    local hasSub = sub ~= nil and sub ~= ""
    p.sub:SetText(hasSub and sub or "")
    p.sub:SetShown(hasSub)
    p.cancel._resetAnim()
    -- The Custom Icon ID row starts empty on every open that asks for it
    p.custom = opts.customID == true
    p.customRow:SetShown(p.custom)
    p.customBox:SetText("")
    p.customApply._resetAnim()
    CustomChanged()
    Update()
    p.dimmer:Show()
    Layout(hasSub)
    -- The bar's range: one row per COLS icons, back at the top on every open.
    p.child:SetHeight(ceil((p.nLead + #gameIcons) / COLS) * SIZE)
    p.scrollTo(0)
    p.updateThumb()
    return handle
end

-- Closes the picker only while it still shows the open whose handle this is.
function EllesmereUI.CloseIconPicker(handle)
    if handle ~= nil and picker and picker.handle == handle then Close() end
end

-- True while the picker shows the open whose handle this is.
function EllesmereUI.IconPickerShown(handle)
    return handle ~= nil and picker ~= nil and picker.handle == handle and picker.dimmer:IsShown()
end
