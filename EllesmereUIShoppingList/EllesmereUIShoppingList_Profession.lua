if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIShoppingList_Profession.lua
--  Our widgets in Blizzard's profession window (Blizzard_Professions, load on
--  demand): a count box (and, when Blizzard's tracking is not used, our own
--  Track Recipe checkbox and an Add button) beside the recipe form's Track
--  Recipe checkbox.
--
--  Zero taint: our own frames only, parented to the recipe form and anchored
--  beside Blizzard's own track checkbox. Blizzard's frames are read (the
--  form's recipe info, the checkbox's place and shown state) and post-hooked
--  (the form's Init, the checkbox's click), never written.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EUI = ns.EUI
local Get = ns.Get

local holder, qtyBox, addBtn, cover
local form            -- ProfessionsFrame.CraftingPage.SchematicForm
local anchor          -- form.TrackRecipeCheckbox
local current         -- { recipeID, recraft } the form shows
local leftSide        -- our widgets sit left of the checkbox (see PlaceHolder)

local function FormRecipe()
    if not (form and form:IsVisible()) then return nil end
    local info = form:GetRecipeInfo()
    if not (info and info.recipeID) then return nil end
    -- Salvage recipes take what you salvage, not reagents.
    if info.isSalvageRecipe then return nil end
    return info
end

-- Blizzard places its checkbox differently per client: top-right of the form
-- with its label running to the form's edge (retail), or bottom-left with room
-- after the label (WoW Forever). Read from the checkbox's own anchor: at the
-- top, our widgets go left of the checkbox; else right of its label.
local function PlaceHolder()
    local point = anchor:GetPoint(1)
    leftSide = type(point) == "string" and point:find("^TOP") ~= nil
    holder:ClearAllPoints()
    if leftSide then
        holder:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
    else
        holder:SetPoint("LEFT", anchor.Text, "RIGHT", 12, 0)
    end
end

-- Count box and Add, packed toward the checkbox.
local function SeatWidgets(showAdd)
    qtyBox:ClearAllPoints()
    addBtn:ClearAllPoints()
    if leftSide then
        if showAdd then
            addBtn:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
            qtyBox:SetPoint("RIGHT", addBtn, "LEFT", -8, 0)
        else
            qtyBox:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
        end
    else
        qtyBox:SetPoint("LEFT", holder, "LEFT", 6, 0)
        addBtn:SetPoint("LEFT", qtyBox, "RIGHT", 6, 0)
    end
end

-- Two modes. Use Blizzard's Track Recipe on: Blizzard's checkbox is the
-- toggle (both trackers stay one set) and only the count box shows. Off: our
-- own checkbox covers Blizzard's (same template, same spot, the label inside
-- its click area), so "Track Recipe" tracks in this list only; the count box
-- and Add wake up once the recipe is tracked. Nothing shows where Blizzard
-- hides its checkbox (minimized form, a recipe that cannot be tracked, the
-- gamepad layout): Init has settled that by the time our post-hook runs.
local function SetEnabled(widget, on)
    widget:SetEnabled(on)
    widget:SetAlpha(on and 1 or 0.45)
end

local function UpdateWidgets()
    if not holder then return end
    local info = ns.IsOn("track") and anchor:IsShown() and FormRecipe()
    if not info then
        holder:Hide()
        cover:Hide()
        current = nil
        return
    end
    current = current or {}
    current.recipeID, current.recraft = info.recipeID, info.isRecraft == true
    local tracked = ns.IsTracked(info.recipeID)
    local r = tracked and ns.Char().recipes[info.recipeID]
    if not qtyBox:HasFocus() then
        qtyBox:SetText(tostring(r and r.qty or Get("defaultQty")))
    end
    PlaceHolder()
    if ns.IsOn("blizzard") then
        cover:Hide()
        addBtn:Hide()
        SetEnabled(qtyBox, true)
    else
        cover:SetChecked(tracked)
        cover:Show()
        addBtn:Show()
        SetEnabled(qtyBox, tracked)
        SetEnabled(addBtn, tracked)
    end
    SeatWidgets(addBtn:IsShown())
    holder:Show()
end
ns.UpdateProfessionWidgets = UpdateWidgets

local function QtyFromBox()
    local v = tonumber(qtyBox:GetText())
    if not v or v < 1 then v = Get("defaultQty") end
    return math.floor(v)
end

-- Blizzard's checkbox tracked the recipe the form shows: its quantity box and recraft flag.
function ns.FormTrackInfo(recipeID)
    if qtyBox and current and current.recipeID == recipeID then return QtyFromBox(), current.recraft end
end

local function Tip(widget, text)
    widget:SetScript("OnEnter", function(self) EUI.ShowWidgetTooltip(self, EUI.L(text)) end)
    widget:SetScript("OnLeave", function() EUI.HideWidgetTooltip() end)
end

-- Blizzard's checkbox template differs per client (retail: UICheckButtonTemplate,
-- WoW Forever: CheckboxWithLabelTemplate); ours matches the one the client has.
local function CheckboxTemplate()
    if C_XMLUtil.GetTemplateInfo("CheckboxWithLabelTemplate") then return "CheckboxWithLabelTemplate" end
    return "UICheckButtonTemplate"
end

local function Build()
    local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
    form = page and page.SchematicForm
    anchor = form and form.TrackRecipeCheckbox
    if not anchor or holder then return end

    holder = CreateFrame("Frame", nil, form)
    holder:SetSize(116, 24)
    holder:SetFrameLevel(form:GetFrameLevel() + 10)

    qtyBox = CreateFrame("EditBox", nil, holder, "InputBoxTemplate")
    qtyBox:SetSize(36, 20)

    addBtn = CreateFrame("Button", nil, holder, "UIPanelButtonTemplate")
    addBtn:SetSize(64, 22)
    addBtn:SetText(EUI.L("Add"))
    addBtn:SetScript("OnClick", function()
        if current and ns.IsTracked(current.recipeID) then
            ns.SetRecipeQty(current.recipeID, ns.Char().recipes[current.recipeID].qty + 1)
        end
    end)
    Tip(addBtn, "One more craft of this recipe.")

    -- Our checkbox over Blizzard's (see UpdateWidgets). A dark backing hides
    -- Blizzard's own tick underneath; the click area runs over its label.
    cover = CreateFrame("CheckButton", nil, form, CheckboxTemplate())
    cover:SetAllPoints(anchor)
    cover:SetFrameLevel(anchor:GetFrameLevel() + 5)
    local back = cover:CreateTexture(nil, "BACKGROUND", nil, -8)
    back:SetPoint("TOPLEFT", cover, "TOPLEFT", 4, -4)
    back:SetPoint("BOTTOMRIGHT", cover, "BOTTOMRIGHT", -4, 4)
    back:SetColorTexture(0.05, 0.05, 0.05, 1)
    cover:SetHitRectInsets(0, -(anchor.Text:GetStringWidth() + 8), 0, 0)
    cover:SetScript("OnClick", function(self)
        if not current then return end
        if self:GetChecked() then
            ns.TrackRecipe(current.recipeID, QtyFromBox(), current.recraft)
        else
            ns.UntrackRecipe(current.recipeID)
        end
    end)
    Tip(cover, "Tracks this recipe in the Shopping List only (Blizzard's tracking is not used).")
    cover:Hide()

    qtyBox:SetAutoFocus(false)
    qtyBox:SetNumeric(true)
    qtyBox:SetMaxLetters(3)
    qtyBox:SetJustifyH("CENTER")
    qtyBox:SetText(tostring(Get("defaultQty")))
    qtyBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if not current then return end
        -- The box is the tracked recipe's count: Enter sets it. With Blizzard's
        -- checkbox as the toggle, Enter on an untracked recipe tracks it.
        if ns.IsTracked(current.recipeID) then
            ns.SetRecipeQty(current.recipeID, QtyFromBox())
        elseif ns.IsOn("blizzard") then
            ns.TrackRecipe(current.recipeID, QtyFromBox(), current.recraft)
        end
    end)
    qtyBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    Tip(qtyBox, "Crafts to track. Tick Track Recipe to add the recipe; Enter changes the count of a tracked one.")
    -- The checkbox's own click, read after Blizzard handled it: covers a client
    -- where the tracking event does not arrive (the handler is idempotent).
    anchor:HookScript("OnClick", function(self)
        if current then ns.OnBlizzardTrack(current.recipeID, self:GetChecked() == true, current.recraft) end
    end)

    holder:Hide()
    -- Post-hooks: the form re-inits on every recipe selection (recrafts too).
    hooksecurefunc(form, "Init", function() UpdateWidgets() end)
    form:HookScript("OnShow", UpdateWidgets)
    form:HookScript("OnHide", UpdateWidgets)
    ns.OnChanged(UpdateWidgets)
end

ns.RegisterFeature({
    key = "track",
    isOn = function() return Get("trackButton") end,
    enable = function()
        EventUtil.ContinueOnAddOnLoaded("Blizzard_Professions", function()
            Build()
            UpdateWidgets()
        end)
    end,
    disable = UpdateWidgets,
})

-------------------------------------------------------------------------------
--  Skill-up colour: the selected recipe's difficulty as the client reports
--  it (recipe info relativeDifficulty / numSkillUps). No thresholds table:
--  a recipe the client gives no difficulty (most modern retail recipes)
--  shows nothing.
-------------------------------------------------------------------------------
local DIFF = Enum.TradeskillRelativeDifficulty
-- Blizzard's classic difficulty colours when the client has the table.
local DIFF_STYLE = {
    [DIFF.Optimal] = { key = "optimal", text = "Skill-up: certain",  r = 1,    g = 0.5,  b = 0.25 },
    [DIFF.Medium]  = { key = "medium",  text = "Skill-up: likely",   r = 1,    g = 1,    b = 0 },
    [DIFF.Easy]    = { key = "easy",    text = "Skill-up: unlikely", r = 0.25, g = 0.75, b = 0.25 },
    [DIFF.Trivial] = { key = "trivial", text = "Skill-up: none",     r = 0.5,  g = 0.5,  b = 0.5 },
}
local skillLabel

local function UpdateSkillUp()
    if not skillLabel then return end
    local info = ns.IsOn("skillup") and FormRecipe()
    local style = info and info.learned and info.relativeDifficulty ~= nil and DIFF_STYLE[info.relativeDifficulty]
    if not style then
        skillLabel:Hide()
        return
    end
    local c = (TradeSkillTypeColor and TradeSkillTypeColor[style.key]) or style
    local text = EUI.L(style.text)
    if (info.numSkillUps or 1) > 1 and info.relativeDifficulty == DIFF.Optimal then
        text = text .. string.format(" (+%d)", info.numSkillUps)
    end
    skillLabel:SetText(text)
    skillLabel:SetTextColor(c.r, c.g, c.b)
    skillLabel:Show()
end

local function BuildSkillLabel()
    if skillLabel or not form then return end
    skillLabel = form:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    -- Beside Blizzard's Track Recipe checkbox: under it, right-aligned with
    -- its label, when it sits at the top of the form (retail); else just
    -- above it, left-aligned (WoW Forever: bottom-left of the form).
    local check = form.TrackRecipeCheckbox
    local point = check:GetPoint(1)
    if type(point) == "string" and point:find("^TOP") then
        skillLabel:SetPoint("TOPRIGHT", check.Text, "BOTTOMRIGHT", 0, -6)
    else
        skillLabel:SetPoint("BOTTOMLEFT", check, "TOPLEFT", 2, 6)
    end
    skillLabel:Hide()
    hooksecurefunc(form, "Init", function() UpdateSkillUp() end)
    form:HookScript("OnShow", UpdateSkillUp)
end

ns.RegisterFeature({
    key = "skillup",
    isOn = function() return Get("skillUpColor") end,
    events = { SKILL_LINES_CHANGED = function() UpdateSkillUp() end },
    enable = function()
        EventUtil.ContinueOnAddOnLoaded("Blizzard_Professions", function()
            local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
            form = form or (page and page.SchematicForm)
            BuildSkillLabel()
            UpdateSkillUp()
        end)
    end,
    disable = UpdateSkillUp,
})

-------------------------------------------------------------------------------
--  Profession tools: secure spell buttons beside the profession window, for
--  the tools the client has (the only list here: the spells themselves, each
--  shown only when known). WoW Forever: Cooking's Basic Campfire.
--  Secure frames are created, placed, shown and hidden out of combat only; a
--  change asked for in combat waits for PLAYER_REGEN_ENABLED (listened to only
--  while one waits, whatever the feature's state: switching it off in combat
--  still hides the buttons at combat end). They sit on
--  UIParent at the window's edge (not anchored to Blizzard's frame, which a
--  protected anchor would restrict in combat) and follow it on show and after
--  a drag.
-------------------------------------------------------------------------------
local COOKING = 185  -- skill line
local TOOLS = {
    { spell = 818, skillLine = COOKING },  -- Basic Campfire
}
local toolButtons = {}

local function CurrentSkillLine()
    local info = C_TradeSkillUI.GetBaseProfessionInfo()
    return info and info.professionID
end

local Layout
local function AfterCombat()
    ns.Unlisten("toolsCombat", "PLAYER_REGEN_ENABLED")
    Layout()
end

local function MakeToolButton(i, tool)
    local b = CreateFrame("Button", "EllesmereUIShoppingListTool" .. i, UIParent, "SecureActionButtonTemplate")
    b:SetSize(32, 32)
    b:SetFrameStrata("HIGH")
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("useOnKeyDown", false)
    b:SetAttribute("type", "spell")
    b:SetAttribute("spell", tool.spell)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    icon:SetTexture(C_Spell.GetSpellTexture(tool.spell))
    b.icon = icon
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(tool.spell)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b.tool = tool
    b:Hide()
    return b
end

Layout = function()
    if InCombatLockdown() then
        ns.Listen("toolsCombat", "PLAYER_REGEN_ENABLED", AfterCombat)
        return
    end
    local pf = ProfessionsFrame
    local show = ns.IsOn("tools") and pf and pf:IsShown()
    local skillLine = show and CurrentSkillLine()
    local x, y
    if show then
        local right, top = pf:GetRight(), pf:GetTop()
        if not (right and top) then show = false end
        if show then
            local k = pf:GetEffectiveScale() / UIParent:GetEffectiveScale()
            x, y = right * k + 2, top * k - 40
        end
    end
    local n = 0
    for i, tool in ipairs(TOOLS) do
        local wanted = show and tool.skillLine == skillLine and C_SpellBook.IsSpellKnown(tool.spell)
        local b = toolButtons[i]
        if wanted and not b then
            b = MakeToolButton(i, tool)
            toolButtons[i] = b
        end
        if b then
            if wanted then
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y - n * 36)
                b:Show()
                n = n + 1
            else
                b:Hide()
            end
        end
    end
end

local toolsHooked = false
local function HookProfessionsFrame()
    if toolsHooked or not ProfessionsFrame then return end
    toolsHooked = true
    -- Blizzard settles the window's position after its show: lay out a frame later.
    local function Later() if ns.IsOn("tools") then C_Timer.After(0, Layout) end end
    ProfessionsFrame:HookScript("OnShow", Later)
    ProfessionsFrame:HookScript("OnHide", function() if ns.IsOn("tools") then Layout() end end)
    -- A drag (Blizzard's or a mover addon's) ends in one of these.
    ProfessionsFrame:HookScript("OnMouseUp", Later)
    ProfessionsFrame:HookScript("OnDragStop", Later)
end

ns.RegisterFeature({
    key = "tools",
    isOn = function() return Get("toolButtons") end,
    events = {
        TRADE_SKILL_SHOW = function() C_Timer.After(0, Layout) end,
        TRADE_SKILL_CLOSE = Layout,
        TRADE_SKILL_DATA_SOURCE_CHANGED = function() C_Timer.After(0, Layout) end,
    },
    enable = function()
        EventUtil.ContinueOnAddOnLoaded("Blizzard_Professions", function()
            HookProfessionsFrame()
            Layout()
        end)
    end,
    disable = Layout,
})
