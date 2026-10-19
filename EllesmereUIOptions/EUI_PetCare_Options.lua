if EUI_CLIENT_BLOCKED then return end
local ns = EllesmereUI._ModuleNS.EllesmereUIPetCare
if not ns then return end
local GO = EllesmereUI.GlowOptions
local editID, editDiet, editLevel, browseID = "", 1, 1, nil
local function Cfg() return ns.Config() end
local function Changed()
    ns.Apply()
    EllesmereUI:RefreshPage()
end
local glow = GO.PrefixSite(Cfg, "feedGlow", "icon", Changed, { r = 1, g = 0.7, b = 0.15 })
glow.disabled = function() return not Cfg().enabled end
glow.disabledTooltip = "Enable Pet Feeding"
GO.RegisterSite({ id = "petCareFeeding", group = "module", module = "EllesmereUIPetCare",
    label = "Feeding Glow", page = "Pet Feeding", section = "FEEDING REMINDER",
    highlight = "Feeding Glow", desc = glow })

local function PreviewHeader(parent)
    GO.BuildPreview(parent, glow, { width = 40, height = 40,
        anchor = parent, point = "CENTER", relPoint = "CENTER", x = 0, y = 0,
        atlas = "UI-PetHappiness" })
    return 76
end

local function IDs(key, title)
    local cfg = Cfg()
    local ids = {}
    if key == "preferred" then
        for _, id in ipairs(cfg.preferred) do ids[#ids + 1] = id end
    else
        for id in pairs(cfg.blacklist) do ids[#ids + 1] = id end
        table.sort(ids)
    end
    for i, id in ipairs(ids) do ids[i] = tostring(id) end
    EllesmereUI:ShowInputPopup({
        title = title, maxLetters = 2048, multiline = true, inputHeight = 90,
        message = EllesmereUI.L("Enter item IDs separated by commas. Preferred items are tried in the listed order; excluded items are never used."),
        initialText = table.concat(ids, ", "), allowEmpty = true,
        onConfirm = function(text)
            local parsed = ns.Model.ParseIDs(text)
            if not parsed then
                print(EllesmereUI.L("Pet Care: enter positive whole item IDs separated by commas."))
                return
            end
            if key == "preferred" then cfg.preferred = parsed
            else
                cfg.blacklist = {}
                for _, id in ipairs(parsed) do cfg.blacklist[id] = true end
            end
            cfg.selectedFood = nil
            Changed()
        end,
    })
end

local function BuildPage(page, parent, yOffset)
    local W, cfg = EllesmereUI.Widgets, Cfg()
    local y, h, row = yOffset, 0, nil
    if page == "Pet Feeding" then EllesmereUI:SetContentHeader(PreviewHeader)
    elseif EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end
    parent._showRowDivider = true
    if page ~= "Pet Feeding" and not EllesmereUI._prebuilding then ns.SetWarningPreview(false) end
    local function Dual(a, b)
        row, h = W:DualRow(parent, y, a, b)
        y = y - h
        return row
    end
    local function Toggle(key, text)
        return { type = "toggle", text = text, getValue = function() return cfg[key] == true end,
            setValue = function(v)
                cfg[key] = v
                if key ~= "screenWarning" then cfg.selectedFood = nil end
                Changed()
            end }
    end
    if page == "Pet Feeding" then
        _, h = W:SectionHeader(parent, "PET FEEDING", y); y = y - h
        y = EllesmereUI.BuildNoteRow(parent, y,
            "Uses the hunter pet happiness icon in Unit Frames. Left-click feeds the selected food; Shift-left-click selects another food without feeding. Feeding is disabled in combat.",
            { banner = true })
        Dual(Toggle("enabled", "Enable Pet Feeding"),
            { type = "dropdown", text = "Food Priority", values = {
                most = "Largest Total Quantity", least = "Smallest Total Quantity", level = "Highest Food Level" },
              order = { "most", "least", "level" },
              getValue = function() return cfg.order end,
              setValue = function(v) cfg.order = v; cfg.selectedFood = nil; Changed() end })
        Dual(Toggle("cooked", "Allow Cooked Food"), Toggle("rawMeat", "Allow Raw Meat"))
        local preferredOnly = Toggle("preferredOnly", "Use Preferred Food Only")
        preferredOnly.tooltip = "Only use food IDs entered under Preferred Food IDs. If none of those items are available and suitable, feeding is unavailable; other food in your bags will not be used. Preferred entries bypass raw/cooked filters, but your pet's diet and exclusions still apply."
        Dual(Toggle("rawFish", "Allow Raw Fish"), preferredOnly)
        Dual({ type = "button", text = "Preferred Food IDs",
            tooltip = "Preferred foods are tried first, in the order listed. Other eligible food is used if none is available, unless Use Preferred Food Only is enabled.", onClick = function()
                IDs("preferred", EllesmereUI.L("Preferred Food IDs")) end },
            { type = "button", text = "Excluded Food IDs", onClick = function()
                IDs("blacklist", EllesmereUI.L("Excluded Food IDs")) end })
        _, h = W:SectionHeader(parent, "FEEDING REMINDER", y); y = y - h
        row = Dual(GO.DropdownSpec(glow, "Feeding Glow"),
            { type = "dropdown", text = "Glow When", values = {
                [1] = "Unhappy Only", [2] = "Unhappy or Content", [3] = "Whenever Feeding Is Available" },
              order = { 1, 2, 3 }, getValue = function() return cfg.glowAt end,
              setValue = function(v) cfg.glowAt = v; Changed() end })
        GO.AttachInline(row._leftRegion, glow)
        row = Dual(Toggle("screenWarning", "On-Screen Feeding Warning"),
            EllesmereUI.BlankRowCfg())
        EllesmereUI.BuildInlineCog(row._leftRegion, {
            title = "Screen Warning Settings",
            disabled = function() return not ns.WarningPreviewActive() and (not cfg.enabled or not cfg.screenWarning) end,
            disabledTooltip = "On-Screen Feeding Warning",
            rows = {
                { type = "dropdown", label = "Warn When", values = {
                    [1] = "Unhappy Only", [2] = "Unhappy or Content" }, order = { 1, 2 },
                  get = function() return cfg.warningAt end,
                  set = function(v) cfg.warningAt = v; ns.UpdateWarning() end },
                { type = "slider", label = "Horizontal Offset", min = -1000, max = 1000, step = 1,
                  get = function() return cfg.warningX end,
                  set = function(v) cfg.warningX = v; ns.UpdateWarning() end },
                { type = "slider", label = "Vertical Offset", min = -600, max = 600, step = 1,
                  get = function() return cfg.warningY end,
                  set = function(v) cfg.warningY = v; ns.UpdateWarning() end },
                { type = "slider", label = "Font Size", min = 12, max = 60, step = 1,
                  get = function() return cfg.warningSize end,
                  set = function(v) cfg.warningSize = v; ns.UpdateWarning() end },
            },
        })
        local eye = EllesmereUI.BuildInlineCog(row._leftRegion, {
            icon = EllesmereUI.EYE_VISIBLE_ICON,
            tip = EllesmereUI.L("Preview screen warning"),
            isOpen = function() return ns.WarningPreviewActive() end,
            disabled = function() return InCombatLockdown() end,
            disabledTooltip = "Cannot preview in combat",
            show = function()
                ns.SetWarningPreview(not ns.WarningPreviewActive())
                EllesmereUI:RefreshPage()
            end,
        })
        if eye then
            local function RefreshEye()
                eye._icon:SetTexture(ns.WarningPreviewActive()
                    and EllesmereUI.EYE_INVISIBLE_ICON or EllesmereUI.EYE_VISIBLE_ICON)
                eye._euiCogState()
            end
            EllesmereUI.RegisterWidgetRefresh(RefreshEye)
            RefreshEye()
        end
        y = EllesmereUI.BuildNoteRow(parent, y,
            "The glow pauses while your pet is eating. A cooldown sweep shows the remaining feeding effect. Staple vendor food is allowed by default. Cooked food may include buff food; use exclusions to protect it.",
            { banner = true })
        y = EllesmereUI.BuildNoteRow(parent, y, ns.Status(), { banner = true })
    else
        ns.LoadFoodData()
        _, h = W:SectionHeader(parent, "FOOD DATABASE", y); y = y - h
        y = EllesmereUI.BuildNoteRow(parent, y,
            "Food categories and levels come from the Forever item database. Your pet's diet is matched in the client language. Only food in your carried bags is considered; quest items and excluded items are skipped.",
            { banner = true })
        local names = ns.FOOD_NAMES[GetLocale()] or ns.FOOD_NAMES.enUS
        local values, order = {}, {}
        for id in pairs(ns.FOODS) do order[#order + 1] = id end
        for id in pairs(cfg.customFoods) do if not ns.FOODS[id] then order[#order + 1] = id end end
        table.sort(order)
        for _, id in ipairs(order) do
            values[id] = (C_Item.GetItemNameByID(id) or ns.FOOD_LABELS[id] or "Item") .. " (" .. id .. ")"
        end
        browseID = browseID or order[1]
        Dual({ type = "dropdown", text = "Browse Food", values = values, order = order,
                getValue = function() return browseID end,
                setValue = function(v) browseID = v; EllesmereUI:RefreshPage(true) end },
            { type = "button", text = "Exclude Selected Food", onClick = function()
                if browseID then cfg.blacklist[browseID] = true; Changed() end end })
        Dual({ type = "button", text = "Prefer Selected Food", onClick = function()
                if browseID then
                    for _, id in ipairs(cfg.preferred) do if id == browseID then return end end
                    table.insert(cfg.preferred, 1, browseID)
                    cfg.selectedFood = nil; Changed()
                end end },
            { type = "button", text = "Remove Food Exclusion", onClick = function()
                if browseID then cfg.blacklist[browseID] = nil; Changed() end end })
        local data = cfg.customFoods[browseID] or ns.FOODS[browseID]
        if data then
            y = EllesmereUI.BuildNoteRow(parent, y,
                (names[data[1]] or "?") .. " | " .. EllesmereUI.L("Food Level") .. ": " .. data[2]
                .. (cfg.blacklist[browseID] and (" | " .. EllesmereUI.L("Excluded")) or ""), { banner = true })
        end
        _, h = W:SectionHeader(parent, "CUSTOM FOOD", y); y = y - h
        y = EllesmereUI.BuildNoteRow(parent, y,
            "Custom entries override the database. Enter the item ID, its actual food level and diet category. Incorrect entries may be rejected by the game. Exclusions still take priority.",
            { banner = true })
        Dual({ type = "input", text = "Item ID", inputWidth = 100,
                getValue = function() return editID end, setValue = function(v) editID = v end },
            { type = "dropdown", text = "Food Category", values = names, order = {1,2,3,4,5,6,7,8},
                getValue = function() return editDiet end, setValue = function(v) editDiet = v end })
        Dual({ type = "slider", text = "Food Level", min = 1, max = 100, step = 1,
                getValue = function() return editLevel end, setValue = function(v) editLevel = v end },
            { type = "button", text = "Save Custom Food", onClick = function()
                local id = tonumber(editID)
                if ns.Model.IsItemID(id) then
                    cfg.customFoods[id] = { editDiet, editLevel, 2 }
                    C_Item.RequestLoadItemDataByID(id)
                    browseID = id; Changed(); EllesmereUI:RefreshPage(true)
                else
                    print(EllesmereUI.L("Pet Care: enter positive whole item IDs separated by commas."))
                end end })
        Dual({ type = "button", text = "Remove Custom Entry", onClick = function()
                if browseID then cfg.customFoods[browseID] = nil; browseID = nil; Changed(); EllesmereUI:RefreshPage(true) end end },
            { type = "button", text = "Reset Food Selection", onClick = function()
                cfg.selectedFood = nil; Changed() end })
    end
    return math.abs(y)
end

EllesmereUI:RegisterModule("EllesmereUIPetCare", {
    title = "Pet Care", description = "Hunter pet feeding, food preferences and happiness reminders.",
    pages = { "Pet Feeding", "Food Database" }, buildPage = BuildPage,
    getHeaderBuilder = function(page) return page == "Pet Feeding" and PreviewHeader or nil end,
    onReset = function() ns.db:ResetProfile(); ns.Apply() end,
    onModuleLeave = function() ns.SetWarningPreview(false) end,
    onPageCacheRestore = function(page) if page ~= "Pet Feeding" then ns.SetWarningPreview(false) end end,
})
EllesmereUI:RegisterOnHide(function() ns.SetWarningPreview(false) end)
EllesmereUI:RegisterOnCollapse(function(collapsed) if collapsed then ns.SetWarningPreview(false) end end)
