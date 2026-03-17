local addonName, ns = ...

local oUF = ns.oUF
local PP = ns.PP

----------------------------------------------------------------------
--  Helpers
----------------------------------------------------------------------

-- Map sortOrder setting to SecureGroupHeader attributes
local SORT_CONFIGS = {
    role = { groupBy = "ASSIGNEDROLE", groupingOrder = "TANK,HEALER,DAMAGER" },
    group = { groupBy = nil, groupingOrder = nil },
    alphabetical = { groupBy = nil, groupingOrder = nil, sortMethod = "NAME" },
}

-- Map growthDirection to header point/offset
local function GetGrowthAttributes(direction, spacing)
    if direction == "horizontal" then
        return "LEFT", spacing, 0
    else -- vertical (default)
        return "TOP", 0, -spacing
    end
end

----------------------------------------------------------------------
--  Role Icon
----------------------------------------------------------------------

local ROLE_TEXCOORDS = {
    TANK    = { 0, 19/64, 22/64, 41/64 },
    HEALER  = { 20/64, 39/64, 1/64, 20/64 },
    DAMAGER = { 20/64, 39/64, 22/64, 41/64 },
}

local function CreateRoleIcon(frame, settings)
    local icon = frame:CreateTexture(nil, "OVERLAY")
    local sz = math.max(math.floor((settings.textSize or 11) + 2), 10)
    PP.Size(icon, sz, sz)
    icon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
    icon:Hide()

    frame._roleIcon = icon
    return icon
end

local function UpdateRoleIcon(frame)
    local icon = frame._roleIcon
    if not icon then return end

    local db = ns.db
    local settings = db and db.profile and db.profile.party
    if not settings or settings.showRoleIcon == false then
        icon:Hide()
        return
    end

    local unit = frame.unit or frame:GetAttribute("unit")
    if not unit then icon:Hide(); return end

    local role = UnitGroupRolesAssigned(unit)
    local coords = ROLE_TEXCOORDS[role]
    if coords then
        icon:SetTexCoord(unpack(coords))
        icon:Show()
    else
        icon:Hide()
    end
end

----------------------------------------------------------------------
--  Party Aura Filter
----------------------------------------------------------------------

local function PartyAuraFilter(element, unit, data)
    -- Prioritize debuffs the player can dispel
    if data.isDebuff then
        return true
    end
    return false
end

local function CreatePartyAuras(frame, settings)
    if not settings.showDebuffs and not settings.showBuffs then return end

    if settings.showDebuffs then
        local debuffs = CreateFrame("Frame", nil, frame)
        debuffs:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
        debuffs.size = math.floor(settings.healthHeight * 0.5)
        debuffs.num = settings.maxDebuffs or 3
        debuffs["growth-x"] = "RIGHT"
        debuffs.FilterAura = PartyAuraFilter

        debuffs.PostCreateButton = function(self, button)
            button.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            -- Dispellable glow
            if not button._dispelGlow then
                local glow = button:CreateTexture(nil, "OVERLAY")
                glow:SetAllPoints()
                glow:SetColorTexture(1, 1, 1, 0)
                button._dispelGlow = glow
            end
        end

        debuffs.PostUpdateButton = function(self, button, unit, data)
            if button._dispelGlow then
                local db = ns.db
                local s = db and db.profile and db.profile.party
                if s and s.highlightDispellable and data.isDebuff and data.dispelName then
                    button._dispelGlow:SetColorTexture(0, 0.8, 1, 0.3)
                else
                    button._dispelGlow:SetColorTexture(1, 1, 1, 0)
                end
            end
        end

        frame.Debuffs = debuffs
    end

    if settings.showBuffs and (settings.maxBuffs or 0) > 0 then
        local buffs = CreateFrame("Frame", nil, frame)
        buffs:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
        buffs.size = math.floor(settings.healthHeight * 0.5)
        buffs.num = settings.maxBuffs or 0
        buffs["growth-x"] = "LEFT"
        buffs.PostCreateButton = function(self, button)
            button.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        frame.Buffs = buffs
    end
end

----------------------------------------------------------------------
--  StylePartyFrame
----------------------------------------------------------------------

local function StylePartyFrame(frame, unit)
    local db = ns.db
    if not db then return end

    local settings = db.profile.party
    if not settings then return end

    local ppPos = settings.powerPosition or "below"
    local ppIsAtt = (ppPos == "below" or ppPos == "above")
    local powerHeight = ppIsAtt and (settings.powerHeight or 4) or 0
    local totalHeight = settings.healthHeight + powerHeight
    local totalWidth = settings.frameWidth

    -- Portrait adds width when visible
    local showPortrait = settings.showPortrait ~= false
        and (db.profile.portraitStyle or "attached") ~= "none"
    if showPortrait then
        totalWidth = totalHeight + settings.frameWidth
    end

    PP.Size(frame, totalWidth, totalHeight)

    -- Health bar
    local healthRightInset = showPortrait and totalHeight or 0
    frame.Health = ns.CreateHealthBar(frame, unit, settings.healthHeight, 0, settings, healthRightInset)

    -- Absorb bar
    ns.CreateAbsorbBar(frame, unit, settings)

    -- Power bar
    if ppPos ~= "none" then
        frame.Power = ns.CreatePowerBar(frame, unit, settings)
    end

    -- Portrait (always create, hide backdrop when disabled — same pattern as boss)
    frame.Portrait = ns.CreatePortrait(frame, "left", totalHeight, unit)
    frame._portraitSide = "left"
    if frame.Portrait and not showPortrait then
        frame.Portrait.backdrop:Hide()
    end

    -- Re-anchor health bar to portrait's snapped width (same fix as boss frames)
    if frame.Portrait and frame.Portrait.backdrop and showPortrait and frame.Health then
        local snappedPortW = frame.Portrait.backdrop:GetWidth()
        local powerAboveOff = (ppPos == "above") and (settings.powerHeight or 4) or 0
        frame.Health:ClearAllPoints()
        PP.Point(frame.Health, "TOPLEFT", frame, "TOPLEFT", snappedPortW, -powerAboveOff)
        PP.Point(frame.Health, "RIGHT", frame, "RIGHT", 0, 0)
        PP.Height(frame.Health, settings.healthHeight)
        frame.Health._xOffset = snappedPortW
        frame.Health._rightInset = 0
        frame.Health._topOffset = powerAboveOff
    end

    -- Border
    ns.CreateUnifiedBorder(frame, unit)
    ns.UpdateBordersForScale(frame, unit)

    -- Clip bars to prevent overflow
    ns.ReparentBarsToClip(frame)

    -- Text overlay
    local textOverlay = CreateFrame("Frame", nil, frame.Health)
    textOverlay:SetAllPoints(frame.Health)
    textOverlay:SetFrameLevel(frame.Health:GetFrameLevel() + 12)
    frame._textOverlay = textOverlay

    local ts = settings.textSize or 11
    local leftContent = settings.leftTextContent or "name"
    local rightContent = settings.rightTextContent or "perhp"
    local centerContent = settings.centerTextContent or "none"

    local leftText = textOverlay:CreateFontString(nil, "OVERLAY")
    ns.SetFSFont(leftText, ts)
    leftText:SetWordWrap(false)
    leftText:SetTextColor(1, 1, 1)
    frame.LeftText = leftText

    local rightText = textOverlay:CreateFontString(nil, "OVERLAY")
    ns.SetFSFont(rightText, ts)
    rightText:SetWordWrap(false)
    rightText:SetTextColor(1, 1, 1)
    frame.RightText = rightText

    local centerText = textOverlay:CreateFontString(nil, "OVERLAY")
    ns.SetFSFont(centerText, ts)
    centerText:SetWordWrap(false)
    centerText:SetTextColor(1, 1, 1)
    frame.CenterText = centerText

    frame.NameText = leftText
    frame.HealthValue = rightText

    -- Tag system (same pattern as boss frames)
    local function ApplyTextTags(lc, rc, cc)
        local ltag = ns.ContentToTag(lc)
        local rtag = ns.ContentToTag(rc)
        local ctag = ns.ContentToTag(cc)
        if leftText._curTag then frame:Untag(leftText); leftText._curTag = nil end
        if rightText._curTag then frame:Untag(rightText); rightText._curTag = nil end
        if centerText._curTag then frame:Untag(centerText); centerText._curTag = nil end
        if ltag then frame:Tag(leftText, ltag); leftText._curTag = ltag end
        if rtag then frame:Tag(rightText, rtag); rightText._curTag = rtag end
        if ctag then frame:Tag(centerText, ctag); centerText._curTag = ctag end
        if frame.UpdateTags then frame:UpdateTags() end
    end
    ApplyTextTags(leftContent, rightContent, centerContent)
    frame._applyTextTags = ApplyTextTags

    -- Text positioning (same pattern as boss frames)
    local function ApplyTextPositions(s)
        local lc = s.leftTextContent or "name"
        local rc = s.rightTextContent or "perhp"
        local cc = s.centerTextContent or "none"
        local barW = s.frameWidth or 160

        -- Account for role icon width on the left
        local roleOffset = (s.showRoleIcon ~= false) and (ts + 6) or 0

        if cc ~= "none" then
            centerText:ClearAllPoints()
            centerText:SetPoint("CENTER", frame.Health, "CENTER", 0, 0)
            centerText:SetWidth(0)
            centerText:Show()
            leftText:Hide(); rightText:Hide()
        else
            centerText:Hide()
            if lc ~= "none" then
                leftText:ClearAllPoints()
                leftText:SetPoint("LEFT", frame.Health, "LEFT", 5 + roleOffset, 0)
                leftText:SetJustifyH("LEFT")
                if rc ~= "none" then
                    local rightUsed = ns.EstimateUFTextWidth(rc)
                    PP.Width(leftText, math.max(barW - rightUsed - 10 - roleOffset, 20))
                else
                    leftText:SetWidth(0)
                end
                leftText:Show()
            else leftText:Hide() end
            if rc ~= "none" then
                rightText:ClearAllPoints()
                rightText:SetPoint("RIGHT", frame.Health, "RIGHT", -5, 0)
                rightText:SetJustifyH("RIGHT")
                if lc ~= "none" then
                    local leftUsed = ns.EstimateUFTextWidth(lc)
                    PP.Width(rightText, math.max(barW - leftUsed - 10 - roleOffset, 20))
                else
                    rightText:SetWidth(0)
                end
                rightText:Show()
            else rightText:Hide() end
        end
    end
    ApplyTextPositions(settings)
    frame._applyTextPositions = ApplyTextPositions

    -- Role icon (anchored to left of health bar, before name text)
    local roleIcon = CreateRoleIcon(frame, settings)
    roleIcon:SetPoint("LEFT", frame.Health, "LEFT", 4, 0)

    -- Auras
    CreatePartyAuras(frame, settings)

    -- Range fading
    if settings.enableRangeFade ~= false then
        frame.Range = {
            insideAlpha = 1,
            outsideAlpha = settings.rangeFadeAlpha or 0.4,
        }
    end

    -- Threat indicator (border glow)
    if settings.showThreat ~= false then
        local threat = frame:CreateTexture(nil, "OVERLAY")
        threat:SetAllPoints()
        threat:Hide()
        frame.ThreatIndicator = threat
    end

    -- Ready check
    local readyCheck = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    readyCheck:SetSize(16, 16)
    readyCheck:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.ReadyCheckIndicator = readyCheck

    -- Leader indicator
    local leader = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    leader:SetSize(12, 12)
    leader:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
    frame.LeaderIndicator = leader

    -- Assistant indicator
    local assist = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    assist:SetSize(12, 12)
    assist:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
    frame.AssistantIndicator = assist

    -- Resurrection indicator
    local resurrect = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    resurrect:SetSize(20, 20)
    resurrect:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.ResurrectIndicator = resurrect

    -- Summon indicator
    local summon = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    summon:SetSize(24, 24)
    summon:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.SummonIndicator = summon

    -- Hook for role icon updates
    -- Note: WoW Frame:RegisterEvent takes only event name (no callback arg).
    -- Use OnEvent script + OnShow hook instead.
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
    frame:HookScript("OnEvent", function(self, event)
        if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" then
            UpdateRoleIcon(self)
        end
    end)
    frame:HookScript("OnShow", function(self)
        UpdateRoleIcon(self)
    end)

    -- Right-click menu
    if ns.SetupUnitMenu then
        ns.SetupUnitMenu(frame, unit or "party")
    end
end

----------------------------------------------------------------------
--  SpawnPartyHeader
----------------------------------------------------------------------

local partyHeader

local function SpawnPartyHeader()
    local db = ns.db
    if not db then return end

    local settings = db.profile.party
    if not settings then return end

    local point, xOff, yOff = GetGrowthAttributes(
        settings.growthDirection or "vertical",
        settings.spacing or 1
    )

    -- Sort config
    local sortCfg = SORT_CONFIGS[settings.sortOrder or "role"] or SORT_CONFIGS.role

    -- Guard: oUF errors on duplicate style registration (e.g. during ReloadFrames)
    if not oUF.styles or not oUF.styles["EllesmereParty"] then
        oUF:RegisterStyle("EllesmereParty", StylePartyFrame)
    end
    oUF:SetActiveStyle("EllesmereParty")

    local headerArgs = {
        "showPlayer", settings.showPlayer or false,
        "showParty", true,
        "showSolo", false,
        "point", point,
        "xOffset", xOff,
        "yOffset", yOff,
        "oUF-initialConfigFunction", ([[
            self:SetWidth(%d)
            self:SetHeight(%d)
        ]]):format(settings.frameWidth or 160, (settings.healthHeight or 36) + ((settings.powerPosition ~= "none") and (settings.powerHeight or 4) or 0)),
    }

    -- Add sort attributes
    if sortCfg.groupBy then
        headerArgs[#headerArgs + 1] = "groupBy"
        headerArgs[#headerArgs + 1] = sortCfg.groupBy
    end
    if sortCfg.groupingOrder then
        headerArgs[#headerArgs + 1] = "groupingOrder"
        headerArgs[#headerArgs + 1] = sortCfg.groupingOrder
    end
    if sortCfg.sortMethod then
        headerArgs[#headerArgs + 1] = "sortMethod"
        headerArgs[#headerArgs + 1] = sortCfg.sortMethod
    end

    partyHeader = oUF:SpawnHeader(
        "EllesmereUIPartyHeader",
        nil,
        "custom [@party1,exists] show;hide",
        unpack(headerArgs)
    )

    ns.ApplyFramePosition(partyHeader, "party")

    local enabled = db.profile.enabledFrames
    if enabled.party == false then
        RegisterAttributeDriver(partyHeader, "state-visibility", "hide")
    end

    -- Store reference
    ns.partyHeader = partyHeader

    return partyHeader
end

----------------------------------------------------------------------
--  UpdatePartyLayout (out of combat only)
----------------------------------------------------------------------

local function UpdatePartyLayout()
    if InCombatLockdown() or not partyHeader then return end

    local db = ns.db
    if not db then return end

    local settings = db.profile.party
    if not settings then return end

    local point, xOff, yOff = GetGrowthAttributes(
        settings.growthDirection or "vertical",
        settings.spacing or 1
    )

    partyHeader:SetAttribute("point", point)
    partyHeader:SetAttribute("xOffset", xOff)
    partyHeader:SetAttribute("yOffset", yOff)
    partyHeader:SetAttribute("showPlayer", settings.showPlayer or false)

    -- Always set all sort attributes to clear stale values when switching modes
    local sortCfg = SORT_CONFIGS[settings.sortOrder or "role"] or SORT_CONFIGS.role
    partyHeader:SetAttribute("groupBy", sortCfg.groupBy)
    partyHeader:SetAttribute("groupingOrder", sortCfg.groupingOrder)
    partyHeader:SetAttribute("sortMethod", sortCfg.sortMethod)

    ns.ApplyFramePosition(partyHeader, "party")
end

----------------------------------------------------------------------
--  Public API
----------------------------------------------------------------------

ns.SpawnPartyHeader = SpawnPartyHeader
ns.UpdatePartyLayout = UpdatePartyLayout
ns.StylePartyFrame = StylePartyFrame
