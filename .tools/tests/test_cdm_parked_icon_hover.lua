-- Stub harness: Cooldown Manager icons parked off screen stay parked.
-- Cuts the viewer re-anchoring (the pending queue, its park and any hook for
-- parked icons) and DecorateFrame's SetPoint hook from EUI_CDM_HookDecorate.lua,
-- and the unclaimed CD/utility park of the reanchor's cleanup pass from
-- EUI_CDM_HookReanchor.lua, then plays Blizzard's viewer over them: a
-- RefreshLayout releases every pool frame (hidden, anchors cleared), acquires it
-- again with the viewer's tooltip motion and lays the grid out against the
-- viewer, which sits on our cooldowns bar.
--   a spell on Hidden CDs since login (never claimed, never decorated) is back
--     off screen after Blizzard's layout, so it cannot catch hover in the grid
--   an icon claimed before keeps its own hook's behaviour, unchanged
--   a parked icon claimed later goes to its bar slot and keeps its alpha
--   the park's own SetPoint queues nothing, and each icon is hooked once
-- The model is this file's reading of the client, not the client.
--   lua .tools/tests/test_cdm_parked_icon_hover.lua        (from the repository root)
local DECORATE = PK_DECORATE or "EllesmereUICooldownManager/EUI_CDM_HookDecorate.lua"
local REANCHOR = PK_REANCHOR or "EllesmereUICooldownManager/EUI_CDM_HookReanchor.lua"

local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        print("  FAIL: " .. msg)
    end
end

local function Read(path)
    local fh = assert(io.open(path, "rb"))
    local s = fh:read("*a"):gsub("\r\n", "\n")
    fh:close()
    return s
end

-- The text between `from` and the first `to` after it, both included.
local function Cut(src, from, to, what)
    local a = assert(src:find(from, 1, true), what .. ": start not found")
    local b, e = src:find(to, a, true)
    assert(b, what .. ": end not found")
    return src:sub(a, e)
end

local dec = Read(DECORATE)
local rea = Read(REANCHOR)

local CHUNK = "local ns, hookFrameData, hooksecurefunc, UIParent = ...\n"
    .. Cut(dec, "local viewerPending = setmetatable({}, { __mode = \"k\" })",
        "viewerRestore:SetScript(\"OnUpdate\", function() RestoreViewerAnchors() end)", "viewer re-anchoring") .. "\n"
    .. "local function Decorate(frame, fd)\n    fd.decorated = true\n"
    .. Cut(dec, "    if not fd._setPointHooked then\n        fd._setPointHooked = true",
        "            QueueViewerAnchor(frame)\n        end)\n    end\n", "DecorateFrame SetPoint hook")
    .. "end\n"
    .. "local function Park(frame, efd)\n"
    .. Cut(rea, "                frame:SetAlpha(0)\n                -- TOPLEFT keyword matches LayoutCDMBar's claim SetPoint",
        "                    frame.Cooldown:SetDrawSwipe(false)\n                end\n", "unclaimed park")
    .. "end\n"
    .. "return RestoreViewerAnchors, Decorate, Park, viewerRestore\n"
local Build = assert(loadstring(CHUNK, "=ParkedIcons"))

-------------------------------------------------------------------------------
--  The world
-------------------------------------------------------------------------------
local hookCalls
local function Frame(name)
    local f = { _name = name, _shown = true, _alpha = 1, _motion = true, _points = {} }
    function f:SetPoint(p, rel, rp, x, y) self._points[#self._points + 1] = { p, rel, rp, x, y } end
    function f:ClearAllPoints() self._points = {} end
    function f:SetAlpha(a) self._alpha = a end
    function f:Show() self._shown = true end
    function f:Hide() self._shown = false end
    function f:IsShown() return self._shown end
    function f:SetMouseMotionEnabled(on) self._motion = on end
    function f:SetScript(k, fn) self["_" .. k] = fn end
    return f
end

-- hooksecurefunc on a frame instance: the original runs, then the hook.
local function hooksecurefunc(obj, method, fn)
    hookCalls[obj] = (hookCalls[obj] or 0) + 1
    local orig = obj[method]
    obj[method] = function(self, ...)
        orig(self, ...)
        fn(self, ...)
    end
end

local UIParent = Frame("UIParent")
local W

local function Load()
    hookCalls = {}
    local ns = { TakeShell = function() local s = Frame("shell"); s._shown = false; return s end }
    local hookFrameData = setmetatable({}, { __mode = "k" })
    local Restore, Decorate, Park, shell = Build(ns, hookFrameData, hooksecurefunc, UIParent)
    W = { fd = hookFrameData, Restore = Restore, Decorate = Decorate, Park = Park, shell = shell }
    W.viewer = Frame("EssentialCooldownViewer")
    W.viewer.tooltipsShown = true
    W.bar = Frame("ECME_CDMBar_cooldowns")
    W.pool = {}
    for i = 1, 4 do
        local f = Frame("EssentialCooldownViewer.item" .. i)
        f.viewerFrame = W.viewer
        f.Cooldown = { SetDrawSwipe = function() end }
        W.pool[i] = f
    end
end

-- Blizzard's grid: every acquired item TOPLEFT on the viewer, left to right.
local function Layout()
    for i, f in ipairs(W.pool) do
        if f._shown then f:SetPoint("TOPLEFT", W.viewer, "TOPLEFT", (i - 1) * 51, 0) end
    end
end

-- RefreshLayout: release all (hide, clear anchors), acquire with the viewer's
-- tooltip motion, lay out, then our RefreshLayout post-hook.
local function RefreshLayout()
    for _, f in ipairs(W.pool) do f:Hide(); f:ClearAllPoints() end
    for _, f in ipairs(W.pool) do
        f:Show()
        f:SetMouseMotionEnabled(W.viewer.tooltipsShown)
    end
    Layout()
    W.Restore(W.viewer)
end

-- The one-shot restore frame, as its OnUpdate runs on the next frame.
local function NextFrame()
    if W.shell._shown and W.shell._OnUpdate then W.shell._OnUpdate(W.shell, 0.016) end
end

local function LastPoint(f) return f._points[#f._points] end

-- Under the cursor: shown, motion on and anchored somewhere on screen. Parked
-- icons hang from UIParent at -10000.
local function CatchesHover(f)
    local pt = LastPoint(f)
    if not (f._shown and f._motion and pt) then return false end
    return not (pt[2] == UIParent and pt[4] == -10000)
end

local function Parked(f)
    local pt = LastPoint(f)
    return pt and pt[2] == UIParent and pt[4] == -10000 and pt[5] == 10000 and #f._points == 1
end

-- Our claim: decorate, stamp the anchor before SetPoint, alpha to the bar's.
local function Claim(f, slot)
    local fd = W.fd[f]
    if not fd then fd = {}; W.fd[f] = fd end
    W.Decorate(f, fd)
    W.fd[f] = fd
    fd._cdmAnchor = { "TOPLEFT", W.bar, "TOPLEFT", slot * 36, 0 }
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", W.bar, "TOPLEFT", slot * 36, 0)
    f:SetAlpha(1)
end

-- The cleanup pass for an unclaimed CD/utility icon (Phase 4).
local function Phase4(f)
    local efd = W.fd[f]
    if efd then efd._cdmAnchor = nil end
    W.Park(f, efd)
end

-------------------------------------------------------------------------------
--  1. A spell on Hidden CDs since login, Blizzard's RefreshLayout after it
-------------------------------------------------------------------------------
print("1. never claimed, RefreshLayout")
Load()
local hidden = W.pool[3]
Claim(W.pool[1], 0); Claim(W.pool[2], 1); Claim(W.pool[4], 2)
Phase4(hidden)
check(Parked(hidden) and hidden._alpha == 0, "the cleanup pass parks it at alpha 0")
check(not W.shell._shown, "the park's own SetPoint queues nothing")
RefreshLayout()
check(not CatchesHover(hidden), "after Blizzard's layout it is off screen, not in the grid catching hover")
check(Parked(hidden), "parked again with one anchor")
check(hidden._alpha == 0, "still alpha 0")
NextFrame()
check(not W.shell._shown, "nothing left pending")
for slot, f in ipairs({ W.pool[1], W.pool[2], W.pool[4] }) do
    local pt = LastPoint(f)
    check(pt and pt[2] == W.bar and pt[4] == (slot - 1) * 36 and #f._points == 1,
        "claimed icon " .. slot .. " is back on its bar slot")
end
RefreshLayout(); RefreshLayout()
check(Parked(hidden) and not CatchesHover(hidden), "every later layout parks it again")

-------------------------------------------------------------------------------
--  2. A Layout outside RefreshLayout (no post-hook): the one-shot frame parks
-------------------------------------------------------------------------------
print("2. never claimed, Layout alone")
Load()
hidden = W.pool[2]
Claim(W.pool[1], 0)
Phase4(hidden); Phase4(W.pool[3]); Phase4(W.pool[4])
Layout()
NextFrame()
check(not CatchesHover(hidden), "parked by the next frame")
check(not W.shell._shown, "the one-shot frame stops")

-------------------------------------------------------------------------------
--  3. Repeated cleanup passes: hooked once, no queue from our own park
-------------------------------------------------------------------------------
print("3. repeated cleanup passes")
Load()
hidden = W.pool[1]
for _ = 1, 5 do Phase4(hidden) end
check((hookCalls[hidden] or 0) <= 1, "hooked at most once")
check(not W.shell._shown, "our park never queues itself")
check(W.fd[hidden] == nil, "no frame data made for an undecorated icon")

-------------------------------------------------------------------------------
--  4. An icon claimed before and moved to Hidden CDs: DecorateFrame's hook only
-------------------------------------------------------------------------------
print("4. claimed before, unclaimed now")
Load()
local was = W.pool[2]
Claim(was, 0)
local hooksAfterClaim = hookCalls[was]
Phase4(was)
check(hookCalls[was] == hooksAfterClaim, "no second hook on a decorated icon")
RefreshLayout()
check(Parked(was) and not CatchesHover(was), "parked by its own hook after the layout")

-------------------------------------------------------------------------------
--  5. Parked first, claimed later: goes to its bar slot and keeps its alpha
-------------------------------------------------------------------------------
print("5. parked, then claimed")
Load()
local late = W.pool[4]
Phase4(late)
Claim(late, 3)
RefreshLayout()
NextFrame()
local pt = LastPoint(late)
check(pt and pt[2] == W.bar and pt[4] == 3 * 36 and #late._points == 1, "on its bar slot after the layout")
check(late._alpha == 1, "its alpha is the claim's")
check(not W.shell._shown, "nothing left pending")

print(string.format("%d checks, %d failed", count, fails))
if fails > 0 then error(fails .. " check(s) failed") end
