if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Minimap_Lifecycle.lua
--
--  Opacity, icon scale, visibility, ApplyAll, the micro menu, OnInitialize,
--  OnEnable and the Farming HUD compatibility.
--  Reads the earlier Minimap files through ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIMinimap.lua or an earlier EUI_Minimap_*.lua file failed to load.
if not I or I.broken then return end
I.broken = true

local defaults, EBS, GetFFD = I.defaults, I.EBS, I.GetFFD
local flyoutSavedRegions, ApplyOmniumFolio = I.flyoutSavedRegions, I.ApplyOmniumFolio
local ApplyMinimap, SetMMKeyHidden = I.ApplyMinimap, I.SetMMKeyHidden
local SetApplyAll = I.SetApplyAll

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._internals, which hands the value to every copy.
local _mmKeyHidden
I.mmKeyHiddenSetters[#I.mmKeyHiddenSetters + 1] = function(v) _mmKeyHidden = v end

-- Assigned below; SetApplyAll hands it to EllesmereUIMinimap.lua. It runs
-- once, at load.
local ApplyAll

-------------------------------------------------------------------------------
--  Visibility (registered with the shared EllesmereUI visibility dispatcher)
-------------------------------------------------------------------------------
-- Opacity (the Visibility cog): the alpha every SHOWN state of the map uses. Hiding
-- stays a real Show()/Hide() in every mode; this only dims a map that is on screen, so
-- every path that shows the map (the apply pass, the visibility pass, the mouseover
-- reveal) writes this value, never a bare 1. Frame alpha is inherited, so everything
-- parented to the map (border, stock chrome, text boxes, buttons, other addons' pins)
-- dims with it; the engine-drawn blips do not (see the mouseover note below).
-- SetAlpha is not a protected call, so it is legal in combat too.
-- Floor 10: below it the map is invisible yet still takes clicks, pings and the wheel;
-- hiding it is Visibility's job. EBS fields, not locals.
-- An open Farming HUD owns the reparented map, so it stays at full alpha until the
-- HUD's hide edge hands the Opacity back.
function EBS._MapAlpha(p)
    if FarmHud and FarmHud:IsShown() then return 1 end
    local o = p and p.opacity
    if type(o) ~= "number" then return 1 end
    return Clamp(o, 10, 100) / 100
end

-- Write the map alpha only when it differs from the stored one (GetAlpha returns the
-- stored float, hence the tolerance); a secret stored alpha is simply overwritten.
function EBS._WriteMapAlpha(mm, p)
    local a = EBS._MapAlpha(p)
    local cur = mm:GetAlpha()
    if issecretvalue(cur) or math.abs(cur - a) > 0.001 then
        mm:SetAlpha(a)
    end
end

-- Opacity setting change or HUD edge: one alpha write, whatever the visibility state.
function EBS._ApplyMapAlpha()
    local p = EBS.db and EBS.db.profile and EBS.db.profile.minimap
    if Minimap and p and p.enabled then EBS._WriteMapAlpha(Minimap, p) end
end

-- Icon Size (the Size row's cog): the scale of the icons on the map, the same
-- property Blizzard's Edit Mode "Icon Size" sets through MinimapCluster:SetIconScale.
-- Ours goes straight to the map, so the Edit Mode layout is never written; unset
-- (nil) leaves Edit Mode's own value. Edit Mode re-applies its value on every
-- layout apply, so a post-hook on that call puts ours back (installed with the
-- first value; it returns at once while the setting is unset).
-- Edit Mode's current Icon Size (percent), or nil before its layout is applied.
function EBS._EditModeIconScale()
    local c = MinimapCluster
    local s = Enum and Enum.EditModeMinimapSetting and Enum.EditModeMinimapSetting.IconScale
    if not (c and s ~= nil and c.GetSettingValue) then return nil end
    local ok, v = pcall(c.GetSettingValue, c, s)
    if ok and type(v) == "number" and v > 0 then return v end
    return nil
end
function EBS._ApplyMinimapIconScale()
    local p = EBS.db and EBS.db.profile and EBS.db.profile.minimap
    local v = p and p.iconScale
    if not (Minimap and Minimap.SetIconScale) then return end
    local d = GetFFD(Minimap)
    if not v then
        -- Unset after a value (a profile swap): hand the map back Edit Mode's.
        if d.iconScaleSet then
            d.iconScaleSet = nil
            local ev = EBS._EditModeIconScale()
            if ev then Minimap:SetIconScale(ev / 100) end
        end
        return
    end
    Minimap:SetIconScale(v / 100)
    d.iconScaleSet = true
    if not d.iconScaleHooked and MinimapCluster and MinimapCluster.SetIconScale then
        d.iconScaleHooked = true
        hooksecurefunc(MinimapCluster, "SetIconScale", function()
            local m = EBS.db and EBS.db.profile and EBS.db.profile.minimap
            if m and m.iconScale then Minimap:SetIconScale(m.iconScale / 100) end
        end)
    end
end

-- Edit Mode's selection box on the minimap cluster ignores the cluster's alpha 0
-- and stays mouse-enabled, so it would show and drag an empty Blizzard minimap:
-- alpha 0 with the mouse off, on that one frame only. Edit Mode never resets
-- either, so one write holds; the minimap stays ours until a reload.
function EBS._SuppressMinimapSelection()
    local sel = MinimapCluster and MinimapCluster.Selection
    if not sel then return end
    local d = GetFFD(sel)
    if d.suppressed then return end
    d.suppressed = true
    sel:SetAlpha(0)
    sel:EnableMouse(false)
end

-- Currently registered secure driver string, nil when none is registered.
local _mmDriverStr

-- Compile the profile's selection into macro-conditional grammar for the secure driver, or nil when it cannot be expressed as one.
local function MinimapDriverString(p, vm)
    -- An applied Visibility override replaces the whole setting: a constant, and the
    -- shared selection underneath never reaches the driver.
    local visOv = EllesmereUI.VisOverrideValue(p)
    if visOv then return (visOv == "never") and "hide" or "show" end
    -- Any match: Lua-only lanes (instances, housing, skyriding mount) are resolved at
    -- build time (caller runs out of combat only); a later zone/mount edge re-runs the
    -- dispatcher and re-registers the string.
    if p.visibilityMatch == "any" and EllesmereUI.BuildAnyMatchTail then
        return (EllesmereUI.BuildAnyMatchTail(p, "visibility", vm))
    end
    if vm then
        return EllesmereUI.BuildVisibilityDriverString("", vm)
    end
    local mode = p.visibility
    if mode == "in_combat" then return "[combat] show; hide" end
    if mode == "out_of_combat" then return "[nocombat] show; hide" end
    return nil
end

local function UpdateMinimapVisibility()
    local p = EBS.db and EBS.db.profile and EBS.db.profile.minimap
    local minimap = Minimap
    if not minimap then return end
    if not p or not p.enabled then
        -- Module off: hand visibility back to Blizzard instead of leaving a driver on.
        if _mmDriverStr and not InCombatLockdown() then
            UnregisterStateDriver(minimap, "visibility")
            _mmDriverStr = nil
        end
        return
    end

    -- Opacity first, in every branch (the driver's, and in combat): the alpha is ours
    -- whoever owns Show()/Hide(), and a hidden map carries it into its next Show().
    EBS._WriteMapAlpha(minimap, p)

    -- Minimap:Show()/Hide() is protected during lockdown, and combat transitions deliver
    -- inside lockdown (PLAYER_REGEN_DISABLED already reports InCombatLockdown), so
    -- skipping the update would leave "Out of Combat" permanently visible and "In Combat"
    -- permanently hidden. Alpha is no stand-in: engine-drawn blips ignore frame alpha,
    -- and a transparent map still takes the mouse. A secure state driver is the only thing that can legally hide this frame mid-combat, so combat-dependent selections get one; others keep plain Show()/Hide().
    local vm = EllesmereUI.GetActiveVisibilityModes(p, "visibility")
    -- Mouseover cannot be expressed as a macro conditional, and the poll's own Show()/Hide() would fight a driver, so those selections stay on Lua.
    local want = not _mmKeyHidden
        and EllesmereUI.VisDependsOnCombat(p, "visibility")
        and not (vm and vm.mouseover)
        and MinimapDriverString(p, vm)
        or nil
    if want ~= _mmDriverStr and not InCombatLockdown() then
        -- Registering evaluates immediately (Show()s/Hide()s the frame), so only swap out of combat; the dispatcher re-fires on PLAYER_REGEN_ENABLED to finish.
        if want then
            RegisterStateDriver(minimap, "visibility", want)
        else
            UnregisterStateDriver(minimap, "visibility")
        end
        _mmDriverStr = want
    end
    -- The driver owns Show()/Hide() from here; the alpha set above is all this pass adds.
    if _mmDriverStr then return end

    if InCombatLockdown() then return end
    local vis = EllesmereUI.EvalVisibility(p)
    if _mmKeyHidden then
        minimap:Hide()
    elseif vis == "mouseover" then
        -- Mouseover idle is a real Hide(), not alpha 0: frame alpha does not cover
        -- everything drawn on this frame, so an alpha-0 map still left its icons on
        -- screen until the first hover. Hide() is also exactly what the shared
        -- mouseover poll applies, so both ends of the mode agree. Shown (not hidden)
        -- while the cursor already sits on the map, so a re-apply mid-hover cannot blink.
        if minimap:IsMouseOver() then minimap:Show() else minimap:Hide() end
    elseif vis then
        minimap:Show()
    else
        minimap:Hide()
    end
end

-- Blizzard's Toggle Minimap keybind (ToggleMinimap) hides the map with a plain Hide(),
-- which our visibility passes would undo on their next run, so the key's state is kept
-- for the session. Blizzard ignores the key while a game rule disables the minimap, and
-- so does this; only the minimap's own visibility is re-applied, and only while the
-- module runs.
hooksecurefunc("ToggleMinimap", function()
    if C_GameRules.IsGameRuleActive(Enum.GameRule.MinimapDisabled) then return end
    SetMMKeyHidden(not Minimap:IsShown())
    local p = EBS.db and EBS.db.profile and EBS.db.profile.minimap
    if p and p.enabled then UpdateMinimapVisibility() end
end)

-------------------------------------------------------------------------------
--  Apply All
-------------------------------------------------------------------------------
ApplyAll = function()
    ApplyMinimap()
    if EllesmereUI.RequestVisibilityUpdate then
        C_Timer.After(0, EllesmereUI.RequestVisibilityUpdate)
    end
end
SetApplyAll(ApplyAll)

-------------------------------------------------------------------------------
--  Minimap Micro Menu (middle-click popup, taint-free): SecureActionButtonTemplate
--  buttons with click passthrough to Blizzard MicroButtons via RegisterStateDriver.
--  NEVER call EnableMouse or SetAlpha on them after creation -- breaks the secure
--  trust chain. Show/hide moves the parent frame offscreen.
-------------------------------------------------------------------------------
do
    local menuFrame
    local menuOpen    = false
    local MENU_WIDTH  = 160
    local BUTTON_H    = 20
    local PADDING     = 6
    local DIVIDER_H   = 9

    local menuItems = {
        { text = "Character",       microButton = "CharacterMicroButton" },
        { text = "Talents",         microButton = "PlayerSpellsMicroButton" },
        { text = "Professions",     microButton = "ProfessionMicroButton" },
        { divider = true },
        { text = "Group Finder",    microButton = "LFDMicroButton" },
        { text = "Adventure Guide", microButton = "EJMicroButton" },
        { text = "Achievements",    microButton = "AchievementMicroButton" },
        { text = "Collections",     microButton = "CollectionsMicroButton" },
        { text = "Quest Log",       microButton = "QuestLogMicroButton" },
        { divider = true },
        { text = "Friends",         microButton = "QuickJoinToastButton" },
        { text = "Guild",           microButton = "GuildMicroButton" },
        { text = "Housing",         microButton = "HousingMicroButton" },
        { text = "Calendar",        fn = function() if ToggleCalendar then ToggleCalendar() end end },
        { divider = true },
        { text = "Game Menu",       fn = function() ToggleFrame(GameMenuFrame) end },
        { text = "Shop",            microButton = "StoreMicroButton" },
        { text = "Support",         microButton = "HelpMicroButton" },
    }

    local function SetMenuVisible(visible)
        if not menuFrame then return end
        menuOpen = visible
        menuFrame:ClearAllPoints()
        if visible then
            menuFrame:SetClampedToScreen(true)
            menuFrame:SetPoint("TOPRIGHT", Minimap, "TOPLEFT", -4, 0)
        else
            menuFrame:SetClampedToScreen(false)
            menuFrame:SetPoint("TOPLEFT", UIParent, "TOPRIGHT", 10000, 0)
        end
    end

    local function CreateMenuFrame()
        -- Never register this with the controller cursor (nor the escape
        -- proxy): it stays shown while parked off-screen, so the cursor would
        -- count it as open forever and hold the D-pad.
        menuFrame = CreateFrame("Frame", "EllesmereUIMicroMenu", UIParent, "BackdropTemplate")
        menuFrame:SetFrameStrata("TOOLTIP")
        menuFrame:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        menuFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.97)
        menuFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        menuFrame:EnableMouse(true)

        -- Close when clicking elsewhere
        menuFrame:RegisterEvent("GLOBAL_MOUSE_DOWN")
        menuFrame:SetScript("OnEvent", function(self, event)
            if event == "GLOBAL_MOUSE_DOWN" and menuOpen then
                if not self:IsMouseOver() then SetMenuVisible(false) end
            end
        end)

        local y = -PADDING
        for _, item in ipairs(menuItems) do
            if item.divider then
                local div = menuFrame:CreateTexture(nil, "ARTWORK")
                div:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 8, y - 4)
                div:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -8, y - 4)
                div:SetHeight(1)
                div:SetColorTexture(0.3, 0.3, 0.3, 0.6)
                y = y - DIVIDER_H
            elseif item.fn then
                -- Plain button (no secure template needed)
                local btn = CreateFrame("Button", nil, menuFrame)
                btn:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 1, y)
                btn:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -1, y)
                btn:SetHeight(BUTTON_H)

                local hl = btn:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 1, 1, 0.08)

                local label = btn:CreateFontString(nil, "OVERLAY")
                EllesmereUI.PrimeFontShadow(label, true)
                label:SetFont((EllesmereUI.GetFontPath("minimap"))
                    or "Fonts\\FRIZQT__.TTF", 11, "")
                label:SetPoint("LEFT", btn, "LEFT", 10, 0)
                label:SetTextColor(0.9, 0.9, 0.9)
                label:SetText(EllesmereUI.L(item.text))

                local itemFn = item.fn
                btn:SetScript("OnClick", function()
                    SetMenuVisible(false)
                    itemFn()
                end)

                y = y - BUTTON_H
            else
                -- Secure click passthrough to a Blizzard MicroButton
                local microRef = item.microButton and _G[item.microButton]
                local btnName = "EUI_MicroMenu_" .. item.text:gsub("%s", "")
                local btn = CreateFrame("Button", btnName, menuFrame, "SecureActionButtonTemplate,SecureHandlerStateTemplate")
                btn:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 1, y)
                btn:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -1, y)
                btn:SetHeight(BUTTON_H)

                -- "/click <name>" macro transport: the 12.1 "click" secure action
                -- crashes on a Blizzard typo (SecureTemplates:564); MicroButtons are globally named so the macro reaches them directly.
                local secureType = "macro"
                if microRef then
                    btn:SetAttribute("*macrotext1", "/click " .. item.microButton)
                end
                btn:SetAttribute("useOnKeyDown", false)
                btn:SetAttribute("*type1", secureType)
                btn:EnableMouse(true)
                btn:RegisterForClicks("AnyUp")

                -- Activate secure click from the restricted environment; without this,
                -- addon-set attributes are not trusted. The restore branch MUST match
                -- the transport above -- a mismatched type silently reverts the 12.1 macro transport on the first combat exit.
                RegisterStateDriver(btn, "combatlock", "[combat] combat; nocombat")
                btn:SetAttribute("_onstate-combatlock", ([[
                    if newstate == 'combat' then
                        self:SetAttribute('*type1', nil)
                        self:EnableMouse(false)
                    else
                        self:SetAttribute('*type1', '%s')
                        self:EnableMouse(true)
                    end
                ]]):format(secureType))

                local hl = btn:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 1, 1, 0.08)

                local label = btn:CreateFontString(nil, "OVERLAY")
                EllesmereUI.PrimeFontShadow(label, true)
                label:SetFont((EllesmereUI.GetFontPath("minimap"))
                    or "Fonts\\FRIZQT__.TTF", 11, "")
                label:SetPoint("LEFT", btn, "LEFT", 10, 0)
                label:SetTextColor(0.9, 0.9, 0.9)
                label:SetText(EllesmereUI.L(item.text))

                btn:HookScript("OnClick", function() C_Timer.After(0, function() SetMenuVisible(false) end) end)

                y = y - BUTTON_H
            end
        end

        menuFrame:SetSize(MENU_WIDTH, -y + PADDING)
        menuFrame:Show()
        SetMenuVisible(false)
    end

    local function ToggleMicroMenu()
        if InCombatLockdown() then
            UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1.0, 0.3, 0.3, 1.0)
            return
        end
        if not menuFrame then CreateMenuFrame() end
        SetMenuVisible(not menuOpen)
    end
    EBS._ToggleMicroMenu = ToggleMicroMenu

    local hookFrame = CreateFrame("Frame")
    hookFrame:RegisterEvent("PLAYER_LOGIN")
    hookFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        CreateMenuFrame()
    end)
end

function EBS:OnInitialize()
    EBS.db = EllesmereUI.Lite.NewDB("EllesmereUIMinimapDB", defaults)

    -- Migrate legacy hideGreatVault/hidePortals into hideExtraBtns table
    local mp = EBS.db and EBS.db.profile and EBS.db.profile.minimap
    if mp then
        if mp.hideGreatVault ~= nil or mp.hidePortals ~= nil then
            if not mp.hideExtraBtns then mp.hideExtraBtns = {} end
            if mp.hideGreatVault ~= nil then
                mp.hideExtraBtns.greatVault = mp.hideGreatVault
                mp.hideGreatVault = nil
            end
            if mp.hidePortals ~= nil then
                mp.hideExtraBtns.portals = mp.hidePortals
                mp.hidePortals = nil
            end
        end
    end

    -- Full rebuild: wipes cached button state so the next ApplyMinimap re-snapshots native sizes/textures (as if /reload). Used by btnBackgrounds and ungrouping.
    local function FullRebuildMinimap()
        wipe(flyoutSavedRegions)
        -- ApplyAll, not bare ApplyMinimap: visibility runs through the shared dispatcher
        -- and only re-evaluates on request, so without it a programmatic change (settings-override transitions) never hides/shows the map.
        ApplyAll()
    end

    -- Global bridge for options <-> main communication
    _G._EMM_DB           = EBS.db
    _G._EMM_ApplyMinimap = ApplyMinimap
    _G._EMM_FullRebuildMinimap = FullRebuildMinimap
    _G._EMM_ApplyMapAlpha = EBS._ApplyMapAlpha
    _G._EMM_ApplyIconScale = EBS._ApplyMinimapIconScale
    _G._EMM_EditModeIconScale = EBS._EditModeIconScale

    -- Register visibility updater + mouseover target
    EllesmereUI.RegisterVisibilityUpdater(UpdateMinimapVisibility)
    if EllesmereUI.RegisterMouseoverTarget and Minimap then
        EllesmereUI.RegisterMouseoverTarget(Minimap, function()
            -- Minimap is the one mouseover target that is a raw protected Blizzard frame
            -- (every other module registers an addon-owned proxy); the shared poll's
            -- Show()/Hide() is blocked in combat lockdown, so report inactive during
            -- combat -- the poll then only resets bookkeeping, and the dispatcher re-applies state on PLAYER_REGEN_ENABLED.
            if InCombatLockdown() or _mmKeyHidden then return false end
            local p = EBS.db and EBS.db.profile and EBS.db.profile.minimap
            if not (p and p.enabled) then return false end
            -- Hover-gated sets only reveal while their conditions pass.
            return EllesmereUI.VisWantsMouseover(p, "visibility")
        end, function()
            -- A hover reveal shows the map at its Opacity, not full alpha.
            return EBS._MapAlpha(EBS.db and EBS.db.profile and EBS.db.profile.minimap)
        end)
    end
end

function EBS:OnEnable()
    ApplyAll()

    -- Re-apply after PLAYER_ENTERING_WORLD so accent colors from the theme system (which updates ELLESMERE_GREEN at PLAYER_LOGIN) are picked up.
    local loginRefresh = CreateFrame("Frame")
    loginRefresh:RegisterEvent("PLAYER_ENTERING_WORLD")
    loginRefresh:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        C_Timer.After(0, ApplyAll)
    end)

    -- The Omnium Folio button must be re-asserted after EVERY loading screen, not just
    -- the first: Blizzard can leave it hidden on zone-in (RefreshButton's early-out),
    -- and another minimap-button addon can re-grab its parent/position -- neither of
    -- which the one-shot loginRefresh above catches. ApplyOmniumFolio is idempotent
    -- when already shown/placed (only nudges RefreshButton when hidden); deferred a frame so Blizzard's own PLAYER_ENTERING_WORLD handling runs first.
    -- The addon compartment needs the same treatment for the same reason: it is
    -- a Blizzard-owned button we reparent out of MinimapCluster, and the cluster
    -- relayout after a loading screen can claim it back.
    local folioRefresh = CreateFrame("Frame")
    folioRefresh:RegisterEvent("PLAYER_ENTERING_WORLD")
    folioRefresh:SetScript("OnEvent", function()
        C_Timer.After(0, ApplyOmniumFolio)
        C_Timer.After(0, EBS._ApplyAddonCompartment)
    end)

    -- If GameTimeFrame still doesn't exist, watch for Blizzard_TimeManager to load
    if not _G.GameTimeFrame then
        local tmWatcher = CreateFrame("Frame")
        tmWatcher:RegisterEvent("ADDON_LOADED")
        tmWatcher:SetScript("OnEvent", function(self, _, addon)
            if addon == "Blizzard_TimeManager" then
                self:UnregisterAllEvents()
                if EBS.db.profile.minimap.enabled then
                    C_Timer.After(0, ApplyMinimap)
                end
            end
        end)
    end

    -- Register minimap with unlock mode
    if EllesmereUI and EllesmereUI.RegisterUnlockElements then
        local MK = EllesmereUI.MakeUnlockElement
        local function MDB() return EBS.db and EBS.db.profile.minimap end
        EllesmereUI:RegisterUnlockElements({
            MK({
                key   = "EBS_Minimap",
                label = "Minimap",
                group = "Minimap",
                order = 500,
                noResize = true,
                noAnchorTo = true,
                getFrame = function() return Minimap end,
                getSize  = function()
                    local layout = GetFFD(Minimap).layoutFrame
                    if layout then return layout:GetWidth(), layout:GetHeight() end
                    return Minimap:GetWidth(), Minimap:GetHeight()
                end,
                isHidden = function()
                    local m = MDB()
                    return not m or not m.enabled
                end,
                savePos = function(_, point, relPoint, x, y)
                    local m = MDB(); if not m then return end
                    m.position = { point = point, relPoint = relPoint, x = x, y = y }
                    if not EllesmereUI._unlockActive then
                        ApplyMinimap()
                    end
                end,
                loadPos = function()
                    local m = MDB()
                    if not m or not m.enabled then return nil end
                    return m.position
                end,
                clearPos = function()
                    local m = MDB(); if not m then return end
                    m.position = nil
                end,
                applyPos = function()
                    local m = MDB()
                    if not m or not m.enabled then return end
                    ApplyMinimap()
                end,
            }),
        })
    end
end

-------------------------------------------------------------------------------
--  Farming HUD Compatibility
--  While the HUD (detected by the global used below) is shown, keep the minimap
--  centered in its frame and hide our border/background so nothing overlaps.
-------------------------------------------------------------------------------
do
    local _fhLock = false

    local fhFix = CreateFrame("Frame")
    fhFix:RegisterEvent("PLAYER_ENTERING_WORLD")
    fhFix:SetScript("OnEvent", function(self)
        if not FarmHud then return end
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")

        -- Keep the minimap centered in the HUD frame on any reposition / reparent.
        hooksecurefunc(Minimap, "SetPoint", function(mm)
            if FarmHud:IsShown() and not _fhLock then
                _fhLock = true
                mm:ClearAllPoints()
                mm:SetPoint("CENTER", FarmHud, "CENTER", 0, 0)
                _fhLock = false
            end
        end)

        hooksecurefunc(Minimap, "SetParent", function(mm, parent)
            if FarmHud:IsShown() and parent ~= FarmHud and not _fhLock then
                _fhLock = true
                mm:SetParent(FarmHud)
                _fhLock = false
            end
        end)

        -- Hide / restore our minimap borders
        local function ToggleMinimapBorders(show)
            local alpha = show and 1 or 0

            if GetFFD(Minimap).circBorder then GetFFD(Minimap).circBorder:SetAlpha(alpha) end
            if GetFFD(Minimap).texCircBorder then GetFFD(Minimap).texCircBorder:SetAlpha(alpha) end

            -- Square border host (solid strips or textured backdrop)
            local host = GetFFD(Minimap).borderHost
            if host then host:SetAlpha(alpha) end

            -- WoW Forever look's Forever Square frame (the apply pass never sets
            -- its alpha, so this one holds while the HUD is up)
            local heavy = GetFFD(Minimap).fvHeavy
            if heavy then heavy:SetAlpha(alpha) end
        end

        -- The HUD owns the map while shown (full alpha, see EBS._MapAlpha); its hide
        -- edge hands our Opacity back.
        FarmHud:HookScript("OnShow", function() ToggleMinimapBorders(false); EBS._ApplyMapAlpha() end)
        FarmHud:HookScript("OnHide", function() ToggleMinimapBorders(true); EBS._ApplyMapAlpha() end)
    end)
end

I.broken = false
