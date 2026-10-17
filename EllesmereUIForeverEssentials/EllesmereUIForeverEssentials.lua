if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials.lua  (WoW Forever only)
--  Essential tools for WoW Forever. Each feature lives in its own file, listed
--  after this one in the TOC; this file publishes the module.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EllesmereUI and EllesmereUI._ModuleNS and EllesmereUI._Pool) then EUI_CLIENT_BLOCKED = true; return end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring
EllesmereUI._ModuleNS[ADDON_NAME] = ns  -- LOD options files read this module ns via the registry

-- Lifecycle object (OnInitialize / OnEnable) for features that need one. No
-- per-profile DB: every feature so far keeps account-wide settings.
ns.addon = EllesmereUI.Lite.NewAddon(ADDON_NAME)

-------------------------------------------------------------------------------
--  Feature kit: settings and the login boot for every feature, plus placement
--  and the unlock element for the ones drawn on one frame of ours that unlock
--  mode places (Travel, Loot, Junk Items).
--  Settings are account-wide in EllesmereUIDB[dbKey]: Read() never creates the
--  table, so a feature nobody touches saves nothing; Cfg() is the write
--  accessor and Get() falls back to defaults. pos (point, relPoint, x, y) is
--  where unlock mode put the frame; defaultPos stands in until then.
-------------------------------------------------------------------------------
function ns.Feature(dbKey, defaults, defaultPos)
    local F, none = {}, {}
    local function Read()
        return EllesmereUIDB and EllesmereUIDB[dbKey] or none
    end
    local function Cfg()
        if not EllesmereUIDB then return {} end
        local c = EllesmereUIDB[dbKey]
        if not c then
            c = {}
            EllesmereUIDB[dbKey] = c
        end
        return c
    end
    local function Get(key)
        local v = Read()[key]
        if v == nil then return defaults[key] end
        return v
    end
    local function Enabled()
        return Get("enabled") == true
    end
    local function SavedPos()
        local pos = Read().pos
        return pos and pos.point and pos or defaultPos
    end
    -- A frame not built yet (nil) has nothing to place. snap: a CENTER point
    -- lands on the pixel grid for the frame's size, as unlock mode places it.
    local function Place(frame, snap)
        if not frame then return end
        local pos = SavedPos()
        local x, y = pos.x or 0, pos.y or 0
        if snap and pos.point == "CENTER" then
            local PP = EllesmereUI.PP
            x = PP.SnapCenterForDim(x, frame:GetWidth())
            y = PP.SnapCenterForDim(y, frame:GetHeight())
        end
        frame:ClearAllPoints()
        frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, x, y)
    end
    F.Read, F.Cfg, F.Get, F.Enabled, F.Place = Read, Cfg, Get, Enabled, Place

    -- At login: apply(), then the unlock element when the feature has a frame
    -- (no u: nothing on screen).
    --   u.key, u.label, u.order
    --   u.frame(build)   the frame (nil until built); build builds it first
    -- By default the frame's width is its "width" setting, which unlock mode
    -- resizes, and its height follows its other settings:
    --   u.height()       the frame's height
    --   u.minWidth       the narrowest width unlock mode sets
    --   u.applyStyle()   lays the frame out again after a width change
    -- A frame whose settings fix its whole size gives u.size() instead; unlock
    -- mode then moves it but never resizes it:
    --   u.size()         the frame's width and height
    --   u.snap           every placement snaps its centre (see Place)
    --   u.noAnchorTarget, u.noSizeMatchTarget  as MakeUnlockElement takes them
    --   u.shown()        whether the frame is in use (default: the "enabled" setting)
    -- Nothing is built while the feature is off (the unlock core calls getFrame
    -- and applyPos for every element at each login).
    function F.Start(apply, u)
        local boot = CreateFrame("Frame")
        boot:RegisterEvent("PLAYER_LOGIN")
        boot:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            apply()
            if not u then return end
            local Shown = u.shown or Enabled
            local e = {
                key      = u.key,
                label    = u.label,
                group    = "Forever Essentials",
                order    = u.order,
                noAnchorTarget    = u.noAnchorTarget,
                noSizeMatchTarget = u.noSizeMatchTarget,
                isHidden = function() return not Shown() end,
                getFrame = function()
                    return Shown() and u.frame(true) or nil
                end,
                savePos = function(_, point, relPoint, x, y)
                    if not point then return end
                    Cfg().pos = { point = point, relPoint = relPoint, x = x, y = y }
                    if not EllesmereUI._unlockActive then Place(u.frame(), u.snap) end
                end,
                loadPos = SavedPos,
                clearPos = function()
                    Cfg().pos = nil
                    Place(u.frame(), u.snap)
                end,
                applyPos = function()
                    if Shown() then Place(u.frame(true), u.snap) end
                end,
            }
            if u.size then
                e.noResize = true
                e.getSize = u.size
            else
                e.getSize = function() return Get("width"), u.height() end
                e.setWidth = function(_, w)
                    Cfg().width = math.max(u.minWidth, EllesmereUI.PP.Snap(w))
                    u.applyStyle()
                    if EllesmereUI._unlockActive and EllesmereUI.RepositionBarToMover then
                        EllesmereUI.RepositionBarToMover(u.key)
                    end
                end
            end
            EllesmereUI:RegisterUnlockElements({ EllesmereUI.MakeUnlockElement(e) }, "EllesmereUIForeverEssentials")
        end)
    end
    return F
end
