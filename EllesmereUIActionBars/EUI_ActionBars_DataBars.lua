if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ActionBars_DataBars.lua
--
--  What the XP, Reputation and House Favor bars share: frame, layout, border,
--  text, visibility and unlock mode registration. Loads after the main file
--  and before EUI_ActionBars_XPBar.lua, which calls into it through ns.
-------------------------------------------------------------------------------
local _, ns = ...

local _G = _G
local ipairs, type = ipairs, type
local max = math.max
local InCombatLockdown = InCombatLockdown
local C_Timer_After = C_Timer.After

local EAB, EAB_VTABLE, BAR_LOOKUP, EXTRA_BARS = ns.EAB, ns.EAB_VTABLE, ns.BAR_LOOKUP, ns.EXTRA_BARS
local ResolveBorderThickness = ns.ResolveBorderThickness
local I = ns._internals
local AttachDataBarHoverHooks, dataBarFrames = I.AttachDataBarHoverHooks, I.dataBarFrames

-------------------------------------------------------------------------------
--  Data Bars (XP, Reputation and House Favor bars): the frame, layout,
--  border, text and visibility all three share. The XP bar's own code is
--  in EUI_ActionBars_XPBar.lua (loaded after this file; called through ns).
-------------------------------------------------------------------------------
-- dataBarFrames is forward-declared near barFrames at the top of the main file
ns.dataBarFrames = dataBarFrames

-- Reputation and House Favor bar colors (the XP bar's are in
-- EUI_ActionBars_XPBar.lua)
local DATA_BAR_COLORS = {
    favor = { r = 0.85, g = 0.64, b = 0.22 },   -- warm gold (house favor)
    rep = {
        [1] = { r = 0.80, g = 0.20, b = 0.20 },  -- Hated
        [2] = { r = 0.75, g = 0.30, b = 0.15 },  -- Hostile
        [3] = { r = 0.75, g = 0.45, b = 0.15 },  -- Unfriendly
        [4] = { r = 0.80, g = 0.70, b = 0.20 },  -- Neutral
        [5] = { r = 0.30, g = 0.70, b = 0.25 },  -- Friendly
        [6] = { r = 0.25, g = 0.65, b = 0.50 },  -- Honored
        [7] = { r = 0.25, g = 0.50, b = 0.75 },  -- Revered
        [8] = { r = 0.35, g = 0.30, b = 0.80 },  -- Exalted
        [9] = { r = 0.80, g = 0.65, b = 0.20 },  -- Paragon
        [10] = { r = 0.20, g = 0.70, b = 0.85 }, -- Renown
    },
}

-- Data bar textures: the suite's built-in bar texture set + SharedMedia.
-- ns-hosted (no new file-scope locals; the chunk is at the 200-local cap).
do
    local lookup, names, order = EllesmereUI.BuildBarTextureTables()
    EllesmereUI.AppendSharedMediaTextures(names, order, nil, lookup)
    ns.dataBarTextures = lookup
    ns.dataBarTextureNames = names
    ns.dataBarTextureOrder = order
end

function ns.ResolveDataBarTexture(key)
    if key and key ~= "none" then
        local path = EllesmereUI.ResolveTexturePath(ns.dataBarTextures, key, nil)
        if path then return path end
    end
    return "Interface\\BUTTONS\\WHITE8X8"
end

-- Color mode per bar: nil/reactive = state-driven defaults, "accent" = live
-- accent color, "custom" = stored custom color.
function ns.ResolveDataBarColor(s, r, g, b)
    local mode = s and s.colorMode
    if mode == "accent" then
        local EG = EllesmereUI.ELLESMERE_GREEN
        if EG then return EG.r or r, EG.g or g, EG.b or b end
    elseif mode == "custom" then
        local c = s.customColor
        if c then return c.r or 1, c.g or 1, c.b or 1 end
        return 1, 1, 1
    end
    return r, g, b
end

-- Accent-mode bars repaint live when the user changes the accent color.
EllesmereUI.RegAccent({ type = "callback", fn = function()
    for _, bk in ipairs({ "XPBar", "RepBar", "FavorBar" }) do
        local f = dataBarFrames[bk]
        if f and f._updateFunc then f._updateFunc() end
    end
end })

-- Custom Border (the data-bar sections' opt-in). Off: the MakeBorder 1px line
-- stays and nothing here runs past one boolean read. On: an owned host (a
-- child of the holder, built the first time the option is on) draws the
-- chosen style through ApplyBorderStyle like every other EUI border (exact
-- size, pixel-snapped anchors, UI-scale re-apply), and MakeBorder's container
-- hides. Turning it off retires the host with HideBorderStyle BEFORE Hide, so
-- the UI-scale re-apply cannot bring an exact-size backdrop back over the
-- line, then shows MakeBorder again. Levels: host = holder+1 (its solid strips
-- land at holder+2, where MakeBorder's do); the textured backdrop is set again
-- after every ApplyBorderStyle (which resets it to the host's level): holder+2
-- above the fill, the holder's own level with Show Behind. The text host stays
-- above it. A child of the holder, so the mouseover fade carries it; the
-- holder's alpha is never read or written. On ns: the chunk is at the local cap.
ns.ApplyDataBarBorder = function(holder, s)
    local host = holder._cbHost
    local line = holder._border and holder._border._frame
    if not s.customBorder then
        if holder._cbOn then
            holder._cbOn = nil
            EllesmereUI.HideBorderStyle(host)
            host:Hide()
            -- An XP bar art frame keeps the line hidden.
            if line and not holder._xpArtOn then line:Show() end
        end
        return
    end
    local lvl = holder:GetFrameLevel()
    if not host then
        host = CreateFrame("Frame", nil, holder)
        host:SetAllPoints(holder)
        host:EnableMouse(false)
        holder._cbHost = host
    end
    host:SetFrameLevel(lvl + 1)
    if not holder._cbOn then
        holder._cbOn = true
        if line then line:Hide() end
    end
    local tex = s.borderTexture or "solid"
    local c = s.borderColor
    local sz, px = ResolveBorderThickness(s)
    EllesmereUI.ApplyBorderStyle(host, sz, c and c.r or 0, c and c.g or 0, c and c.b or 0, c and c.a or 1,
        tex, s.borderTextureOffset, s.borderTextureOffsetY, s.borderTextureShiftX, s.borderTextureShiftY,
        "actionbars", s.borderThickness or "thin", nil, px)
    local top = lvl + 2
    if tex ~= "" and tex ~= "solid" then
        local bd = EllesmereUI._bdBorderData[host]
        if bd then
            if s.borderBehind then top = lvl end
            bd:SetFrameLevel(top)
        end
    end
    local textHost = holder._textHost
    if textHost then
        local want = max(lvl + 3, top + 1)
        if textHost:GetFrameLevel() ~= want then textHost:SetFrameLevel(want) end
    end
end

-- Places a data bar's readout. Unrotated: inside the bar at its textAnchor
-- edge (4 in from a left or right end), nudged by the offsets. rotateText on
-- a vertical bar turns it to run along the bar (textReadDown: reading down),
-- the offsets turning with it (X along the reading direction, Y across it),
-- placed by its drawn centre: a rotated string pivots about the top centre of
-- its unrotated region, so the anchor is moved back by that displacement.
-- Text Background (showTextBg): on the text itself while unrotated, so it
-- follows every SetText; rotated, an upright box on the holder. _textPost:
-- a rotated placement is measured from the string, so the bar's update
-- re-places it after every SetText.
function ns.DataBarPlaceText(frame, s)
    local text = frame._text
    local rot = 0
    if s.rotateText and s.orientation == "VERTICAL" then
        rot = s.textReadDown and -math.pi / 2 or math.pi / 2
    end
    -- SetRotation only while rotated, and once more on the way back.
    if rot ~= 0 or frame._textRotated then
        text:SetRotation(rot)
        frame._textRotated = (rot ~= 0) or nil
    end
    local anchor = s.textAnchor
    local ox, oy = s.textOffsetX or 0, s.textOffsetY or 0
    local bgOn = s.showTextBg
    local bg = frame._textBg
    if bgOn and not bg then
        bg = frame._textHost:CreateTexture(nil, "ARTWORK")
        frame._textBg = bg
    end
    text:ClearAllPoints()
    if rot == 0 then
        local ap, padX = "CENTER", 0
        if anchor == "top" then ap = "TOP"
        elseif anchor == "bottom" then ap = "BOTTOM"
        elseif anchor == "left" then ap, padX = "LEFT", 4
        elseif anchor == "right" then ap, padX = "RIGHT", -4 end
        text:SetPoint(ap, frame._textHost, ap, ox + padX, oy)
        if bgOn then
            -- 3 past the text's ends and 1 above and below it, none past the
            -- edge a top or bottom anchor sets it flush with (the border's).
            bg:ClearAllPoints()
            bg:SetPoint("TOPLEFT", text, "TOPLEFT", -3, ap == "TOP" and 0 or 1)
            bg:SetPoint("BOTTOMRIGHT", text, "BOTTOMRIGHT", 3, ap == "BOTTOM" and 0 or -1)
        end
        frame._textPost = nil
    else
        -- Drawn box: sw along the bar by sh across it; its centre (vx, vy)
        -- from the holder's centre, inside the border.
        local sw = text:GetStringWidth()
        local sh = text:GetStringHeight()
        if not sh or sh <= 0 then sh = text:GetLineHeight() end
        if not sh or sh <= 0 then sh = s.textSize or 9 end
        local vx, vy = 0, 0
        if anchor == "top" or anchor == "bottom" then
            vy = max(0, (s.height or 18) / 2 - 1 - 4 - sw / 2)
            if anchor == "bottom" then vy = -vy end
        elseif anchor == "left" or anchor == "right" then
            vx = max(0, (s.width or 400) / 2 - 1 - sh / 2)
            if anchor == "left" then vx = -vx end
        end
        local cs, sn = math.cos(rot), math.sin(rot)
        vx = vx + ox * cs - oy * sn
        vy = vy + ox * sn + oy * cs
        local hh = sh / 2
        text:SetPoint("CENTER", frame, "CENTER", vx - hh * sn, vy - hh * (1 - cs))
        if bgOn then
            -- No pad across the bar at a left or right anchor, where the
            -- text sits flush with the border.
            bg:ClearAllPoints()
            bg:SetSize((anchor == "left" or anchor == "right") and sh or sh + 2, sw + 6)
            bg:SetPoint("CENTER", frame, "CENTER", vx, vy)
        end
        frame._textPost = true
    end
    if bg then
        if bgOn then
            local c = s.textBgColor
            bg:SetColorTexture(c and c.r or 0.06, c and c.g or 0.06, c and c.b or 0.08, c and c.a or 0.9)
            bg:Show()
        else
            bg:Hide()
        end
    end
end

local function ApplyDataBarLayout(barKey)
    local frame = dataBarFrames[barKey]
    if not frame then return end
    local s = EAB.db.profile.bars[barKey]
    if not s then return end
    local w = s.width or 400
    local h = s.height or 18
    local orient = s.orientation or "HORIZONTAL"

    -- Centered growth on resize is handled by the centralized unlock mode
    -- position system (NotifyElementResized re-applies CENTER anchor).
    local PP = EllesmereUI and EllesmereUI.PP
    if PP then
        PP.Size(frame, w, h)
    else
        frame:SetSize(w, h)
    end

    local texPath = ns.ResolveDataBarTexture(s.barTexture)
    frame._bar:SetStatusBarTexture(texPath)
    frame._bar:GetStatusBarTexture():SetDrawLayer("ARTWORK", 4)
    if frame._restedBar then
        frame._restedBar:SetStatusBarTexture(texPath)
        frame._restedBar:GetStatusBarTexture():SetDrawLayer("ARTWORK", 1)
    end

    frame._bar:SetOrientation(orient)
    frame._bar:SetRotatesTexture(orient ~= "HORIZONTAL")
    if frame._restedBar then
        frame._restedBar:SetOrientation(orient)
        frame._restedBar:SetRotatesTexture(orient ~= "HORIZONTAL")
    end

    -- XP bar art style and profession fill (both opt-in; EUI_ActionBars_XPBar.lua).
    if barKey == "XPBar" then ns.ApplyXPBarStyle(frame, s) end

    -- Per-bar Text Size (default 9) and the readout's placement (anchor,
    -- offsets, rotation, background). Re-applied here so the options take
    -- effect live through the existing ApplyDataBarLayout calls.
    if frame._text then
        -- Read live, not FONT_PATH: that load-time capture misses a standalone's
        -- saved fonts and a login spec-profile switch.
        frame._text:SetFont(EllesmereUI.GetFontPath("actionBars"), s.textSize or 9, EllesmereUI.GetFontOutlineFlag("actionBars"))
        ns.DataBarPlaceText(frame, s)
        if barKey == "XPBar" then ns.XPBarTextSlots(frame, s) end
    end

    -- Dividers (EUI_ActionBars_XPBar.lua): one boolean read while off; a
    -- built host is called to hide.
    if frame._divHost or s.showDividers then
        ns.AB_DataBarDividers(frame, w, h, orient, s)
    end

    -- Custom Border (one boolean read while off), then its reach for width /
    -- height matching (value-compared and deferred; a no-op in unlock mode and
    -- before the bar is registered).
    ns.ApplyDataBarBorder(frame, s)
    EllesmereUI.MatchPadChanged(barKey)

    if frame._updateFunc then frame._updateFunc() end
end
ns.ApplyDataBarLayout = ApplyDataBarLayout

local function CreateDataBarFrame(barKey, updateFunc)
    local holder = CreateFrame("Frame", "EllesmereEAB_" .. barKey, UIParent)
    holder:SetSize(400, 18)
    holder:SetClampedToScreen(true)

    -- Pixel-perfect background
    local bg = holder:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(0.06, 0.06, 0.08, 0.85)
    local PP = EllesmereUI and EllesmereUI.PP
    if PP then
        PP.SetInside(bg, holder, 1, 1)
    else
        bg:SetPoint("TOPLEFT", 1, -1)
        bg:SetPoint("BOTTOMRIGHT", -1, 1)
    end
    holder._bg = bg

    -- Pixel-perfect 1px border via MakeBorder
    if EllesmereUI and EllesmereUI.MakeBorder then
        holder._border = EllesmereUI.MakeBorder(holder, 0, 0, 0, 1)
    end

    local bar = CreateFrame("StatusBar", "EllesmereEAB_" .. barKey .. "_Bar", holder)
    bar:SetStatusBarTexture("Interface\\BUTTONS\\WHITE8X8")
    if PP then
        PP.SetInside(bar, holder, 1, 1)
    else
        bar:SetPoint("TOPLEFT", 1, -1)
        bar:SetPoint("BOTTOMRIGHT", -1, 1)
    end
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:GetStatusBarTexture():SetDrawLayer("ARTWORK", 4)

    -- Text lives on its own host ABOVE the MakeBorder strips: the border
    -- container renders two levels above the holder, and frame level beats
    -- draw layer, so a string on the bar itself gets cut by the border edges
    -- whenever the glyphs reach them (large Text Size / short bars).
    local textHost = CreateFrame("Frame", nil, bar)
    textHost:SetAllPoints(bar)
    local edges = holder._border and holder._border.edges
    textHost:SetFrameLevel(((edges and edges.GetFrameLevel and edges:GetFrameLevel())
        or holder:GetFrameLevel() + 2) + 1)

    -- Kept for Custom Border, which holds it above its own backdrop.
    holder._textHost = textHost

    local text = textHost:CreateFontString(nil, "OVERLAY")
    EllesmereUI.PrimeFontShadow(text, EllesmereUI.GetFontUseShadow("actionBars"))
    local sInit = EAB.db and EAB.db.profile and EAB.db.profile.bars
        and EAB.db.profile.bars[barKey]
    text:SetFont(EllesmereUI.GetFontPath("actionBars"), sInit and sInit.textSize or 9, EllesmereUI.GetFontOutlineFlag("actionBars"))
    text:SetPoint("CENTER", sInit and sInit.textOffsetX or 0, sInit and sInit.textOffsetY or 0)
    text:SetTextColor(1, 1, 1, 1)

    holder._bar = bar
    holder._text = text
    holder._updateFunc = updateFunc

    dataBarFrames[barKey] = holder
    return holder
end
-- The XP bar (EUI_ActionBars_XPBar.lua) builds its frame through this too.
ns.CreateDataBarFrame = CreateDataBarFrame

-- Data bars own their content updates, but visibility is shared with the
-- generic non-secure visibility system above. Guard each update callback so a
-- later XP/reputation event cannot re-show a bar that runtime conditions have
-- already hidden (for example `solo` while grouped).
function EAB_VTABLE.ExtraBars.BeginManagedDataBarUpdate(barKey)
    local frame = dataBarFrames[barKey]
    if not frame then return nil, nil end
    local info = BAR_LOOKUP[barKey]
    if EAB.db.profile.useBlizzardDataBars then
        if info then
            EAB_VTABLE.ExtraBars.ApplyManagedNonSecurePresentation(info, frame, EAB.db.profile.bars[barKey], false, true)
        else
            frame:Hide()
        end
        return nil, nil
    end

    local s = EAB.db.profile.bars[barKey]
    if not s then return nil, nil end
    if s.alwaysHidden or not EAB_VTABLE.ExtraBars.ShouldShowManagedNonSecureBar(s) then
        if info then
            EAB_VTABLE.ExtraBars.ApplyManagedNonSecurePresentation(info, frame, s, false, true)
        else
            frame:Hide()
        end
        return nil, s
    end

    return frame, s
end

function EAB_VTABLE.ExtraBars.FinishManagedDataBarUpdate(barKey, frame, s)
    if not frame or not s then return end

    local info = BAR_LOOKUP[barKey]
    if info then
        EAB_VTABLE.ExtraBars.ApplyManagedNonSecurePresentation(info, frame, s, true, true)
    else
        frame:Show()
    end
end

-------------------------------------------------------------------------------
--  Reputation Bar
-------------------------------------------------------------------------------
local function UpdateRepBar()
    local frame, s = EAB_VTABLE.ExtraBars.BeginManagedDataBarUpdate("RepBar")
    if not frame then return end

    local bar = frame._bar
    local text = frame._text

    local data = C_Reputation and C_Reputation.GetWatchedFactionData and C_Reputation.GetWatchedFactionData()
    if not data or not data.name then
        EAB_VTABLE.ExtraBars.ApplyManagedNonSecurePresentation(BAR_LOOKUP["RepBar"], frame, s, false, true)
        return
    end

    local name = data.name
    local reaction = data.reaction or 4
    local factionID = data.factionID
    local currentStanding = data.currentStanding or 0
    local currentReactionThreshold = data.currentReactionThreshold or 0
    local nextReactionThreshold = data.nextReactionThreshold or 1
    local standing

    -- Friendship handling (check first friendships override normal standing)
    local isFriendship = false
    if factionID then
        local friendInfo = C_GossipInfo and C_GossipInfo.GetFriendshipReputation and C_GossipInfo.GetFriendshipReputation(factionID)
        if friendInfo and friendInfo.friendshipFactionID and friendInfo.friendshipFactionID > 0 then
            isFriendship = true
            standing = friendInfo.reaction
            currentReactionThreshold = friendInfo.reactionThreshold or 0
            nextReactionThreshold = friendInfo.nextThreshold or math.huge
            currentStanding = friendInfo.standing or 1
        end
    end

    -- Paragon handling (check before renown max-renown factions become paragon)
    local isParagon = false
    if factionID and C_Reputation.IsFactionParagonForCurrentPlayer and C_Reputation.IsFactionParagonForCurrentPlayer(factionID) then
        local paragonVal, paragonThreshold = C_Reputation.GetFactionParagonInfo(factionID)
        if paragonVal and paragonThreshold then
            isParagon = true
            standing = EllesmereUI.L("Paragon")
            currentStanding = paragonVal % paragonThreshold
            currentReactionThreshold = 0
            nextReactionThreshold = paragonThreshold
            reaction = 9
        end
    end

    -- Renown handling (only if not already paragon or friendship)
    if not isParagon and not isFriendship and factionID and C_Reputation.IsMajorFaction and C_Reputation.IsMajorFaction(factionID) then
        local majorData = C_MajorFactions and C_MajorFactions.GetMajorFactionData and C_MajorFactions.GetMajorFactionData(factionID)
        if majorData then
            local hasMax = C_MajorFactions.HasMaximumRenown and C_MajorFactions.HasMaximumRenown(factionID)
            if hasMax then
                EAB_VTABLE.ExtraBars.ApplyManagedNonSecurePresentation(BAR_LOOKUP["RepBar"], frame, s, false, true)
                return
            end
            reaction = 10
            standing = EllesmereUI.L("Renown")
            currentReactionThreshold = 0
            nextReactionThreshold = majorData.renownLevelThreshold
            currentStanding = majorData.renownReputationEarned or 0
        end
    end

    if not standing then
        standing = _G["FACTION_STANDING_LABEL" .. reaction] or ""
    end

    local color = DATA_BAR_COLORS.rep[reaction] or DATA_BAR_COLORS.rep[4]
    bar:SetStatusBarColor(ns.ResolveDataBarColor(s, color.r, color.g, color.b))

    -- Hide capped / maxed factions (Exalted with no paragon, max friendship, etc.)
    if nextReactionThreshold == math.huge or currentReactionThreshold == nextReactionThreshold then
        EAB_VTABLE.ExtraBars.ApplyManagedNonSecurePresentation(BAR_LOOKUP["RepBar"], frame, s, false, true)
        return
    end

    local current = currentStanding - currentReactionThreshold
    local maximum = nextReactionThreshold - currentReactionThreshold
    if maximum <= 0 then maximum = 1 end

    bar:SetMinMaxValues(0, maximum)
    bar:SetValue(current)

    local pct = (current / maximum) * 100
    -- The tooltip must show the same numbers the bar shows. Recomputing them
    -- from the raw watched-faction payload there breaks on paragon/renown
    -- factions (negative reputation, wrong standing), so stash the resolved
    -- values for the OnEnter handler below.
    frame._tipStanding, frame._tipCurrent, frame._tipMaximum = standing, current, maximum
    text:SetText(format("%s: %.0f%% [%s]", name, pct, standing))

    -- Auto-size text if bar is too narrow (too short, for text rotated to
    -- run along a vertical bar)
    local room = (s.rotateText and s.orientation == "VERTICAL") and frame:GetHeight() or frame:GetWidth()
    if text:GetStringWidth() > room - 4 then
        text:SetText(format("%.0f%%", pct))
    end
    if frame._textPost then ns.DataBarPlaceText(frame, s) end

    EAB_VTABLE.ExtraBars.FinishManagedDataBarUpdate("RepBar", frame, s)
end

local function CreateRepBar()
    local holder = CreateDataBarFrame("RepBar", UpdateRepBar)
    holder:SetPoint("TOP", UIParent, "TOP", 0, -84)

    -- Tooltip (suppressed under Click Through, as on the XP bar)
    holder:EnableMouse(true)
    holder:SetScript("OnEnter", function(self)
        local cfg = EAB and EAB.db and EAB.db.profile and EAB.db.profile.bars and EAB.db.profile.bars["RepBar"]
        if cfg and cfg.clickThrough then return end
        local data = C_Reputation and C_Reputation.GetWatchedFactionData and C_Reputation.GetWatchedFactionData()
        if not data or not data.name then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(data.name, 1, 1, 1)
        -- Use the values the bar already resolved (paragon/renown/friendship
        -- aware); fall back to the raw payload only if the bar has not run yet.
        local standing = self._tipStanding
        if not standing or standing == "" then
            standing = _G["FACTION_STANDING_LABEL" .. (data.reaction or 4)] or ""
        end
        GameTooltip:AddDoubleLine(EllesmereUI.L("Standing"), standing, 1, 1, 1, 1, 1, 1)
        local current = self._tipCurrent
            or ((data.currentStanding or 0) - (data.currentReactionThreshold or 0))
        local maximum = self._tipMaximum
            or ((data.nextReactionThreshold or 1) - (data.currentReactionThreshold or 0))
        if maximum <= 0 then maximum = 1 end
        local pct = (current / maximum) * 100
        GameTooltip:AddDoubleLine(EllesmereUI.L("Reputation"), format("%s / %s (%.1f%%)", BreakUpLargeNumbers(current), BreakUpLargeNumbers(maximum), pct), 1, 1, 1, 1, 1, 1)
        GameTooltip:Show()
    end)
    holder:SetScript("OnLeave", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)

    -- Events
    local evFrame = ns.TakeShell()
    evFrame:RegisterEvent("UPDATE_FACTION")
    evFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    evFrame:RegisterEvent("QUEST_FINISHED")
    if C_MajorFactions then
        evFrame:RegisterEvent("MAJOR_FACTION_RENOWN_LEVEL_CHANGED")
        evFrame:RegisterEvent("MAJOR_FACTION_UNLOCKED")
    end
    evFrame:SetScript("OnEvent", UpdateRepBar)

    ApplyDataBarLayout("RepBar")
    UpdateRepBar()
end

-------------------------------------------------------------------------------
--  House Favor Bar: Blizzard's "Show as Experience Bar" favor watch renders
--  through StatusTrackingBarManager, which the custom data bars replace --
--  this bar is the house-favor equivalent. The favor API is asynchronous:
--  GetPlayerOwnedHouses() -> PLAYER_HOUSE_LIST_UPDATED (house list) ->
--  GetCurrentHouseLevelFavor(guid) -> HOUSE_LEVEL_FAVOR_UPDATED (level +
--  favor payload); GetHouseLevelFavorForLevel(n) is the only sync read.
-------------------------------------------------------------------------------
-- Block-scoped + ns export: the file-scope local budget is nearly at the
-- Lua 5.1 200 cap. WoW Forever has no housing: there the block never runs,
-- so no bar is built, nothing registers and ns._CreateFavorBar stays nil.
if not EllesmereUI.IS_FOREVER then
local favorState  -- { level, displayLevel, favor, needed } from the last payload
local favorEv, favorArmed
local ArmFavorEvents  -- forward: mutual recursion with UpdateFavorBar

-- No favor requests or repaints inside an active keystone or a raid instance.
local function FavorBlocked()
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
        and C_ChallengeMode.IsChallengeModeActive() then
        return true
    end
    local inInst, instType = IsInInstance()
    return (inInst and instType == "raid") and true or false
end

-- Zero cost while hidden: events stay unregistered unless the bar can actually show.
local function FavorWanted()
    if not (C_Housing and C_Housing.GetPlayerOwnedHouses) then return false end
    local p = EAB.db and EAB.db.profile
    if not p or p.useBlizzardDataBars then return false end
    local s = p.bars and p.bars.FavorBar
    return (s and not s.alwaysHidden) and true or false
end

local function UpdateFavorBar()
    if ArmFavorEvents then ArmFavorEvents() end
    local frame, s = EAB_VTABLE.ExtraBars.BeginManagedDataBarUpdate("FavorBar")
    if not frame then return end

    local bar = frame._bar
    local text = frame._text

    -- No house / no data yet / max house level (no next-level requirement).
    local st = favorState
    if not st or not st.needed or st.needed <= 0 then
        EAB_VTABLE.ExtraBars.ApplyManagedNonSecurePresentation(BAR_LOOKUP["FavorBar"], frame, s, false, true)
        return
    end

    local current = st.favor or 0
    if current > st.needed then current = st.needed end
    bar:SetMinMaxValues(0, st.needed)
    bar:SetValue(current)
    bar:SetStatusBarColor(ns.ResolveDataBarColor(s, DATA_BAR_COLORS.favor.r, DATA_BAR_COLORS.favor.g, DATA_BAR_COLORS.favor.b))

    local pct = (current / st.needed) * 100
    text:SetText(format(EllesmereUI.L("House Level %d: %d / %d"), st.displayLevel or 1, current, st.needed))

    -- Auto-size text if bar is too narrow (too short, for text rotated to
    -- run along a vertical bar)
    local room = (s.rotateText and s.orientation == "VERTICAL") and frame:GetHeight() or frame:GetWidth()
    if text:GetStringWidth() > room - 4 then
        text:SetText(format("%.0f%%", pct))
    end
    if frame._textPost then ns.DataBarPlaceText(frame, s) end

    EAB_VTABLE.ExtraBars.FinishManagedDataBarUpdate("FavorBar", frame, s)
end

local function OnFavorEvent(_, event, arg1)
    if FavorBlocked() then return end
    if not (C_Housing and C_Housing.GetPlayerOwnedHouses) then return end
    if event == "PLAYER_ENTERING_WORLD" then
        C_Housing.GetPlayerOwnedHouses()
    elseif event == "PLAYER_HOUSE_LIST_UPDATED" then
        local info = type(arg1) == "table" and arg1[1]
        local guid = info and info.houseGUID
        if guid and C_Housing.GetCurrentHouseLevelFavor then
            C_Housing.GetCurrentHouseLevelFavor(guid)
        else
            favorState = nil
            UpdateFavorBar()
        end
    elseif event == "HOUSE_LEVEL_FAVOR_UPDATED" then
        if type(arg1) == "table" and arg1.houseLevel ~= nil then
            local level = arg1.houseLevel or 0
            local needed = C_Housing.GetHouseLevelFavorForLevel
                and C_Housing.GetHouseLevelFavorForLevel(level + 1)
            favorState = {
                level = level,
                displayLevel = level + 1,
                favor = arg1.houseFavor or 0,
                needed = needed or 0,
            }
        else
            favorState = nil
        end
        UpdateFavorBar()
    end
end

ArmFavorEvents = function()
    local want = FavorWanted()
    if want and not favorArmed then
        favorArmed = true
        if not favorEv then
            favorEv = ns.TakeShell()
            favorEv:SetScript("OnEvent", OnFavorEvent)
        end
        favorEv:RegisterEvent("PLAYER_ENTERING_WORLD")
        favorEv:RegisterEvent("PLAYER_HOUSE_LIST_UPDATED")
        favorEv:RegisterEvent("HOUSE_LEVEL_FAVOR_UPDATED")
        -- Kick the async chain now; if inside blocked content the next
        -- world-enter re-kicks instead.
        if not FavorBlocked() then
            C_Housing.GetPlayerOwnedHouses()
        end
    elseif not want and favorArmed then
        favorArmed = false
        if favorEv then favorEv:UnregisterAllEvents() end
    end
end

local function CreateFavorBar()
    local holder = CreateDataBarFrame("FavorBar", UpdateFavorBar)
    holder:SetPoint("TOP", UIParent, "TOP", 0, -68)

    -- Tooltip (suppressed under Click Through, as on the XP bar)
    holder:EnableMouse(true)
    holder:SetScript("OnEnter", function(self)
        local cfg = EAB and EAB.db and EAB.db.profile and EAB.db.profile.bars and EAB.db.profile.bars["FavorBar"]
        if cfg and cfg.clickThrough then return end
        local st = favorState
        if not st or not st.needed or st.needed <= 0 then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(EllesmereUI.L("House Favor"), 1, 1, 1)
        GameTooltip:AddDoubleLine(EllesmereUI.L("House Level"), tostring(st.displayLevel or 1), 1, 1, 1, 1, 1, 1)
        local current = math.min(st.favor or 0, st.needed)
        local pct = (current / st.needed) * 100
        GameTooltip:AddDoubleLine(EllesmereUI.L("Favor"), format("%s / %s (%.1f%%)", BreakUpLargeNumbers(current), BreakUpLargeNumbers(st.needed), pct), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine(EllesmereUI.L("Remaining"), BreakUpLargeNumbers(st.needed - current), 1, 1, 1, 1, 1, 1)
        GameTooltip:Show()
    end)
    holder:SetScript("OnLeave", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)

    -- Event registration is handled by ArmFavorEvents (via UpdateFavorBar):
    -- nothing is registered while the bar is hidden.
    ApplyDataBarLayout("FavorBar")
    UpdateFavorBar()
end

ns._CreateFavorBar = CreateFavorBar
end -- not IS_FOREVER

-------------------------------------------------------------------------------
--  Register Data Bars with Unlock Mode: same pattern as action bars and
--  Blizzard movable frames -- savePosition/loadPosition/applyPosition/
--  clearPosition callbacks.
-------------------------------------------------------------------------------
local function RegisterDataBarsWithUnlockMode()
    if not EllesmereUI or not EllesmereUI.RegisterUnlockElements then return end
    local MK = EllesmereUI.MakeUnlockElement
    local elements = {}
    local orderBase = 300
    for idx, info in ipairs(EXTRA_BARS) do
        -- Only a bar that was built gets a mover (WoW Forever never builds
        -- the House Favor bar).
        if info.isDataBar and dataBarFrames[info.key] then
            local bk = info.key
            elements[#elements + 1] = MK({
                key   = bk,
                label = info.label,
                group = "Action Bars",
                order = orderBase + idx,
                getFrame = function() return dataBarFrames[bk] end,
                getSize = function()
                    -- Return stored DB values so cog menu shows what the
                    -- user typed, not the pixel-snapped frame size.
                    local s = EAB.db.profile.bars[bk]
                    if s then return s.width or 400, s.height or 18 end
                    return 400, 18
                end,
                -- A Custom Border's textured reach past the bar's edges counts
                -- in size matching (the same arguments ApplyDataBarBorder
                -- paints with). nil while Custom Border is off: MakeBorder's
                -- line and solid strips sit inside the frame.
                getMatchPad = function()
                    local s = EAB.db and EAB.db.profile and EAB.db.profile.bars[bk]
                    if not (s and s.customBorder) then return nil end
                    local sz, px = ResolveBorderThickness(s)
                    local c = s.borderColor
                    return EllesmereUI.BorderMatchPad(sz, s.borderTexture or "solid",
                        s.borderTextureOffset, s.borderTextureOffsetY, s.borderTextureShiftX, s.borderTextureShiftY,
                        "actionbars", s.borderThickness or "thin", px, nil, c and c.a or 1)
                end,
                setWidth = function(_, w)
                    local s = EAB.db.profile.bars[bk]
                    local PPab = EllesmereUI and EllesmereUI.PP
                    if s then s.width = PPab and PPab.Snap(w) or math.floor(w + 0.5) end
                    ApplyDataBarLayout(bk)
                end,
                setHeight = function(_, h)
                    local s = EAB.db.profile.bars[bk]
                    local PPab = EllesmereUI and EllesmereUI.PP
                    if s then s.height = PPab and PPab.Snap(h) or math.floor(h + 0.5) end
                    ApplyDataBarLayout(bk)
                end,
                savePos = function(_, point, relPoint, x, y)
                    if point and x and y then
                        EAB.db.profile.barPositions[bk] = {
                            point = point, relPoint = relPoint or point, x = x, y = y,
                        }
                    end
                    if not EllesmereUI._unlockActive then
                        local frame = dataBarFrames[bk]
                        if frame and point and x and y then
                            frame:ClearAllPoints()
                            frame:SetPoint(point, UIParent, relPoint or point, x, y)
                        end
                    end
                end,
                loadPos = function()
                    local pos = EAB.db.profile.barPositions[bk]
                    if not pos then return nil end
                    local pt = pos.point
                    return { point = pt, relPoint = pos.relPoint or pt, x = pos.x, y = pos.y }
                end,
                clearPos = function()
                    EAB.db.profile.barPositions[bk] = nil
                end,
                applyPos = function()
                    local pos = EAB.db.profile.barPositions[bk]
                    local frame = dataBarFrames[bk]
                    if not frame then return end
                    frame:ClearAllPoints()
                    if pos and pos.point then
                        local pt, rpt = pos.point, pos.relPoint or pos.point
                        local px, py = pos.x, pos.y
                        local PPa = EllesmereUI and EllesmereUI.PP
                        if PPa and px and py then
                            local es = frame:GetEffectiveScale()
                            local isCenterAnchor = (pt == "CENTER") and (rpt == "CENTER")
                            if isCenterAnchor and PPa.SnapCenterForDim then
                                px = PPa.SnapCenterForDim(px, frame:GetWidth() or 0, es)
                                py = PPa.SnapCenterForDim(py, frame:GetHeight() or 0, es)
                            elseif PPa.SnapForES then
                                px = PPa.SnapForES(px, es)
                                py = PPa.SnapForES(py, es)
                            end
                        end
                        frame:SetPoint(pt, UIParent, rpt, px or 0, py or 0)
                    else
                        if bk == "XPBar" then
                            frame:SetPoint("TOP", UIParent, "TOP", 0, -100)
                        elseif bk == "RepBar" then
                            frame:SetPoint("TOP", UIParent, "TOP", 0, -84)
                        elseif bk == "FavorBar" then
                            frame:SetPoint("TOP", UIParent, "TOP", 0, -68)
                        end
                    end
                end,
            })
        end
    end
    EllesmereUI:RegisterUnlockElements(elements, "EllesmereUIActionBars")
end

function EAB_VTABLE.ExtraBars.CreateManagedDataBarFrames()
    ns.CreateXPBar()
    CreateRepBar()
    if ns._CreateFavorBar then ns._CreateFavorBar() end
end

function EAB_VTABLE.ExtraBars.InitializeDataBarHoverState()
    for _, info in ipairs(EXTRA_BARS) do
        if info.isDataBar then
            AttachDataBarHoverHooks(info.key)
        end
    end
end

function EAB_VTABLE.ExtraBars.RestoreSavedDataBarPositions()
    local positions = EAB.db.profile.barPositions
    if not positions then return end

    for _, info in ipairs(EXTRA_BARS) do
        if info.isDataBar then
            local pos = positions[info.key]
            local frame = dataBarFrames[info.key]
            if pos and frame and pos.point then
                frame:ClearAllPoints()
                frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
            end
        end
    end
end

function EAB_VTABLE.ExtraBars.RegisterDataBarsWithUnlockModeWhenReady()
    if EllesmereUI and EllesmereUI.RegisterUnlockElements then
        RegisterDataBarsWithUnlockMode()
        return
    end

    C_Timer_After(1, function()
        if EllesmereUI and EllesmereUI.RegisterUnlockElements then
            RegisterDataBarsWithUnlockMode()
        end
    end)
end

function EAB_VTABLE.ExtraBars.EnsureManagedDataBarRuntimeState()
    -- Apply the current combat/group/mouseover state now that every managed
    -- non-secure frame exists. ApplyAll runs earlier in startup before these
    -- holders/data bars are created.
    EAB_VTABLE.ExtraBars._managedNonSecureInCombat = InCombatLockdown()
    EAB_VTABLE.ExtraBars.RefreshManagedNonSecureVisibility()

    if EAB_VTABLE.ExtraBars._managedDataBarCombatFrame then return end

    -- Managed non-secure bars need a runtime combat refresh because secure
    -- state drivers are not available for these frames.
    EAB_VTABLE.ExtraBars._managedDataBarCombatFrame = ns.TakeShell()
    EAB_VTABLE.ExtraBars._managedDataBarCombatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    EAB_VTABLE.ExtraBars._managedDataBarCombatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    EAB_VTABLE.ExtraBars._managedDataBarCombatFrame:SetScript("OnEvent", function(_, event)
        -- Rely on the combat event direction here instead of sampling
        -- `InCombatLockdown()` during the transition. That keeps the managed
        -- non-secure bars in sync with the same edge that triggered the event.
        EAB_VTABLE.ExtraBars._managedNonSecureInCombat = (event == "PLAYER_REGEN_DISABLED")
        EAB_VTABLE.ExtraBars.RefreshManagedNonSecureVisibility()
    end)
end

local function SetupDataBars()
    -- Skip creating custom bars entirely if user wants Blizzard to control them
    if EAB.db.profile.useBlizzardDataBars then return end

    -- Phase 1: create the frames and their update callbacks.
    EAB_VTABLE.ExtraBars.CreateManagedDataBarFrames()

    -- Phase 2: attach hover handling now that the holders exist.
    EAB_VTABLE.ExtraBars.InitializeDataBarHoverState()

    -- Phase 3: restore saved positions onto the live holders.
    EAB_VTABLE.ExtraBars.RestoreSavedDataBarPositions()

    -- Phase 4: register the frames with Unlock Mode once the shared shell is ready.
    EAB_VTABLE.ExtraBars.RegisterDataBarsWithUnlockModeWhenReady()

    -- Phase 5: apply the current runtime visibility state and keep it in sync.
    EAB_VTABLE.ExtraBars.EnsureManagedDataBarRuntimeState()
end

-- The profile's one Blizzard data bar switch (useBlizzardDataBars: the XP,
-- reputation and House Favor bars together), applied live. The XP Bar tab's
-- Blizz Default style and the Use Blizzard's Rep Bars toggle both set it
-- here. On: our built data bars hide (each update then runs its hidden
-- path, so the Favor bar disarms its events) and Blizzard's status tracking
-- bars return. Off: our built bars show unless set to Never and repaint, and
-- Blizzard's hide. Returns true when a bar this client builds does not exist
-- yet (they are built at login only while the switch is off), so the caller
-- can offer a reload. On ns: the chunk is at the local cap.
function ns.SetUseBlizzardDataBars(v)
    local p = EAB.db.profile
    p.useBlizzardDataBars = v
    local anyMissing = false
    for _, info in ipairs(EXTRA_BARS) do
        local k = info.key
        -- WoW Forever builds no House Favor bar: never a reload for it there.
        if info.isDataBar and not (k == "FavorBar" and EllesmereUI.IS_FOREVER) then
            local frame = dataBarFrames[k]
            if not frame then
                if not v then anyMissing = true end
            elseif v then
                frame:Hide()
                if frame._updateFunc then frame._updateFunc() end
            else
                local s = p.bars[k]
                if not s or not s.alwaysHidden then
                    frame:Show()
                    if frame._updateFunc then frame._updateFunc() end
                end
            end
        end
    end
    if StatusTrackingBarManager then
        if v then
            StatusTrackingBarManager:Show()
            StatusTrackingBarManager:RegisterAllEvents()
        else
            StatusTrackingBarManager:UnregisterAllEvents()
            StatusTrackingBarManager:Hide()
        end
    end
    return anyMissing
end

I.SetupDataBars = SetupDataBars -- called by EUI_ActionBars_ExtraBars.lua
