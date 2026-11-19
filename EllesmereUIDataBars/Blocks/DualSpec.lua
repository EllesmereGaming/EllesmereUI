if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not EllesmereUI.IS_FOREVER then return end
-- Dual Spec block (WoW Forever): the active spec group by its leading talent
-- tree, or the player's own name for it, and both groups in the tooltip. Left
-- Click opens the talents, Right Click the spellbook, Shift + Left / Right Click
-- activates the primary / secondary group. The switch is a cast that the game
-- refuses in combat, so the block says so instead of trying.

local ADDON_NAME, ns = ...
local L = ns.L
local K = ns.BlockKit
local max, min, floor = math.max, math.min, math.floor

-- Registered here so the block exists on WoW Forever only. It sits after XP /
-- Reputation, where the retail Spec block is.
do
    local pos = #ns.BLOCK_TYPES + 1
    for i, t in ipairs(ns.BLOCK_TYPES) do
        if t.key == "xprep" then pos = i + 1 break end
    end
    table.insert(ns.BLOCK_TYPES, pos, { key = "dualspec", label = "Dual Spec" })
    ns.BLOCK_DEFAULTS.dualspec = { showIcon = true }
end

-- The suite's spec art by talent tree position, for the nine classes WoW
-- Forever has. Rogue's Combat tree uses the outlaw art.
local SPEC_MEDIA = ns.MEDIA .. "spec\\"
local TREE_ICONS = {
    WARRIOR = { "warrior-arms", "warrior-fury", "warrior-prot" },
    PALADIN = { "paladin-holy", "paladin-prot", "paladin-ret" },
    HUNTER  = { "hunter-beastmaster", "hunter-marksman", "hunter-survival" },
    ROGUE   = { "rogue-assasin", "rogue-outlaw", "rogue-sub" },
    PRIEST  = { "priest-disc", "priest-holy", "priest-shadow" },
    SHAMAN  = { "shaman-ele", "shaman-enhance", "shaman-resto" },
    MAGE    = { "mage-arcane", "mage-fire", "mage-frost" },
    WARLOCK = { "warlock-aff", "warlock-demo", "warlock-destro" },
    DRUID   = { "druid-balance", "druid-feral", "druid-resto" },
}

-- paladin-ret's art fills more of its canvas than the rest of the set, so it
-- draws smaller, centered in the same slot so the text never shifts.
local ICON_SCALE = {
    ["paladin-ret"] = 0.9,
}

-- One spec group's build: { trees = { { name, spent }, ... } in talent window
-- order, lead = the tree with the most points (leftmost on a tie, nil with
-- nothing spent) }, or nil while the build is not readable. Called through pcall.
local function ReadGroup(group)
    local configID = C_SpecializationInfo.GetCombatConfigIDForSpecGroup(group)
    if not configID then return nil end
    local _, _, list = EllesmereUI.ForeverTalentTrees(configID, true)
    if not list or #list == 0 then return nil end
    local ids = {}
    for i = 1, #list do ids[i] = list[i].groupID end
    local spent = {}
    for _, gi in ipairs(C_Traits.GetGroupCurrencyInfo(configID, ids) or {}) do
        local c = gi.currencyInfos and gi.currencyInfos[1]
        if c then spent[gi.traitNodeGroupID] = c.spent end
    end
    local trees, lead, best = {}, nil, 0
    for i = 1, #list do
        local n = spent[list[i].groupID] or 0
        trees[i] = { name = list[i].name, spent = n }
        if n > best then lead, best = i, n end
    end
    return { trees = trees, lead = lead }
end

-- The leading talent tree's name, or the plain group name without points.
local function TreeName(group, d)
    if d and d.lead and d.trees[d.lead].name then return d.trees[d.lead].name end
    if group == 2 then return EllesmereUI.L("Secondary Spec") end
    return EllesmereUI.L("Primary Spec")
end

-- The player's own name for a group (block settings primaryLabel /
-- secondaryLabel), else its leading tree.
local LABEL_KEYS = { "primaryLabel", "secondaryLabel" }
local function GroupName(group, d, s)
    local custom = s and s[LABEL_KEYS[group]]
    if type(custom) == "string" and custom ~= "" then return custom end
    return TreeName(group, d)
end

-- "31 / 20 / 0", or "" without a readable build.
local function PointsText(d)
    if not d then return "" end
    local p = {}
    for i, t in ipairs(d.trees) do p[i] = tostring(t.spent) end
    return table.concat(p, " / ")
end

local function ActiveGroup()
    local SI = C_SpecializationInfo
    return (SI and SI.GetActiveSpecGroup and SI.GetActiveSpecGroup()) or 1
end

local function NumGroups()
    return (GetNumSpecGroups and GetNumSpecGroups()) or 1
end

ns.BlockFactories.dualspec = function(blockCfg, slot, content, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = content, ctx = barCtx }
    inst.key = K.InstKey(barCtx, blockCfg)
    -- Talent edits land as trait updates; SPELLS_CHANGED is the settled
    -- catch-all. K.RegisterInstEvents skips an event the client does not know.
    inst.events = { "PLAYER_ENTERING_WORLD", "ACTIVE_TALENT_GROUP_CHANGED",
        "TRAIT_CONFIG_UPDATED", "TRAIT_TREE_CURRENCY_INFO_UPDATED",
        "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "SPELLS_CHANGED" }

    local _, classFile = UnitClass("player")
    local icons = classFile and TREE_ICONS[classFile]
    local data = {}            -- [group] = ReadGroup result, or false
    local active, numGroups = 1, 1
    local dirty, hovered = true, false

    local button = CreateFrame("Button", nil, content)
    button:SetAllPoints()
    button:EnableMouse(true)
    button:RegisterForClicks("AnyUp")
    local icon = content:CreateTexture(nil, "OVERLAY")
    local text = content:CreateFontString(nil, "OVERLAY")
    K.AttachTextOffset(inst, text)

    local function Sample()
        dirty = false
        active, numGroups = ActiveGroup(), NumGroups()
        for g = 1, 2 do
            local ok, r = pcall(ReadGroup, g)
            data[g] = (ok and r) or false
        end
    end

    -- One tooltip row per group: its name (accent + "(Active)" for the live
    -- one) and the points per tree.
    local function GroupRow(g, s, ar, ag, ab)
        local d = data[g] or nil
        local name = GroupName(g, d, s)
        local right = PointsText(d)
        if g == active then
            ns.Tip_AddDouble(name .. " " .. EllesmereUI.L("(Active)"), right, ar, ag, ab, 1, 1, 1)
        else
            ns.Tip_AddDouble(name, right, 1, 1, 1, 1, 1, 1)
        end
    end

    local function ShowTooltip()
        local ar, ag, ab = ns.GetAccent()
        local s = blockCfg.settings or {}
        ns.Tip_Begin(button)
        ns.Tip_AddLine(EllesmereUI.L("Dual Specialization"), 1, 1, 1)
        if numGroups < 2 then
            GroupRow(active, s, ar, ag, ab)
            ns.Tip_AddLine(" ")
            ns.Tip_AddLine(EllesmereUI.L("Dual Specialization is not learned."), 0.6, 0.6, 0.6)
        else
            GroupRow(1, s, ar, ag, ab)
            GroupRow(2, s, ar, ag, ab)
        end
        ns.Tip_AddLine(" ")
        ns.Tip_AddDouble(L["LEFT_CLICK"], L["OPEN_TALENTS"], 1, 1, 1, ar, ag, ab)
        ns.Tip_AddDouble(L["RIGHT_CLICK"], EllesmereUI.L("Open Spellbook"), 1, 1, 1, ar, ag, ab)
        if numGroups >= 2 then
            ns.Tip_AddDouble(L["SHIFT_LEFT_CLICK"],
                EllesmereUI.L("Activate") .. " " .. GroupName(1, data[1] or nil, s), 1, 1, 1, ar, ag, ab)
            ns.Tip_AddDouble("|cffFFFFFF" .. EllesmereUI.L("Shift + Right Click:") .. "|r",
                EllesmereUI.L("Activate") .. " " .. GroupName(2, data[2] or nil, s), 1, 1, 1, ar, ag, ab)
        end
        ns.Tip_Show()
    end

    -- Icon tint: class color, like the retail Spec block, unless the block
    -- carries an explicit icon color.
    local function IconTint()
        if blockCfg.useIconClassColor or blockCfg.useIconAccentColor
            or blockCfg.useIconDefaultColor or blockCfg.iconColor then
            return K.IconColorOf(blockCfg)
        end
        local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
        if cc then return cc.r, cc.g, cc.b end
        return 1, 1, 1
    end

    function inst:Refresh()
        if dirty then Sample() end
        local s = blockCfg.settings or {}
        local d = data[active] or nil
        local fontSize = max(9, floor(K.CONTENT_BASE * 0.4333 + 0.5))
        local iconSz = min(fontSize + 8, max(14, floor(K.CONTENT_BASE * 0.72 + 0.5)))
        local vertical = barCtx.IsVertical()
        local barH = barCtx.GetThickness()

        ns.SetFont(text, fontSize, barCtx.cfg)
        text:SetText(GroupName(active, d, s))

        -- No points spent = no leading tree to picture.
        local file = icons and d and d.lead and icons[d.lead]
        local showIcon = s.showIcon ~= false and file ~= nil
        local drawSz, inset = iconSz, 0
        if showIcon then
            icon:SetTexture(SPEC_MEDIA .. file .. ".png")
            icon:SetTexCoord(0, 1, 0, 1)
            drawSz = floor(iconSz * (ICON_SCALE[file] or 1) + 0.5)
            inset = floor((iconSz - drawSz) / 2)
        end

        local tr, tg, tb, ir, ig, ib
        if hovered then
            tr, tg, tb = ns.GetAccent()
            ir, ig, ib = tr, tg, tb
        else
            tr, tg, tb = K.BlockColorOf(blockCfg)
            ir, ig, ib = IconTint()
        end
        text:SetTextColor(tr, tg, tb, 1)
        icon:SetVertexColor(ir, ig, ib, 1)

        icon:ClearAllPoints()
        text:ClearAllPoints()
        if vertical then
            local width = K.VSlotW(inst)
            local y = 4
            if showIcon then
                icon:SetSize(drawSz, drawSz)
                icon:SetPoint("TOP", content, "TOP", 0, -(y + inset))
                icon:Show()
                y = y + iconSz + 2
            else
                icon:Hide()
            end
            ns.SetWrappedText(text, max(24, width - 8), "CENTER")
            text:SetPoint("TOP", content, "TOP", 0, -y)
            y = y + ns.SnapToPixelGrid(text:GetStringHeight()) + 4
            content:SetSize(width, max(barH, y))
        else
            ns.ResetInlineText(text, "LEFT")
            local x = 0
            if showIcon then
                icon:SetSize(drawSz, drawSz)
                icon:SetPoint("LEFT", content, "LEFT", inset, 0)
                icon:Show()
                x = iconSz + K.ICON_GAP
            else
                icon:Hide()
            end
            text:SetPoint("LEFT", content, "LEFT", x, 0)
            content:SetSize(max(10, x + ns.SnapToPixelGrid(text:GetStringWidth()) + 4), barH)
        end
        button:ClearAllPoints()
        button:SetAllPoints(content)
        K.MaybeRelayout(inst)
        if hovered then ShowTooltip() end
    end

    -- Shift + Left Click = primary (1), Shift + Right Click = secondary (2).
    -- Asking for the group already active does nothing.
    local function ActivateGroup(target)
        -- Fresh reads: the cached state can trail a swap that just landed.
        if ActiveGroup() == target then return end
        if NumGroups() < 2 then
            EllesmereUI.PrintError(EllesmereUI.L("Dual Specialization is not learned."))
            return
        end
        if InCombatLockdown() then
            EllesmereUI.PrintError(EllesmereUI.L("Cannot change specialization during combat."))
            return
        end
        if not pcall(C_SpecializationInfo.SetActiveSpecGroup, target) then
            EllesmereUI.PrintError(EllesmereUI.L("Could not switch specialization."))
        end
    end

    button:SetScript("OnEnter", function() hovered = true; inst:Refresh() end)
    button:SetScript("OnLeave", function()
        hovered = false
        ns.Tip_Hide(button)
        inst:Refresh()
    end)
    -- Forever Essentials' routes first (its Classic windows while those are
    -- on), then the game's micro buttons, like the Micro Menu block. A plain
    -- button, so out of combat only.
    local function ClickFirst(names)
        for _, name in ipairs(names) do
            local b = _G[name]
            if b and b.Click then
                b:Click("LeftButton")
                return true
            end
        end
        return false
    end
    local function OpenTalents()
        if ClickFirst({ "EUI_TalentsRoute", "TalentMicroButton" }) then return end
        if PlayerSpellsUtil and PlayerSpellsUtil.ToggleClassTalentFrame then
            PlayerSpellsUtil.ToggleClassTalentFrame()
        elseif ToggleTalentFrame then
            ToggleTalentFrame()
        end
    end
    local function OpenSpellbook()
        if ClickFirst({ "EUI_SpellbookRoute", "SpellbookMicroButton" }) then return end
        if PlayerSpellsUtil and PlayerSpellsUtil.ToggleSpellBookFrame then
            PlayerSpellsUtil.ToggleSpellBookFrame()
        elseif _G.SpellBookFrame then
            ToggleFrame(_G.SpellBookFrame)
        end
    end

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton ~= "LeftButton" and mouseButton ~= "RightButton" then return end
        if IsShiftKeyDown() then
            ActivateGroup(mouseButton == "LeftButton" and 1 or 2)
            return
        end
        if InCombatLockdown() then
            EllesmereUI.PrintError(EllesmereUI.L("Cannot open this during combat."))
            return
        end
        ns.Tip_Hide(button)
        if mouseButton == "LeftButton" then OpenTalents() else OpenSpellbook() end
    end)

    inst.eventFrame = K.MakeEventFrame(inst, function(self)
        dirty = true
        self:Refresh()
    end)

    function inst:Enable()
        dirty = true
        content:Show()
        K.RegisterInstEvents(self)
    end
    function inst:Disable()
        K.UnregisterInstEvents(self)
        hovered = false
        ns.Tip_Hide(button)
        content:Hide()
    end
    function inst:GetAutoLength()
        if barCtx.IsVertical() then return max(content:GetHeight(), 30) end
        return max(content:GetWidth(), 24)
    end
    function inst:Destroy()
        self._dead = true
        self:Disable()
    end
    return inst
end
