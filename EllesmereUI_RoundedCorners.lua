if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_RoundedCorners.lua
--
--  Shared rounded corners for bar frames (unit frames, power bars, raid and
--  party cells, swing timer, nameplates). EllesmereUI.RoundCorners(owner,
--  radius, opts):
--    owner         the frame that keeps the state and hosts the body mask;
--                  an ancestor of every body texture
--    radius        0..16, 0 removes everything this owner added
--    opts.style    the border style key; only Solid, Glow and Shadow round
--                  (EllesmereUI.RoundedStyleOK), any other style removes it
--    opts.roots    up to 6 frames whose Texture regions (recursively) form
--                  the body; nil slots are fine
--    opts.textures up to 8 single textures of the body; nil slots are fine
--    opts.border   the frame EllesmereUI.ApplyBorderStyle draws on (optional)
--    opts.clip     a SetClipsChildren frame to switch off while rounded
--    opts.rect     the region whose rect is the rounded shape (default owner)
--
--  Body: a texture takes at most 3 masks, so each body texture gets ONE
--  nine-sliced rounded-rect mask. The mask lives on the owner, outside every
--  clipping frame of the body: a mask on an ancestor masks textures inside
--  SetClipsChildren frames too (the nameplate absorb mask does the same),
--  while a mask hosted INSIDE a clipping frame hides its textures. The bar
--  clip in opts.clip is still switched off (the inset mask does its job).
--  Solid: the body mask sits inside the border strips; the border is a
--  rounded fill in the border color with the body's exact inverse (same
--  nine-slice, same anchors) cut out, so body and border meet without a gap
--  and the fill never sits behind the body. The square strips are masked out.
--  Glow / Shadow: the stock nine-slice glow is faded out and redrawn round:
--  its own edge art along the sides plus generated round corners with the
--  same profile, its peak on the rounded outline.
--
--  Cost: nothing until a radius above 0 is set (no masks, no hook). On: the
--  textures are masked once per settings pass; the recolor hook is a lookup.
-------------------------------------------------------------------------------
if not EllesmereUI then return end

local MEDIA = "Interface\\AddOns\\EllesmereUI\\media\\rounded\\"
local GLOW_EDGE = "Interface\\AddOns\\EllesmereUI\\media\\borders\\glow-border"
local MAX_RADIUS = 16 -- rounded-1.tga .. rounded-16.tga
-- glow-corner-1..16.tga: q = (E/2) / (E/2 + r) from QMIN to QMAX.
local GLOW_QMIN, GLOW_QMAX, GLOW_NQ = 0.25, 0.95, 16

local CORNERS = {
    { k = "tl", p = "TOPLEFT",     tc = { 0, 1, 0, 1 } },
    { k = "tr", p = "TOPRIGHT",    tc = { 1, 0, 0, 1 } },
    { k = "bl", p = "BOTTOMLEFT",  tc = { 0, 1, 1, 0 } },
    { k = "br", p = "BOTTOMRIGHT", tc = { 1, 0, 1, 0 } },
}
local STRIPS = { "_top", "_bottom", "_left", "_right" }
local STYLE_OK = { solid = true, glow = true, shadow = true }

local state = setmetatable({}, { __mode = "k" })       -- owner -> rounding state
local byBorder = setmetatable({}, { __mode = "k" })    -- border frame -> state
local ownTex = setmetatable({}, { __mode = "k" })      -- our pieces, never masked
local hooked = false

EllesmereUI.ROUNDED_MAX_RADIUS = MAX_RADIUS
function EllesmereUI.RoundedStyleOK(style)
    return STYLE_OK[style or "solid"] == true
end

-- Guarded: a texture takes at most 3 masks; a full one stays square.
local function AddMask(tex, m)
    return (pcall(tex.AddMaskTexture, tex, m))
end

local function SetRounded(obj, radius, wrap)
    obj:SetTexture(MEDIA .. "rounded-" .. radius .. ".tga", wrap, wrap)
    obj:SetTextureSliceMargins(radius, radius, radius, radius)
    obj:SetTextureSliceMode(0) -- Stretched
end

-- skip: the border frame (handled apart).
local function CollectTextures(root, out, skip)
    if root == skip then return end
    local regions = { root:GetRegions() }
    for i = 1, #regions do
        local r = regions[i]
        if r:GetObjectType() == "Texture" and not ownTex[r] then out[#out + 1] = r end
    end
    local children = { root:GetChildren() }
    for i = 1, #children do CollectTextures(children[i], out, skip) end
end

-------------------------------------------------------------------------------
--  Body
-------------------------------------------------------------------------------
-- Shape and place a body mask: inside the border strips' inner corners (they
-- follow every re-snap and a scale-decoupled border), else the shape rect.
-- Only while detached: a mask must carry its texture before it is added.
local function ShapeMask(st, m, radius, cont)
    SetRounded(m, radius, "CLAMPTOBLACKADDITIVE")
    m:ClearAllPoints()
    if cont then
        m:SetPoint("TOPLEFT", cont._left, "TOPRIGHT", 0, 0)
        m:SetPoint("BOTTOMRIGHT", cont._right, "BOTTOMLEFT", 0, 0)
    else
        m:SetAllPoints(st.rect)
    end
end

-- A shape change detaches every mask, reshapes it and seats it again.
local function MaskBody(st, roots, singles, radius, cont, skip)
    local key = radius .. (cont and ":in" or ":out")
    if st.key ~= key then
        for tex, m in pairs(st.masked) do tex:RemoveMaskTexture(m) end
        wipe(st.masked)
        if st.mask then ShapeMask(st, st.mask, radius, cont) end
        st.key = key
    end
    local texs = {}
    for i = 1, 6 do -- fixed slots: roots may hold nils
        if roots[i] then CollectTextures(roots[i], texs, skip) end
    end
    for i = 1, 8 do
        if singles[i] then texs[#texs + 1] = singles[i] end
    end
    -- Release textures that left the body (a bar moved out, e.g. detached).
    local current = {}
    for i = 1, #texs do current[texs[i]] = true end
    for tex, m in pairs(st.masked) do
        if not current[tex] then
            tex:RemoveMaskTexture(m)
            st.masked[tex] = nil
        end
    end
    for i = 1, #texs do
        local tex = texs[i]
        if not st.masked[tex] then
            local m = st.mask
            if not m then
                m = st.owner:CreateMaskTexture()
                ShapeMask(st, m, radius, cont)
                st.mask = m
            end
            if AddMask(tex, m) then st.masked[tex] = m end
        end
    end
end

-------------------------------------------------------------------------------
--  Solid: a rounded fill with the body's exact inverse cut out of it
-------------------------------------------------------------------------------
local function SolidOff(st)
    local sd = st.solid
    if not sd or not sd.on then return end
    for _, k in ipairs(STRIPS) do sd.cont[k]:RemoveMaskTexture(sd.hide) end
    sd.fill:Hide()
    sd.on = nil
end

-- radius: outer radius; inner: the body mask's radius (the hole is the same
-- nine-slice shape at the same anchors, so body and border always meet
-- without a gap, whatever size the client draws slice corners at).
local function SolidOn(st, cont, radius, inner)
    local sd = st.solid
    if not sd then
        sd = { cont = cont }
        local fill = cont:CreateTexture(nil, "OVERLAY", nil, 7)
        fill:SetAllPoints(st.rect)
        ownTex[fill] = true
        sd.fill = fill
        local hole = cont:CreateMaskTexture()
        hole:SetPoint("TOPLEFT", cont._left, "TOPRIGHT", 0, 0)
        hole:SetPoint("BOTTOMRIGHT", cont._right, "BOTTOMLEFT", 0, 0)
        sd.hole = hole
        local hide = cont:CreateMaskTexture()
        hide:SetTexture(MEDIA .. "hide.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        hide:SetAllPoints(st.rect)
        sd.hide = hide
        st.solid = sd
    end
    -- The hole is reshaped only while detached (it must carry its texture
    -- before it is added).
    if sd.inner ~= inner then
        if sd.inner then sd.fill:RemoveMaskTexture(sd.hole) end
        sd.hole:SetTexture(MEDIA .. "rounded-inv-" .. inner .. ".tga", "CLAMPTOWHITE", "CLAMPTOWHITE")
        sd.hole:SetTextureSliceMargins(inner, inner, inner, inner)
        sd.hole:SetTextureSliceMode(0)
        AddMask(sd.fill, sd.hole)
        sd.inner = inner
    end
    if not sd.on then
        for _, k in ipairs(STRIPS) do AddMask(cont[k], sd.hide) end
        sd.on = true
    end
    SetRounded(sd.fill, radius)
    sd.fill:SetVertexColor(cont._top:GetVertexColor())
    sd.fill:Show()
end

-------------------------------------------------------------------------------
--  Glow / Shadow: the stock glow redrawn round
-------------------------------------------------------------------------------
local function GlowOff(st)
    local gl = st.glow
    if not gl or not gl.on then return end
    gl.bd:SetAlpha(1)
    gl.frame:Hide()
    gl.on = nil
end

local function GlowOn(st, border, bd, radius)
    local bdInfo = bd.GetBackdrop and bd:GetBackdrop()
    local E = bdInfo and bdInfo.edgeSize
    if not E or E <= 0 then GlowOff(st); return end
    local gl = st.glow
    if not gl then
        local f = CreateFrame("Frame", nil, border)
        f:EnableMouse(false)
        gl = { frame = f, corner = {}, edge = {} }
        for _, c in ipairs(CORNERS) do
            local t = f:CreateTexture(nil, "BORDER")
            t:SetTexCoord(c.tc[1], c.tc[2], c.tc[3], c.tc[4])
            t:SetPoint(c.p, f, c.p, 0, 0)
            ownTex[t] = true
            gl.corner[c.k] = t
        end
        for _, side in ipairs({ "top", "bottom", "left", "right" }) do
            local t = f:CreateTexture(nil, "BORDER")
            t:SetTexture(GLOW_EDGE)
            -- The left edge slice: profile across u, rotated for top/bottom.
            if side == "top" or side == "bottom" then
                t:SetTexCoord(0, 0, 0.125, 0, 0, 1, 0.125, 1)
            else
                t:SetTexCoord(0, 0.125, 0, 1)
            end
            ownTex[t] = true
            gl.edge[side] = t
        end
        st.glow = gl
    end
    local f = gl.frame
    f:ClearAllPoints()
    f:SetAllPoints(bd)
    f:SetFrameLevel(bd:GetFrameLevel())
    -- Corner square: from the glow's outer corner to the arc center.
    local S = E / 2 + radius
    local q = (E / 2) / S
    local n = math.floor((q - GLOW_QMIN) / ((GLOW_QMAX - GLOW_QMIN) / (GLOW_NQ - 1)) + 0.5) + 1
    if n < 1 then n = 1 elseif n > GLOW_NQ then n = GLOW_NQ end
    for _, c in ipairs(CORNERS) do
        local t = gl.corner[c.k]
        t:SetTexture(MEDIA .. "glow-corner-" .. n .. ".tga")
        t:SetSize(S, S)
    end
    local e = gl.edge
    e.top:ClearAllPoints()
    e.top:SetPoint("TOPLEFT", f, "TOPLEFT", S, 0)
    e.top:SetPoint("TOPRIGHT", f, "TOPRIGHT", -S, 0)
    e.top:SetHeight(E)
    e.bottom:ClearAllPoints()
    e.bottom:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", S, 0)
    e.bottom:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -S, 0)
    e.bottom:SetHeight(E)
    e.left:ClearAllPoints()
    e.left:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -S)
    e.left:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, S)
    e.left:SetWidth(E)
    e.right:ClearAllPoints()
    e.right:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -S)
    e.right:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, S)
    e.right:SetWidth(E)
    local r, g, b, a = bd:GetBackdropBorderColor()
    for _, t in pairs(gl.corner) do t:SetVertexColor(r, g, b, a) end
    for _, t in pairs(e) do t:SetVertexColor(r, g, b, a) end
    gl.bd = bd
    bd:SetAlpha(0)
    f:Show()
    gl.on = true
end

-------------------------------------------------------------------------------
local function Clear(st)
    for tex, m in pairs(st.masked) do tex:RemoveMaskTexture(m) end
    wipe(st.masked)
    st.key = nil
    SolidOff(st)
    GlowOff(st)
    if st.border then byBorder[st.border] = nil end
    if st.clip then st.clip:SetClipsChildren(true); st.clip = nil end
end

local function OnBorderColor(borderFrame, r, g, b, a)
    local st = byBorder[borderFrame]
    if not st then return end
    a = a or 1
    local sd = st.solid
    if sd and sd.on then sd.fill:SetVertexColor(r, g, b, a) end
    local gl = st.glow
    if gl and gl.on then
        for _, t in pairs(gl.corner) do t:SetVertexColor(r, g, b, a) end
        for _, t in pairs(gl.edge) do t:SetVertexColor(r, g, b, a) end
    end
end

function EllesmereUI.RoundCorners(owner, radius, opts)
    if not owner then return end
    local st = state[owner]
    radius = math.min(math.floor(tonumber(radius) or 0), MAX_RADIUS)
    if radius > 0 and opts and not STYLE_OK[opts.style or "solid"] then radius = 0 end
    if radius <= 0 then
        if st then Clear(st); state[owner] = nil end
        return
    end
    if not st then
        st = { owner = owner, masked = {} }
        state[owner] = st
    end
    if not hooked then
        hooked = true
        hooksecurefunc(EllesmereUI, "SetBorderStyleColor", OnBorderColor)
    end
    local rect = opts.rect or owner
    if st.rect ~= rect then
        st.rect = rect
        st.key = nil
    end
    local border = opts.border
    if st.border ~= border then
        if st.border then byBorder[st.border] = nil end
        st.border = border
    end
    if border then byBorder[border] = st end

    -- What the border draws now: Solid strips, a glow backdrop, or nothing.
    local cont = border and EllesmereUI.PP.GetBorders(border)
    local edge = cont and cont._top and border:IsShown() and cont:IsShown()
        and cont._top:IsShown() and cont._snapEdge or 0
    local solid = edge > 0
    local bd = border and not solid and EllesmereUI._bdBorderData
        and EllesmereUI._bdBorderData[border]
    local glow = bd and bd:IsShown() and (opts.style == "glow" or opts.style == "shadow")

    -- Solid: the body sits inside the strips; strip width in shape units (the
    -- container may run its own scale).
    local inner = radius
    if solid then
        local cs, rs = cont:GetEffectiveScale(), rect:GetEffectiveScale()
        if rs > 0 then edge = edge * cs / rs end
        inner = math.max(1, math.floor(radius - edge + 0.5))
    end

    local clip = opts.clip
    if clip and st.clip ~= clip then
        if st.clip then st.clip:SetClipsChildren(true) end
        clip:SetClipsChildren(false)
        st.clip = clip
    end

    MaskBody(st, opts.roots or { owner }, opts.textures or {}, inner, solid and cont or nil, border)
    if solid then SolidOn(st, cont, radius, inner) else SolidOff(st) end
    if glow then GlowOn(st, border, bd, radius) else GlowOff(st) end
end
