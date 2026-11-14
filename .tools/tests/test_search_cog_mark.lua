-- Run from the repository root: lua5.1 .tools/tests/test_search_cog_mark.lua [RowAddons file]
-- After a search jump to a row inside a cog's popup, MarkSearchCog paints that
-- cog's dots in the accent: only the visible cog whose search key matches, and
-- only until it is opened or hidden or another jump marks something else.
-- Runs EllesmereUI_Widgets_RowAddons.lua's real BuildInlineCog over stub frames.

-- Stub frames: methods (capitalized keys) are no-ops unless defined here,
-- fields read as nil, the dots record their colour.
local Frame
local FrameMeta = {}
FrameMeta.__index = function(self, k)
    local m = FrameMeta.methods[k]
    if m then return m end
    if type(k) == "string" and k:match("^%u") then return function() end end
end
FrameMeta.methods = {
    GetSize = function() return 24, 30 end,
    GetFrameLevel = function() return 1 end,
    GetParent = function(self) return rawget(self, "_parent") end,
    IsVisible = function(self) return rawget(self, "_shown") ~= false end,
    IsMouseOver = function() return false end,
    CreateTexture = function(self) return Frame(self) end,
    CreateAnimationGroup = function(self) return Frame(self) end,
    CreateAnimation = function(self) return Frame(self) end,
    SetVertexColor = function(self, r, g, b) rawset(self, "_rgb", { r, g, b }) end,
    SetAlpha = function(self, a) rawset(self, "_alpha", a) end,
    SetScript = function(self, name, fn)
        local s = rawget(self, "_scripts") or {}
        s[name] = fn
        rawset(self, "_scripts", s)
    end,
    Hide = function(self)
        rawset(self, "_shown", false)
        local s = rawget(self, "_scripts")
        if s and s.OnHide then s.OnHide(self) end
    end,
}
Frame = function(parent) return setmetatable({ _parent = parent }, FrameMeta) end

local ACCENT = { 1, 0.4, 0.7 }
local dotsOf = {}
local EllesmereUI = {
    _deferredInits = {},
    _Pool = { CreateFrame = function(_, _, parent) return Frame(parent) end },
    PanelPP = setmetatable({}, { __index = function() return function() end end }),
    GetAccentColor = function() return ACCENT[1], ACCENT[2], ACCENT[3] end,
    MakePixelLayer = function(btn)
        local L = { _frame = Frame(btn), parent = btn, Fit = function() end }
        dotsOf[btn] = L
        return L
    end,
    BuildCogPopup = function() return nil, function() end end,
    IsDevModeActive = function() return false end,
    GetActiveModule = function() return "M" end,
    GetActivePage = function() return "P" end,
}
setmetatable(EllesmereUI, { __index = function(_, k)
    if type(k) == "string" and k:match("^%u") then return function() end end
end })
_G.EllesmereUI = EllesmereUI
EUI_CLIENT_BLOCKED = nil

assert(loadfile(arg and arg[1] or "EllesmereUIOptions/EllesmereUI_Widgets_RowAddons.lua"))()
for _, init in ipairs(EllesmereUI._deferredInits) do init() end
local BuildInlineCog, MarkSearchCog = EllesmereUI.BuildInlineCog, EllesmereUI.MarkSearchCog
assert(BuildInlineCog and MarkSearchCog, "RowAddons publishes BuildInlineCog and MarkSearchCog")

-- The search key each cog is built with comes from _RegisterCogSearch.
local nextKey
EllesmereUI._RegisterCogSearch = function() return nextKey end
local function Cog(key)
    nextKey = key
    local rgn = Frame(Frame())
    return (BuildInlineCog(rgn, { title = "T", rows = { { type = "toggle", label = "X" } } }))
end

local fails = 0
local function Check(ok, what)
    if ok then print("ok    " .. what) else fails = fails + 1; print("FAIL  " .. what) end
end
local function Accent(btn)
    local d = dotsOf[btn][1]
    local c = rawget(d, "_rgb")
    return c and c[1] == ACCENT[1] and c[2] == ACCENT[2] and c[3] == ACCENT[3] and rawget(d, "_alpha") == 1
end

local a, b, hidden = Cog("A"), Cog("B"), Cog("A")
hidden:Hide()
Check(not Accent(a) and not Accent(b), "built cogs show plain dots")

Check(MarkSearchCog("A") == true, "a visible cog with the key is found")
Check(Accent(a) and not Accent(b), "only the matching cog wears the accent")
Check(not Accent(hidden), "a hidden cog with the key is not marked")

MarkSearchCog("B")
Check(not Accent(a) and Accent(b), "the next jump moves the mark")
MarkSearchCog(nil)
Check(not Accent(a) and not Accent(b), "a jump to an ordinary row clears the mark")

MarkSearchCog("A")
rawget(a, "_scripts").OnClick(a)
Check(not Accent(a), "opening the cog clears its mark")

MarkSearchCog("B")
b:Hide()
Check(not Accent(b), "hiding the cog (leaving the page) clears its mark")

Check(not MarkSearchCog("none"), "no cog with the key: nothing found")

print(fails == 0 and "all passed" or (fails .. " failed"))
os.exit(fails == 0 and 0 or 1)
