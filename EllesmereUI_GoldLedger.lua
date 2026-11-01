if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  EllesmereUI_GoldLedger.lua -- the one gold record shared by Bags and DataBars.
--
--  ACCOUNT-level, NOT the profile: it lists the player's characters and
--  balances, and a profile copy would ride export strings (EllesmereUI_Profiles
--  FULL_EXPORT_EXCLUDED keeps this key out of full-account exports too).
--
--  EllesmereUIDB.goldLedger = {
--      chars    = { ["Name-Realm"] = { money, class, name, realm, updated } },
--      warband  = { money, updated },    -- nil until first successful read
--      tracking = false,                 -- only present when switched off
--  }
--  money is copper. A character's entry is only ever written by that character
--  while it is online, so an offline entry is its balance at logout.
--
--  The ledger owns money tracking for every module: one tracking switch
--  (IsTracking / SetTracking, account-wide) and one set of money events,
--  registered only while a module is Register()ed. Modules never register
--  PLAYER_MONEY / ACCOUNT_MONEY themselves; they get a callback after the
--  ledger has recorded. With the switch off nothing is written and only
--  PLAYER_MONEY stays registered, so displays and live reads keep working.
--
--  Built lazily: EllesmereUI.GetGoldLedger() creates it on the first call, and
--  only a module that is actually loading calls it. A setup with neither Bags
--  nor DataBars never builds the ledger, however modules get enabled or
--  disabled.
--------------------------------------------------------------------------------

local EUI = _G.EllesmereUI
local built

local function Build()
    local GL = {}

    local type, pairs = type, pairs
    local issecretvalue = issecretvalue

    local function IsUsable(v)
        return type(v) == "number" and not (issecretvalue and issecretvalue(v))
    end

    -- "Name-Realm": a character name never contains a hyphen, a realm name can (Azjol-Nerub).
    local function SplitKey(key)
        local name, realm = key:match("^([^%-]+)%-(.+)$")
        return name or key, realm
    end

    --------------------------------------------------------------------------------
    --  One-time absorb of the legacy stores:
    --    EllesmereUIDB.characterGold  (Bags)     { gold, lastUpdated, class, classColor }
    --    EllesmereUIDB.dataBarsGold   (DataBars) { currentMoney, class, realm, name }
    --    EllesmereUIDB.warbandGold    (Bags)     { gold, lastUpdated }
    --  Neither store carries both a balance and a trustworthy age, so when both
    --  know a character and disagree the DataBars value wins (written on every
    --  PLAYER_MONEY, ungated) and the entry has no age until that character next
    --  plays. Runs lazily from Data(); idempotent, and the old keys are dropped.
    --------------------------------------------------------------------------------
    local function MigrateLegacy(db, ledger)
        local bags, dbars, wband = db.characterGold, db.dataBarsGold, db.warbandGold
        if bags == nil and dbars == nil and wband == nil then return end
        local chars = ledger.chars

        if type(bags) == "table" then
            for key, e in pairs(bags) do
                if type(key) == "string" and type(e) == "table" and IsUsable(e.gold) and e.gold >= 0 then
                    local name, realm = SplitKey(key)
                    chars[key] = { money = e.gold, class = e.class, name = name, realm = realm,
                        updated = IsUsable(e.lastUpdated) and e.lastUpdated or nil }
                end
            end
        end
        if type(dbars) == "table" then
            for key, e in pairs(dbars) do
                if type(key) == "string" and type(e) == "table" and IsUsable(e.currentMoney) and e.currentMoney >= 0 then
                    local cur = chars[key]
                    local name, realm = SplitKey(key)
                    if cur and cur.money == e.currentMoney then
                        cur.class = cur.class or e.class
                        cur.name, cur.realm = e.name or cur.name, e.realm or cur.realm
                    else
                        chars[key] = { money = e.currentMoney, class = e.class,
                            name = e.name or name, realm = e.realm or realm }
                    end
                end
            end
        end
        if type(wband) == "table" and IsUsable(wband.gold) and wband.gold >= 0 and not ledger.warband then
            ledger.warband = { money = wband.gold, updated = IsUsable(wband.lastUpdated) and wband.lastUpdated or nil }
        end

        db.characterGold, db.dataBarsGold, db.warbandGold = nil, nil, nil
    end

    -- Bags used to keep the tracking switch per profile (addons.EllesmereUIBags.enableGoldTracking).
    -- Absorbed once: a profile that had it off turns it off for the account, and the key goes.
    -- Later sessions skip it, so an imported profile cannot flip the account switch.
    local function AbsorbTrackingSwitch(db, ledger)
        if ledger.trackingMigrated or type(db.profiles) ~= "table" then return end
        for _, pd in pairs(db.profiles) do
            local addons = type(pd) == "table" and pd.addons
            local bags = type(addons) == "table" and addons.EllesmereUIBags
            if type(bags) == "table" and bags.enableGoldTracking ~= nil then
                if bags.enableGoldTracking == false then ledger.tracking = false end
                bags.enableGoldTracking = nil
            end
        end
        ledger.trackingMigrated = true
    end

    --- The ledger table. Never nil; a throwaway table if the account DB is somehow
    --- absent (never assign the global here: a pre-SavedVariables call could
    --- shadow the real table).
    function GL.Data()
        local db = _G.EllesmereUIDB
        if type(db) ~= "table" then return { chars = {} } end
        local ledger = db.goldLedger
        if type(ledger) ~= "table" then
            ledger = {}
            db.goldLedger = ledger
        end
        if type(ledger.chars) ~= "table" then ledger.chars = {} end
        MigrateLegacy(db, ledger)
        AbsorbTrackingSwitch(db, ledger)
        return ledger
    end

    --- "Name-Realm" for the current character (Forever: "Name-Ruleset"), or nil when either part is unknown
    --- (an "Unknown" placeholder would file the balance under a key no later
    --- session can match).
    function GL.CharKey()
        local name, realm = UnitName("player"), EUI.RealmGroupName()
        if not name or not realm then return nil end
        return name .. "-" .. realm
    end

    -- The only places the modules touch the money APIs. A secret or non-number
    -- read comes back nil, so no caller ever does arithmetic on one.
    local function LiveMoney()
        local money = GetMoney()
        if IsUsable(money) then return money end
    end

    -- Readable at any time, not only with the warband bank open.
    local function LiveWarband()
        local bank = C_Bank
        if not (bank and bank.FetchDepositedMoney and Enum and Enum.BankType) then return nil end
        local money = bank.FetchDepositedMoney(Enum.BankType.Account)
        if IsUsable(money) then return money end
    end

    --- The current character's balance, for display. Does not write the ledger
    --- (writing is the caller's call; Bags can turn tracking off). When the live
    --- read is unusable, falls back to the last stored balance; nil if neither.
    function GL.Money()
        local money = LiveMoney()
        if money then return money end
        local key = GL.CharKey()
        local e = key and GL.Data().chars[key]
        return e and e.money
    end

    --- The warband bank balance, for display. Live when the read is usable,
    --- otherwise the last stored balance; nil if never seen. Does not write.
    function GL.WarbandMoney()
        local money = LiveWarband()
        if money then return money end
        local w = GL.Data().warband
        return w and w.money
    end

    --- Store the current character's balance. `money` defaults to a live read.
    --- Returns the balance, or nil when the read was unusable (secret or not a
    --- number); a failed read never overwrites a good entry. Nothing is written
    --- while tracking is off, but the balance is still returned.
    function GL.RecordCharacter(money)
        if money == nil then money = LiveMoney() end
        if not IsUsable(money) then return nil end
        if not GL.IsTracking() then return money end
        local key = GL.CharKey()
        if not key then return money end
        local chars = GL.Data().chars
        -- Forever: drop the entry an older build filed under the realm name.
        local oldKey = UnitName("player") .. "-" .. (GetRealmName() or "")
        if oldKey ~= key then chars[oldKey] = nil end
        local e = chars[key]
        if not e then e = {}; chars[key] = e end
        local _, class = UnitClass("player")
        e.money, e.class, e.name, e.realm, e.updated = money, class, UnitName("player"), EUI.RealmGroupName(), time()
        return money
    end

    --- Store the warband bank balance. An unusable read (secret or not a number)
    --- changes nothing and the stored value stays.
    function GL.RecordWarband()
        if not GL.IsTracking() then return nil end
        local money = LiveWarband()
        if not money then return nil end
        local ledger = GL.Data()
        local w = ledger.warband
        if not w then w = {}; ledger.warband = w end
        w.money, w.updated = money, time()
        return money
    end

    --- Account-wide tracking switch. On by default; only the off state is stored.
    function GL.IsTracking()
        return GL.Data().tracking ~= false
    end

    function GL.SetTracking(on)
        local ledger = GL.Data()
        if on == false then
            ledger.tracking = false
        else
            ledger.tracking = nil
        end
        GL.SyncEvents()
        if on ~= false then
            GL.RecordCharacter()
            GL.RecordWarband()
        end
    end

    --------------------------------------------------------------------------------
    --  Money events. One frame, registered only while a module is Register()ed.
    --  Tracking on: PLAYER_MONEY, ACCOUNT_MONEY, BANKFRAME_OPENED and
    --  PLAYER_ENTERING_WORLD, each recorded before the callbacks run.
    --  Tracking off: PLAYER_MONEY alone, so displays can repaint; nothing is
    --  recorded and nothing else runs.
    --  Writes from these events are coalesced: the first event of a burst starts a
    --  0.5s timer and one write then stores the latest values, so a flurry of
    --  PLAYER_MONEY (looting, vendor sweeps) costs one table write.
    --  Callbacks run immediately, fn(event, money): the live balance for
    --  character events, nil for warband ones. Display code reads live values.
    --------------------------------------------------------------------------------
    local consumers, consumerCount = {}, 0
    local eventFrame

    function GL.SyncEvents()
        if not eventFrame then return end
        eventFrame:UnregisterAllEvents()
        if consumerCount == 0 then return end
        eventFrame:RegisterEvent("PLAYER_MONEY")
        if GL.IsTracking() then
            eventFrame:RegisterEvent("ACCOUNT_MONEY")
            eventFrame:RegisterEvent("BANKFRAME_OPENED")
            eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        end
    end

    local WRITE_DELAY = 0.5
    local dirtyChar, dirtyWarband, flushQueued

    local function FlushWrites()
        flushQueued = false
        if dirtyChar then dirtyChar = false; GL.RecordCharacter() end
        if dirtyWarband then dirtyWarband = false; GL.RecordWarband() end
    end

    local function OnMoneyEvent(_, event)
        local money
        if event ~= "ACCOUNT_MONEY" and event ~= "BANKFRAME_OPENED" then
            money = LiveMoney()
            if GL.IsTracking() then dirtyChar = true end
        end
        if event ~= "PLAYER_MONEY" then dirtyWarband = true end
        if (dirtyChar or dirtyWarband) and not flushQueued then
            flushQueued = true
            C_Timer.After(WRITE_DELAY, FlushWrites)
        end
        for owner, fn in pairs(consumers) do
            if fn ~= true then
                local ok, err = pcall(fn, event, money)
                if not ok then geterrorhandler()(err) end
            end
        end
    end

    --- Start money tracking for `owner` (any unique key). `fn` is optional.
    --- Registering twice for one owner just replaces its callback.
    function GL.Register(owner, fn)
        if consumers[owner] == nil then consumerCount = consumerCount + 1 end
        consumers[owner] = fn or true
        if not eventFrame then
            eventFrame = CreateFrame("Frame")
            eventFrame:SetScript("OnEvent", OnMoneyEvent)
        end
        GL.SyncEvents()
        if GL.IsTracking() then
            GL.RecordCharacter()
            GL.RecordWarband()
        end
    end

    function GL.Unregister(owner)
        if consumers[owner] == nil then return end
        consumers[owner] = nil
        consumerCount = consumerCount - 1
        GL.SyncEvents()
    end

    --- Drop a character the player no longer has (renamed, deleted, transferred).
    function GL.Forget(key)
        GL.Data().chars[key] = nil
    end

    --- Wipe every character and the warband figure.
    function GL.Reset()
        local ledger = GL.Data()
        ledger.chars = {}
        ledger.warband = nil
    end

    return GL
end

function EUI.GetGoldLedger()
    if not built then built = Build() end
    return built
end
