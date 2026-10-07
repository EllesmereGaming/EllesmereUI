if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end -- Forever Essentials loads on WoW Forever only
-------------------------------------------------------------------------------
--  EUI_ForeverEssentials_Targets_Options.lua
--  Builds the "Targets" page inside the Forever Essentials module: the Target
--  Helper's settings, then its farm list (grouped by category) and every
--  quest in the log with its objectives. Kill objectives can be switched off
--  for the bar; other objectives are listed for reference.
--  The list rows are pooled and re-parented into each rebuilt page.
-------------------------------------------------------------------------------
if not EllesmereUI._ModuleNS["EllesmereUIForeverEssentials"] then return end  -- module disabled: no options page

local ICONS = "Interface\\AddOns\\EllesmereUI\\media\\icons\\"
local LIST_H = 28
local QUEST_C = { 0.88, 0.72, 0.31 }
local FARM_C = { 0.44, 0.66, 0.86 }

local pool, used = {}, 0
local shownParent

local function Glyph(parent, file, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(14, 14)
    b.tex = b:CreateTexture(nil, "OVERLAY")
    b.tex:SetAllPoints()
    b.tex:SetTexture(ICONS .. file)
    b:SetAlpha(0.5)
    b:SetScript("OnEnter", function(self) self:SetAlpha(0.9) end)
    b:SetScript("OnLeave", function(self) self:SetAlpha(0.5) end)
    b:SetScript("OnClick", onClick)
    return b
end

-- One pooled list row; its parts are shown as each line needs them.
local function NewRow()
    local r = CreateFrame("Button", nil, UIParent)
    r:SetHeight(LIST_H)
    r.bg = EllesmereUI.SolidTex(r, "BACKGROUND", 0, 0, 0, 0.1)
    r.bg:SetAllPoints()
    r.text = EllesmereUI.MakeFont(r, 12, nil, 1, 1, 1, 1)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r.right = EllesmereUI.MakeFont(r, 11, nil, 1, 1, 1, 0.53)
    r.right:SetJustifyH("RIGHT")
    r.right:SetWordWrap(false)

    r.marker = CreateFrame("Button", nil, r)
    r.marker:SetSize(16, 16)
    r.marker.tex = r.marker:CreateTexture(nil, "ARTWORK")
    r.marker.tex:SetAllPoints()
    r.marker:SetScript("OnClick", function(self) if r.onMarker then r.onMarker(self) end end)

    r.check = CreateFrame("Button", nil, r)
    r.check:SetSize(14, 14)
    EllesmereUI.SolidTex(r.check, "BACKGROUND", 0.114, 0.106, 0.098, 1):SetAllPoints()
    EllesmereUI.MakeBorder(r.check, 1, 1, 1, 0.15)
    r.check.mark = r.check:CreateTexture(nil, "ARTWORK")
    r.check.mark:SetPoint("TOPLEFT", 3, -3)
    r.check.mark:SetPoint("BOTTOMRIGHT", -3, 3)
    r.check:SetScript("OnClick", function() if r.onCheck then r.onCheck() end end)

    r.del = Glyph(r, "eui-close.png", function() if r.onDelete then r.onDelete() end end)
    r.del:SetPoint("RIGHT", -16, 0)
    r.down = Glyph(r, "eui-arrow-down3.png", function() if r.onMove then r.onMove(1) end end)
    r.down:SetPoint("RIGHT", r.del, "LEFT", -6, 0)
    r.up = Glyph(r, "eui-arrow-up3.png", function() if r.onMove then r.onMove(-1) end end)
    r.up:SetPoint("RIGHT", r.down, "LEFT", -4, 0)
    return r
end

-- The next row at y, emptied; indent moves its text right.
local function NextRow(parent, y, indent)
    used = used + 1
    local r = pool[used]
    if not r then
        r = NewRow()
        pool[used] = r
    end
    local pad = EllesmereUI.CONTENT_PAD
    r:SetParent(parent)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", parent, "TOPLEFT", pad, y)
    r:SetPoint("RIGHT", parent, "RIGHT", -pad, 0)
    r.onCheck, r.onMarker, r.onDelete, r.onMove = nil, nil, nil, nil
    r.check:Hide()
    r.marker:Hide()
    r.del:Hide()
    r.up:Hide()
    r.down:Hide()
    r.bg:SetColorTexture(0, 0, 0, used % 2 == 0 and 0.2 or 0.1)
    r.text:SetTextColor(1, 1, 1, 1)
    r.right:SetText("")
    r.right:ClearAllPoints()
    r.right:SetPoint("RIGHT", -20, 0)
    r.text:ClearAllPoints()
    r.text:SetPoint("LEFT", 20 + (indent or 0), 0)
    r.text:SetPoint("RIGHT", r.right, "LEFT", -10, 0)
    r:Show()
    return r
end

local function Note(parent, y, text)
    local r = NextRow(parent, y, 0)
    r.text:SetTextColor(1, 1, 1, 0.53)
    r.text:SetText(text)
    return y - LIST_H
end

local function BuildFarmList(parent, y, TH)
    local farm = TH.Read("farm")
    if #farm == 0 then return Note(parent, y, EllesmereUI.L("None yet. Enter a name above or target a mob.")) end
    local order, groups = {}, {}
    for _, f in ipairs(farm) do
        local cat = f.cat or TH.FARM_CATEGORY
        if not groups[cat] then
            groups[cat] = {}
            order[#order + 1] = cat
        end
        table.insert(groups[cat], f)
    end
    for _, cat in ipairs(order) do
        local h = NextRow(parent, y, 0)
        h.text:SetTextColor(FARM_C[1], FARM_C[2], FARM_C[3], 1)
        h.text:SetText(cat)
        h.right:SetText(#groups[cat])
        y = y - LIST_H
        for _, f in ipairs(groups[cat]) do
            local name = f.name
            local r = NextRow(parent, y, 26)
            local m = TH.MarkerFor(name)
            r.marker:Show()
            r.marker:ClearAllPoints()
            r.marker:SetPoint("LEFT", 20, 0)
            r.marker.tex:SetTexture(TH.MarkerTexture(m) or TH.NO_MARKER)
            r.onMarker = function(anchor)
                local items = { TH.MarkerMenu(m, function(v) TH.SetMarker(name, v) end) }
                EllesmereUI.ShowContextMenu(anchor, TH.FarmMenuItems(name, items), { below = true })
            end
            r.text:SetText(name)
            if not TH.FarmInZone(f) then r.text:SetTextColor(1, 1, 1, 0.53) end
            r.right:SetText(f.sub and (f.sub .. ", " .. (f.zone or "?")) or (f.zone or "?"))
            r.del:Show()
            r.onDelete = function() TH.RemoveFarm(name) end
            r.up:SetShown(TH.FarmNeighbour(name, -1) ~= nil)
            r.down:SetShown(TH.FarmNeighbour(name, 1) ~= nil)
            r.onMove = function(d) TH.MoveFarm(name, d) end
            r.right:ClearAllPoints()
            r.right:SetPoint("RIGHT", r.up, "LEFT", -10, 0)
            y = y - LIST_H
        end
    end
    return y
end

local function BuildQuestList(parent, y, TH, TG)
    if not TG.Get("enabled") then return Note(parent, y, EllesmereUI.L("Enable the Target Helper to list your quests.")) end
    local quests = TH.Quests()
    if #quests == 0 then return Note(parent, y, EllesmereUI.L("No quests in your quest log.")) end
    local hidden = TH.Read("hidden")
    local ac = EllesmereUI.ELLESMERE_GREEN
    for _, q in ipairs(quests) do
        local h = NextRow(parent, y, 0)
        local inZone = not TG.Get("zoneOnly") or TH.QuestInZone(q)
        h.text:SetTextColor(QUEST_C[1], QUEST_C[2], QUEST_C[3], inZone and 1 or 0.5)
        h.text:SetText(q.title)
        h.right:SetText(q.zone or "")
        y = y - LIST_H
        if #q.objectives == 0 then y = Note(parent, y, "    " .. EllesmereUI.L("No objectives")) end
        for _, ob in ipairs(q.objectives) do
            local r = NextRow(parent, y, 26)
            r.right:SetText((ob.have and ob.need) and (ob.have .. "/" .. ob.need) or "")
            if ob.kill then
                local key = ob.key
                r.check:Show()
                r.check:ClearAllPoints()
                r.check:SetPoint("LEFT", 22, 0)
                r.check.mark:SetColorTexture(ac.r, ac.g, ac.b, 1)
                r.check.mark:SetShown(not hidden[key])
                r.onCheck = function() TH.SetQuestHidden(key, not hidden[key]) end
                r.text:SetText(ob.name)
                if ob.finished then
                    r.text:SetTextColor(1, 1, 1, 0.53)
                    r.right:SetText(EllesmereUI.L("Done"))
                end
            else
                r.text:SetTextColor(1, 1, 1, 0.53)
                local kind = ob.type == "item" and EllesmereUI.L("Item") or (ob.type or "?")
                r.text:SetText((ob.name or ob.text or "?") .. "  |cff8a8a8a[" .. kind .. "]|r")
            end
            y = y - LIST_H
        end
    end
    return y
end

_G._EUI_BuildTargetHelperPage = function(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local TG = EllesmereUI._TargetHelper
    local TH = TG.TH
    local BLANK = EllesmereUI.BlankRowCfg
    local y = yOffset
    local _, h
    parent._showRowDivider = true

    local function off()
        return not TG.Get("enabled")
    end
    -- Binds cfg to setting key; apply runs after a change. Greyed out while
    -- the helper is off unless disabled is given.
    local function Bind(cfg, key, apply, disabled, disabledTooltip)
        cfg.disabled, cfg.disabledTooltip = disabled or off, disabledTooltip or "Target Helper"
        cfg.getValue = cfg.getValue or function() return TG.Get(key) end
        cfg.setValue = cfg.setValue or function(v)
            TG.Cfg()[key] = v
            if apply then apply() end
        end
        return cfg
    end
    -- Settings that change which targets are listed.
    local function Toggle(key, text, tooltip, disabled, disabledTooltip)
        return Bind({ type = "toggle", text = text, tooltip = tooltip }, key, TH.Changed, disabled, disabledTooltip)
    end

    ---------------------------------------------------------------------------
    --  TARGET HELPER
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "TARGET HELPER", y);  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Enable Target Helper",
          tooltip = "A bar of target buttons for your quest mobs and farm targets. A click targets the mob and puts a raid marker on it.",
          getValue = function() return not off() end,
          setValue = function(v)
              TG.Cfg().enabled = v
              TG.Apply()
              EllesmereUI:RefreshPage(true)
          end },
        { type = "labeledButton", text = "Farm Target", buttonText = "Add Current Target",
          tooltip = "Adds your current target to the farm list.",
          disabled = off, disabledTooltip = "Target Helper",
          onClick = function() TH.AddCurrentTarget() end }
    );  y = y - h

    _, h = W:DualRow(parent, y,
        Toggle("showQuests", "Show Quest Targets", "Lists the unfinished kill objectives of your quests."),
        Toggle("questsFirst", "Quest Targets First", "Lists quest targets above farm targets.",
            function() return off() or not TG.Get("showQuests") end,
            function() return off() and "Target Helper" or "Show Quest Targets" end)
    );  y = y - h

    _, h = W:DualRow(parent, y,
        Toggle("zoneOnly", "Current Zone Only", "Only lists targets of the zone you are in."),
        Toggle("showCategories", "Show Categories", "Groups the bar by quest and farm category.")
    );  y = y - h

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  TARGETING
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "TARGETING", y);  y = y - h

    local markerValues, markerOrder = {}, {}
    for m = 8, 0, -1 do
        local key = tostring(m)
        local tex = TH.MarkerTexture(m) or TH.NO_MARKER
        markerValues[key] = "|T" .. tex .. ":14:14|t  " .. (m > 0 and _G["RAID_TARGET_" .. m] or EllesmereUI.L("No Marker"))
        markerOrder[#markerOrder + 1] = key
    end

    _, h = W:DualRow(parent, y,
        Toggle("skipDead", "Ignore Dead Mobs", "Never targets a corpse."),
        Toggle("skipMarked", "Skip Mobs Marked by Others",
            "Passes over mobs a group member already marked. Out of combat only.")
    );  y = y - h

    _, h = W:DualRow(parent, y,
        Toggle("skipTapped", "Skip Mobs Tagged by Others",
            "Passes over mobs another player already tagged. Out of combat only."),
        Bind({ type = "dropdown", text = "Default Marker", values = markerValues, order = markerOrder,
               tooltip = "Used for every target without its own marker. Right-click a row on the bar to give it its own.",
               getValue = function() return tostring(TG.Get("defaultMarker")) end,
               setValue = function(v)
                   TG.Cfg().defaultMarker = tonumber(v)
                   TH.Changed()
               end })
    );  y = y - h

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  DISPLAY
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "DISPLAY", y);  y = y - h

    _, h = W:DualRow(parent, y,
        Bind({ type = "slider", text = "Width", min = 150, max = 400, step = 1 }, "width", TG.Refresh),
        Toggle("showPortraits", "Show Portraits", "A small 3D portrait of the mob on each row.")
    );  y = y - h

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  FARM TARGETS
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "FARM TARGETS", y);  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "input", text = "Add Farm Target", inputStyle = "popup", inputWidth = 200,
          placeholder = "Mob name",
          tooltip = "Adds a mob by name, bound to the zone you are in.",
          disabled = off, disabledTooltip = "Target Helper",
          getValue = function() return "" end,
          setValue = function(text)
              if TH.Trim(text) ~= "" then TH.AddFarm(text) end
          end },
        BLANK()
    );  y = y - h

    if EllesmereUI._prebuilding then return math.abs(y) end

    for i = 1, #pool do pool[i]:Hide() end
    used = 0
    shownParent = parent

    y = BuildFarmList(parent, y - 4, TH)

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  QUEST TARGETS
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "QUEST TARGETS", y);  y = y - h

    y = BuildQuestList(parent, y - 4, TH, TG)

    return math.abs(y) + 10
end

-- A list change while the page is on screen rebuilds it.
EllesmereUI._TargetHelper.TH.OnChange(function()
    if shownParent and shownParent:IsVisible() then EllesmereUI:RefreshPage(true) end
end)
