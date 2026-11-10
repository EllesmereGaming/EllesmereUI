-- Stub harness: the dropdown list clip of EllesmereUI.MakeRoundedBorder
-- (EllesmereUI_RoundedCorners.lua). On every show a clipped list masks the
-- textures of its scroll content with its inner mask; the client loads art in
-- the background, and a masked texture drawn before both arts have loaded
-- draws nothing until something redraws it.
--   the mask's art: a list's checkboxes stayed blank on the session's first
--     open. The walk waits for it (ClipWhenLoaded): at once when it has
--     loaded, else from a frame of ours shown only while something waits. A
--     card's clip and accent mask wait the same way, per texture
--     (MaskWhenLoaded).
--   a texture's own art: a list of spell icons the session had not shown yet
--     drew most of them blank. The walk leaves such a texture without the
--     mask, takes off one an earlier show gave it, and the same frame masks
--     it once its art is in, while its list is still open.
-- Cuts the walk out of the file and drives it on fake frames.
--   lua .tools/tests/test_rounded_clip_wait.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return (src:gsub("\r\n", "\n"))
end

local SRC = ReadSource("EllesmereUI_RoundedCorners.lua")
local a = assert(SRC:find("local cMask, cSet, cOwner\n", 1, true), "the clip walk is missing")
local endMark = "maskWaiting[tex] = { m = m, gen = PoolDress(tex) } end\nend\n"
local e = assert(SRC:find(endMark, a, true), "the mask wait is missing")
local CUT = SRC:sub(a, e + #endMark - 1) .. "\nreturn ClipContent, ClipWhenLoaded, MaskWhenLoaded\n"
assert(SRC:find("o.clipped, o.onShow = setmetatable({}, WEAK_K), ClipWhenLoaded", 1, true),
    "MakeRoundedBorder does not show its list through ClipWhenLoaded")
assert(SRC:find("local function CardClip(o, tex)\n    MaskWhenLoaded(tex, InnerMask(o))\nend", 1, true),
    "a card's clip does not wait for its mask's art")
assert(SRC:find("SetRounded(am, o.r - 1, ALL_CORNERS, \"CLAMPTOBLACKADDITIVE\")\n        MaskWhenLoaded(accent, am)", 1, true),
    "a card's accent does not wait for its mask's art")

local fails = 0
local function check(cond, msg)
    if not cond then
        fails = fails + 1
        print("FAIL: " .. msg)
    end
end

-- Fakes ----------------------------------------------------------------------
local function Tex(name)
    local t = { name = name, masks = {}, dupes = 0 }
    function t:GetObjectType() return "Texture" end
    function t:AddMaskTexture(m)
        for i = 1, #self.masks do
            if self.masks[i] == m then
                self.dupes = self.dupes + 1
                error("mask added twice")
            end
        end
        self.masks[#self.masks + 1] = m
    end
    function t:RemoveMaskTexture(m)
        for i = #self.masks, 1, -1 do
            if self.masks[i] == m then table.remove(self.masks, i) end
        end
    end
    return t
end
-- A texture whose own art comes from a file the client loads in the
-- background (a spell icon); reads counts the load checks made on it.
local function Icon(name, loaded)
    local t = Tex(name)
    t.loaded, t.reads = loaded == true, 0
    function t:IsObjectLoaded()
        self.reads = self.reads + 1
        return self.loaded
    end
    return t
end
local function Font()
    local f = {}
    function f:GetObjectType() return "FontString" end
    return f
end
local function Frame(kind, regions, children)
    local f = { kind = kind or "Frame", regions = regions or {}, children = children or {}, visible = true }
    function f:GetObjectType() return self.kind end
    function f:GetRegions() return unpack(self.regions) end
    function f:GetChildren() return unpack(self.children) end
    function f:IsVisible() return self.visible end
    return f
end
local function Mask()
    local m = { loaded = false }
    function m:IsObjectLoaded() return self.loaded end
    return m
end

-- One list: menu > scroll frame > content > row > box, with a highlight, a
-- check box (fill, border strip, check) and a label. icons: file-backed
-- textures on the row (true = art loaded, false = still loading).
local function List(...)
    local box = { fill = Tex("fill"), strip = Tex("strip"), check = Tex("check") }
    local borderFrame = Frame("Frame", { box.strip })
    local boxFrame = Frame("Frame", { box.fill, box.check }, { borderFrame })
    local hl = Tex("hl")
    local regions, icons = { hl, Font() }, {}
    for i = 1, select("#", ...) do
        icons[i] = Icon("icon" .. i, (select(i, ...)))
        regions[#regions + 1] = icons[i]
    end
    local row = Frame("Button", regions, { boxFrame })
    local content = Frame("Frame", {}, { row })
    local sf = Frame("ScrollFrame")
    function sf:GetScrollChild() return content end
    local layer = Frame("Frame")
    local menu = Frame("Frame", {}, { sf, layer })
    local o = { _frame = layer, parent = menu, innerMask = Mask(), clipped = {} }
    o.texs = { hl, box.fill, box.strip, box.check }
    o.icons = icons
    return o
end
local function Masked(o)
    for _, t in ipairs(o.texs) do
        if #t.masks ~= 1 or t.masks[1] ~= o.innerMask then return false end
    end
    return true
end
local function Bare(o)
    for _, t in ipairs(o.texs) do
        if #t.masks ~= 0 then return false end
    end
    return true
end
-- The icon carries the list's mask, once.
local function Has(o, icon) return #icon.masks == 1 and icon.masks[1] == o.innerMask end

local frames, waitFrame = 0, nil
local layers = {}
local env = setmetatable({
    layers = layers,
    WEAK_K = { __mode = "k" },
    -- A texture's pool dress: its .gen (a reuse bumps it), 1 for the rest.
    PoolDress = function(obj) return type(obj) == "table" and obj.gen or 1 end,
    AddMask = function(tex, m) return (pcall(tex.AddMaskTexture, tex, m)) end,
    RemoveMask = function(tex, m) pcall(tex.RemoveMaskTexture, tex, m) end,
    CreateFrame = function()
        frames = frames + 1
        local f = { shown = true, scripts = {} }
        function f:Hide() self.shown = false end
        function f:Show() self.shown = true end
        function f:SetScript(name, fn) self.scripts[name] = fn end
        waitFrame = f
        return f
    end,
}, { __index = _G })
local cut = assert(loadstring(CUT, "=clip"))
-- The cut reads the file's other locals (layers, AddMask...) as globals: the env's.
setfenv(cut, env)
local _, ClipWhenLoaded, MaskWhenLoaded = cut()
local function Tick()
    if waitFrame and waitFrame.shown then waitFrame.scripts.OnUpdate(waitFrame) end
end
local function Waiting() return waitFrame ~= nil and waitFrame.shown end

-- 1. The art has loaded: the walk masks every texture at once, no frame.
local A = List()
layers[A._frame] = A
A.innerMask.loaded = true
ClipWhenLoaded(A)
check(Masked(A), "loaded art: the rows' textures were not masked")
check(frames == 0, "loaded art: a wait frame was made")
-- A second show adds nothing twice (the per-dress set).
ClipWhenLoaded(A)
check(Masked(A), "a second show masked a texture twice")

-- 1b. Icons whose own art has loaded are masked with the rest, still no frame.
local A2 = List(true, true)
layers[A2._frame] = A2
A2.innerMask.loaded = true
ClipWhenLoaded(A2)
check(Masked(A2) and Has(A2, A2.icons[1]) and Has(A2, A2.icons[2]), "loaded icons were not masked at the walk")
check(frames == 0, "loaded icons: a wait frame was made")

-- 2. The art is still loading: nothing is masked until it has loaded.
local B = List()
layers[B._frame] = B
ClipWhenLoaded(B)
check(Bare(B), "loading art: textures were masked before the art loaded")
check(frames == 1 and waitFrame.shown, "loading art: no frame waits for it")
Tick()
check(Bare(B) and waitFrame.shown, "still loading: the wait masked or stopped")
-- Shown again while it waits: still one frame, still waiting.
ClipWhenLoaded(B)
check(frames == 1 and waitFrame.shown and Bare(B), "a second show while waiting made a frame or masked")
B.innerMask.loaded = true
Tick()
check(Masked(B), "the art loaded: the rows' textures were not masked")
check(not waitFrame.shown, "nothing waits: the frame kept running")

-- 3. A list closed before its art loads is not walked; its next show is.
local C = List()
layers[C._frame] = C
ClipWhenLoaded(C)
check(waitFrame.shown and frames == 1, "the frame did not wait again")
C._frame.visible = false
C.innerMask.loaded = true
Tick()
check(Bare(C) and not waitFrame.shown, "a closed list was walked, or the wait kept running")
C._frame.visible = true
ClipWhenLoaded(C)
check(Masked(C), "the next show of a list closed while waiting did not mask")

-- 4. A layer handed to another build while it waits is not walked.
local D = List()
layers[D._frame] = D
ClipWhenLoaded(D)
layers[D._frame] = nil
D.innerMask.loaded = true
Tick()
check(Bare(D) and not waitFrame.shown, "a layer of an earlier build was walked")

-- 5. Two lists waiting: each is walked when its own art has loaded.
local E, F = List(), List()
layers[E._frame], layers[F._frame] = E, F
ClipWhenLoaded(E)
ClipWhenLoaded(F)
E.innerMask.loaded = true
Tick()
check(Masked(E) and Bare(F) and waitFrame.shown, "the first list's load was not walked alone")
F.innerMask.loaded = true
Tick()
check(Masked(F) and not waitFrame.shown, "the second list's load was not walked")
check(frames == 1, "a second wait frame was made")

-- 6. An edit box in the content keeps its textures (the engine makes some of them).
local G = List()
local editTex = Tex("edit")
local edit = Frame("EditBox", { editTex })
local content = G.parent.children[1]:GetScrollChild()
content.children[#content.children + 1] = edit
layers[G._frame] = G
G.innerMask.loaded = true
ClipWhenLoaded(G)
check(Masked(G) and #editTex.masks == 0, "an edit box's texture was masked")

-- 7. A mask with no load check is walked at once, as before the wait.
local H = List()
layers[H._frame] = H
H.innerMask.IsObjectLoaded = nil
local before = frames
local shownBefore = waitFrame and waitFrame.shown
ClipWhenLoaded(H)
check(Masked(H) and frames == before and (waitFrame and waitFrame.shown) == shownBefore,
    "a mask with no load check waited")

-- 8. A card's texture (MaskWhenLoaded): loaded art masks at once and starts nothing.
local strip = Tex("strip")
local inner = Mask()
inner.loaded = true
local waitingBefore = waitFrame and waitFrame.shown
MaskWhenLoaded(strip, inner)
check(#strip.masks == 1 and strip.masks[1] == inner, "loaded art: the card texture was not masked")
check((waitFrame and waitFrame.shown) == waitingBefore, "loaded art: the card texture started a wait")

-- 9. Loading art: unmasked until it has loaded, then masked once; the frame stops.
local hover, innerB = Tex("hover"), Mask()
MaskWhenLoaded(hover, innerB)
check(#hover.masks == 0 and waitFrame.shown, "loading art: the card texture was masked or nothing waits")
Tick()
check(#hover.masks == 0 and waitFrame.shown, "still loading: the card texture was masked or the wait stopped")
innerB.loaded = true
Tick()
check(#hover.masks == 1 and hover.masks[1] == innerB and not waitFrame.shown,
    "the art loaded: the card texture was not masked, or the wait kept running")

-- 10. A texture the page pool handed to another build meanwhile is left alone.
local reused, innerC = Tex("reused"), Mask()
reused.gen = 1
MaskWhenLoaded(reused, innerC)
reused.gen = 2
innerC.loaded = true
Tick()
check(#reused.masks == 0 and not waitFrame.shown, "a texture of another build took the old mask")

-- 11. A re-shaped mask while waiting (the accent re-fits): the latest one, once.
local accent, amOld, amNew = Tex("accent"), Mask(), Mask()
MaskWhenLoaded(accent, amOld)
MaskWhenLoaded(accent, amNew)
amNew.loaded = true
Tick()
check(#accent.masks == 1 and accent.masks[1] == amNew and not waitFrame.shown,
    "a re-shaped mask: the accent did not take the latest mask once")

-- 12. A list and a card texture waiting together: the frame stops after both.
local L2, cardTex, innerD = List(), Tex("card"), Mask()
layers[L2._frame] = L2
ClipWhenLoaded(L2)
MaskWhenLoaded(cardTex, innerD)
L2.innerMask.loaded = true
Tick()
check(Masked(L2) and #cardTex.masks == 0 and waitFrame.shown, "the list's load stopped the card's wait")
innerD.loaded = true
Tick()
check(#cardTex.masks == 1 and not waitFrame.shown, "the card's load was not finished, or the frame kept running")
check(frames == 1, "a second wait frame was made")

-- 13. An icon whose own art is still loading at the walk goes without the
-- mask while every loaded texture takes it; the frame masks it once its art
-- is in, then stops.
local I = List(false, true, false)
layers[I._frame] = I
I.innerMask.loaded = true
ClipWhenLoaded(I)
check(Masked(I) and Has(I, I.icons[2]), "icon art loading: the loaded textures were not masked")
check(#I.icons[1].masks == 0 and #I.icons[3].masks == 0, "an icon was masked while its own art was loading")
check(Waiting(), "icon art loading: nothing waits for it")
Tick()
check(#I.icons[1].masks == 0 and #I.icons[3].masks == 0 and Waiting(), "still loading: an icon was masked or the wait stopped")
I.icons[3].loaded = true
Tick()
check(Has(I, I.icons[3]) and #I.icons[1].masks == 0 and Waiting(), "one icon's art arrived: it was not masked alone")
I.icons[1].loaded = true
Tick()
check(Has(I, I.icons[1]) and Has(I, I.icons[3]) and not Waiting(), "the last icon's art arrived: it was not masked, or the frame kept running")
Tick()
check(Has(I, I.icons[1]) and Has(I, I.icons[2]) and Has(I, I.icons[3]) and Masked(I), "a later tick or show changed a mask")
-- A loaded list's next show reads each icon once and starts nothing.
local reads = I.icons[1].reads
ClipWhenLoaded(I)
check(I.icons[1].reads == reads + 1 and not Waiting() and Has(I, I.icons[1]), "a loaded list's next show waited or masked twice")

-- 14. A row dressed again with another icon whose art is still loading: the
-- mask an earlier show gave the texture comes off at the next show, and goes
-- back on once the art is in. The other textures keep theirs.
local J = List(true)
layers[J._frame] = J
J.innerMask.loaded = true
ClipWhenLoaded(J)
check(Has(J, J.icons[1]), "a loaded icon was not masked")
J.icons[1].loaded = false
ClipWhenLoaded(J)
check(#J.icons[1].masks == 0 and Masked(J) and Waiting(), "a re-dressed icon kept its mask while its new art loads")
J.icons[1].loaded = true
Tick()
check(Has(J, J.icons[1]) and not Waiting(), "the re-dressed icon's art arrived: it was not masked again")

-- 15. A list closed while an icon waits drops the wait (nothing polls a
-- closed list); its next show walks it again.
local K = List(false)
layers[K._frame] = K
K.innerMask.loaded = true
ClipWhenLoaded(K)
check(Waiting(), "the frame did not wait for the icon")
K._frame.visible = false
reads = K.icons[1].reads
Tick()
check(not Waiting() and #K.icons[1].masks == 0, "a closed list's icon kept the frame running, or was masked")
check(K.icons[1].reads == reads, "a closed list's icon was polled")
K.icons[1].loaded = true
Tick()
check(#K.icons[1].masks == 0, "an icon of a closed list was masked off screen")
K._frame.visible = true
ClipWhenLoaded(K)
check(Has(K, K.icons[1]) and not Waiting(), "the next show of a list closed while its icon waited did not mask it")

-- 16. A layer handed to another build while an icon waits: the wait is dropped.
local N = List(false)
layers[N._frame] = N
N.innerMask.loaded = true
ClipWhenLoaded(N)
layers[N._frame] = nil
N.icons[1].loaded = true
Tick()
check(#N.icons[1].masks == 0 and not Waiting(), "an icon of an earlier build's list was masked")

-- 17. Shown again once the art is in, before the frame ran: masked by that
-- walk, and the frame's own pass adds nothing twice.
local P = List(false)
layers[P._frame] = P
P.innerMask.loaded = true
ClipWhenLoaded(P)
P.icons[1].loaded = true
ClipWhenLoaded(P)
check(Has(P, P.icons[1]), "the second show did not mask the icon whose art had arrived")
Tick()
check(Has(P, P.icons[1]) and not Waiting(), "the frame dropped the mask, or kept running")
check(P.icons[1].dupes == 0, "the frame asked for the mask a second time")

-- 18. The mask's art and an icon's art both loading: the walk waits for the
-- mask, then the icon waits for its own.
local Q = List(false)
layers[Q._frame] = Q
ClipWhenLoaded(Q)
check(Bare(Q) and #Q.icons[1].masks == 0 and Waiting(), "nothing waited for the mask's art")
Q.icons[1].loaded = false
Q.innerMask.loaded = true
Tick()
check(Masked(Q) and #Q.icons[1].masks == 0 and Waiting(), "the mask loaded: the walk masked the loading icon, or stopped waiting")
Q.icons[1].loaded = true
Tick()
check(Has(Q, Q.icons[1]) and not Waiting(), "the icon's art arrived after the mask's: it was not masked")

-- 19. A texture handed to another build's dress while it waits takes the
-- mask under its new dress number, so that build's next walk adds nothing twice.
local S = List(false)
layers[S._frame] = S
S.innerMask.loaded = true
ClipWhenLoaded(S)
S.icons[1].gen = 5
S.icons[1].loaded = true
Tick()
check(Has(S, S.icons[1]) and S.clipped[S.icons[1]] == 5, "the mask was not filed under the texture's dress")
ClipWhenLoaded(S)
check(Has(S, S.icons[1]) and not Waiting(), "the next walk masked the texture a second time")
check(frames == 1, "a second wait frame was made")

if fails > 0 then error(fails .. " check(s) failed") end
print("rounded corners list clip wait harness: ok")
