if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not EllesmereUI.IS_FOREVER then return end
-- Dual Spec block (WoW Forever): the active spec group by its leading talent
-- tree, or the player's own name for it, and both groups in the tooltip. Left
-- Click opens the talents, Right Click the spellbook (a secure click, out of
-- combat, as the Micro Menu block's), Shift + Left / Right Click activates the
-- primary / secondary group. The switch is a cast that the game refuses in
-- combat, so the block says so instead of trying.

local ADDON_NAME, ns = ...
local L = ns.L
local K = ns.BlockKit
local max, min, floor = math.max, math.min, math.floor

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

-- A group's build (trees, points, lead) is the parent's
-- EllesmereUI.ForeverSpecGroupTalents, which the Loadout Manager reads too.

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
    -- Talent edits land as trait updates, a group switch as a talent update.
    -- K.RegisterInstEvents skips an event the client does not know.
    inst.events = { "PLAYER_ENTERING_WORLD", "ACTIVE_TALENT_GROUP_CHANGED",
        "TRAIT_CONFIG_UPDATED", "TRAIT_TREE_CURRENCY_INFO_UPDATED",
        "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED" }

    local _, classFile = UnitClass("player")
    local icons = classFile and TREE_ICONS[classFile]
    local data = {}            -- [group] = ForeverSpecGroupTalents result, or false
    local active, numGroups = 1, 1
    local dirty, hovered = true, false

    local icon = content:CreateTexture(nil, "OVERLAY")
    local text = content:CreateFontString(nil, "OVERLAY")
    K.AttachTextOffset(inst, text)
    -- The secure click-through over the block (EnsureButton), made out of combat.
    local button, EnsureButton
    -- A refresh that combat held back runs once at the fight's end (one key and
    -- one function per block, so a fight's events add nothing).
    local deferKey = "dualspec:" .. inst.key
    local function RefreshIfAlive()
        if not inst._dead then inst:Refresh() end
    end

    local function Sample()
        dirty = false
        active, numGroups = ActiveGroup(), NumGroups()
        for g = 1, 2 do
            data[g] = EllesmereUI.ForeverSpecGroupTalents(g) or false
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
        -- In combat every click is refused (the secure button drops its action,
        -- the switch is a cast), so the hints give way to the notice.
        if InCombatLockdown() then
            ns.Tip_AddLine(L["CANNOT_USE_COMBAT"], 0.65, 0.65, 0.65)
            ns.Tip_Show()
            return
        end
        ns.Tip_AddDouble(L["LEFT_CLICK"], L["OPEN_TALENTS"], 1, 1, 1, ar, ag, ab)
        ns.Tip_AddDouble(L["RIGHT_CLICK"], EllesmereUI.L("Open Spellbook"), 1, 1, 1, ar, ag, ab)
        if numGroups >= 2 then
            ns.Tip_AddDouble(L["SHIFT_LEFT_CLICK"],
                EllesmereUI.L("Activate") .. " " .. GroupName(1, data[1] or nil, s), 1, 1, 1, ar, ag, ab)
            ns.Tip_AddDouble(L["SHIFT_RIGHT_CLICK"],
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

    -- The text and icon colors, the accent while hovered: all a hover changes,
    -- so the hover scripts repaint these alone.
    local function Recolor()
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

        Recolor()

        -- Sizing and anchoring are protected once the secure button exists (it
        -- puts the block's bar under protection): in lockdown only the text and
        -- colors update, and the layout waits for the fight's end.
        if InCombatLockdown() then
            ns.DeferUntilOOC(deferKey, RefreshIfAlive)
            if hovered then ShowTooltip() end
            return
        end
        EnsureButton()

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

    -- Forever Essentials' routes first (its Classic windows while those are
    -- on), then the game's micro buttons, like the Micro Menu block. Looked up
    -- when the button is made: Forever Essentials loads after this addon.
    local function FirstGlobal(names)
        for _, name in ipairs(names) do
            if _G[name] then return _G[name] end
        end
    end

    -- Left / Right Click pass through to the talents / spellbook route as a
    -- secure click, so the game opens its windows from its own code. type1 /
    -- type2 carry no modifier, so a Shift click finds no action and PostClick
    -- activates a spec group instead. Refresh makes it, out of combat; anchored
    -- once, it follows the content frame's size.
    EnsureButton = function()
        if button then return end
        button = CreateFrame("Button", "EWB_DUALSPEC_" .. inst.key, content,
            "SecureActionButtonTemplate,SecureHandlerStateTemplate")
        button:SetAllPoints(content)
        -- Without this, the ActionButtonUseKeyDown CVar makes the secure handler act on key-down only, discarding our "AnyUp" clicks.
        button:SetAttribute("useOnKeyDown", false)
        button:SetAttribute("type1", "click")
        button:SetAttribute("type2", "click")
        button:SetAttribute("*clickbutton1", FirstGlobal({ "EUI_TalentsRoute", "TalentMicroButton" }))
        button:SetAttribute("*clickbutton2", FirstGlobal({ "EUI_SpellbookRoute", "SpellbookMicroButton" }))
        button:EnableMouse(true)
        button:RegisterForClicks("AnyUp")
        -- Combat: drop the click actions from inside the secure environment, as
        -- every secure Data Bars block does. A bar its visibility hides in combat
        -- cannot hide this protected button, which would otherwise stay
        -- clickable unseen. Still mouse-enabled, so the tooltip shows the notice.
        RegisterStateDriver(button, "combatlock", "[combat] combat; nocombat")
        button:SetAttribute("_onstate-combatlock", [[
            if newstate == 'combat' then
                self:SetAttribute('type1', nil)
                self:SetAttribute('type2', nil)
            else
                self:SetAttribute('type1', 'click')
                self:SetAttribute('type2', 'click')
            end
        ]])
        button:SetScript("OnEnter", function() hovered = true; Recolor(); ShowTooltip() end)
        button:SetScript("OnLeave", function(self)
            hovered = false
            ns.Tip_Hide(self)
            Recolor()
        end)
        button:SetScript("PostClick", function(self, mouseButton)
            if mouseButton ~= "LeftButton" and mouseButton ~= "RightButton" then return end
            if IsShiftKeyDown() then
                ActivateGroup(mouseButton == "LeftButton" and 1 or 2)
            elseif not InCombatLockdown() then
                -- (In combat the click did nothing: the notice stays up.)
                ns.Tip_Hide(self)
            end
        end)
    end

    -- Events only mark the builds stale. A talent change fires several at
    -- once, so one refresh on the next frame reads both groups and lays the
    -- block out a single time.
    local queued = false
    local function QueuedRefresh()
        queued = false
        RefreshIfAlive()
    end
    inst.eventFrame = K.MakeEventFrame(inst, function()
        dirty = true
        if queued then return end
        queued = true
        C_Timer.After(0, QueuedRefresh)
    end)

    -- Showing and hiding the content are protected in combat once the secure
    -- button exists.
    function inst:Enable()
        dirty = true
        if not (button and InCombatLockdown()) then content:Show() end
        K.RegisterInstEvents(self)
    end
    function inst:Disable()
        K.UnregisterInstEvents(self)
        hovered = false
        if button then ns.Tip_Hide(button) end
        if not (button and InCombatLockdown()) then content:Hide() end
    end
    function inst:GetAutoLength()
        if barCtx.IsVertical() then return max(content:GetHeight(), 30) end
        return max(content:GetWidth(), 24)
    end
    function inst:Destroy()
        self._dead = true
        self:Disable()
        if button then
            -- A parked button keeps no state driver running (out of combat only).
            local parked = button
            ns.DeferUntilOOC(deferKey .. ":lock", function()
                UnregisterStateDriver(parked, "combatlock")
            end)
            K.ParkSecureFrame(button, self.key .. "_dualspec")
            button = nil
        end
    end
    return inst
end
