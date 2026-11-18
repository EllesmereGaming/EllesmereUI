if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CDM_CdBuffStacks.lua
--
--  Per-spell "Buff Stacks" for cooldown and utility icons: the stack count of
--  the spell's own buff, drawn on the cooldown icon. Blizzard's cooldown items
--  have no stack counter (no Applications frame), so a spell whose buff
--  stacks (e.g. Shield Block on WoW Forever, which blocks two attacks) shows
--  its cooldown but never how many stacks are left.
--
--  Eligible spells only: the cooldown entry has selfAura and no charges (the
--  copy sits in the stack text corner, where a charge number would overlap
--  it), and Blizzard's buff catalogue (Tracked Buff / Tracked Bar, displayed
--  or not) has an entry for the same spell. On by default for those; the
--  per-spell setting showBuffStacks = false turns it off. Every other spell
--  gets no menu row and no count. Blizzard builds a buff item only for a buff
--  it displays, so a spell whose buff is Not Displayed keeps its row but shows
--  no number (owner pick 2026-11-17: the row stays).
--
--  Source: the same spell's item in Blizzard's buff viewers. BuffIcon items
--  keep the count at item.Applications.Applications, BuffBar items at
--  item.Icon.Applications. The text is mirrored as Blizzard sets it
--  (hooksecurefunc on that FontString and its show state), so a secret count
--  (aura restrictions) goes straight to SetText, never read.
--
--  Items are paired by cooldownID through GetCooldownViewerCooldownInfo, whose
--  copy is never secret (the live frame.cooldownInfo can turn secret mid
--  fight). Each pass shows only what an active buff item pushed and hides
--  every other copy, so a re-pointed or vanished item never leaves a stale
--  number.
--
--  The text is a FontString of ours on the icon's text overlay, keyed weakly
--  by frame (no fields on Blizzard frames), styled with the bar's stack text
--  settings (ns.StyleCustomChargeText).
--
--  Cost: the pass runs at the end of every reanchor. It allocates nothing
--  (file-level scratch, wiped per pass) and returns at once while no eligible
--  spell exists, or none sits on a bar. Entry data is cached per cooldownID
--  and dropped with the CDM spell caches (ns.MarkCDMSpellCacheDirty calls
--  ns.CdBuffStacksInvalidate: data load, hotfix, talents, rebuilds). A talent
--  change in combat can drop it there, and the next pass builds it again once.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._hookInternals
if not I or I.broken then return end
local GetViewerFrame, hookFrameData = I.GetViewerFrame, I.hookFrameData
local IsSecret = EllesmereUI.IsSecret
local CV = C_CooldownViewer

-- cooldown frame -> our FontString
local texts = setmetatable({}, { __mode = "k" })
-- buff item frames hooked once (pooled frames are rebound: the item's spell is
-- looked up at each push, never captured)
local hooked = setmetatable({}, { __mode = "k" })

-- cooldownID -> entry spell / override spell (false: none), and whether the
-- entry is a selfAura one without charges, from the API copy
local spellA, spellB, selfNoCharge = {}, {}, {}
-- Eligibility, built together: cooldown cooldownIDs and their spells
local eligibleCd, eligibleSpell = {}, {}
-- Scratch: buff catalogue spells, used only while building
local catalogue = {}
local built = false

-- Enabled icons of the last pass: parallel arrays, reused (n = live count)
local enFrame, enA, enB = {}, {}, {}
local enN = 0
-- Pass scratch: frames a shown buff item pushed this pass
local pushed = {}
local inPass = false

local function PlainID(v)
    if type(v) == "number" and not IsSecret(v) and v > 0 then return v end
    return nil
end

-- Called by ns.MarkCDMSpellCacheDirty (EllesmereUICdmSpellPicker.lua).
function ns.CdBuffStacksInvalidate()
    wipe(spellA); wipe(spellB); wipe(selfNoCharge)
    wipe(eligibleCd); wipe(eligibleSpell)
    built = false
end

-- The spells a cooldownID names (entry, override), cached.
local function SpellsOf(cdID)
    cdID = PlainID(cdID)
    if not cdID then return nil, nil end
    local a = spellA[cdID]
    if a == nil then
        local info = CV.GetCooldownViewerCooldownInfo(cdID)
        a = info and PlainID(info.spellID) or false
        spellA[cdID] = a
        spellB[cdID] = info and PlainID(info.overrideSpellID) or false
        selfNoCharge[cdID] = (info and info.selfAura == true and not info.charges) or false
    end
    return a or nil, spellB[cdID] or nil
end

local function AddCatalogue(cat)
    local ok, ids = pcall(CV.GetCooldownViewerCategorySet, cat, true)
    if not ok or type(ids) ~= "table" then return end
    for i = 1, #ids do
        local a, b = SpellsOf(ids[i])
        if a then catalogue[a] = true end
        if b then catalogue[b] = true end
    end
end

local function AddEligible(cat)
    local ok, ids = pcall(CV.GetCooldownViewerCategorySet, cat, true)
    if not ok or type(ids) ~= "table" then return end
    for i = 1, #ids do
        local cdID = PlainID(ids[i])
        local a, b = SpellsOf(cdID)
        if selfNoCharge[cdID] then
            if (a and catalogue[a]) or (b and catalogue[b]) then
                eligibleCd[cdID] = true
                if a then eligibleSpell[a] = true end
                if b then eligibleSpell[b] = true end
            end
        end
    end
end

-- Build eligibility on first need after an invalidation. The category sets
-- are Blizzard's static per-spec catalogue (unlearned spells included); the
-- player's own layout never enters them, so the eligibility does not follow
-- it. Not before Blizzard's CDM data has loaded (ns._cdmDataLoaded,
-- EUI_CDM_Lifecycle.lua), which may be absent until then; Lifecycle queues a
-- reanchor when the data arrives, which builds it.
local function EnsureBuilt()
    if built or not ns._cdmDataLoaded then return end
    local cats = Enum.CooldownViewerCategory
    built = true
    wipe(catalogue)
    AddCatalogue(cats.TrackedBuff)
    AddCatalogue(cats.TrackedBar)
    if next(catalogue) then
        AddEligible(cats.Essential)
        AddEligible(cats.Utility)
    end
    wipe(catalogue)
end

-- Whether the options menu offers the Buff Stacks row for this key: a spell
-- ID, or a cooldownID-keyed "c<id>" slot.
function ns.CdBuffStacksEligible(key)
    EnsureBuilt()
    if type(key) == "string" and string.byte(key, 1) == 99 then
        local id = tonumber(key:sub(2))
        return id and eligibleCd[id] or false
    end
    return (type(key) == "number" and eligibleSpell[key]) or false
end

local function TextFor(frame, barKey)
    local fs = texts[frame]
    if fs then return fs end
    local fd = hookFrameData[frame]
    local overlay = fd and fd.textOverlay
    if not overlay then return nil end
    fs = overlay:CreateFontString(nil, "OVERLAY")
    texts[frame] = fs
    ns.StyleCustomChargeText(frame, barKey, fs)
    return fs
end

-- A buff item's count FontString, and for BuffIcon items the frame holding it
-- (Applications.Applications). BuffBar items keep it at Icon.Applications and
-- have no holder to test: Blizzard's Name Only bar content hides the bar's
-- Icon, while the count still counts.
local function CountOf(buff)
    local apps = buff.Applications
    if apps and apps.Applications then return apps.Applications, apps end
    local icon = buff.Icon
    if icon and icon.Applications then return icon.Applications, nil end
    return nil, nil
end

-- Whether an enabled icon names one of these spells.
local function Wanted(a, b)
    for i = 1, enN do
        local ea, eb = enA[i], enB[i]
        if (a and (a == ea or a == eb)) or (b and (b == ea or b == eb)) then return true end
    end
    return false
end

-- Copy one buff item's count onto every enabled icon of its spell. Inside a
-- pass only a shown count is pushed (the pass hides the rest); a hook push
-- between passes shows or hides.
local function Push(buff)
    if enN == 0 then return end
    local a, b = SpellsOf(buff.cooldownID)
    if not a and not b then return end
    -- A hooked item Blizzard re-pointed to a spell no icon names.
    if not Wanted(a, b) then return end
    local afs, holder = CountOf(buff)
    local shown = afs and buff:IsShown() and (not holder or holder:IsShown()) and afs:IsShown()
    if inPass and not shown then return end
    for i = 1, enN do
        local ea, eb = enA[i], enB[i]
        if (a and (a == ea or a == eb)) or (b and (b == ea or b == eb)) then
            local frame = enFrame[i]
            local fs = texts[frame]
            if fs then
                if shown then
                    -- Possibly secret: passed on untouched.
                    fs:SetText(afs:GetText())
                    fs:Show()
                    if inPass then pushed[frame] = true end
                else
                    fs:Hide()
                end
            end
        end
    end
end

local function Hook(buff)
    if hooked[buff] then return end
    local afs, holder = CountOf(buff)
    if not afs then return end
    hooked[buff] = true
    local function push() Push(buff) end
    hooksecurefunc(afs, "SetText", push)
    hooksecurefunc(afs, "Show", push)
    hooksecurefunc(afs, "Hide", push)
    if afs.SetShown then hooksecurefunc(afs, "SetShown", push) end
    if holder then
        hooksecurefunc(holder, "Show", push)
        hooksecurefunc(holder, "Hide", push)
        if holder.SetShown then hooksecurefunc(holder, "SetShown", push) end
    end
    buff:HookScript("OnShow", push)
    buff:HookScript("OnHide", push)
end

local function HideAll()
    for _, fs in pairs(texts) do fs:Hide() end
end

-- After every reanchor: enroll the enabled cooldown icons, push the buff
-- items of their spells, hide every copy nothing pushed.
function ns.CDM_CdBuffStacksPlaced()
    EnsureBuilt()
    if not next(eligibleCd) then
        if enN > 0 then enN = 0; HideAll() end
        return
    end
    enN = 0
    local fcs = ns._ecmeFC
    for vi = 1, 2 do
        local vf = GetViewerFrame(vi)
        local pool = vf and vf.itemFramePool
        if pool and pool.EnumerateActive then
            for frame in pool:EnumerateActive() do
                local cdID = PlainID(frame.cooldownID)
                local fc = cdID and eligibleCd[cdID] and fcs and fcs[frame]
                if fc and fc.barKey then
                    local ss = ns._ResolveCdmSS(frame)
                    if not (ss and ss.showBuffStacks == false) then
                        local fs = TextFor(frame, fc.barKey)
                        if fs then
                            enN = enN + 1
                            enFrame[enN] = frame
                            enA[enN], enB[enN] = SpellsOf(cdID)
                        end
                    end
                end
            end
        end
    end
    -- Drop references past the live count.
    for i = enN + 1, #enFrame do enFrame[i] = nil; enA[i] = nil; enB[i] = nil end
    if enN == 0 then HideAll(); return end

    wipe(pushed)
    inPass = true
    for vi = 3, 4 do
        local vf = GetViewerFrame(vi)
        local pool = vf and vf.itemFramePool
        if pool and pool.EnumerateActive then
            for buff in pool:EnumerateActive() do
                local a, b = SpellsOf(buff.cooldownID)
                if (a or b) and Wanted(a, b) then
                    Hook(buff)
                    Push(buff)
                end
            end
        end
    end
    inPass = false
    for frame, fs in pairs(texts) do
        if not pushed[frame] then fs:Hide() end
    end
    wipe(pushed)
end

-- Restyle with the bar's stack text settings (RefreshCDMIconAppearance).
function ns.CdBuffStacksRestyle(frame, barKey)
    local fs = texts[frame]
    if fs then ns.StyleCustomChargeText(frame, barKey, fs) end
end
