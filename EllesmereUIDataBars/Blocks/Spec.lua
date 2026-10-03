if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if EllesmereUI.IS_FOREVER then return end -- one spec per class on WoW Forever, nothing to switch: no factory, no loadout hook (the main file drops the block from BLOCK_TYPES too)
-- Blocks\Spec.lua
-- Specialization block factory (spec, loot spec, loadout popups).

local ADDON_NAME, ns = ...
local L = ns.L
local MEDIA = ns.MEDIA
local K = ns.BlockKit

-- Upvalues
local CreateFrame      = CreateFrame
local UIParent         = UIParent
local InCombatLockdown = InCombatLockdown
local ipairs           = ipairs
local select           = select
local floor            = math.floor
local max              = math.max
local min              = math.min

local ICON_GAP             = K.ICON_GAP
local CONTENT_BASE         = K.CONTENT_BASE
local InstKey              = K.InstKey
local MakeEventFrame       = K.MakeEventFrame
local RegisterInstEvents   = K.RegisterInstEvents
local UnregisterInstEvents = K.UnregisterInstEvents
local HBudget              = K.HBudget
local VSlotW               = K.VSlotW
local MaybeRelayout        = K.MaybeRelayout
local AttachTextOffset     = K.AttachTextOffset
local BlockColorOf         = K.BlockColorOf
local IconColorOf          = K.IconColorOf

-------------------------------------------------------------------------------
--  SPEC (specialisation, loot-spec, loadout popups)
-------------------------------------------------------------------------------
-- Loadout-name freshness: the "last selected loadout" pointer is written AFTER
-- talent-commit events fire (TRAIT_CONFIG_UPDATED/SPELLS_CHANGED both race it and
-- read the OLD name), so hook the WRITE itself -- talent UI and loadout addons all
-- funnel through UpdateLastSelectedSavedConfigID. Skips in combat; PLAYER_REGEN_ENABLED catches up.
local specInstances = {}
local specPointerHooked = false
local function HookLoadoutPointer()
    if specPointerHooked then return end
    if not (C_ClassTalents and C_ClassTalents.UpdateLastSelectedSavedConfigID
            and hooksecurefunc) then return end
    specPointerHooked = true
    hooksecurefunc(C_ClassTalents, "UpdateLastSelectedSavedConfigID", function()
        if InCombatLockdown() then return end
        for i = 1, #specInstances do
            local si = specInstances[i]
            if not si._dead and si.Refresh then si:Refresh() end
        end
    end)
end

ns.BlockFactories.spec = function(blockCfg, slot, content, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = content, ctx = barCtx }
    inst.key = InstKey(barCtx, blockCfg)
    specInstances[#specInstances + 1] = inst
    HookLoadoutPointer()
    inst.events = { "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_LOOT_SPEC_UPDATED",
                    -- TRAIT_CONFIG_UPDATED fires BEFORE the last-selected pointer moves, so
                    -- its name read is stale; SPELLS_CHANGED fires once the swap applied
                    -- (same signal CDM keys its talent-swap rebuilds off) and re-reads the settled name.
                    "TRAIT_CONFIG_UPDATED", "SPELLS_CHANGED",
                    -- Combat cancelling a loadout swap started from this block.
                    "CONFIG_COMMIT_FAILED",
                    "PLAYER_ENTERING_WORLD",
                    -- Refresh runs in combat too (our frames only); regen is a cheap catch-up for anything a combat path missed.
                    "PLAYER_REGEN_ENABLED" }

    local SPEC_MEDIA = MEDIA .. "spec\\"
    local _specFitBuf1 = { "" }
    local _specFitBuf2 = { "" }
    -- One PNG per spec in media\spec\, named <class>-<spec>.png, listed here in SPEC
    -- INDEX order per class (GetSpecializationInfo order is fixed) -- no spec-ID table; new specs just append.
    local SPEC_ICON_FILES = {
        WARRIOR     = { "warrior-arms", "warrior-fury", "warrior-prot" },
        PALADIN     = { "paladin-holy", "paladin-prot", "paladin-ret" },
        HUNTER      = { "hunter-beastmaster", "hunter-marksman", "hunter-survival" },
        ROGUE       = { "rogue-assasin", "rogue-outlaw", "rogue-sub" },
        PRIEST      = { "priest-disc", "priest-holy", "priest-shadow" },
        DEATHKNIGHT = { "dk-blood", "dk-frost", "dk-unholy" },
        SHAMAN      = { "shaman-ele", "shaman-enhance", "shaman-resto" },
        MAGE        = { "mage-arcane", "mage-fire", "mage-frost" },
        WARLOCK     = { "warlock-aff", "warlock-demo", "warlock-destro" },
        MONK        = { "monk-brew", "monk-mw", "monk-ww" },
        DRUID       = { "druid-balance", "druid-feral", "druid-bear", "druid-resto" },
        DEMONHUNTER = { "dh-havoc", "dh-vengeance", "dh-devourer" },
        EVOKER      = { "evoker-dev", "evoker-pres", "evoker-aug" },
    }
    local POPUP_FONT_SIZE = 12
    local POPUP_PAD = 8

    local specCache, numSpecs = {}, 0
    local currentSpecIdx, currentLootSpecID = nil, 0
    local mouseOver = false

    -- Loadout swap, Blizzard's sequence: the last-selected pointer is written
    -- only once the swap is real -- immediately when no commit is needed,
    -- else on the TRAIT_CONFIG_UPDATED that lands the commit. Nothing is
    -- written up front, so a commit cancelled by combat leaves the pointer
    -- on the loadout still applied.
    local pendingSwapSpecId, pendingSwapConfigID
    local function BeginLoadoutSwap(specId, configID)
        local result = C_ClassTalents.LoadConfig(configID, true)
        local R = Enum.LoadConfigResult
        if result == R.NoChangesNecessary then
            C_ClassTalents.UpdateLastSelectedSavedConfigID(specId, configID)
        elseif result ~= R.Error then
            pendingSwapSpecId, pendingSwapConfigID = specId, configID
        end
        inst:Refresh()
    end

    -- Per-instance popup pools (lazy). Two spec blocks never fight over the same popup frames.
    local specPool, lootPool, loadoutPool

    local function D() return blockCfg.settings or {} end
    local function BC() return barCtx.cfg end

    -- Spec reads go through C_SpecializationInfo: the legacy globals are not
    -- registered on WoW Forever (same native functions on retail). The loot
    -- spec pair and GetNumSpecializations are plain globals on both clients.
    local function BuildSpecCache()
        specCache = {}; numSpecs = GetNumSpecializations() or 0
        for i = 1, numSpecs do
            local id, name, _, icon, role = C_SpecializationInfo.GetSpecializationInfo(i)
            if id then specCache[i] = { id = id, name = name, icon = icon, role = role } end
        end
    end

    local function UpdateCurrentSpec()
        currentSpecIdx    = C_SpecializationInfo.GetSpecialization()
        currentLootSpecID = GetLootSpecialization() or 0
    end

    local function GetCurrentLoadoutName()
        if not (C_ClassTalents and C_ClassTalents.GetLastSelectedSavedConfigID) then return nil end
        local specId = PlayerUtil and PlayerUtil.GetCurrentSpecID and PlayerUtil.GetCurrentSpecID()
        if not specId then return nil end
        local configID = C_ClassTalents.GetLastSelectedSavedConfigID(specId)
        if not configID then return nil end
        local info = C_Traits and C_Traits.GetConfigInfo and C_Traits.GetConfigInfo(configID)
        if info then return info.name end
        return nil
    end

    local function GetLootSpecName()
        if currentLootSpecID == 0 then
            if currentSpecIdx and specCache[currentSpecIdx] then
                return specCache[currentSpecIdx].name
            end
            return nil
        end
        local _, name
        if GetSpecializationInfoByID then _, name = GetSpecializationInfoByID(currentLootSpecID) end
        return name
    end

    local function GetBarDisplayText()
        local d = D()
        local text
        if d.showLoadout ~= false then text = GetCurrentLoadoutName() end
        if not text then
            if currentSpecIdx and specCache[currentSpecIdx] then
                text = specCache[currentSpecIdx].name
            end
        end
        if not text then text = "" end
        -- Opt-in only (default off): never force-capitalize.
        if d.useUppercase == true then return text:upper() end
        return text
    end

    local specButton = CreateFrame("Button", nil, content)
    specButton:SetAllPoints()
    specButton:EnableMouse(true)
    specButton:RegisterForClicks("AnyUp")

    local specIcon = content:CreateTexture(nil, "OVERLAY"); specIcon:SetSize(16, 16)
    local specText = content:CreateFontString(nil, "OVERLAY")
    local infoText = content:CreateFontString(nil, "OVERLAY"); infoText:Hide()
    AttachTextOffset(inst, specText)   -- infoText chains to specText

    -- Generic popup builder (shared across the three popups of THIS instance)
    local function BuildPopup(pool, parent, title, entries, onClickEntry, noCatcher, footerLines, combatClicks)
        if not pool then return nil end
        pool:ReleaseAll()
        local popup = pool._popup
        if not popup then
            popup = ns.CreatePopupFrame(parent)
            pool._popup = popup
        end
        popup._wbNoCatcher = noCatcher and true or nil
        popup._wbOnHide = function()
            pool:ReleaseAll()
            if pool._onHide then pool._onHide() end
        end
        popup:Show()

        local ar, ag, ab = ns.GetAccent()
        local fontSize = POPUP_FONT_SIZE
        local iconSz = fontSize + 2
        local PAD, LINE = POPUP_PAD, 18

        -- Title is optional: a nil/empty title (the loadout subnav) renders a plain list with even PAD margins on all four sides.
        if not popup._title then
            popup._title = popup:CreateFontString(nil, "OVERLAY")
        end
        popup._title:ClearAllPoints()
        popup._title:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD, -PAD)
        local maxW, yOff
        if title and title ~= "" then
            ns.SetFont(popup._title, fontSize)
            -- Localize here: these popups SetText directly instead of the Tip_* helpers that normally route fixed strings through the locale.
            popup._title:SetText(EllesmereUI.L(title)); popup._title:SetTextColor(1, 1, 1, 1)
            popup._title:Show()
            maxW = popup._title:GetStringWidth()
            yOff = PAD + LINE + PAD
        else
            popup._title:Hide()
            maxW = 0
            yOff = PAD
        end

        local rowBtns = {}
        for _, entry in ipairs(entries) do
            local btn = pool:Acquire()
            btn:SetParent(popup)
            -- 2px band above/below the content, matching the shared tip's clickable rows.
            btn:SetHeight(iconSz + 4)
            btn:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD, -yOff)
            btn:EnableMouse(true); btn:RegisterForClicks("AnyUp")
            -- Full-row white hover wash (house style 0.10), same as the shared tip's
            -- clickable rows; HIGHLIGHT layer needs no scripts. Color RE-ASSERTED every
            -- build: the pool resetter nils the highlight texture on every release.
            if not btn._hl then
                btn._hl = btn:CreateTexture(nil, "HIGHLIGHT")
                btn._hl:SetAllPoints()
            end
            btn._hl:SetColorTexture(1, 1, 1, 0.10)

            if not btn._icon then btn._icon = btn:CreateTexture(nil, "OVERLAY") end
            btn._icon:SetSize(iconSz, iconSz)
            btn._icon:ClearAllPoints()
            btn._icon:SetPoint("LEFT")

            if not btn._label then btn._label = btn:CreateFontString(nil, "OVERLAY") end
            btn:Show()
            ns.SetFont(btn._label, fontSize)
            btn._label:SetText(entry.name)
            btn._label:Show()
            btn._label:ClearAllPoints()
            if entry.icon then
                btn._icon:SetTexture(entry.icon)
                btn._icon:SetTexCoord(4 / 64, 60 / 64, 4 / 64, 60 / 64)
                btn._icon:Show()
                btn._label:SetPoint("LEFT", btn._icon, "RIGHT", 4, 0)
            else
                -- Icon-less rows (loadouts): flush left -- anchoring to the hidden icon's stale rect left a phantom indent.
                btn._icon:Hide()
                btn._label:SetPoint("LEFT", btn, "LEFT", 0, 0)
            end

            if entry.isActive then btn._label:SetTextColor(ar, ag, ab, 1)
            else btn._label:SetTextColor(1, 1, 1, 1) end

            -- Right-edge arrow (entry.arrow): the active spec row uses it to signal its loadout subnav.
            if entry.arrow then
                if not btn._arrow then
                    btn._arrow = btn:CreateTexture(nil, "OVERLAY")
                end
                -- FULL re-assert every build: the pool resetter hides and strips regions on release, so creation-only setup does not survive.
                btn._arrow:SetSize(10, 10)
                btn._arrow:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-right.png")
                btn._arrow:ClearAllPoints()
                btn._arrow:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
                btn._arrow:SetVertexColor(ar, ag, ab, 0.9)
                btn._arrow:Show()
            elseif btn._arrow then
                btn._arrow:Hide()
            end

            btn:SetScript("OnEnter", function()
                btn._label:SetTextColor(ar, ag, ab, 1)
                -- Row hover callback (spec popup: open/close the loadout subnav depending on which row the cursor is on).
                if entry.onHover then entry.onHover(btn) end
            end)
            btn:SetScript("OnLeave", function()
                if entry.isActive then btn._label:SetTextColor(ar, ag, ab, 1)
                else btn._label:SetTextColor(1, 1, 1, 1) end
            end)
            btn:SetScript("OnClick", function(_, mb)
                -- entry.noClick: informational row (the active spec opens a subnav instead of re-selecting itself).
                if entry.noClick then return end
                -- combatClicks: the loot-spec popup's action is combat-legal (unprotected preference call); everything else stays gated.
                if mb == "LeftButton" and (combatClicks or not InCombatLockdown()) then
                    onClickEntry(entry)
                    popup:Hide()
                end
            end)

            local iconExtra = 0
            if btn._icon:IsShown() then iconExtra = iconSz + 4 end
            local bw = iconExtra + btn._label:GetStringWidth()
            if entry.arrow then bw = bw + 16 end
            if bw > maxW then maxW = bw end
            btn:SetWidth(bw)
            rowBtns[#rowBtns + 1] = btn
            yOff = yOff + (iconSz + 4) + 3
        end
        -- Trim the last row's trailing gap so the bottom padding stays PAD.
        if #entries > 0 then yOff = yOff - 3 end

        -- Optional footer descriptor lines ({left, right} pairs): the same Left Click / Right Click hints the shared tip footers use.
        if not popup._foot then popup._foot = {} end
        local footCount = footerLines and #footerLines or 0
        if footCount > 0 then
            yOff = yOff + 8
            for i = 1, footCount do
                local fl = popup._foot[i]
                if not fl then
                    fl = { l = popup:CreateFontString(nil, "OVERLAY"),
                           r = popup:CreateFontString(nil, "OVERLAY") }
                    popup._foot[i] = fl
                end
                ns.SetFont(fl.l, fontSize); ns.SetFont(fl.r, fontSize)
                fl.l:SetText(EllesmereUI.L(footerLines[i][1])); fl.l:SetTextColor(1, 1, 1, 1)
                fl.r:SetText(EllesmereUI.L(footerLines[i][2])); fl.r:SetTextColor(1, 1, 1, 1)
                fl.l:ClearAllPoints()
                fl.l:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD, -yOff)
                fl.r:ClearAllPoints()
                fl.r:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -PAD, -yOff)
                fl.l:Show(); fl.r:Show()
                local fw = (fl.l:GetStringWidth() or 0) + 16 + (fl.r:GetStringWidth() or 0)
                if fw > maxW then maxW = fw end
                yOff = yOff + fontSize + 4
            end
            yOff = yOff - 4
        end
        for i = footCount + 1, #popup._foot do
            popup._foot[i].l:Hide(); popup._foot[i].r:Hide()
        end

        popup:SetSize(maxW + PAD * 2, yOff + PAD)
        -- Stretch every row to the popup's inner width: the wash and the click target span the full row, not just the text.
        for i = 1, #rowBtns do rowBtns[i]:SetWidth(maxW) end
        popup:ClearAllPoints()
        if barCtx.IsVertical() then
            -- Bar on the right half of the screen: popup opens to the left.
            local cx = parent:GetCenter()
            if cx and cx > UIParent:GetWidth() / 2 then
                popup:SetPoint("RIGHT", parent, "LEFT", -4, 0)
            else
                popup:SetPoint("LEFT", parent, "RIGHT", 4, 0)
            end
        else
            if barCtx.IsBarAtTop() then
                popup:SetPoint("TOP", parent, "BOTTOM", 0, -4)
            else
                popup:SetPoint("BOTTOM", parent, "TOP", 0, 4)
            end
        end
        popup:SetClampedToScreen(true)
        if popup._wbClickCatcher then
            popup._wbClickCatcher:ClearAllPoints()
            popup._wbClickCatcher:SetAllPoints(UIParent)
        end
        return popup
    end

    -- Forward-declared: the loot toggle arms it for in-combat dismissal and it is built (as a frame) below the popups.
    local hoverWatch

    -- Loadout SUBNAV: flyout beside the spec popup, opened by hovering the ACTIVE spec row (not clickable), listing its loadouts click-to-swap.
    local subnavPool
    local function CloseLoadoutSubnav()
        if subnavPool and subnavPool._popup and subnavPool._popup:IsShown() then
            subnavPool._popup:Hide()
        end
    end
    local function OpenLoadoutSubnav(rowBtn)
        if subnavPool and subnavPool._popup and subnavPool._popup:IsShown() then return end
        if not (C_ClassTalents and C_ClassTalents.GetConfigIDsBySpecID
                and C_Traits and C_Traits.GetConfigInfo) then return end
        local specId = currentSpecIdx and specCache[currentSpecIdx]
            and specCache[currentSpecIdx].id
        if not specId then return end
        if not subnavPool then subnavPool = ns.CreateFramePool("Button", UIParent) end
        local activeConfigID
        if C_ClassTalents.GetLastSelectedSavedConfigID then
            activeConfigID = C_ClassTalents.GetLastSelectedSavedConfigID(specId)
        end
        local entries = {}
        for _, cid in ipairs(C_ClassTalents.GetConfigIDsBySpecID(specId) or {}) do
            local info = C_Traits.GetConfigInfo(cid)
            if info and info.name then
                entries[#entries + 1] = { name = info.name, isActive = (cid == activeConfigID), configID = cid }
            end
        end
        if #entries == 0 then return end
        local pop = BuildPopup(subnavPool, specButton, nil, entries, function(e)
            BeginLoadoutSwap(specId, e.configID)
        end, true)
        -- Flyout anchoring: flush against the spec popup's edge, with its
        -- FIRST entry level with the row the cursor is on, so a straight
        -- rightward move lands inside the list. Anchoring to the popup with
        -- a row-derived offset, rather than to the row button itself, keeps
        -- the anchor between two long-lived frames: the rows are POOLED and
        -- ResetPooledFrame clears their points on release, which _wbOnHide
        -- does BEFORE it closes this flyout. Vertical overflow is left to
        -- SetClampedToScreen (already set), so the flyout only bumps when it
        -- would leave the screen.
        local main = specPool and specPool._popup
        if pop and main then
            local mainTop = main:GetTop()
            local rowTop  = rowBtn and rowBtn.GetTop and rowBtn:GetTop()
            local dy = 0
            if mainTop and rowTop then dy = POPUP_PAD - (mainTop - rowTop) end
            pop:ClearAllPoints()
            local right = main:GetRight() or 0
            if right + (pop:GetWidth() or 0) > UIParent:GetWidth() then
                pop:SetPoint("TOPRIGHT", main, "TOPLEFT", 0, dy)
            else
                pop:SetPoint("TOPLEFT", main, "TOPRIGHT", 0, dy)
            end
        end
    end

    local function ToggleSpecPopup()
        if specPool and specPool._popup and specPool._popup:IsShown() then
            specPool._popup:Hide(); return
        end
        if not specPool then specPool = ns.CreateFramePool("Button", UIParent) end
        -- Any path that hides the spec popup takes the loadout subnav with it.
        specPool._onHide = CloseLoadoutSubnav
        local entries = {}
        for i = 1, numSpecs do
            local info = specCache[i]
            if info then
                local isActive = (i == currentSpecIdx)
                entries[#entries + 1] = {
                    name = info.name, icon = info.icon, isActive = isActive,
                    specIndex = i,
                    -- Active spec: not clickable; hover opens the loadout subnav (arrow marks it), any other row closes it.
                    noClick = isActive,
                    arrow = isActive,
                    onHover = isActive and OpenLoadoutSubnav or CloseLoadoutSubnav,
                }
            end
        end
        BuildPopup(specPool, specButton, L["CHANGE_SPEC"], entries, function(e)
            C_SpecializationInfo.SetSpecialization(e.specIndex)
        end, true, {
            { L["LEFT_CLICK"],       L["CHANGE_SPEC_SHORT"] },
            { L["CTRL_LEFT_CLICK"],  L["CHANGE_LOADOUT"] },
            { L["SHIFT_LEFT_CLICK"], L["OPEN_TALENTS"] },
            { L["RIGHT_CLICK"],      L["CHANGE_LOOT_SPEC"] },
        })
    end

    local function ToggleLootSpecPopup()
        if lootPool and lootPool._popup and lootPool._popup:IsShown() then
            lootPool._popup:Hide(); return
        end
        if not lootPool then lootPool = ns.CreateFramePool("Button", UIParent) end
        local activeIcon = nil
        if currentSpecIdx and specCache[currentSpecIdx] then activeIcon = specCache[currentSpecIdx].icon end
        local entries = { {
            name = L["CURRENT_SPEC"],
            icon = activeIcon,
            isActive = currentLootSpecID == 0,
            specIndex = 0,
        } }
        for i = 1, numSpecs do
            local info = specCache[i]
            if info then
                entries[#entries + 1] = { name = info.name, icon = info.icon, isActive = (info.id == currentLootSpecID), specIndex = i }
            end
        end
        -- Loot spec switching is combat-legal: SetLootSpecialization is an
        -- unprotected server-preference call. In lockdown the popup opens
        -- WITHOUT the fullscreen click-catcher (an invisible click-eater must
        -- never go live in combat) and dismisses via the hover watcher.
        local inCombat = InCombatLockdown()
        BuildPopup(lootPool, specButton, L["CHANGE_LOOT_SPEC"], entries, function(e)
            local id = 0
            if e.specIndex > 0 then id = select(1, C_SpecializationInfo.GetSpecializationInfo(e.specIndex)) or 0 end
            SetLootSpecialization(id)
        end, inCombat, nil, true)
        if inCombat and hoverWatch then
            hoverWatch._watchPool = lootPool
            hoverWatch:Show()
        end
    end

    local function ToggleLoadoutPopup()
        if loadoutPool and loadoutPool._popup and loadoutPool._popup:IsShown() then
            loadoutPool._popup:Hide(); return
        end
        if not (C_ClassTalents and C_ClassTalents.GetConfigIDsBySpecID and C_Traits and C_Traits.GetConfigInfo) then return end
        if not loadoutPool then loadoutPool = ns.CreateFramePool("Button", UIParent) end

        local specId = nil
        if currentSpecIdx and specCache[currentSpecIdx] then specId = specCache[currentSpecIdx].id end
        if not specId then return end
        local activeConfigID = nil
        if C_ClassTalents.GetLastSelectedSavedConfigID then
            activeConfigID = C_ClassTalents.GetLastSelectedSavedConfigID(specId)
        end
        local configIDs = C_ClassTalents.GetConfigIDsBySpecID(specId)
        local entries = {}
        for _, cid in ipairs(configIDs) do
            local info = C_Traits.GetConfigInfo(cid)
            if info and info.name then
                entries[#entries + 1] = { name = info.name, isActive = (cid == activeConfigID), configID = cid }
            end
        end
        -- In lockdown: catcher-free + hover-watch dismissal like the loot popup.
        -- Row clicks stay gated (LoadConfig is blocked); the list is viewable.
        local inCombat = InCombatLockdown()
        BuildPopup(loadoutPool, specButton, L["CHANGE_LOADOUT"], entries, function(e)
            BeginLoadoutSwap(specId, e.configID)
        end, inCombat)
        if inCombat and hoverWatch then
            hoverWatch._watchPool = loadoutPool
            hoverWatch:Show()
        end
    end

    local function HideAllPopups()
        if specPool    and specPool._popup    and specPool._popup:IsShown()    then specPool._popup:Hide()    end
        if lootPool    and lootPool._popup    and lootPool._popup:IsShown()    then lootPool._popup:Hide()    end
        if loadoutPool and loadoutPool._popup and loadoutPool._popup:IsShown() then loadoutPool._popup:Hide() end
    end

    function inst:Refresh()
        -- No combat gate: only our own insecure frames (text, textures, sizes),
        -- and an in-combat loot spec change must repaint immediately.
        UpdateCurrentSpec()
        local d = D()
        local barCfg = BC()
        local barH = barCtx.GetThickness()
        local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
        -- Loot spec rides smaller than the main label (11px at the 30 base).
        local infoSz   = max(8, floor(CONTENT_BASE * 0.36 + 0.5))
        local gap = 4
        -- Icon -> content spacing only; text-to-text rows (loot spec info
        -- after the main label) keep the tighter gap above.
        local iconGap = ICON_GAP
        local ar, ag, ab = ns.GetAccent()
        local isSide = barCtx.IsVertical()
        local specLabel = GetBarDisplayText()

        if isSide then
            local slotW = VSlotW(inst)
            local innerW = max(30, slotW - 8)
            _specFitBuf1[1] = specLabel
            local lootNameForFit = GetLootSpecName()
            if lootNameForFit then
                if d.useUppercase ~= false then
                    _specFitBuf2[1] = lootNameForFit:upper()
                else
                    _specFitBuf2[1] = lootNameForFit
                end
            end
        end
        local iconSz = fontSize + 8

        ns.SetFont(specText, fontSize, barCfg); ns.SetFont(infoText, infoSz, barCfg)
        specText:SetText(specLabel)

        if currentSpecIdx then
            local _, classId = UnitClass("player")
            local files = classId and SPEC_ICON_FILES[classId]
            local file = files and files[currentSpecIdx]
            local spec = specCache[currentSpecIdx]
            -- Blizzard style: the game's own spec icon, cropped off its border.
            if (blockCfg.settings or {}).iconStyle == "wow" and spec and spec.icon then
                specIcon:SetTexture(spec.icon)
                K.CropStockIcon(specIcon)
            elseif file then
                specIcon:SetTexture(SPEC_MEDIA .. file .. ".png")
                specIcon:SetTexCoord(0, 1, 0, 1)
            end
        end

        if mouseOver then
            specText:SetTextColor(ar, ag, ab, 1); specIcon:SetVertexColor(ar, ag, ab, 1)
        else
            local br, bgr, bb = BlockColorOf(blockCfg)
            local ir, ig, ib = IconColorOf(blockCfg)
            specText:SetTextColor(br, bgr, bb, 1); specIcon:SetVertexColor(ir, ig, ib, 1)
        end

        local lootName = GetLootSpecName()
        local activeSpecName = nil
        if currentSpecIdx and specCache[currentSpecIdx] then activeSpecName = specCache[currentSpecIdx].name end
        if lootName and lootName ~= activeSpecName then
            if d.useUppercase ~= false then
                infoText:SetText("(" .. lootName:upper() .. ")")
            else
                infoText:SetText("(" .. lootName .. ")")
            end
            infoText:SetTextColor(1, 1, 1, 0.8); infoText:Show()
        else
            infoText:Hide()
        end

        -- Show Icon (default ON): hidden drops the icon width and gap entirely.
        local showIcon = d.showIcon ~= false
        if showIcon then specIcon:Show() else specIcon:Hide(); iconSz = 0 end

        if isSide then
            iconSz = min(iconSz, max(14, floor(CONTENT_BASE * 0.72 + 0.5)))
            if not showIcon then iconSz = 0 end
        end
        if showIcon then specIcon:SetSize(iconSz, iconSz) end

        if isSide then
            local slotW = VSlotW(inst)
            local innerW = max(30, slotW - 8)
            local totalH = 8 + iconSz + 2

            specIcon:ClearAllPoints()
            specIcon:SetPoint("TOP", content, "TOP", 0, -4)

            ns.SetWrappedText(specText, innerW, "CENTER")
            specText:ClearAllPoints()
            if showIcon then
                specText:SetPoint("TOP", specIcon, "BOTTOM", 0, -2)
            else
                specText:SetPoint("TOP", content, "TOP", 0, -4)
            end
            totalH = totalH + ns.SnapToPixelGrid(specText:GetStringHeight())

            if infoText:IsShown() then
                ns.SetWrappedText(infoText, innerW, "CENTER")
                infoText:ClearAllPoints()
                infoText:SetPoint("TOP", specText, "BOTTOM", 0, -2)
                totalH = totalH + 2 + ns.SnapToPixelGrid(infoText:GetStringHeight())
            end

            totalH = max(totalH, barH)
            content:SetSize(slotW, totalH)
        else
            local slotW = HBudget(inst, 120)
            local textBudget = max(30, slotW - iconSz - gap - 8)
            _specFitBuf1[1] = specLabel
            ns.SetFont(specText, fontSize, barCfg)
            specText:SetText(specLabel)
            if infoText:IsShown() then
                local infoLabel = infoText:GetText() or ""
                _specFitBuf2[1] = infoLabel
                ns.SetFont(infoText, infoSz, barCfg)
            end
            if showIcon then
                iconSz = min(fontSize + 8, max(14, floor(CONTENT_BASE * 0.72 + 0.5)))
                specIcon:SetSize(iconSz, iconSz)
            else
                iconSz = 0
            end
            ns.ResetInlineText(specText, "LEFT")
            ns.ResetInlineText(infoText, "LEFT")
            local tw = ns.SnapToPixelGrid(specText:GetStringWidth())
            -- Loot spec sits INLINE right of the spec/loadout label (below on
            -- vertical bars); content width includes it so Auto bars reserve it.
            local iw = 0
            if infoText:IsShown() then
                iw = ns.SnapToPixelGrid(infoText:GetStringWidth() or 0)
            end
            local infoPad = 0
            if iw > 0 then infoPad = gap + iw end
            local effIconGap = showIcon and iconGap or 0
            local totalW = min(slotW, iconSz + effIconGap + tw + infoPad + 4)
            specIcon:ClearAllPoints(); specIcon:SetPoint("LEFT", content, "LEFT", 0, 0)
            specText:ClearAllPoints(); specText:SetPoint("LEFT", content, "LEFT", iconSz + effIconGap, 0)
            infoText:ClearAllPoints(); infoText:SetPoint("LEFT", specText, "RIGHT", gap, 0)
            content:SetSize(totalW, barH)
        end
        specButton:ClearAllPoints(); specButton:SetAllPoints(content)
        MaybeRelayout(inst)
    end

    -- The spec popup opens on hover, closes only once the cursor is over neither
    -- the block nor the popup; both rects padded 8px so the 4px anchor gap never counts as "outside" mid-travel.
    hoverWatch = CreateFrame("Frame")
    hoverWatch:Hide()
    hoverWatch:SetScript("OnUpdate", function(self)
        -- Watches whichever pool armed it (spec hover popup, or loot popup
        -- opened catcher-free in combat). The subnav counts as inside-bounds.
        local pool = self._watchPool or specPool
        local popup = pool and pool._popup
        if not (popup and popup:IsShown()) then self:Hide(); return end
        local sub = subnavPool and subnavPool._popup
        local subShown = sub and sub:IsShown()
        if specButton:IsMouseOver(8, -8, -8, 8) or popup:IsMouseOver(8, -8, -8, 8)
           or (subShown and sub:IsMouseOver(8, -8, -8, 8)) then return end
        popup:Hide()
        if subShown then sub:Hide() end
        self:Hide()
    end)

    specButton:SetScript("OnEnter", function()
        mouseOver = true; inst:Refresh()
        -- No combat gate: the hover popup is our own insecure frames, opens
        -- catcher-free and dismisses via the hover watcher; only swap clicks
        -- are gated. Never stomp a click-opened popup (loot spec / loadout).
        if lootPool and lootPool._popup and lootPool._popup:IsShown() then return end
        if loadoutPool and loadoutPool._popup and loadoutPool._popup:IsShown() then return end
        if not (specPool and specPool._popup and specPool._popup:IsShown()) then
            ToggleSpecPopup()
        end
        hoverWatch._watchPool = specPool
        hoverWatch:Show()
    end)
    specButton:SetScript("OnLeave", function() mouseOver = false; inst:Refresh() end)
    specButton:SetScript("OnClick", function(_, button)
        -- No blanket combat gate: popups open catcher-free in lockdown and the talent
        -- frame is viewable in combat; only swapping ROW clicks are locked (loot spec is legal).
        if button == "LeftButton" then
            if IsControlKeyDown() then
                if loadoutPool and loadoutPool._popup and loadoutPool._popup:IsShown() then loadoutPool._popup:Hide(); return end
                HideAllPopups(); ToggleLoadoutPopup()
            elseif IsShiftKeyDown() then
                HideAllPopups()
                if PlayerSpellsUtil and PlayerSpellsUtil.ToggleClassTalentFrame then PlayerSpellsUtil.ToggleClassTalentFrame()
                elseif ToggleTalentFrame then ToggleTalentFrame() end
            end
        elseif button == "RightButton" then
            if lootPool and lootPool._popup and lootPool._popup:IsShown() then lootPool._popup:Hide(); return end
            HideAllPopups(); ToggleLootSpecPopup()
        end
    end)

    inst.eventFrame = MakeEventFrame(inst, function(self, event, eventConfigID)
        if pendingSwapConfigID then
            if event == "TRAIT_CONFIG_UPDATED" then
                -- The commit-landing event carries the ACTIVE combat config's id,
                -- never the loadout's. Updates for any other config (loadout
                -- saves/syncs, hero-talent data -- instance background churn) are
                -- not the commit; the pointer is written from the remembered
                -- loadout id once the active config reports the landing.
                local active = C_ClassTalents.GetActiveConfigID
                    and C_ClassTalents.GetActiveConfigID()
                if active and eventConfigID == active then
                    local specId, configID = pendingSwapSpecId, pendingSwapConfigID
                    pendingSwapSpecId, pendingSwapConfigID = nil, nil
                    C_ClassTalents.UpdateLastSelectedSavedConfigID(specId, configID)
                end
            elseif event == "CONFIG_COMMIT_FAILED" then
                -- Payload deliberately not consulted: a failed commit while we are
                -- pending is ours, whichever id it names.
                pendingSwapSpecId, pendingSwapConfigID = nil, nil
            end
        end
        self:Refresh()
    end)

    function inst:Enable()
        content:Show()
        BuildSpecCache()
        UpdateCurrentSpec()
        RegisterInstEvents(self)
    end

    function inst:Disable()
        UnregisterInstEvents(self)
        HideAllPopups()
        content:Hide()
    end

    function inst:GetAutoLength()
        local barH = barCtx.GetThickness()
        if barCtx.IsVertical() then
            local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
            local iconSz = min(fontSize + 8, max(14, floor(CONTENT_BASE * 0.72 + 0.5)))
            local textH = specText:GetStringHeight() or fontSize
            local infoH = 0
            if infoText:IsShown() then infoH = (infoText:GetStringHeight() or 0) + 2 end
            return max(8 + iconSz + 2 + textH + infoH + 4, barH, 60)
        end
        return max(content:GetWidth() or 120, 40)
    end

    function inst:Destroy()
        self._dead = true
        HideAllPopups()
        content:Hide()
    end

    return inst
end
