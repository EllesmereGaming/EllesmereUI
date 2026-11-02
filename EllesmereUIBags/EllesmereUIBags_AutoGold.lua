if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- Auto Deposit/Withdraw: on bank open, moves gold to or from the warband bank
-- so the character carries the set amount. Off: nothing registered.
local EUI = EllesmereUI
local ns = select(2, ...)
if EUI.IS_FOREVER then return end  -- no warband bank there

local COPPER_PER_GOLD = 10000
local _emptyP = {}
local function BP() return (EUI._bagsDB and EUI._bagsDB.profile) or _emptyP end

local AutoGold = {}
ns.AutoGold = AutoGold

-- The gold to keep on hand, or nil while the box is empty.
function AutoGold.Target()
    local g = BP().bankAutoGoldAmount
    return type(g) == "number" and g >= 0 and g or nil
end

function AutoGold.Enabled() return BP().bankAutoGold == true end
function AutoGold.ChatEnabled() return BP().bankAutoGoldChat == true end

-- Opt-in chat line; EllesmereUI.Print stays quiet where chat output could taint.
local function Announce(text) EUI.Print("|cff0cd29fEllesmereUI:|r " .. text) end
local function Coins(copper) return C_CurrencyInfo.GetCoinTextureString(copper) end

local function Balance()
    local target = AutoGold.Target()
    if not target then return end
    local bankType = Enum.BankType.Account
    local diff = GetMoney() - target * COPPER_PER_GOLD
    if diff > 0 then
        if C_Bank.CanDepositMoney(bankType) then
            C_Bank.DepositMoney(bankType, diff)
            if AutoGold.ChatEnabled() then
                Announce(EllesmereUI.Lf("Deposited %1$s to the warband bank.", Coins(diff)))
            end
        end
    elseif diff < 0 and C_Bank.CanWithdrawMoney(bankType) then
        -- Never ask for more than the warband bank holds.
        local amount = math.min(-diff, C_Bank.FetchDepositedMoney(bankType) or 0)
        if amount > 0 then
            C_Bank.WithdrawMoney(bankType, amount)
            if AutoGold.ChatEnabled() then
                Announce(EllesmereUI.Lf("Withdrew %1$s from the warband bank.", Coins(amount)))
            end
        end
    end
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", Balance)
local listening = false

-- Listens for the bank only while the toggle is on and an amount is set.
function AutoGold.Sync()
    local on = AutoGold.Enabled() and AutoGold.Target() ~= nil
    if on == listening then return end
    listening = on
    if on then ev:RegisterEvent("BANKFRAME_OPENED") else ev:UnregisterEvent("BANKFRAME_OPENED") end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    AutoGold.Sync()
end)
