if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_TeleportMenu.lua  (WoW Forever only)
--  The Teleport Menu of the Minimap's button: the hearthstone and every
--  teleport the character has, one secure button each. Spells and items the
--  character does not own are left out, so a class sees its own spells and a
--  bag shows its own gadgets. Built on the first click, never in combat, and
--  its events live only while it is shown; the button itself is the Minimap's
--  (EUI_Minimap_Indicators.lua), off until ticked in Show Extra Buttons.
-------------------------------------------------------------------------------
local ENTRIES = {
    { "item",  6948 },   -- Hearthstone
    { "spell", 556 },    -- Astral Recall
    { "spell", 18960 },  -- Teleport: Moonglade
    { "spell", 3561 },   -- Teleport: Stormwind
    { "spell", 3562 },   -- Teleport: Ironforge
    { "spell", 3565 },   -- Teleport: Darnassus
    { "spell", 3567 },   -- Teleport: Orgrimmar
    { "spell", 3563 },   -- Teleport: Undercity
    { "spell", 3566 },   -- Teleport: Thunder Bluff
    { "item",  18984 },  -- Dimensional Ripper - Everlook
    { "item",  18986 },  -- Ultrasafe Transporter: Gadgetzan
}

local BTN_SIZE, SPACING, PADDING, COLS = 32, 1, 2, 4
local HEARTH_ICON = 134414

local function Owned(kind, id)
    if kind == "spell" then return IsPlayerSpell(id) end
    return C_Item.GetItemCount(id) > 0
end

local function IconOf(kind, id)
    if kind == "spell" then
        local info = C_Spell.GetSpellInfo(id)
        return info and info.iconID or HEARTH_ICON
    end
    return C_Item.GetItemIconByID(id) or HEARTH_ICON
end

local function Create(opts)
    if InCombatLockdown() then return nil end
    local PP = EllesmereUI.PP

    local flyout = CreateFrame("Frame", opts.name .. "TeleportMenu", UIParent)
    flyout:SetFrameStrata("DIALOG")
    flyout:SetFrameLevel(100)
    if opts.clamp then flyout:SetClampedToScreen(true) end
    flyout:Hide()

    local bg = flyout:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(opts.bg[1], opts.bg[2], opts.bg[3], 0.95)
    if PP and PP.CreateBorder then
        PP.CreateBorder(flyout, 1, 1, 1, 0.06, 1, "OVERLAY", 7)
    end

    -- Close in combat
    local guard = CreateFrame("Frame")
    guard:RegisterEvent("PLAYER_REGEN_DISABLED")
    guard:SetScript("OnEvent", function() flyout:Hide() end)

    local buttons = {}
    for i, e in ipairs(ENTRIES) do
        local kind, id = e[1], e[2]
        local btn = CreateFrame("Button", opts.name .. "Teleport" .. i, flyout, "SecureActionButtonTemplate")
        btn:SetSize(BTN_SIZE, BTN_SIZE)
        btn.kind, btn.id = kind, id

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexCoord(6/64, 58/64, 6/64, 58/64)
        btn.icon = icon
        if PP and PP.CreateBorder then
            PP.CreateBorder(btn, 0, 0, 0, 1, 1, "OVERLAY", 7)
        end

        local cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
        cd:SetAllPoints()
        cd:SetHideCountdownNumbers(true)
        cd:SetDrawSwipe(true)
        cd:SetDrawBling(false)
        cd:SetDrawEdge(false)
        btn.cooldown = cd

        local hover = btn:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.20)
        local castHL = btn:CreateTexture(nil, "OVERLAY", nil, 1)
        castHL:SetAllPoints()
        castHL:SetColorTexture(1, 1, 1, 0.4)
        castHL:Hide()
        btn._castHL = castHL

        btn:RegisterForClicks("AnyUp", "AnyDown")
        if kind == "spell" then
            btn:SetAttribute("type", "spell")
            btn:SetAttribute("spell", id)
        else
            btn:SetAttribute("type", "item")
            btn:SetAttribute("item", "item:" .. id)
        end
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.kind == "spell" then
                GameTooltip:SetSpellByID(self.id)
            else
                GameTooltip:SetItemByID(self.id)
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        btn:HookScript("PostClick", function(self) self._castHL:Show() end)
        btn:Hide()
        buttons[i] = btn
    end

    -- Shows the owned entries in a grid and sizes the flyout to them.
    local function Layout()
        local n = 0
        for _, btn in ipairs(buttons) do
            if Owned(btn.kind, btn.id) then
                local col = n % COLS
                local row = math.floor(n / COLS)
                n = n + 1
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", flyout, "TOPLEFT",
                    PADDING + col * (BTN_SIZE + SPACING),
                    -(PADDING + row * (BTN_SIZE + SPACING)))
                btn.icon:SetTexture(IconOf(btn.kind, btn.id))
                btn:Show()
            else
                btn:Hide()
            end
        end
        local cols = math.min(math.max(n, 1), COLS)
        local rows = math.max(math.ceil(n / COLS), 1)
        flyout:SetSize(PADDING * 2 + cols * BTN_SIZE + (cols - 1) * SPACING,
                       PADDING * 2 + rows * BTN_SIZE + (rows - 1) * SPACING)
    end

    local function RefreshCooldowns()
        for _, btn in ipairs(buttons) do
            if btn:IsShown() then
                local start, dur
                if btn.kind == "spell" then
                    local info = C_Spell.GetSpellCooldown(btn.id)
                    start, dur = info and info.startTime, info and info.duration
                else
                    local ok, s, d = pcall(C_Container.GetItemCooldown, btn.id)
                    if ok then start, dur = s, d end
                end
                if start and dur and dur > 0 then
                    btn.cooldown:SetCooldown(start, dur)
                else
                    btn.cooldown:Clear()
                end
            end
        end
    end

    -- Events live only while shown: cooldown and cast highlight refresh.
    local CAST_END = { "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED",
                       "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }
    flyout:SetScript("OnShow", function(self)
        self:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        self:RegisterEvent("BAG_UPDATE_COOLDOWN")
        for _, ev in ipairs(CAST_END) do
            if opts.unitEvents then self:RegisterUnitEvent(ev, "player") else self:RegisterEvent(ev) end
        end
        Layout()
        RefreshCooldowns()
        -- Controller cursor: a window the player opened brings the gamepad pointer up.
        if EllesmereUI.PadNative() then EllesmereUI.RaiseGamePadCursor() end
    end)
    flyout:SetScript("OnHide", function(self)
        self:UnregisterAllEvents()
        for _, btn in ipairs(buttons) do btn._castHL:Hide() end
    end)
    flyout:SetScript("OnEvent", function(self, event)
        if event == "SPELL_UPDATE_COOLDOWN" or event == "BAG_UPDATE_COOLDOWN" then
            RefreshCooldowns()
        else
            for _, btn in ipairs(buttons) do btn._castHL:Hide() end
        end
    end)

    EllesmereUI.RegisterEscapeClose(flyout)
    return flyout
end

EllesmereUI._ForeverTeleport = { Create = Create }
