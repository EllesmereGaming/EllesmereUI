-- C_Spell
if not C_Spell then
    C_Spell = {}

    C_Spell.GetSpellInfo = function(spell)
        local name, rank, icon, castTime, minRange, maxRange, spellID = GetSpellInfo(spell)
        if name then
            return {
                name = name,
                iconID = icon,
                originalIconID = icon,
                castTime = castTime,
                minRange = minRange,
                maxRange = maxRange,
                spellID = spellID or (type(spell) == "number" and spell) or nil
            }
        end
        return nil
    end

    C_Spell.GetSpellCooldown = function(spell)
        return GetSpellCooldown(spell)
    end

    C_Spell.GetSpellCooldownDuration = function(spell)
        local start, duration = GetSpellCooldown(spell)
        start = start or 0
        duration = duration or 0
        return _G.EllesmereUI.DurationObject:Create(start, duration, start + duration)
    end

    C_Spell.IsSpellPassive = function(spellID)
        if IsPassiveSpell then
            return IsPassiveSpell(spellID) == true
        end
        return false
    end

    C_Spell.GetSpellName = function(spell)
        return select(1, GetSpellInfo(spell))
    end

    C_Spell.GetSpellTexture = function(spell)
        return select(3, GetSpellInfo(spell))
    end

    C_Spell.GetSpellDescription = function(spell)
        if GetSpellDescription then
            return GetSpellDescription(spell)
        end
        return ""
    end

    C_Spell.IsSpellInRange = function(spell, unit)
        if IsSpellInRange then
            return IsSpellInRange(spell, unit)
        end
        return nil
    end

    C_Spell.GetSpellCastCount = function(spell)
        return 0
    end

    C_Spell.GetSpellCharges = function(spell)
        return {
            currentCharges = 0,
            maxCharges = 0,
            cooldownStart = 0,
            cooldownDuration = 0
        }
    end
end
