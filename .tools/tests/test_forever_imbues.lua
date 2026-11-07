-- Run from the repository root: lua .tools/tests/test_forever_imbues.lua
-- Loads the real EUI_UnitFrames_ForeverImbues.lua under stubs and checks that
-- every weapon enchant on the WoW Forever Buffs bar shows exactly once: the
-- engine's weapon-enchant cell takes what GetTemporaryEnchantmentInfo reports
-- (the imbue first since the 1.60.1 launch, the temporary enchant before it),
-- and this file's cells take the rest.
local function noop() end

local MAIN, OFF, RANGED = 0, 1, 2
local INV = { [MAIN] = 16, [OFF] = 17, [RANGED] = 18 }
local weapons, reports, cvarIcon = {}, {}, false
local applies = 0

local function Frame()
    local f = { shown = false, points = 0 }
    function f:GetParent() return self.parent end
    function f:SetParent(p) self.parent = p end
    f.EnableMouse, f.SetMouseClickEnabled, f.SetScript = noop, noop, function(self, k, fn) self[k] = fn end
    function f:ClearAllPoints() self.points = 0 end
    function f:SetPoint() self.points = self.points + 1 end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:RegisterEvent() end
    function f:UnregisterAllEvents() end
    return f
end

local made = {}
EllesmereUI = {
    IS_FOREVER = true,
    AuraKit = {
        styles = {},
        EnchantCellInit = noop,
        CreateStyledCell = function(parent)
            local f = Frame()
            f.parent = parent
            local d = {
                icon = { SetTexture = function(self, v) self.v = v end },
                stack = { SetText = function(self, v) self.v = v end },
                cooldown = { SetCooldown = noop },
                duration = {},
            }
            made[#made + 1] = { f = f, d = d }
            return f, d
        end,
        GetDurationFormatter = noop,
        DurationTextColor = noop,
        SetContainerRowWidth = noop,
    },
}
Enum = {
    ItemEnchantType = { None = 0, Permanent = 1, Temporary = 2, Imbue = 3 },
    WeaponSlot = { MainHand = MAIN, OffHand = OFF, Ranged = RANGED },
}
C_Item = { GetWeaponEnchantInfo = function(ws) return weapons[ws] or {} end }
C_PaperDollInfo = { GetTemporaryEnchantmentInfo = function(inv) return reports[inv] end }
C_CVar = { GetCVarBool = function(name) return name == "displayTemporaryEnchantIcon" and cvarIcon end }
GetInventoryItemTexture = function(_, inv) return 1000 + inv end
GetTime = function() return 100 end
issecretvalue = function() return false end
InCombatLockdown = function() return false end
local frames = {}
CreateFrame = function() local f = Frame(); frames[#frames + 1] = f; return f end
INVSLOT_MAINHAND, INVSLOT_OFFHAND, INVSLOT_RANGED = 16, 17, 18

local ns = {}
ns.PAB_ApplyLiveConfig = function() applies = applies + 1 end
assert(loadfile("EllesmereUIUnitFrames/EUI_UnitFrames_ForeverImbues.lua"))("test", ns)
assert(ns.PAB_FvImbueLayout and ns.PAB_FvImbueSync and ns.PAB_FvImbueCount, "the file did not load")

local function Imbue(id, charges) return { hasEnchant = true, enchantType = 3, timeLeft = 60000, charges = charges or 0, enchantID = id, enchantIconID = 5000 + id } end
local function Temp(id, charges) return { hasEnchant = true, enchantType = 2, timeLeft = 60000, charges = charges or 0, enchantID = id, enchantIconID = 5000 + id } end
local function Report(id) return { enchantID = id, remainingTimeMs = 60000, chargesRemaining = 0, hasExpirationTime = true } end

local container = { ClearAllPoints = noop, SetPoint = noop }
local parent = {}
local cfg = { growDirection = "LEFT" }
local layout = { elementWidth = 30, elementHeight = 30, elementSpacing = 2 }
local function Layout(enchSlots)
    ns.PAB_FvImbueLayout(container, parent, cfg, { enchSlots = enchSlots or 3, rowWidth = 300 }, layout, "TOPRIGHT")
    local out = {}
    for _, c in ipairs(made) do
        if c.f.shown then out[#out + 1] = { icon = c.d.icon.v, stack = c.d.stack.v } end
    end
    return out
end
local function Reset() weapons, reports, cvarIcon = {}, {}, false end

ns.PAB_FvImbueSync(true)

-- 1. since the launch: a poison (an imbue) the engine cell already shows -> no cell (the doubled poison)
Reset()
weapons[MAIN] = { { hasEnchant = false, enchantType = 0 }, Imbue(7, 40) }
reports[16] = Report(7)
local got = Layout()
assert(#got == 0 and ns.PAB_FvImbueCount() == 0, "an imbue the engine cell shows is not drawn again")

-- 2. since the launch: a poison and a sharpening stone on one weapon -> the engine cell
--    shows the poison, a cell here the stone, with the weapon's icon
Reset()
weapons[MAIN] = { Temp(20), Imbue(7, 40) }
reports[16] = Report(7)
got = Layout()
assert(#got == 1 and got[1].icon == 1016 and got[1].stack == "", "the stone under the poison gets a cell")
assert(ns.PAB_FvImbueCount() == 1, "that cell comes off the aura budget")

-- 3. before the launch: an imbue the engine cell cannot see -> a cell here
Reset()
weapons[MAIN] = { Imbue(29) }
got = Layout()
assert(#got == 1, "an imbue the game leaves out is drawn here")

-- 4. before the launch: an imbue and an oil -> the engine cell shows the oil, a cell here the imbue
Reset()
weapons[MAIN] = { Temp(20), Imbue(29) }
reports[16] = Report(20)
got = Layout()
assert(#got == 1, "the imbue beside the oil the engine cell shows")

-- 5. an oil alone -> the engine cell only
Reset()
weapons[OFF] = { Temp(21) }
reports[17] = Report(21)
got = Layout()
assert(#got == 0, "an oil alone is the engine cell's")

-- 6. both on a weapon, reported ID matching neither -> the imbue counts as shown (it takes priority)
Reset()
weapons[MAIN] = { Temp(20), Imbue(7) }
reports[16] = Report(999)
got = Layout()
assert(#got == 1 and got[1].icon == 1016, "priority: the stone is drawn here")

-- 7. a slot the bar did not declare (a grid of one cell): its engine cell does not exist
Reset()
weapons[OFF] = { Imbue(7) }
reports[17] = Report(7)
got = Layout(1)
assert(#got == 1, "an undeclared slot's imbue is drawn here")

-- 8. the enchant's own icon only while the game's Display Temporary Enchant Icon is on
Reset()
weapons[MAIN] = { Temp(20), Imbue(7) }
reports[16] = Report(7)
cvarIcon = true
got = Layout()
assert(got[1].icon == 5020, "the enchant icon with the CVar on")
weapons[MAIN][1].enchantIconID = 0
got = Layout()
assert(got[1].icon == 1016, "no enchant icon: the weapon's")

-- 9. the weapon events (the file's own event frame, made by the Sync above): a cell
--    coming re-lays the bar; a poison charge tick on the engine's cell re-lays nothing
local events = frames[1]
assert(events and events.OnEvent, "the weapon event frame")
Reset()
weapons[MAIN] = { Imbue(7, 40) }
reports[16] = Report(7)
Layout()
applies = 0
weapons[MAIN] = { Imbue(7, 39) }
events.OnEvent(events, "WEAPON_ENCHANT_CHANGED")
assert(applies == 0, "a charge tick on the engine cell's poison re-lays nothing")
weapons[MAIN] = { Temp(20), Imbue(7, 39) }
events.OnEvent(events, "WEAPON_ENCHANT_CHANGED")
assert(applies == 1, "a stone joining the poison re-lays the bar")
print("forever imbues OK")
