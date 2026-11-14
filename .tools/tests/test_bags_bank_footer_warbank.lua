-- Stub harness: the bank footer's right side (the Warband gold total, its
-- tooltip area, the gold Deposit / Withdraw buttons and the item deposit button)
-- on a client with a Warband bank and on one without (WoW Forever).
-- Runs the real code: the footer block of EllesmereUIBags_Bank.lua (cut by its
-- section banners) over stub frames, the no-tab return of the bank refresh, and
-- the offline bank view's gold placement (EllesmereUIBags_OfflineView.lua). The
-- C_Bank answers per client are a model, taken from Blizzard's own bank panel.
--   lua .tools/tests/test_bags_bank_footer_warbank.lua        (from the repository root)

local function ReadSource(path)
    local f = assert(io.open(path, "rb"), "cannot open " .. path)
    local src = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return src
end

local function Count(src, text)
    local n, at = 0, 1
    while true do
        local s, e = src:find(text, at, true)
        if not s then return n end
        n, at = n + 1, e + 1
    end
end

local count, fails = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        print("  FAIL: " .. msg)
    end
end

local BANK = ReadSource("EllesmereUIBags/EllesmereUIBags_Bank.lua")
local OFFLINE = ReadSource("EllesmereUIBags/EllesmereUIBags_OfflineView.lua")

-------------------------------------------------------------------------------
--  Stub frames: what the footer block calls, recorded
-------------------------------------------------------------------------------
local made = {}
local methods = {
    SetShown = function(self, v) self._shown = v and true or false; self._showCalls = self._showCalls + 1 end,
    Show = function(self) self._shown = true; self._showCalls = self._showCalls + 1 end,
    Hide = function(self) self._shown = false; self._showCalls = self._showCalls + 1 end,
    IsShown = function(self) return self._shown end,
    ClearAllPoints = function(self) self._points = {}; self._anchorCalls = self._anchorCalls + 1 end,
    SetPoint = function(self, p, rel, rp, x, y)
        self._points[#self._points + 1] = { p, rel, rp, x, y }
        self._anchorCalls = self._anchorCalls + 1
    end,
    GetFrameLevel = function() return 1 end,
    GetParent = function(self) return self._parent end,
    SetText = function(self, t) self._text = t end,
    GetText = function(self) return self._text end,
    GetStringWidth = function(self) return #tostring(self._text) * 5 end,
    SetWidth = function(self, w) self._width = w end,
    SetScript = function(self, k, fn) self._scripts[k] = fn end,
}
local function NewRegion(kind, parent)
    local r = { _kind = kind, _parent = parent, _shown = true, _points = {}, _scripts = {}, _text = "",
        _showCalls = 0, _anchorCalls = 0 }
    function r:CreateTexture() return NewRegion("Texture", self) end
    function r:CreateFontString() return NewRegion("FontString", self) end
    -- A field the code keeps on a frame (its names start with "_") reads nil until
    -- it is set; any other unknown name is a widget method that does nothing.
    return setmetatable(r, { __index = function(_, k)
        if methods[k] then return methods[k] end
        if type(k) == "string" and k:sub(1, 1) == "_" then return nil end
        return function() end
    end })
end
function CreateFrame(kind, _, parent)
    local r = NewRegion(kind, parent)
    made[#made + 1] = r
    return r
end

-------------------------------------------------------------------------------
--  The world the footer block reads
-------------------------------------------------------------------------------
local popup
EUI_Bank = NewRegion("Frame")
FOOTER_H = 30
EUI = {
    PP = nil,
    ShowWidgetTooltip = function() end,
    HideWidgetTooltip = function() end,
    GetGoldLedger = function() return { Money = function() return 0 end, WarbandMoney = function() return 0 end } end,
    ShowInputPopup = function(_, opts) popup = opts end,
}
EllesmereUI = { L = function(s) return s end }
function SetBankFont() end
function GetAccentRGB() return 1, 1, 1 end
function BreakUpLargeNumbers(n) return tostring(n) end
ACCEPT, CANCEL = "Accept", "Cancel"
Enum = { BankType = { Character = 0, Guild = 1, Account = 2 } }
local CHARACTER, ACCOUNT = 0, 2

local asked, did = {}, {}
local client
local canWithdraw, canDeposit = true, true
C_Bank = {
    CanViewBank = function(t) asked[#asked + 1] = "view" .. t; return client.view[t] end,
    DoesBankTypeSupportMoneyTransfer = function(t) asked[#asked + 1] = "money" .. t; return client.money[t] end,
    DoesBankTypeSupportAutoDeposit = function(t) asked[#asked + 1] = "auto" .. t; return client.auto[t] end,
    CanWithdrawMoney = function(t) asked[#asked + 1] = "canWithdraw" .. t; return canWithdraw end,
    CanDepositMoney = function(t) asked[#asked + 1] = "canDeposit" .. t; return canDeposit end,
    WithdrawMoney = function(t, copper) did[#did + 1] = "withdraw" .. t .. ":" .. copper end,
    DepositMoney = function(t, copper) did[#did + 1] = "deposit" .. t .. ":" .. copper end,
    AutoDepositItemsIntoBank = function(t) did[#did + 1] = "items" .. t end,
}
local RETAIL = { view = { [0] = true, [2] = true }, money = { [0] = false, [2] = true }, auto = { [0] = true, [2] = true } }
local FOREVER = { view = { [0] = true, [2] = false }, money = { [0] = false, [2] = false }, auto = { [0] = true, [2] = false } }
local FOREVER_NO_AUTO = { view = { [0] = true, [2] = false }, money = { [0] = false, [2] = false },
    auto = { [0] = false, [2] = false } }
local NO_ANSWER = { view = {}, money = {}, auto = { [0] = true } }
-- A Warband bank that can be viewed and takes no gold.
local VIEW_NO_MONEY = { view = { [0] = true, [2] = true }, money = { [0] = false, [2] = false }, auto = { [0] = true, [2] = true } }

-------------------------------------------------------------------------------
--  The footer block, run for real
-------------------------------------------------------------------------------
local footerBlock
do
    local s, e = BANK:find("%-%-  Footer: Player Gold %(left%) %+ Warband Gold %(right%)\n%-+\n")
    assert(s, "the footer banner was not found")
    local stop = BANK:find("\n%-+\n%-%-  Drag to Move", e)
    assert(stop, "the banner after the footer was not found")
    footerBlock = assert(loadstring(BANK:sub(e + 1, stop), "=bank footer"))
end

local footer, warbandGold, warbandHitbox, depositMoney, withdrawMoney, depositItems
local function Build()
    for i = #made, 1, -1 do made[i] = nil end
    EUI_Bank = NewRegion("Frame")
    footerBlock()
    footer, warbandGold = EUI_Bank.Footer, EUI_Bank._warbandGoldText
    assert(footer and warbandGold and made[1] == footer, "the footer and its gold text")
    warbandHitbox, depositMoney, withdrawMoney, depositItems = made[3], made[4], made[5], made[6]
    assert(warbandHitbox._points[1][2] == warbandGold, "the Warband gold hitbox")
    assert(withdrawMoney._points[1][2] == depositMoney, "Withdraw sits left of Deposit")
    assert(depositItems._points[1][2] == withdrawMoney, "the item button sits left of Withdraw")
end

local function Update(c, isWarband, noTab)
    client = c
    for i = #asked, 1, -1 do asked[i] = nil end
    EUI_Bank:UpdateDepositButton(isWarband, noTab)
end
local function Asked(what)
    for i = 1, #asked do if asked[i] == what then return true end end
    return false
end
local function GoldShown()
    return withdrawMoney._shown and depositMoney._shown and warbandGold._shown and warbandHitbox._shown
end
local function GoldHidden()
    return not (withdrawMoney._shown or depositMoney._shown or warbandGold._shown or warbandHitbox._shown)
end
-- The item button's one anchor: "withdraw" (left of the gold buttons) or "edge".
local function ItemsAnchor()
    if #depositItems._points ~= 1 then return "anchors: " .. #depositItems._points end
    local p = depositItems._points[1]
    if p[1] == "RIGHT" and p[2] == withdrawMoney and p[3] == "LEFT" and p[4] == -8 then return "withdraw" end
    if p[1] == "RIGHT" and p[2] == warbandGold and p[3] == "RIGHT" and p[4] == 0 then return "edge" end
    return "other"
end
local function GoldCalls()
    return withdrawMoney._showCalls + depositMoney._showCalls + warbandGold._showCalls + warbandHitbox._showCalls
end

-------------------------------------------------------------------------------
--  1. A client with a Warband bank
-------------------------------------------------------------------------------
Build()
Update(RETAIL, false)
check(GoldShown(), "Warband bank: the gold total, its tooltip area and both gold buttons show")
check(depositItems._shown and ItemsAnchor() == "withdraw", "Warband bank: the item button shows left of Withdraw")
check(depositItems._bankType == CHARACTER and depositItems._label:GetText() == "Deposit Reagents",
    "character view: Deposit Reagents into the character bank")
Update(RETAIL, true)
check(depositItems._bankType == ACCOUNT and depositItems._label:GetText() == "Deposit Warbound Items",
    "Warband view: Deposit Warbound Items into the Warband bank")
check(GoldShown() and depositItems._shown and ItemsAnchor() == "withdraw", "Warband view: everything shows")

-------------------------------------------------------------------------------
--  2. A client without one (WoW Forever), from the footer as it is built
-------------------------------------------------------------------------------
Build()
Update(FOREVER, false)
check(GoldHidden(), "no Warband bank: the gold total, its tooltip area and both gold buttons are hidden")
check(depositItems._shown and ItemsAnchor() == "edge", "no Warband bank: the item button takes the right edge")
check(Asked("view" .. ACCOUNT) and not Asked("money" .. ACCOUNT), "a bank that cannot be viewed is not asked about money")
Update(FOREVER_NO_AUTO, false)
check(not depositItems._shown and GoldHidden(), "no automatic deposit: the item button is hidden too")
Update(RETAIL, false)
check(GoldShown() and depositItems._shown and ItemsAnchor() == "withdraw", "back to a Warband bank: everything as at first")
Update(NO_ANSWER, false)
check(GoldHidden() and ItemsAnchor() == "edge", "no answer from the client counts as no Warband bank")
Update(RETAIL, false)
Update(VIEW_NO_MONEY, false)
check(GoldHidden() and ItemsAnchor() == "edge", "a Warband bank that takes no gold: the gold controls are hidden")
check(Asked("view" .. ACCOUNT) and Asked("money" .. ACCOUNT), "a bank that can be viewed is asked about money")
-- No answer as the very first one, on the footer as it is built (everything shown).
Build()
Update(NO_ANSWER, false)
check(GoldHidden() and ItemsAnchor() == "edge", "no answer on the first update hides the gold controls")

-------------------------------------------------------------------------------
--  3. Only a changed answer touches the gold controls and the item button's anchor
-------------------------------------------------------------------------------
for _, c in ipairs({ RETAIL, FOREVER }) do
    local name = c == RETAIL and "Warband bank" or "no Warband bank"
    Build()
    Update(c, false)
    local gold, anchors, shows = GoldCalls(), depositItems._anchorCalls, depositItems._showCalls
    Update(c, false)
    Update(c, true)
    Update(c, false, true)
    check(GoldCalls() == gold, name .. ": the same answer shows and hides nothing again")
    check(depositItems._anchorCalls == anchors, name .. ": the same answer leaves the item button's anchor alone")
    check(depositItems._showCalls == shows + 3, name .. ": the item button still follows each view")
end
Build()
Update(RETAIL, false)
local anchorsBefore = depositItems._anchorCalls
Update(FOREVER, false)
check(depositItems._anchorCalls == anchorsBefore + 2 and ItemsAnchor() == "edge", "a changed answer re-anchors the item button once")

-------------------------------------------------------------------------------
--  4. A bank with no tab yet: nothing to deposit items into
-------------------------------------------------------------------------------
Build()
Update(FOREVER, false, true)
check(not depositItems._shown, "no tab, no Warband bank: the item button is hidden")
check(GoldHidden(), "no tab, no Warband bank: the gold controls are hidden")
Update(FOREVER, false)
check(depositItems._shown and ItemsAnchor() == "edge", "the first tab brings the item button back")
Build()
Update(RETAIL, false, true)
check(not depositItems._shown and GoldShown(), "no tab, Warband bank: the gold controls show, the item button does not")

-- The bank refresh's return for a bank with no tab updates the footer.
do
    local first = "    if #_allTabs == 0 then\n        DiscoverBankTabs()\n"
    local s = BANK:find(first, 1, true)
    assert(s, "the no-tab block of the bank refresh was not found")
    local _, e = BANK:find("\n    end\n", s, true)
    local chunk = assert(loadstring("local _allTabs, DiscoverBankTabs, BuildBankSidebar, UpdateBaseTabPrompt, EUI_Bank = ...\n"
        .. BANK:sub(s, e) .. "\nreturn 'refresh goes on'", "=no-tab block"))
    local log
    local bank = { UpdateDepositButton = function(_, isWarband, noTab)
        log[#log + 1] = "footer:" .. tostring(isWarband) .. ":" .. tostring(noTab)
    end }
    local function Run(tabsAfterDiscovery)
        log = {}
        local tabs = {}
        return chunk(tabs, function()
            log[#log + 1] = "discover"
            for i = 1, tabsAfterDiscovery do tabs[i] = {} end
        end, function() log[#log + 1] = "sidebar" end, function(on) log[#log + 1] = "prompt:" .. tostring(on) end, bank)
    end
    local went = Run(0)
    check(went == nil, "a bank with no tab ends the refresh there")
    check(table.concat(log, " ") == "discover sidebar prompt:true footer:false:true",
        "a bank with no tab: sidebar, the open-slots prompt, then the footer as a tabless character view")
    went = Run(2)
    check(went == "refresh goes on" and table.concat(log, " ") == "discover",
        "tabs found on the second look: the refresh goes on and updates the footer at its end")
end

-------------------------------------------------------------------------------
--  5. The buttons' clicks
-------------------------------------------------------------------------------
Build()
Update(RETAIL, false)
local function Click(btn)
    popup = nil
    for i = #did, 1, -1 do did[i] = nil end
    btn._scripts.OnClick(btn)
end
canWithdraw = false
Click(withdrawMoney)
check(popup == nil and #did == 0, "Withdraw does nothing while the client refuses a withdrawal")
canWithdraw = true
Click(withdrawMoney)
check(popup ~= nil and popup.money == true, "Withdraw asks for an amount")
if popup then
    popup.onConfirm(0)
    check(#did == 0, "an amount of zero withdraws nothing")
    popup.onConfirm(12345)
    check(did[1] == "withdraw" .. ACCOUNT .. ":12345" and #did == 1, "Withdraw takes the amount from the Warband bank")
end
canDeposit = false
Click(depositMoney)
check(popup == nil and #did == 0, "Deposit does nothing while the client refuses a deposit")
canDeposit = true
Click(depositMoney)
check(popup ~= nil, "Deposit asks for an amount")
if popup then
    popup.onConfirm(777)
    check(did[1] == "deposit" .. ACCOUNT .. ":777" and #did == 1, "Deposit puts the amount into the Warband bank")
end
Click(depositItems)
check(did[1] == "items" .. CHARACTER and #did == 1, "character view: the item button deposits into the character bank")
Update(RETAIL, true)
Click(depositItems)
check(did[1] == "items" .. ACCOUNT and #did == 1, "Warband view: the item button deposits into the Warband bank")

-------------------------------------------------------------------------------
--  6. The offline bank view's gold lines up with the live readout's spot,
--     also while that readout is hidden
-------------------------------------------------------------------------------
do
    local s = OFFLINE:find("local function PaintGold(v, gold)", 1, true)
    assert(s, "PaintGold was not found")
    local _, e = OFFLINE:find("\nend\n", s, true)
    MoneyFrame_Update = function() end
    local PaintGold = assert(loadstring(OFFLINE:sub(s, e) .. "\nreturn PaintGold", "=PaintGold"))()
    local function Box(right, shown)
        local r = NewRegion("Frame")
        r._shown = shown ~= false
        r.GetRight = function() return right end
        return r
    end
    local function Dx(ref, flag)
        local v = { money = Box(0), bar = Box(500), info = NewRegion("FontString"), moneyName = "TestMoney",
            goldRef = ref and function() return ref end or nil, goldRefHidden = flag }
        PaintGold(v, 250000)
        local p = v.money._points[1]
        return p and p[1] == "RIGHT" and p[2] == v.bar and p[3] == "RIGHT" and p[4]
    end
    check(Dx(Box(480, true), true) == -20, "a shown readout: the gold's right edge sits on it")
    check(Dx(Box(480, false), true) == -20, "the bank view: a hidden readout still gives the spot")
    check(Dx(Box(480, false), nil) == -10, "a view without that rule: a hidden readout gives the fallback")
    check(Dx(Box(480, true), nil) == -20, "a view without that rule: a shown readout gives the spot")
    check(Dx(Box(nil, false), true) == -10, "a readout with no place on screen gives the fallback")
    check(Dx(nil, true) == -10, "no readout gives the fallback")
    check(Count(OFFLINE, "bankView.goldRefHidden = true") == 1, "the bank view keeps its readout's spot while hidden")
    check(Count(OFFLINE, "bagsView.goldRefHidden") == 0, "the bags view does not")
end

if fails > 0 then error(fails .. " of " .. count .. " checks failed") end
print("PASS test_bags_bank_footer_warbank (" .. count .. " checks)")
