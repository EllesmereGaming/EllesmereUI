local _G = _G or getfenv(0)
local EllesmereUI = _G.EllesmereUI or {}

_G.EllesmereUI = EllesmereUI
EUI = EUI or {}
EUI.Spec = EUI.Spec or {}

local Spec = EUI.Spec

local CLASS_SPECS = {
    WARRIOR = {
        { id = 71, name = "Arms",        fileName = "WarriorArms",        role = "DAMAGER" },
        { id = 72, name = "Fury",        fileName = "WarriorFury",        role = "DAMAGER" },
        { id = 73, name = "Protection", fileName = "WarriorProtection", role = "TANK"    },
    },
    PALADIN = {
        { id = 65, name = "Holy",        fileName = "PaladinHoly",        role = "HEALER"  },
        { id = 66, name = "Protection", fileName = "PaladinProtection", role = "TANK"    },
        { id = 70, name = "Retribution", fileName = "PaladinRetribution", role = "DAMAGER" },
    },
    HUNTER = {
        { id = 253, name = "Beast Mastery", fileName = "HunterBeastMastery", role = "DAMAGER" },
        { id = 254, name = "Marksmanship",  fileName = "HunterMarksmanship",  role = "DAMAGER" },
        { id = 255, name = "Survival",      fileName = "HunterSurvival",      role = "DAMAGER" },
    },
    ROGUE = {
        { id = 259, name = "Assassination", fileName = "RogueAssassination", role = "DAMAGER" },
        { id = 260, name = "Combat",        fileName = "RogueCombat",        role = "DAMAGER" },
        { id = 261, name = "Subtlety",      fileName = "RogueSubtlety",      role = "DAMAGER" },
    },
    PRIEST = {
        { id = 256, name = "Discipline", fileName = "PriestDiscipline", role = "HEALER"  },
        { id = 257, name = "Holy",       fileName = "PriestHoly",       role = "HEALER"  },
        { id = 258, name = "Shadow",     fileName = "PriestShadow",     role = "DAMAGER" },
    },
    DEATHKNIGHT = {
        { id = 250, name = "Blood",  fileName = "DeathKnightBlood",  role = "TANK",    roles = { "TANK", "DAMAGER" } },
        { id = 251, name = "Frost",  fileName = "DeathKnightFrost",  role = "DAMAGER", roles = { "TANK", "DAMAGER" } },
        { id = 252, name = "Unholy", fileName = "DeathKnightUnholy", role = "DAMAGER", roles = { "TANK", "DAMAGER" } },
    },
    SHAMAN = {
        { id = 262, name = "Elemental",   fileName = "ShamanElemental",   role = "DAMAGER" },
        { id = 263, name = "Enhancement", fileName = "ShamanEnhancement", role = "DAMAGER" },
        { id = 264, name = "Restoration", fileName = "ShamanRestoration", role = "HEALER"  },
    },
    MAGE = {
        { id = 62, name = "Arcane", fileName = "MageArcane", role = "DAMAGER" },
        { id = 63, name = "Fire",   fileName = "MageFire",   role = "DAMAGER" },
        { id = 64, name = "Frost",  fileName = "MageFrost",  role = "DAMAGER" },
    },
    WARLOCK = {
        { id = 265, name = "Affliction",  fileName = "WarlockAffliction",  role = "DAMAGER" },
        { id = 266, name = "Demonology",  fileName = "WarlockDemonology",  role = "DAMAGER" },
        { id = 267, name = "Destruction", fileName = "WarlockDestruction", role = "DAMAGER" },
    },
    DRUID = {
        { id = 102, name = "Balance",    fileName = "DruidBalance",    role = "DAMAGER" },
        { id = 103, name = "Feral",      fileName = "DruidFeralCombat", role = "DAMAGER", roles = { "DAMAGER", "TANK" } },
        { id = 105, name = "Restoration", fileName = "DruidRestoration", role = "HEALER"  },
    },
}

local CLASS_IDS = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5,
    DEATHKNIGHT = 6, SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11,
}

-- These checks are intentionally empty for now.  They provide a stable place
-- for class-specific talent checks to distinguish the roles available from a
-- single talent tree.
Spec.RoleChecks = Spec.RoleChecks or {
    DEATHKNIGHT = { [1] = nil, [2] = nil, [3] = nil },
    DRUID = { [2] = nil },
}

local BY_ID = {}
for classToken, specs in pairs(CLASS_SPECS) do
    for index, info in ipairs(specs) do
        info.index = index
        info.classToken = classToken
        BY_ID[info.id] = info
    end
end

local function PlayerClass()
    if not UnitClass then return nil end
    return select(2, UnitClass("player"))
end

local function ActiveTalentGroup()
    return (GetActiveTalentGroup and GetActiveTalentGroup()) or 1
end

local function TalentTabInfo(index, group)
    if not GetTalentTabInfo then return end
    return GetTalentTabInfo(index, false, false, group)
end

local function ResolveRole(template, classToken, index, group)
    local checks = Spec.RoleChecks[classToken]
    local check = checks and checks[index]
    local role = check and check(classToken, index, group, template)
    return role or template.role
end

local function LegacyInfo(classToken, index, group)
    local template = CLASS_SPECS[classToken] and CLASS_SPECS[classToken][index]
    if not template then return end

    local name, icon, points, fileName = TalentTabInfo(index, group)
    return {
        id = template.id,
        index = index,
        name = name or template.name,
        icon = icon,
        role = ResolveRole(template, classToken, index, group),
        roles = template.roles,
        fileName = fileName or template.fileName,
        classToken = classToken,
        group = group,
        points = tonumber(points) or 0,
    }
end

local function CurrentLegacy()
    local classToken = PlayerClass()
    local specs = CLASS_SPECS[classToken]
    if not specs or not GetTalentTabInfo then return end

    local group = ActiveTalentGroup()
    local bestIndex, bestPoints = nil, 0
    for index = 1, #specs do
        local _, _, points = TalentTabInfo(index, group)
        points = tonumber(points) or 0
        if points > bestPoints then
            bestIndex, bestPoints = index, points
        end
    end
    if not bestIndex then return end
    return LegacyInfo(classToken, bestIndex, group)
end

function Spec:GetCurrent()
    return CurrentLegacy()
end

function Spec:GetCurrentID()
    local info = self:GetCurrent()
    return info and info.id
end

function Spec:GetCurrentIndex()
    local info = self:GetCurrent()
    return info and info.index
end

function Spec:GetInfo(index)
    local classToken = PlayerClass()
    return LegacyInfo(classToken, index, ActiveTalentGroup())
end

function Spec:GetInfoByID(id)
    id = tonumber(id) or id
    local info = BY_ID[id]
    if not info then return end
    if info.classToken == PlayerClass() then
        return LegacyInfo(info.classToken, info.index, ActiveTalentGroup())
    end
    return info
end

function Spec:GetInfoForClassID(classID, index)
    for classToken, id in pairs(CLASS_IDS) do
        if id == classID then
            if classToken == PlayerClass() then
                return LegacyInfo(classToken, index, ActiveTalentGroup())
            end
            local info = CLASS_SPECS[classToken] and CLASS_SPECS[classToken][index]
            return info
        end
    end
end

function Spec:GetList()
    local classToken = PlayerClass()
    local result = {}
    for index = 1, #(CLASS_SPECS[classToken] or {}) do
        result[#result + 1] = LegacyInfo(classToken, index, ActiveTalentGroup())
    end
    return result
end

function Spec:GetNum()
    return #self:GetList()
end

EllesmereUI.Spec = Spec
