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
--  Source: the same spell's item in Blizzard's buff viewers (BuffIcon /
--  BuffBar), which draws the count. Its Applications text is mirrored as
--  Blizzard sets it (hooksecurefunc on that FontString's SetText, and on its
--  frame's show state), so the copy is as live as Blizzard's own and a secret
--  count (aura restrictions, i.e. combat) goes straight to SetText, never
--  read. The buff must therefore be tracked in Blizzard's Cooldown Manager
--  buffs; it does not have to be shown on any EUI bar.
--
--  The text is a FontString of ours on the icon's text overlay, keyed weakly
--  by frame (no fields on Blizzard frames), styled with the bar's stack text
--  settings (ns.StyleCustomChargeText).
--
--  Stored per spell like every per-spell setting: showBuffStacks = true.
--  Cost: nothing until some saved spell has the setting. ns._cdmAnyCdBuffStacks
--  is set once by RescanCdBuffStacksFlag at setup, or by the menu on first use
--  (monotonic, like the other per-spell gates). Hooks are installed only on
--  buff items whose spell an enabled icon names.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._hookInternals
if not I or not I.GetViewerFrame then return end
local GetViewerFrame, hookFrameData = I.GetViewerFrame, I.hookFrameData
local IsSecret = EllesmereUI.IsSecret

-- cooldown frame -> our FontString
local texts = setmetatable({}, { __mode = "k" })
-- spell ID -> { [cooldown frame] = true } for enabled icons, rebuilt per reanchor
local wanted = {}
-- buff item frames hooked once (pooled frames are rebound: the spell is read
-- from the item at each push, never captured)
local hooked = setmetatable({}, { __mode = "k" })

local function PlainID(v)
    if type(v) == "number" and not IsSecret(v) and v > 0 then return v end
    return nil
end

-- The spell IDs an item answers to: its entry spell and override.
local function ItemSpells(frame)
    local info = frame.cooldownInfo
    if not info or IsSecret(info) then return nil, nil end
    return PlainID(info.spellID), PlainID(info.overrideSpellID)
end

local function TextFor(frame, barKey)
    local fs = texts[frame]
    if fs then return fs end
    local fd = hookFrameData and hookFrameData[frame]
    local overlay = fd and fd.textOverlay
    if not overlay then return nil end
    fs = overlay:CreateFontString(nil, "OVERLAY")
    texts[frame] = fs
    if ns.StyleCustomChargeText then ns.StyleCustomChargeText(frame, barKey, fs) end
    return fs
end

-- Copy one buff item's count onto every enabled icon of its spell.
local function Push(buff)
    local a, b = ItemSpells(buff)
    local set = (a and wanted[a]) or (b and wanted[b])
    if not set then return end
    local apps = buff.Applications
    local afs = apps and apps.Applications
    local shown = afs and buff:IsShown() and apps:IsShown() and afs:IsShown()
    for frame in pairs(set) do
        local fs = texts[frame]
        if fs then
            if shown then
                -- Possibly secret: passed on untouched.
                fs:SetText(afs:GetText())
                fs:Show()
            else
                fs:Hide()
            end
        end
    end
end

local function Hook(buff)
    if hooked[buff] then return end
    local apps = buff.Applications
    local afs = apps and apps.Applications
    if not afs then return end
    hooked[buff] = true
    local function push() Push(buff) end
    hooksecurefunc(afs, "SetText", push)
    hooksecurefunc(afs, "Show", push)
    hooksecurefunc(afs, "Hide", push)
    hooksecurefunc(apps, "Show", push)
    hooksecurefunc(apps, "Hide", push)
    if apps.SetShown then hooksecurefunc(apps, "SetShown", push) end
    buff:HookScript("OnShow", push)
    buff:HookScript("OnHide", push)
end

-- After every reanchor: enroll the enabled cooldown icons, then hook and push
-- the buff items of their spells.
function ns.CDM_CdBuffStacksPlaced()
    if not ns._cdmAnyCdBuffStacks then return end
    wipe(wanted)
    local any = false
    local live = {}
    for vi = 1, 2 do
        local vf = GetViewerFrame(vi)
        local pool = vf and vf.itemFramePool
        if pool and pool.EnumerateActive then
            for frame in pool:EnumerateActive() do
                local ss = ns._ResolveCdmSS and ns._ResolveCdmSS(frame)
                if ss and ss.showBuffStacks == true then
                    local fc = ns._ecmeFC and ns._ecmeFC[frame]
                    local fs = TextFor(frame, fc and fc.barKey)
                    if fs then
                        live[frame] = true
                        local a, b = ItemSpells(frame)
                        for _, sid in ipairs({ a, b }) do
                            if sid then
                                wanted[sid] = wanted[sid] or {}
                                wanted[sid][frame] = true
                                any = true
                            end
                        end
                    end
                end
            end
        end
    end
    -- Icons no longer enabled (setting cleared, frame rebound): blank.
    for frame, fs in pairs(texts) do
        if not live[frame] then fs:Hide() end
    end
    if not any then return end
    for vi = 3, 4 do
        local vf = GetViewerFrame(vi)
        local pool = vf and vf.itemFramePool
        if pool and pool.EnumerateActive then
            for buff in pool:EnumerateActive() do
                local a, b = ItemSpells(buff)
                if (a and wanted[a]) or (b and wanted[b]) then
                    Hook(buff)
                    Push(buff)
                end
            end
        end
    end
end

-- Restyle with the bar's stack text settings (RefreshCDMIconAppearance).
function ns.CdBuffStacksRestyle(frame, barKey)
    local fs = texts[frame]
    if fs and ns.StyleCustomChargeText then ns.StyleCustomChargeText(frame, barKey, fs) end
end

-- Gate: set ns._cdmAnyCdBuffStacks once if any saved spell (any spec) or bar
-- tier has the setting. Same monotonic, scanned-once contract as the others.
function ns.RescanCdBuffStacksFlag()
    if ns._cdmAnyCdBuffStacks or ns._cdBuffStacksFlagScanned then return end
    if not EllesmereUIDB or not ns.ForEachSavedSettingsBlock then return end
    ns._cdBuffStacksFlagScanned = true
    ns.ForEachSavedSettingsBlock(function(ss)
        if rawget(ss, "showBuffStacks") == true then
            ns._cdmAnyCdBuffStacks = true
            return true
        end
    end)
end
