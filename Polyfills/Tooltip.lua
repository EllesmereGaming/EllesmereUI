-- TooltipDataProcessor Polyfill
if not TooltipDataProcessor then
    TooltipDataProcessor = {}
    local tooltipCallbacks = {}

    TooltipDataProcessor.AddTooltipPostCall = function(dataType, callback)
        if not tooltipCallbacks[dataType] then
            tooltipCallbacks[dataType] = {}
        end
        table.insert(tooltipCallbacks[dataType], callback)
    end

    local function OnTooltipSetSpell(self)
        if not self.GetSpell then return end
        local name, rank, id = self:GetSpell()
        if id and tooltipCallbacks[Enum.TooltipDataType.Spell] then
            local tooltipData = { id = id }
            for _, cb in ipairs(tooltipCallbacks[Enum.TooltipDataType.Spell]) do
                pcall(cb, self, tooltipData)
            end
        end
    end

    local function OnTooltipSetItem(self)
        if not self.GetItem then return end
        local name, link = self:GetItem()
        if link then
            local id = tonumber(link:match("item:(%d+)"))
            if id and tooltipCallbacks[Enum.TooltipDataType.Item] then
                local tooltipData = { id = id }
                for _, cb in ipairs(tooltipCallbacks[Enum.TooltipDataType.Item]) do
                    pcall(cb, self, tooltipData)
                end
            end
        end
    end

    if GameTooltip then
        GameTooltip:HookScript("OnTooltipSetSpell", OnTooltipSetSpell)
        GameTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
    end
    if ItemRefTooltip then
        ItemRefTooltip:HookScript("OnTooltipSetSpell", OnTooltipSetSpell)
        ItemRefTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
    end

    if GameTooltip.SetUnitAura then
        hooksecurefunc(GameTooltip, "SetUnitAura", function(self, unit, index, filter)
            if tooltipCallbacks[Enum.TooltipDataType.UnitAura] then
                local _, _, _, _, _, _, _, _, _, _, spellID = UnitAura(unit, index, filter)
                if spellID then
                    local tooltipData = { id = spellID }
                    for _, cb in ipairs(tooltipCallbacks[Enum.TooltipDataType.UnitAura]) do
                        pcall(cb, self, tooltipData)
                    end
                end
            end
        end)
    end

    if GameTooltip.SetUnitBuff then
        hooksecurefunc(GameTooltip, "SetUnitBuff", function(self, unit, index)
            if tooltipCallbacks[Enum.TooltipDataType.UnitAura] then
                local _, _, _, _, _, _, _, _, _, _, spellID = UnitBuff(unit, index)
                if spellID then
                    local tooltipData = { id = spellID }
                    for _, cb in ipairs(tooltipCallbacks[Enum.TooltipDataType.UnitAura]) do
                        pcall(cb, self, tooltipData)
                    end
                end
            end
        end)
    end

    if GameTooltip.SetUnitDebuff then
        hooksecurefunc(GameTooltip, "SetUnitDebuff", function(self, unit, index)
            if tooltipCallbacks[Enum.TooltipDataType.UnitAura] then
                local _, _, _, _, _, _, _, _, _, _, spellID = UnitDebuff(unit, index)
                if spellID then
                    local tooltipData = { id = spellID }
                    for _, cb in ipairs(tooltipCallbacks[Enum.TooltipDataType.UnitAura]) do
                        pcall(cb, self, tooltipData)
                    end
                end
            end
        end)
    end
end
