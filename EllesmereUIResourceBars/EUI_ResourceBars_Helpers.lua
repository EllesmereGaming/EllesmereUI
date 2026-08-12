if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ResourceBars_Options.lua
--  Registers the Resource Bars module with EllesmereUI
--  Pages: Class, Power and Health Bars | Cast Bar | Unlock Mode
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local function DB()
	local db = _G._ERB_AceDB
	return db and db.profile
end

-- A threshold card is shadowed when an earlier card with the same talent gate covers an
-- overlapping spec scope - a duplicate the resolver can never reach (first match wins).
-- Cards that target another spec, or a talent you aren't running right now, are not
-- shadowed. Spec-overlap mirrors the popup's SpecsConflict (a concrete spec shared, or
-- both "All Specs"); an All-Specs card and a spec-specific card do not shadow each
-- other since the resolver prioritises the specific one.
ns._ERB_IsThresholdCardShadowed = function(entries, idx)
    local cur = entries and entries[idx]
    if not cur or not cur.specIDs then return false end
    local curGate = cur.talentSpellID
    local curAll, curSet = false, {}
    for _, s in ipairs(cur.specIDs) do
        if s == 0 then curAll = true else curSet[s] = true end
    end
    for j = 1, idx - 1 do
        local o = entries[j]
        if o and o.specIDs and o.talentSpellID == curGate then
            for _, s in ipairs(o.specIDs) do
                if s == 0 then
                    if curAll then return true end
                elseif curSet[s] then
                    return true
                end
            end
        end
    end
    return false
end

-- The unlock-mode open/close cycle leaves these overlays with an undefined rect, so the
-- frame and its regions draw nothing even though it still exists. Capture the overlay's
-- own anchors + height at build time, then on show re-assert them one frame later
ns.ERB_OverlayHealOnShow = function(ov, obg, olbl, bgAlpha)
	local txt = olbl:GetText() or ""
	local pts = {}
	for p = 1, ov:GetNumPoints() do pts[p] = { ov:GetPoint(p) } end
	local ovH = ov:GetHeight()
	ov:SetScript("OnShow", function()
		C_Timer.After(0, function()
			if not ov:IsVisible() then return end
			if #pts > 0 then
				ov:ClearAllPoints()
				for p = 1, #pts do ov:SetPoint(unpack(pts[p])) end
			end
			if ovH and ovH > 0 then ov:SetHeight(ovH) end
			obg:SetColorTexture(13 / 255, 17 / 255, 25 / 255, bgAlpha or 0.96)
			obg:ClearAllPoints(); obg:SetAllPoints(ov)
			olbl:ClearAllPoints(); olbl:SetPoint("CENTER")
			olbl:SetText(""); olbl:SetText(txt)
		end)
	end)
end

-- Simple page: when the player's current spec overrides this section in
-- Advanced, its Simple controls are being ignored right now. Cover them with
-- a click-to-Advanced hint so edits here aren't silently lost
-- sectionKey: "health" | "primary" | "secondary".
ns.ERB_SimpleOverrideOverlay = function(parent, topY, botY, sectionKey)
	if not topY then return end
	if not (_G._ERB_CurSpecOverridesSection
			and _G._ERB_CurSpecOverridesSection(sectionKey)) then
		return
	end
	local EGc  = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
	local CPAD = EllesmereUI.CONTENT_PAD or 45
	local PP   = EllesmereUI.PanelPP or EllesmereUI.PP
	local ov   = CreateFrame("Button", nil, parent)
	-- Anchor via PP so it lines up with the section header/rows.
	PP.Point(ov, "TOPLEFT", parent, "TOPLEFT", CPAD, topY)
	PP.Point(ov, "TOPRIGHT", parent, "TOPRIGHT", -CPAD, topY)
	PP.Point(ov, "BOTTOMLEFT", parent, "TOPLEFT", CPAD, botY)
	ov:SetFrameLevel(parent:GetFrameLevel() + 50)
	local obg = ov:CreateTexture(nil, "BACKGROUND"); obg:SetAllPoints()
	obg:SetColorTexture(13 / 255, 17 / 255, 25 / 255, 0.9)
	local olbl = EllesmereUI.MakeFont(ov, 12, nil, 1, 1, 1); olbl:SetPoint("CENTER")
	olbl:SetTextColor(1, 1, 1, 0.7)
	olbl:SetText(EllesmereUI.L("Active spec uses Advanced settings")
		.. "   —   " .. EllesmereUI.L("click to edit"))
	ns.ERB_OverlayHealOnShow(ov, obg, olbl, 0.9)
	ov:SetScript("OnEnter", function() olbl:SetTextColor(EGc.r, EGc.g, EGc.b, 1) end)
	ov:SetScript("OnLeave", function() olbl:SetTextColor(1, 1, 1, 0.7) end)
	ov:SetScript("OnClick", function()
		local p = DB(); if not p then return end
		local idx = GetSpecialization and GetSpecialization()
		local cur = idx and C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo(idx)
		if cur then p.advancedSelectedSpec = cur end
		p.barDisplayMode = "advanced"
		EllesmereUI:RefreshPage(true)
		-- Clicking to edit navigates to the top of the Advanced page
		if EllesmereUI.ScrollToTop then EllesmereUI:ScrollToTop() end
	end)
end

local barTypeSpecs = _G._ERB_BAR_TYPE_SPECS or {}
-- bar-type spec lookup
ns.IsSpecBarType = function(specID)
	if specID == 0 then return ns.IsBarTypeSecondary() end
	return barTypeSpecs[specID] or false
end
ns.IsEntryBarType = function(entry)
	if not entry or not entry.specIDs or #entry.specIDs == 0 then return false end
	return ns.IsSpecBarType(entry.specIDs[1])
end
local SpecName = function(specID)
	if specID == 0 then return "All Specs" end
	local _, name, _, _, _, _, className = GetSpecializationInfoByID(specID)
	if name and className then return name .. " " .. className end
	return name or ("Spec " .. specID)
end
ns.EntryLabel = function(entry)
	if not entry or not entry.specIDs or #entry.specIDs == 0 then return "Unknown" end
	if entry.specIDs[1] == 0 then return "All Specs" end
	local names = {}
	for _, sid in ipairs(entry.specIDs) do names[#names + 1] = SpecName(sid) end
	return table.concat(names, ", ")
end

-- Helper: returns true if the current class/spec uses a bar-type secondary (no pips)
ns.IsBarTypeSecondary = function()
	local _, cf = UnitClass("player")
	local spec = GetSpecialization()
	local gsr = _G._ERB_GetSecondaryResource
	local info = gsr and gsr()
	if info and info.power == "IRONFUR_BAR" then return true end            -- Guardian Ironfur bar
	if info and info.power == "IGNOREPAIN_BAR" then return true end         -- Prot Warrior Ignore Pain bar
	if cf == "DRUID" and spec == 1 then return true end                     -- Balance (Astral Power bar)
	if cf == "SHAMAN" and spec == 1 then return true end                    -- Elemental
	if cf == "PRIEST" and spec == 3 then return true end                    -- Shadow
	if cf == "MONK" and spec == 1 then return true end                      -- Brewmaster
	if cf == "HUNTER" and (spec == 1 or spec == 2) then return true end     -- BM / MM Focus bar
	if cf == "DEMONHUNTER" and spec then
		local specID = C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo(spec)
		if specID == 1480 then return true end     -- Devourer
	end
	return false
end

-- Two cards collide in the resolver only if they share a spec context: a common
-- non-zero specID, OR both are All Specs (0). (A spec-specific card and an All-Specs
-- card sit in different resolver tiers, so they never collide.)
ns.SpecsConflict = function(aIDs, bIDs)
	if not aIDs or not bIDs then return false end
	local aHasAll, aSet = false, {}
	for _, s in ipairs(aIDs) do
		if s == 0 then aHasAll = true else aSet[s] = true end
	end
	for _, s in ipairs(bIDs) do
		if s == 0 then
			if aHasAll then return true end
		elseif aSet[s] then
			return true
		end
	end
	return false
end

ns.IsCRSpecClaimed = function(specID)
	local p = DB()
	local sec = p and p.secondary
	if not sec or not sec.thresholdSpecs then return false end
	for _, entry in ipairs(sec.thresholdSpecs) do
		if entry.specIDs then
			for _, sid in ipairs(entry.specIDs) do
				if sid == 0 then return true end
				if sid == specID then return true end
			end
		end
	end
	return false
end

ns.HasCRAllSpecs = function()
	local p = DB()
	local sec = p and p.secondary
	if not sec or not sec.thresholdSpecs then return false end
	for _, entry in ipairs(sec.thresholdSpecs) do
		if entry.specIDs then
			for _, sid in ipairs(entry.specIDs) do
				if sid == 0 then return true end
			end
		end
	end
	return false
end

-- Enumerate every choosable talent in the active loadout (class + spec trees),
-- returning a name-sorted list of { spellID, name }. Returns {} when traits
-- aren't available yet. Only the active loadout is enumerable by the API.
ns.GetLoadoutTalents = function()
	local talents = {}
	local configID = C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
	if not configID then return talents end
	local configInfo = C_Traits and C_Traits.GetConfigInfo and C_Traits.GetConfigInfo(configID)
	if not configInfo or not configInfo.treeIDs then return talents end

	local seenSpells = {}
	for _, treeID in ipairs(configInfo.treeIDs) do
		local nodes = C_Traits.GetTreeNodes(treeID)
		if nodes then
			for _, nodeID in ipairs(nodes) do
				local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
				if nodeInfo and nodeInfo.ID and nodeInfo.ID > 0
					and nodeInfo.entryIDs and #nodeInfo.entryIDs > 0
					and not nodeInfo.subTreeID then
					for _, entryID in ipairs(nodeInfo.entryIDs) do
						local entryInfo = C_Traits.GetEntryInfo(configID, entryID)
						if entryInfo and entryInfo.definitionID then
							local defInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID)
							if defInfo and defInfo.spellID and not seenSpells[defInfo.spellID] then
								local spellName = C_Spell.GetSpellName(defInfo.spellID)
								if spellName and spellName ~= "" then
									seenSpells[defInfo.spellID] = true
									talents[#talents + 1] = { spellID = defInfo.spellID, name = spellName }
								end
							end
						end
					end
				end
			end
		end
	end

	table.sort(talents, function(a, b) return a.name < b.name end)
	return talents
end
