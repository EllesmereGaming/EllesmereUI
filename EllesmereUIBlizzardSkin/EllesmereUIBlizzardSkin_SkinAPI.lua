-------------------------------------------------------------------------------
--  EllesmereUIBlizzardSkin_SkinAPI.lua
--  Public skinning API for third-party addons. Devs call
--  EllesmereUI.RegisterSkin("TheirAddon", function(S) ... end) (the stub in
--  the parent addon queues the entry); this file dispatches those callbacks
--  and hands each one a facade S built over the window-skin engine.
--
--  Design contract (developer guide: SKINNING_API.md at the parent root):
--   - The facade is the public surface, never raw ns.WSkin. Entries are
--     late-bound pass-throughs, so engine internals stay free to change;
--     facade signatures are additive-only, versioned by S.apiVersion.
--   - Style is OUR concern, invisible to the dev: S.Shell resolves through
--     the "tp:<name>" virtual winKey -> EllesmereUI.GetThirdPartySkinStyle()
--     majority vote (most windows Modern -> modern, else EUI). Registered
--     shells live-restyle through the normal RefreshStyles path.
--   - Third-party skinning is decoupled from the window-skin kill switch and
--     from every per-window enable: it has its own master + per-addon
--     toggles (account-global, on by default). Skins install at load, so
--     turning OFF is reload-bound; turning ON dispatches live when possible.
--   - Each callback is pcall-isolated: a broken third-party skin can never
--     break ours, and vice versa.
--   - Zero cost when disabled: callbacks simply never fire; the queue is an
--     inert table.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EUI = EllesmereUI
local WSkin = ns.WSkin
if not (EUI and WSkin) then return end

-------------------------------------------------------------------------------
--  Gating: master switch + per-addon switches, account-global, nil = on.
-------------------------------------------------------------------------------
local function MasterOn()
    return not (EllesmereUIDB and EllesmereUIDB.thirdPartySkinsOff)
end

local function AddonOn(name)
    local t = EllesmereUIDB and EllesmereUIDB.thirdPartySkinAddons
    return not (t and t[name] == false)
end

-------------------------------------------------------------------------------
--  The facade. Late-bound pass-throughs into the engine: resolving WSkin[k]
--  at call time (not load time) keeps the facade valid across any internal
--  reshuffle, and every primitive is already idempotent (FFD-guarded) and
--  taint-safe, so re-calls from the dev's own refresh hooks are near-free.
-------------------------------------------------------------------------------
local base = {}
base.apiVersion = 1

local PASS = {
    -- Containers / chrome
    "Panel", "Inset", "FadeRegions", "FadeNineSlice",
    -- Widgets
    "Button", "WhiteButtonLabel", "StateButtonLabel", "EditBox", "Checkbox", "Dropdown",
    "ScrollBar", "Tab", "CloseButton", "PageButton", "SquareIcon",
    "SortHeaderBar",
    -- Text / bars
    "Font", "White", "ApplyBarFill",
}
for _, fname in ipairs(PASS) do
    base[fname] = function(...)
        local fn = WSkin[fname]
        if fn then return fn(...) end
    end
end

-- Resolved third-party theme: "eui" or "modern" (never "off"; if skinning
-- were off the callback would not have fired at all).
function base.GetStyle()
    return (EUI.GetThirdPartySkinStyle and EUI.GetThirdPartySkinStyle()) or "eui"
end

-- Live accent color (r, g, b). Prefer OnLooksChanged over caching this.
function base.GetAccentColor()
    local c = EUI.ELLESMERE_GREEN or {}
    return c.r or 0.047, c.g or 0.824, c.b or 0.616
end

-- House panel fill (r, g, b, a) for custom elements that should match.
function base.GetPanelColor()
    local T = WSkin.Theme
    if not T.bgR then WSkin.ResolveTheme() end
    return T.bgR, T.bgG, T.bgB, T.bgA
end

-- The user's UI font: path, outline flag ("" when none).
function base.GetFont()
    local T = WSkin.Theme
    if not T.fontPath then WSkin.ResolveTheme() end
    return T.fontPath, T.fontFlag
end

-- Fires when suite-wide looks change live (accent color, bar fill, Modern
-- backdrop color, window styles). Shell/primitive visuals refresh on their
-- own; this is only for custom elements colored via the getters above.
function base.OnLooksChanged(fn)
    if type(fn) == "function" then WSkin.OnLooksChanged(fn) end
end

-- Per-addon facade: Shell is curried with the addon's virtual winKey so the
-- dev never sees style plumbing, and IsEnabled reflects their own toggles.
local function MakeFacade(name)
    local winKey = "tp:" .. name
    local S = {
        Shell = function(frame, opts)
            return WSkin.Shell(winKey, frame, opts)
        end,
        IsEnabled = function()
            return MasterOn() and AddonOn(name)
        end,
    }
    return setmetatable(S, { __index = base })
end

-------------------------------------------------------------------------------
--  Dispatcher. Fires each registered callback ONCE per session, at
--  PLAYER_LOGIN (after the engine's own boot -- this file loads later, so
--  its handler runs later) or immediately for late/LoD registrations.
-------------------------------------------------------------------------------
local _fired = {}
local _loginDone = false

local function Dispatch(entry)
    if _fired[entry.name] then return end
    if not (MasterOn() and AddonOn(entry.name)) then return end
    _fired[entry.name] = true
    if not WSkin.Theme.fontPath then WSkin.ResolveTheme() end
    local ok, err = pcall(entry.apply, MakeFacade(entry.name))
    if not ok and err then
        -- Surface through the normal error pipeline without stopping the
        -- other skins (ours or theirs).
        geterrorhandler()(err)
    end
end

-- Called by the parent stub for registrations arriving after login (LoD
-- third-party addons); pre-login entries wait in the queue for the boot.
EUI._DispatchSkinRegistration = function(entry)
    if _loginDone then Dispatch(entry) end
end

-- Options page support: registered names + whether each ran this session.
function ns.GetThirdPartySkinList()
    local out = {}
    local reg = EUI._skinRegistry or {}
    for i = 1, #reg do
        out[i] = { name = reg[i].name, active = _fired[reg[i].name] or false }
    end
    return out
end

-- Options page support: when a toggle turns skinning ON mid-session, fire
-- any now-eligible unfired entries live (skins install fine at any time;
-- only REMOVING them needs the reload). Returns true if anything fired.
function ns.TryDispatchThirdPartySkins()
    if not _loginDone then return false end
    local fired = false
    local reg = EUI._skinRegistry or {}
    for i = 1, #reg do
        local entry = reg[i]
        if not _fired[entry.name] and MasterOn() and AddonOn(entry.name) then
            Dispatch(entry)
            fired = true
        end
    end
    return fired
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    _loginDone = true
    local reg = EUI._skinRegistry or {}
    for i = 1, #reg do Dispatch(reg[i]) end
end)
