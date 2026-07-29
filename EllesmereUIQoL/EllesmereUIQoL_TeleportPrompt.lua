-------------------------------------------------------------------------------
--  EllesmereUIQoL_TeleportPrompt.lua
--  When the player joins a Group Finder (LFGList) group for a dungeon that has
--  a known teleport, show a small square popup ("LFG Reminder") with the dungeon
--  name and a one-click teleport button. The popup hides when the player enters
--  the dungeon, leaves the group, or enters combat. A "Disable Feature" text
--  below the button turns the whole feature off (re-enable in QoL options).
--
--  Taint / secret-value safety (this is critical, read before editing):
--   - The teleport spellID fed to SetAttribute("spell", id) is ALWAYS a static
--     integer resolved from our own name->spell table, never an LFG field.
--   - The dungeon is resolved on LFG_LIST_JOINED_GROUP, where the search result
--     is readable. While browsing/applying, GetSearchResultInfo returns secret
--     values (activityIDs is a secret table -> indexing throws); joining lifts
--     that. We still guard every field with issecretvalue() and wrap the whole
--     lookup in pcall, so a secret value can only make us skip the prompt, never
--     error. The dungeon name is only ever SetText'd (which accepts secrets).
--   - The secure button is created ONCE at login (out of combat); only the
--     "spell" attribute is rewritten later, and only out of combat (deferred to
--     PLAYER_REGEN_ENABLED when an accept lands mid-combat).
--   - We never hook, SetScript, or write keys onto any Blizzard Group Finder
--     frame. All state lives on frames we create or in file-local upvalues.
-------------------------------------------------------------------------------
local EUI = EllesmereUI
local PP  = EUI and EUI.PP
local issecretvalue = issecretvalue or function() return false end

-- Settings live on the shared EllesmereUIDB (lazy-init, never re-init at scope).
local function TeleCfg()
    if not EllesmereUIDB then return {} end
    EllesmereUIDB.teleportPrompt = EllesmereUIDB.teleportPrompt or {}
    return EllesmereUIDB.teleportPrompt
end

local function IsEnabled()
    return TeleCfg().enabled ~= false  -- default ON
end

-------------------------------------------------------------------------------
--  Layout constants
-------------------------------------------------------------------------------
local POPUP_W   = 210
local TITLE_H   = 27
local PAD       = 10
local NAME_TOP    = TITLE_H + 9       -- dungeon-name text top offset
local NAME_H      = 24                 -- reserved height for the name line
local BTN_TOP     = NAME_TOP + NAME_H
local BTN_H       = 56
local DISABLE_TOP = BTN_TOP + BTN_H + 8  -- "Disable Feature" text below the button
local DISABLE_H   = 16
local POPUP_H     = DISABLE_TOP + DISABLE_H + 10

-------------------------------------------------------------------------------
--  State (plain upvalues; never keyed by a possibly-secret resultID)
-------------------------------------------------------------------------------
local popup, secureBtn
local pendingSpellID       -- resolved teleport spell (static integer) to use
local pendingName          -- dungeon display name for the title (guaranteed clean)
local pendingAttrSpellID   -- spell attr stashed to write when leaving combat
local pendingShow          -- join landed in combat; show on PLAYER_REGEN_ENABLED
local pendingHide          -- hide requested in combat; hide on PLAYER_REGEN_ENABLED

-- Forward declarations (closures reference each other)
local BuildPopup, ShowPrompt, HidePrompt, ClearPending
local ApplyTeleportPrompt  -- live enable/disable entry point (defined in the events section)
local UpdateButtonVisuals, ResolveDungeon
local SavePosition, ApplySavedPosition, ApplyDisableVisibility

-------------------------------------------------------------------------------
--  Font helpers (mirror the /keys popup)
-------------------------------------------------------------------------------
local function ResolveFont()
    return (EUI and EUI.GetFontPath and EUI.GetFontPath("extras")) or "Fonts\\FRIZQT__.TTF"
end
local function ResolveOutline()
    return (EUI and EUI.GetFontOutlineFlag and EUI.GetFontOutlineFlag("extras")) or ""
end
local function MakeLabel(parent, size, r, g, b, a)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    local flags = ResolveOutline()
    if EUI and EUI.PrimeFontShadow then EUI.PrimeFontShadow(fs, flags == "") end
    fs:SetFont(ResolveFont(), size, flags)
    if r then fs:SetTextColor(r, g or 1, b or 1, a or 1) end
    return fs
end

-------------------------------------------------------------------------------
--  Position persistence (per-feature DB key only)
-------------------------------------------------------------------------------
SavePosition = function()
    if not popup then return end
    local p, _, rp, x, yo = popup:GetPoint()
    if p then TeleCfg().pos = { p = p, rp = rp, x = x, y = yo } end
end

ApplySavedPosition = function()
    if not popup then return end
    popup:ClearAllPoints()
    local pos = TeleCfg().pos
    if pos and pos.p then
        popup:SetPoint(pos.p, UIParent, pos.rp or pos.p, pos.x or 0, pos.y or 0)
    else
        popup:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
    end
end

-- Show/hide the "Disable Feature" text and trim the window height by 20px when
-- it is hidden. Driven by EllesmereUIDB.teleportPrompt.showDisable (default ON).
ApplyDisableVisibility = function()
    if not popup then return end
    local show = TeleCfg().showDisable ~= false
    if popup._disableBtn then popup._disableBtn:SetShown(show) end
    popup:SetHeight(show and POPUP_H or (POPUP_H - 20))
end

-------------------------------------------------------------------------------
--  Build the popup + secure button (called once at login, out of combat)
-------------------------------------------------------------------------------
BuildPopup = function()
    if popup then return popup end

    popup = CreateFrame("Frame", "EUITeleportPopup", UIParent)
    popup:SetSize(POPUP_W, POPUP_H)
    popup:SetFrameStrata("DIALOG")
    popup:SetMovable(true)
    popup:EnableMouse(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", function(s) s:StartMoving() end)
    popup:SetScript("OnDragStop", function(s) s:StopMovingOrSizing(); SavePosition() end)

    local bg = popup:CreateTexture(nil, "BACKGROUND", nil, 0)
    bg:SetAllPoints()
    bg:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\modern_blizz.png")
    bg:SetTexCoord(0.25, 1, 0, 0.75)
    local overlay = popup:CreateTexture(nil, "BACKGROUND", nil, 1)
    overlay:SetAllPoints()
    overlay:SetColorTexture(0, 0, 0, 0.55)

    if PP and PP.CreateBorder then PP.CreateBorder(popup, 0.1, 0.1, 0.1, 1, 1, "OVERLAY", 7) end

    -- Header bar with the dungeon title
    local hdrBg = popup:CreateTexture(nil, "BORDER")
    hdrBg:SetColorTexture(0, 0, 0, 0.25)
    hdrBg:SetPoint("TOPLEFT", 1, -1); hdrBg:SetPoint("TOPRIGHT", -1, 0); hdrBg:SetHeight(TITLE_H)

    local title = MakeLabel(popup, 11, 1, 1, 1, 1)
    title:SetPoint("TOPLEFT", PAD, -8)
    title:SetPoint("TOPRIGHT", -(PAD + 16), -8)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    title:SetText("LFG Reminder")

    -- Joined dungeon's full name, centered above the teleport button. Set in
    -- ShowPrompt; the name may be a secret string and SetText accepts secrets.
    local nameFS = MakeLabel(popup, 13, 1, 1, 1, 1)
    nameFS:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD, -NAME_TOP)
    nameFS:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -PAD, -NAME_TOP)
    nameFS:SetJustifyH("CENTER")
    nameFS:SetWordWrap(true)
    popup._name = nameFS

    -- Close (X) in the header
    local ICON_SZ, ICON_ALPHA = 14, 0.5
    local xBtn = CreateFrame("Button", nil, popup)
    xBtn:SetSize(ICON_SZ, ICON_SZ)
    xBtn:SetPoint("RIGHT", hdrBg, "RIGHT", -8, 0)
    local xTex = xBtn:CreateTexture(nil, "ARTWORK")
    xTex:SetAllPoints()
    xTex:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png")
    xTex:SetAlpha(ICON_ALPHA)
    xBtn:SetScript("OnEnter", function() xTex:SetAlpha(1) end)
    xBtn:SetScript("OnLeave", function() xTex:SetAlpha(ICON_ALPHA) end)
    xBtn:SetScript("OnClick", function() HidePrompt() end)

    -- Secure teleport button (created out of combat, once). type + clicks are
    -- set here and NEVER touched again; only "spell" is rewritten (out of combat).
    secureBtn = CreateFrame("Button", "EUITeleportButton", popup, "SecureActionButtonTemplate")
    secureBtn:SetSize(POPUP_W - PAD * 2, BTN_H)
    -- A protected frame can only be anchored to another FRAME, never to a region
    -- (texture/fontstring). Anchor to the popup frame, below the name text.
    secureBtn:SetPoint("TOP", popup, "TOP", 0, -BTN_TOP)
    secureBtn:RegisterForClicks("AnyUp", "AnyDown")
    secureBtn:SetAttribute("type", "spell")

    local btnBg = secureBtn:CreateTexture(nil, "BACKGROUND")
    btnBg:SetAllPoints()
    btnBg:SetColorTexture(0.04, 0.04, 0.06, 0.9)
    if PP and PP.CreateBorder then PP.CreateBorder(secureBtn, 0, 0, 0, 1, 1, "OVERLAY", 7) end

    local icon = secureBtn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(40, 40)
    icon:SetPoint("LEFT", 8, 0)
    icon:SetTexCoord(6/64, 58/64, 6/64, 58/64)
    secureBtn._icon = icon

    local btnLabel = MakeLabel(secureBtn, 12, 1, 1, 1, 1)
    btnLabel:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    btnLabel:SetPoint("RIGHT", -6, 0)
    btnLabel:SetJustifyH("LEFT")
    btnLabel:SetWordWrap(false)
    btnLabel:SetText("Teleport")
    secureBtn._label = btnLabel

    local hover = secureBtn:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.12)

    -- The cooldown inherits the button's protection, so anchor it to the button
    -- FRAME (matching the icon's position/size), never to the icon texture.
    local cd = CreateFrame("Cooldown", nil, secureBtn, "CooldownFrameTemplate")
    cd:SetPoint("LEFT", secureBtn, "LEFT", 8, 0)
    cd:SetSize(40, 40)
    cd:SetHideCountdownNumbers(true)
    cd:SetDrawSwipe(true); cd:SetDrawBling(false); cd:SetDrawEdge(false)
    secureBtn._cd = cd

    secureBtn:SetScript("OnEnter", function(self)
        local sid = pendingSpellID
        if not sid then return end
        if not IsPlayerSpell(sid) then
            if EUI.ShowWidgetTooltip then
                EUI.ShowWidgetTooltip(self, "You have not learned this dungeon teleport yet.")
            end
            return
        end
        local cdInfo = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(sid)
        if cdInfo and cdInfo.duration and cdInfo.duration > 0 then
            if EUI.ShowWidgetTooltip then EUI.ShowWidgetTooltip(self, "Teleport on Cooldown") end
        elseif EUI.ShowWidgetTooltip then
            EUI.ShowWidgetTooltip(self, "Teleport to " .. (pendingName or "dungeon"))
        end
    end)
    secureBtn:SetScript("OnLeave", function()
        if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
    end)

    -- "Disable Feature" text below the teleport button. Clicking it turns the
    -- whole LFG Reminder feature off and hides the popup immediately.
    local disableBtn = CreateFrame("Button", nil, popup)
    disableBtn:SetSize(POPUP_W - PAD * 2, DISABLE_H)
    disableBtn:SetPoint("TOP", popup, "TOP", 0, -DISABLE_TOP)
    local disableLbl = MakeLabel(disableBtn, 10, 0.6, 0.6, 0.6, 1)
    disableLbl:SetAllPoints()
    disableLbl:SetJustifyH("CENTER")
    disableLbl:SetText("Disable Feature")
    disableBtn:SetScript("OnEnter", function() disableLbl:SetTextColor(1, 0.3, 0.3, 1) end)
    disableBtn:SetScript("OnLeave", function() disableLbl:SetTextColor(0.6, 0.6, 0.6, 1) end)
    disableBtn:SetScript("OnClick", function()
        TeleCfg().enabled = false
        ApplyTeleportPrompt()
    end)
    popup._disableBtn = disableBtn

    -- Intentionally NOT registered for Escape-close: the popup should stay until
    -- the player teleports, enters the dungeon, leaves the group, or disables it.

    popup:SetScale(TeleCfg().scale or 1.05)
    ApplySavedPosition()
    ApplyDisableVisibility()
    popup:Hide()
    return popup
end

-------------------------------------------------------------------------------
--  Visuals (all use the clean static integer, so compares are safe)
-------------------------------------------------------------------------------
UpdateButtonVisuals = function()
    if not secureBtn or not pendingSpellID then return end
    local sid = pendingSpellID
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
    if info and info.iconID then secureBtn._icon:SetTexture(info.iconID) end
    local known = IsPlayerSpell(sid)
    secureBtn._icon:SetDesaturated(not known)
    secureBtn._icon:SetAlpha(known and 1 or 0.4)
    local lc = known and 1 or 0.5
    secureBtn._label:SetTextColor(lc, lc, lc, 1)
    if known then
        local cdInfo = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(sid)
        if cdInfo and cdInfo.startTime and cdInfo.duration and cdInfo.duration > 0 then
            secureBtn._cd:SetCooldown(cdInfo.startTime, cdInfo.duration)
        else
            secureBtn._cd:Clear()
        end
    else
        secureBtn._cd:Clear()
    end
end

-------------------------------------------------------------------------------
--  Resolve the accepted dungeon -> teleport spell via a CLEAN string chain.
--  resultID is only ever passed as a function argument (safe even if secret).
-------------------------------------------------------------------------------
ResolveDungeon = function(resultID)
    if not (C_LFGList and C_LFGList.GetSearchResultInfo) then return end
    -- Called from LFG_LIST_JOINED_GROUP, where the search result is readable (the
    -- secrecy that applies while browsing/applying is lifted once you have joined).
    -- Still wrapped in pcall and guarded with issecretvalue as defense in depth:
    -- if any needed field is secret, it bails gracefully (no prompt) rather than
    -- erroring. Capture is synchronous because the result can expire after joining.
    pcall(function()
        local info = C_LFGList.GetSearchResultInfo(resultID)
        if type(info) ~= "table" then return end
        local activityID = info.activityID
        if activityID == nil and info.activityIDs and not issecretvalue(info.activityIDs) then
            activityID = info.activityIDs[1]
        end
        if issecretvalue(activityID) or activityID == nil then return end
        local act = C_LFGList.GetActivityInfoTable(activityID)
        if type(act) ~= "table" then return end
        local fullName = act.fullName
        if type(fullName) ~= "string" or issecretvalue(fullName) then return end
        local spellID = EUI and EUI.ResolveTeleportSpellByName and EUI.ResolveTeleportSpellByName(fullName)
        if spellID then
            pendingSpellID = spellID
            -- Display only the dungeon name, not the trailing difficulty suffix
            -- (e.g. "Skyreach (Mythic Keystone)" -> "Skyreach").
            pendingName    = (fullName:gsub("%s*%b()%s*$", ""))
        end
    end)
end

-------------------------------------------------------------------------------
--  Show / Hide / Clear
-------------------------------------------------------------------------------
ShowPrompt = function()
    if not IsEnabled() or not pendingSpellID then return end
    BuildPopup()
    popup._name:SetText(pendingName or "")  -- SetText accepts secret strings natively
    if InCombatLockdown() then
        -- Cannot write the secure attribute or surface the protected teleport
        -- button in combat (and teleports cannot be cast in combat anyway).
        -- Defer the whole show to PLAYER_REGEN_ENABLED.
        pendingAttrSpellID = pendingSpellID
        pendingShow = true
        pendingHide = nil   -- a deferred show supersedes any deferred hide
        return
    end
    secureBtn:SetAttribute("spell", pendingSpellID)  -- always a static integer
    pendingAttrSpellID = nil
    pendingHide = nil
    UpdateButtonVisuals()
    popup:Show()
end

HidePrompt = function()
    pendingShow = nil
    -- popup parents a SecureActionButton, so popup:Hide() is a protected call the
    -- game blocks in combat. If it's already hidden there is nothing to do (avoids
    -- the blocked call entirely -- the common case when leaving an instance in
    -- combat). If it's genuinely shown during combat, defer the hide to
    -- PLAYER_REGEN_ENABLED instead of calling the protected method now.
    if not (popup and popup:IsShown()) then pendingHide = nil; return end
    if InCombatLockdown() then pendingHide = true; return end
    pendingHide = nil
    popup:Hide()
end

ClearPending = function()
    pendingSpellID = nil
    pendingName    = nil
    pendingShow    = nil
end

-- Live update hook for the options slider/toggles (scale + disable-text row).
_G._EUI_RefreshTeleportPrompt = function()
    if not popup then return end
    popup:SetScale(TeleCfg().scale or 1.05)
    ApplyDisableVisibility()
end

-- Immediate hide hook used by the options toggle when disabling the feature.
_G._EUI_HideTeleportPrompt = function()
    ClearPending()
    HidePrompt()
end

-------------------------------------------------------------------------------
--  Events. No Blizzard frame is ever hooked or SetScript-ed. Heavy events are
--  only registered when the feature is enabled (zero cost when disabled).
-------------------------------------------------------------------------------
local ev = CreateFrame("Frame")

-- Feature events are registered only while enabled and unregistered on
-- disable, so a disabled reminder costs nothing on roster/zone/combat events.
-- PLAYER_REGEN_ENABLED outlives a mid-combat disable while a combat-blocked
-- hide or secure attribute write is pending; its handler re-syncs afterwards.
local function SyncEvents()
    if IsEnabled() then
        ev:RegisterEvent("LFG_LIST_JOINED_GROUP")
        ev:RegisterEvent("GROUP_ROSTER_UPDATE")
        ev:RegisterEvent("PLAYER_ENTERING_WORLD")
        ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        ev:RegisterEvent("PLAYER_REGEN_DISABLED")
        ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        ev:UnregisterEvent("LFG_LIST_JOINED_GROUP")
        ev:UnregisterEvent("GROUP_ROSTER_UPDATE")
        ev:UnregisterEvent("PLAYER_ENTERING_WORLD")
        ev:UnregisterEvent("ZONE_CHANGED_NEW_AREA")
        ev:UnregisterEvent("PLAYER_REGEN_DISABLED")
        if not (pendingHide or pendingAttrSpellID) then
            ev:UnregisterEvent("PLAYER_REGEN_ENABLED")
        end
    end
end

-- Live enable/disable (options toggle and the in-popup Disable Feature text):
-- takes effect immediately in both directions, no reload. The popup parents a
-- secure button, so a mid-combat first enable defers the build to combat end.
local pendingBuild
ApplyTeleportPrompt = function()
    if IsEnabled() then
        if not popup and InCombatLockdown() then
            pendingBuild = true
            ev:RegisterEvent("PLAYER_REGEN_ENABLED")
            return
        end
        pendingBuild = nil
        BuildPopup()
        SyncEvents()
    else
        pendingBuild = nil
        ClearPending()
        HidePrompt()
        SyncEvents()
    end
end
_G._EUI_ApplyTeleportPrompt = ApplyTeleportPrompt

ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "PLAYER_LOGIN" then
        -- Login is always out of combat: safe to create the secure button now.
        if IsEnabled() then
            BuildPopup()
            SyncEvents()
        end
        return
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Finish a mid-combat enable: safe to build the secure button now.
        if pendingBuild then
            pendingBuild = nil
            if IsEnabled() then BuildPopup() end
        end
        -- Flush a secure attribute write that was blocked during combat.
        if pendingAttrSpellID and secureBtn then
            secureBtn:SetAttribute("spell", pendingAttrSpellID)
            pendingAttrSpellID = nil
        end
        -- Surface a prompt whose accept landed mid-combat.
        if pendingShow and pendingSpellID and IsEnabled() then
            pendingShow = nil
            UpdateButtonVisuals()
            if popup then popup:Show() end
        end
        -- Flush a hide that was blocked during combat (protected popup:Hide()).
        if pendingHide then
            pendingHide = nil
            if popup and popup:IsShown() then popup:Hide() end
        end
        -- Drop any event that only stayed registered for the flushes above.
        SyncEvents()
        return
    elseif event == "PLAYER_REGEN_DISABLED" then
        HidePrompt()  -- combat-start guard (teleports cannot be cast in combat)
        return
    end

    -- Defense in depth: feature events unregister on disable, but bail if one
    -- lands mid-transition.
    if not IsEnabled() then
        ClearPending(); HidePrompt(); return
    end

    if event == "LFG_LIST_JOINED_GROUP" then
        -- arg1 = searchResultID. This fires the moment the player joins a Group
        -- Finder group (i.e. accepted the invite). Unlike the browse/apply phase,
        -- the search result info is readable here, so the dungeon can be resolved.
        -- Capture immediately; the search result can expire shortly after joining.
        ClearPending()
        ResolveDungeon(arg1)
        if pendingSpellID then ShowPrompt() end
    elseif event == "GROUP_ROSTER_UPDATE" then
        if not IsInGroup() then
            ClearPending(); HidePrompt()
        end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        local inInstance, instanceType = IsInInstance()
        if inInstance and instanceType == "party" then
            ClearPending(); HidePrompt()
        end
    end
end)
