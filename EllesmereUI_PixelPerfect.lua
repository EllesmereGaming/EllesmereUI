if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_PixelPerfect.lua
--  Pixel perfect system (PP), panel pixel perfect (PanelPP) and the border
--  texture system. Loads before EllesmereUI.lua, which reads PP at load time.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI

local PP

-------------------------------------------------------------------------------
--  Pixel Perfect System
--  Snaps UI elements to exact physical pixel boundaries regardless of UI scale, resolution, or element scale.
--    perfect = 768 / physicalScreenHeight   (1 pixel in WoW's 768-based coord)
--    mult    = perfect / UIParent:GetScale() (1 physical pixel at current scale)
--    Scale(x) snaps any value to the nearest mult boundary.
--  Usage: local PP = EllesmereUI.PP
--    PP.Size/Width/Height/Point, PP.SetInside/SetOutside(obj, anchor, x, y),
--    PP.DisablePixelSnap(texture), PP.Scale(x) -> snapped value
-------------------------------------------------------------------------------
do
    local GetPhysicalScreenSize = GetPhysicalScreenSize
    local InCombatLockdown = InCombatLockdown
    local type = type

    local PP = {}
    EllesmereUI.PP = PP

    ---------------------------------------------------------------------------
    --  Core pixel-perfect values
    ---------------------------------------------------------------------------
    -- perfect = 1 physical pixel in WoW's 768-based coords at scale 1.0. Keep the last known-
    -- good height when GetPhysicalScreenSize() reports 0/nil mid display-mode change (768/0 is infinite, and perfect divides every pixel snap -> NaN sizes suite-wide).
    function PP.RefreshPhysical()
        local pw, ph = GetPhysicalScreenSize()
        if ph and ph > 0 then
            PP.physicalWidth, PP.physicalHeight = pw, ph
        elseif not PP.physicalHeight then
            PP.physicalWidth, PP.physicalHeight = 1920, 1080
        end
        PP.perfect = 768 / PP.physicalHeight
    end
    PP.RefreshPhysical()

    -- mult = 1 physical pixel at current UIParent scale. When UIParent scale ==
    -- perfect, mult == 1 and every integer is pixel-perfect with no snapping.
    PP.mult = PP.perfect / (UIParent and UIParent:GetScale() or 1)

    --- Returns the ideal pixel-perfect scale, clamped to WoW's valid range.
    function PP.PixelBestSize()
        return max(0.4, min(PP.perfect, 1.15))
    end

    --- Recalculate mult after a scale or resolution change.
    function PP.UpdateMult()
        PP.RefreshPhysical()
        local uiScale = EllesmereUIDB and EllesmereUIDB.ppUIScale or PP.PixelBestSize()
        PP.mult = PP.perfect / uiScale
    end

    --- Apply a new UI scale. Stores it, sets UIParent, recalculates mult.
    --- Defers to PLAYER_REGEN_ENABLED if called during combat.
    function PP.SetUIScale(newScale)
        if InCombatLockdown() then
            EllesmereUI.CombatQueue.Defer("SetUIScale", function() PP.SetUIScale(newScale) end)
            return
        end
        if not EllesmereUIDB then EllesmereUIDB = {} end
        local currentScale = UIParent and UIParent:GetScale() or 1
        local scaleChanged = math.abs(currentScale - newScale) > 0.0001
        EllesmereUIDB.ppUIScale = newScale
        UIParent:SetScale(newScale)
        PP.UpdateMult()
        if scaleChanged then
            -- Exact-size borders are pixels at UIParent scale (this path never fires
            -- UI_SCALE_CHANGED, so the watcher below cannot do it).
            if EllesmereUI.ReapplyPxBorders then EllesmereUI.ReapplyPxBorders() end
            -- Re-snap all stored values to the new pixel grid
            if EllesmereUI.SnapProfilePositions then
                local activeName = EllesmereUIDB.activeProfile or "Default"
                local profData = EllesmereUIDB.profiles and EllesmereUIDB.profiles[activeName]
                if profData then EllesmereUI.SnapProfilePositions(profData) end
            end
            if _G._EUF_ReloadFrames then _G._EUF_ReloadFrames() end
            if _G._ERB_Apply then _G._ERB_Apply() end
            if _G._EAB_Apply then _G._EAB_Apply() end
            if _G._ECME_Apply then _G._ECME_Apply() end
            if _G._EDM_Rescale then _G._EDM_Rescale() end
            -- Re-sync width/height matches against the new grid. UIParent:SetScale()
            -- does NOT fire UI_SCALE_CHANGED (that event is CVar-tied), so no listener
            -- catches this path. Debounced: the Options slider calls this repeatedly
            -- while dragged and re-matching on every call never converges.
            if EllesmereUI.ApplyAllWidthHeightMatches then
                if PP._scaleMatchDebounce then PP._scaleMatchDebounce:Cancel() end
                PP._scaleMatchDebounce = C_Timer.NewTimer(0.3, function()
                    PP._scaleMatchDebounce = nil
                    EllesmereUI.ApplyAllWidthHeightMatches()
                end)
            end
        end
    end

    ---------------------------------------------------------------------------
    --  Scale(x) -- snap to the nearest physical-pixel boundary (sizes, positions, offsets).
    --  Divides x into whole-pixel chunks of `mult`, truncating toward zero (positive floors, negative ceils).
    ---------------------------------------------------------------------------
    function PP.Scale(x)
        if x == 0 then return 0 end
        local m = PP.mult
        if m == 1 then return x end
        local pixels = x / m
        -- Epsilon-guarded truncation: pixel-unit slider values sit exactly ON a grid boundary
        -- (px*mult); float dust can land a hair below, dropping a whole pixel at floor. 0.001 px is below any legitimate distance.
        pixels = x > 0 and math.floor(pixels + 0.001) or math.ceil(pixels - 0.001)
        return pixels * m
    end

    --- Snap a value to the nearest physical pixel at UIParent scale.
    --- Convenience wrapper for save paths that don't have a frame reference.
    function PP.Snap(x)
        if x == 0 then return 0 end
        local m = PP.mult
        local result = math.floor(x / m + 0.5) * m
        -- Clean float dust: within 0.001 of an integer, round to it (prevents drift)
        local rounded = math.floor(result + 0.5)
        if math.abs(result - rounded) < 0.001 then result = rounded end
        return result
    end

    --- Coord-space value -> physical pixel count (for display). Epsilon-guarded round (ties up):
    --- a value a hair off a half-pixel boundary (uiScale CVar != 768/screenHeight) must round the same every call/reload or coords flip by 1.
    function PP.ToPixels(coord)
        if coord == 0 then return 0 end
        return math.floor(coord / PP.mult + 0.5 + 0.001)
    end

    --- Convert a physical pixel count to a grid-aligned coord value (for storage).
    function PP.FromPixels(px)
        if px == 0 then return 0 end
        return px * PP.mult
    end

    ---------------------------------------------------------------------------
    --  IsNum(n) -- true for a finite number. WoW Forever's Lua raises an error on a
    --  division by zero or with a NaN or infinite operand (retail yields NaN or inf
    --  quietly), so an engine width/height that is not a real number must never reach
    --  the snaps' divisions. The NaN test is picked once: n == n where NaN compares
    --  normally, else the number's text form (no string built per call otherwise).
    ---------------------------------------------------------------------------
    do
        local huge = math.huge
        local okNaN, nan = pcall(function() return huge - huge end)
        if okNaN and type(nan) == "number" and nan ~= nan then
            function PP.IsNum(n)
                return type(n) == "number" and n == n and n ~= huge and n ~= -huge
            end
        else
            function PP.IsNum(n)
                if type(n) ~= "number" then return false end
                local s = tostring(n)
                return not (s:find("nan", 1, true) or s:find("inf", 1, true))
            end
        end
    end

    ---------------------------------------------------------------------------
    --  SnapForES(x, effectiveScale) -- snap to a whole number of physical pixels at the
    --  given effective scale (border-system approach): onePixel = perfect / es; result =
    --  round(x / onePixel) * onePixel. Guarantees exactly N physical pixels, no sub-pixel drift between siblings.
    --  A value or scale that is not a real number snaps to 0 / scale 1 instead of erroring.
    ---------------------------------------------------------------------------
    function PP.SnapForES(x, es)
        if x == 0 or not PP.IsNum(x) then return 0 end
        if not (PP.IsNum(es) and es > 0) then es = 1 end
        local onePixel = PP.perfect / es
        -- Epsilon-guarded round (ties up): inputs a hair below a half-pixel boundary
        -- (imperfect uiScale CVars) must snap the same way or frames shift 1px per reload.
        local physPixels = math.floor(x / onePixel + 0.5 + 0.001)
        local result = physPixels * onePixel
        local rounded = math.floor(result + 0.5)
        if math.abs(result - rounded) < 0.001 then result = rounded end
        return result
    end

    ---------------------------------------------------------------------------
    --  SnapCenterForDim(value, dim, effectiveScale) -- snap a CENTER coord so both edges land
    --  on physical pixels: EVEN dim -> whole-pixel center; ODD -> half-pixel center (integer +
    --  0.5) so center +/- dim/2 are both whole. THE snap for CENTER/CENTER-stored frames --
    --  plain SnapForES loses the +0.5 for odd dims and drifts 1px on save/exit, profile change, spec swap.
    ---------------------------------------------------------------------------
    function PP.SnapCenterForDim(value, dim, es)
        if value == nil then return value end
        if not PP.IsNum(value) then return 0 end
        es = es or (UIParent and UIParent:GetEffectiveScale() or 1)
        if not (PP.IsNum(es) and es > 0) then es = 1 end
        -- A dim that is not a real number is unknown (the even/whole-pixel path).
        if dim and not PP.IsNum(dim) then dim = nil end
        local onePixel = PP.perfect / es
        local valuePx = value / onePixel
        -- Clean float dust BEFORE any floor: N +/- 1e-9 must not flip which half/whole pixel it
        -- lands on between reloads (visible 1px jump); cleaned, an exact integer takes the +0.5 odd-branch side.
        local vClean = math.floor(valuePx + 0.5)
        if math.abs(valuePx - vClean) < 0.001 then valuePx = vClean end
        local result
        if dim and dim > 0 then
            local dimPx = math.floor(dim / onePixel + 0.5 + 0.001)
            if dimPx % 2 == 1 then
                -- Odd dim: snap center to nearest half-pixel (integer + 0.5)
                result = (math.floor(valuePx) + 0.5) * onePixel
                -- Clean floating point dust (half-pixel values)
                local rounded = math.floor(result) + 0.5
                if math.abs(result - rounded) < 0.001 then result = rounded end
                return result
            end
        end
        -- Even dimension (or unknown): snap center to nearest whole pixel.
        result = math.floor(valuePx + 0.5 + 0.001) * onePixel
        local rounded = math.floor(result + 0.5)
        if math.abs(result - rounded) < 0.001 then result = rounded end
        return result
    end

    ---------------------------------------------------------------------------
    --  CenterToPixels(center, dim, effectiveScale) -- inverse of SnapCenterForDim for LIVE-
    --  geometry readouts/deltas: live CENTER coord (UIParent units) -> stored-convention pixel
    --  value. Odd-dim centers rest on a half pixel (stored N means N+0.5), so subtract it before
    --  rounding, or ToPixels' tie-up maps N+0.5 to N+1 and the delta overshoots a whole pixel (even dims behave like ToPixels).
    ---------------------------------------------------------------------------
    function PP.CenterToPixels(center, dim, es)
        if center == nil or not PP.IsNum(center) then return nil end
        local v = center / PP.mult
        if dim and PP.IsNum(dim) and dim > 0 then
            es = es or (UIParent and UIParent:GetEffectiveScale() or 1)
            if not (PP.IsNum(es) and es > 0) then es = 1 end
            local onePixel = PP.perfect / es
            local dimPx = math.floor(dim / onePixel + 0.5 + 0.001)
            if dimPx % 2 == 1 then v = v - 0.5 end
        end
        return math.floor(v + 0.5 + 0.001)
    end

    ---------------------------------------------------------------------------
    --  Convenience wrappers -- pixel-snapped frame geometry
    ---------------------------------------------------------------------------
    function PP.Size(frame, w, h)
        frame:SetSize(PP.Scale(w), h and PP.Scale(h) or PP.Scale(w))
    end

    function PP.Width(frame, w)
        frame:SetWidth(PP.Scale(w))
    end

    function PP.Height(frame, h)
        frame:SetHeight(PP.Scale(h))
    end

    function PP.Point(obj, anchor, p1, p2, p3, p4)
        if not p1 then p1 = obj:GetParent() end
        if type(p1) == "number" then p1 = PP.Scale(p1) end
        if type(p2) == "number" then p2 = PP.Scale(p2) end
        if type(p3) == "number" then p3 = PP.Scale(p3) end
        if type(p4) == "number" then p4 = PP.Scale(p4) end
        obj:SetPoint(anchor, p1, p2, p3, p4)
    end

    function PP.SetInside(obj, anchor, xOff, yOff)
        anchor = anchor or obj:GetParent()
        local inset = PP.Scale(xOff or 1)
        local insetY = PP.Scale(yOff or 1)
        obj:ClearAllPoints()
        PP.DisablePixelSnap(obj)
        obj:SetPoint("TOPLEFT", anchor, "TOPLEFT", inset, -insetY)
        obj:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -inset, insetY)
    end

    function PP.SetOutside(obj, anchor, xOff, yOff)
        anchor = anchor or obj:GetParent()
        local outset = PP.Scale(xOff or 1)
        local outsetY = PP.Scale(yOff or 1)
        obj:ClearAllPoints()
        PP.DisablePixelSnap(obj)
        obj:SetPoint("TOPLEFT", anchor, "TOPLEFT", -outset, outsetY)
        obj:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", outset, -outsetY)
    end

    ---------------------------------------------------------------------------
    --  DisablePixelSnap -- stop WoW rounding texture coords to the nearest pixel (blurs sub-pixel-sized elements).
    ---------------------------------------------------------------------------
    -- External weak-keyed set: NEVER write custom keys onto Blizzard's secure widget
    -- tables (taints them -> "secret value" errors).
    local _pixelSnapDisabled = setmetatable({}, { __mode = "k" })

    function PP.DisablePixelSnap(obj)
        if not obj then return end
        if issecretvalue and issecretvalue(obj) then return end
        if issecrettable and issecrettable(obj) then return end
        if _pixelSnapDisabled[obj] then return end
        if obj.IsForbidden and obj:IsForbidden() then return end

        -- Textures and FontStrings expose SetSnapToPixelGrid directly
        local target = obj
        if not obj.SetSnapToPixelGrid and obj.GetStatusBarTexture then
            -- StatusBars need their inner texture unsnapped instead
            target = obj:GetStatusBarTexture()
            if type(target) ~= "table" or not target.SetSnapToPixelGrid then
                _pixelSnapDisabled[obj] = true
                return
            end
        end

        if target.SetSnapToPixelGrid then
            target:SetSnapToPixelGrid(false)
            target:SetTexelSnappingBias(0)
        end
        _pixelSnapDisabled[obj] = true
    end

    ---------------------------------------------------------------------------
    --  Global Pixel Snap Prevention -- pixel-snap is a persistent property of each
    --  texture OBJECT: defaults ON at creation, when SetStatusBarTexture mints a new
    --  inner texture, or when foreign code calls SetSnapToPixelGrid(true). Image setters
    --  (SetTexture/SetColorTexture/SetAtlas) do NOT reset snap; tint/UV changes never do.
    --  So hook only: image setters (one-time first-touch disable), SetStatusBarTexture
    --  (fill swaps), and SetSnapToPixelGrid via WatchPixelSnap (re-catch Blizzard
    --  re-enabling). NOT hooked: SetVertexColor/SetTexCoord -- fire constantly (nameplate
    --  recolor churn) yet never blur a texture, so skipping them is the CPU win.
    --  PP.DisablePixelSnap caches into _pixelSnapDisabled (snap C-calls run once each).
    --  INVARIANT: cache keys on the StatusBar OBJECT, so re-calling SetStatusBarTexture
    --  on a cached bar does NOT re-disable snap on the new inner texture -- runtime
    --  bar-fill swaps MUST call PP.DisablePixelSnap on the new GetStatusBarTexture() themselves.
    ---------------------------------------------------------------------------
    local function WatchPixelSnap(frame, snap)
        if issecrettable and issecrettable(frame) then return end
        if (frame and not frame:IsForbidden()) and _pixelSnapDisabled[frame] and snap then
            _pixelSnapDisabled[frame] = nil
        end
    end

    local _hookedMetatables = {}
    local function HookPixelSnap(object)
        local mk = getmetatable(object)
        if not mk then return end
        mk = mk.__index
        if not mk or _hookedMetatables[mk] then return end

        if mk.SetSnapToPixelGrid or mk.SetStatusBarTexture or mk.SetColorTexture
           or mk.SetAtlas or mk.SetTexture then
            -- Rationale in the banner. CreateTexture is NOT hooked: hooksecurefunc
            -- passes the parent frame, not the new texture, so it would be a no-op.
            if mk.SetSnapToPixelGrid then hooksecurefunc(mk, "SetSnapToPixelGrid", WatchPixelSnap) end
            if mk.SetStatusBarTexture then hooksecurefunc(mk, "SetStatusBarTexture", PP.DisablePixelSnap) end
            if mk.SetColorTexture then hooksecurefunc(mk, "SetColorTexture", PP.DisablePixelSnap) end
            if mk.SetAtlas then hooksecurefunc(mk, "SetAtlas", PP.DisablePixelSnap) end
            if mk.SetTexture then hooksecurefunc(mk, "SetTexture", PP.DisablePixelSnap) end
            _hookedMetatables[mk] = true
        end
    end

    -- Hook all known widget types by creating one of each and hooking its metatable
    local hookFrame = CreateFrame("Frame")
    do
        -- Raw ORIGINAL image setters captured BEFORE HookPixelSnap wraps the Texture
        -- metatable. Pooled hot-path textures (nameplate aura slots) snap once at
        -- creation then use these to skip wrapper + guard + cache lookup per swap.
        -- Only legal when the texture had PP.DisablePixelSnap applied once and nothing
        -- can re-enable snap on it afterwards (our own pooled textures qualify).
        local mt = getmetatable(hookFrame:CreateTexture())
        if mt and mt.__index then
            PP.RawSetTexture = mt.__index.SetTexture
            PP.RawSetColorTexture = mt.__index.SetColorTexture
        end
    end
    HookPixelSnap(hookFrame)
    HookPixelSnap(hookFrame:CreateTexture())
    HookPixelSnap(hookFrame:CreateFontString())
    HookPixelSnap(hookFrame:CreateMaskTexture())

    -- No frame-tree enumeration here, deliberately. An EnumerateFrames() walk
    -- used to run at this point "to catch any type we missed": 11,305 frames,
    -- 248 ms of a 419 ms load, and its only new metatable was StatusBar, which
    -- the explicit hook below already covers (measured 2026-09-07, identical in
    -- open world and in a M+ key). It also never saw ItemButton,
    -- ScrollingMessageFrame or AuraContainer, which this suite creates later, so
    -- it was not the net it claimed to be. HookPixelSnap dedupes by metatable,
    -- so every type sharing one hooked here is covered anyway.

    -- Also hook ScrollFrame and StatusBar metatables
    HookPixelSnap(CreateFrame("ScrollFrame"))
    do
        local sb = CreateFrame("StatusBar")
        sb:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        HookPixelSnap(sb)
        local sbt = sb:GetStatusBarTexture()
        if sbt then HookPixelSnap(sbt) end
    end

    ---------------------------------------------------------------------------
    --  UNIFIED BORDER SYSTEM -- the single border API for every EllesmereUI addon. 4 manual
    --  texture strips, each exactly borderSize*mult UI units thick (= borderSize physical
    --  pixels); no BackdropTemplate, no sub-pixel interp. Border data lives in the external
    --  weak-keyed _ppBorderData, NEVER on the frame (taints Blizzard's secure frame tables);
    --  entry = { container, borderSize, borderColor }, container holds _top/_bottom/_left/_right textures.
    --  API:
    --    PP.CreateBorder(frame, r, g, b, a, borderSize, drawLayer, subLevel)
    --    PP.SetBorderSize(frame, borderSize)   PP.SetBorderColor(frame, r, g, b, a)
    --    PP.UpdateBorder(frame, borderSize, r, g, b, a)
    --    PP.HideBorder(frame)   PP.ShowBorder(frame)
    local _ppBorderData = setmetatable({}, { __mode = "k" })
    ---------------------------------------------------------------------------

    local function SnapBorderTextures(container, frame, borderSize)
        if not container.GetEffectiveScale then return end
        local ok, es = pcall(container.GetEffectiveScale, container)
        if not ok or not es then return end
        -- Degenerate PARENT-scale guard, OPT-IN via container._scaleGuard (nameplates, see
        -- PP.CreateBorder): those containers are scale-DECOUPLED so their own es pins to 1
        -- and onePixel cannot explode, but the plate they anchor to hits near-zero scale during
        -- recycle/hide/PEW (SetScale(0.001)) -- snapping against that rect is churn, skip it (the skipped state is re-asserted via ArmPendingSnap below -- do NOT assume some later pass comes on its own, pooled plates get none); UIParent-based borders leave the flag unset.
        if container._scaleGuard then
            local pok, pes = pcall(frame.GetEffectiveScale, frame)
            if pok and pes and pes < 0.1 then
                -- Skipping the snap is right (the rect is collapsed, snapping against it is
                -- churn), but the CALLER'S INTENT MUST NOT BE LOST. A state change that lands
                -- in this window is otherwise dropped for good: the nameplate cast-bar wrap
                -- clears its hidden-bottom seam when the cast ends, which for a dying/despawning
                -- unit happens exactly while the plate is collapsed -- and since plates are
                -- POOLED and the paths that would re-snap on re-use are appearance-generation
                -- cached, the bottom strip then stays hidden for every unit that plate is
                -- recycled onto. Drop the geometry key so the next pass cannot match it as
                -- identical and skip, and arm a one-shot re-snap for when the container is
                -- visible again.
                container._snapEdge = nil
                PP.ArmPendingSnap(container, frame)
                return
            end
        end
        local onePixel = es > 0 and (PP.perfect / es) or PP.mult
        local bs = borderSize or 1
        local edgeSize = bs > 0 and math.max(onePixel, math.floor(bs + 0.5) * onePixel) or 0

        local t, b, l, r = container._top, container._bottom, container._left, container._right
        if not t then return end

        if edgeSize == 0 then
            t:Hide(); b:Hide(); l:Hide(); r:Hide()
            -- Clear the geometry key so the next non-zero pass cannot match a stale one and skip the Show().
            container._snapEdge = nil
            return
        end

        -- Edge suppression for joined bars: flags live on the container so they survive
        -- re-snaps (a one-shot :Hide() is clobbered by the next snap). Hidden top/bottom
        -- edges also drop the matching side-strip inset so stacked borders fuse with no
        -- corner notch.
        local topInset, botInset = -edgeSize, edgeSize
        if container._hideTop then topInset = 0 end
        if container._hideBottom then botInset = 0 end

        -- Geometry is idempotent (~30 frame API calls per invocation, per-aura-per-refresh):
        -- skip when the layout is identical. Compare POST-transform values (edgeSize + both
        -- insets), NEVER borderSize input -- an input-vs-applied guard can't match a non-trivial
        -- transform and re-fires forever. Scale flows through (es -> onePixel -> edgeSize), so an
        -- equal-edgeSize skip is correct (every SetPoint here is anchor-relative, insets-only).
        -- The colour block stays OUTSIDE this guard (textured path zeroes strip alpha; SetVertexColor
        -- restores it); side-strip hidden flags need their own key slots since a left/right-only
        -- flip at unchanged geometry moves no inset and would otherwise be skipped.
        local hideL = container._hideLeft or false
        local hideR = container._hideRight or false
        local geomSame = container._snapEdge == edgeSize
            and container._snapTop == topInset
            and container._snapBot == botInset
            and container._snapHideL == hideL
            and container._snapHideR == hideR
            and container._snapFrame == frame
        if not geomSame then
            container._snapEdge, container._snapTop = edgeSize, topInset
            container._snapBot, container._snapFrame = botInset, frame
            container._snapHideL, container._snapHideR = hideL, hideR

            if container._hideTop then
                t:Hide()
            else
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
                t:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
                t:SetHeight(edgeSize); t:Show()
            end
            if container._hideBottom then
                b:Hide()
            else
                b:ClearAllPoints()
                b:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
                b:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
                b:SetHeight(edgeSize); b:Show()
            end
            if container._hideLeft then
                l:Hide()
            else
                l:ClearAllPoints()
                l:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, topInset)
                l:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, botInset)
                l:SetWidth(edgeSize); l:Show()
            end
            if container._hideRight then
                r:Hide()
            else
                r:ClearAllPoints()
                r:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, topInset)
                r:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, botInset)
                r:SetWidth(edgeSize); r:Show()
            end
        end

        local bc = container._bdColor
        if bc then
            t:SetVertexColor(bc[1], bc[2], bc[3], bc[4])
            b:SetVertexColor(bc[1], bc[2], bc[3], bc[4])
            l:SetVertexColor(bc[1], bc[2], bc[3], bc[4])
            r:SetVertexColor(bc[1], bc[2], bc[3], bc[4])
        end
    end

    --  Deferred re-snap for a guarded container whose snap was swallowed at degenerate parent
    --  scale (rationale at the guard in SnapBorderTextures). OnShow is the trigger because it is
    --  exactly the moment the plate un-collapses, costs nothing while idle, and needs no ticker.
    --  Nothing else scripts OnShow on a border container, so SetScript is safe here; the handler
    --  is shared, NOT a per-container closure (these arm on pooled nameplate borders).
    --  Two further nets catch a container whose OnShow never fires: the cleared _snapEdge means
    --  no later snap can skip it as unchanged, and PP.ResnapAllBorders re-snaps it wholesale.
    function PP._pendingSnapOnShow(container)
        local frame = container._pendingSnap
        if not frame then
            container:SetScript("OnShow", nil)
            return
        end
        local pok, pes = pcall(frame.GetEffectiveScale, frame)
        -- Still collapsed (shown inside a hidden/zero-scale ancestor): stay armed for the next show.
        if not pok or not pes or pes < 0.1 then return end
        container._pendingSnap = nil
        container:SetScript("OnShow", nil)
        local bd = _ppBorderData[frame]
        SnapBorderTextures(container, frame, bd and bd.borderSize or 1)
    end

    function PP.ArmPendingSnap(container, frame)
        if container._pendingSnap then return end
        container._pendingSnap = frame
        container:SetScript("OnShow", PP._pendingSnapOnShow)
    end

    ---------------------------------------------------------------------------
    --  Border registry -- tracks all border containers for centralized re-snap
    --  when UI scale or resolution changes. Avoids per-border OnUpdate overhead.
    ---------------------------------------------------------------------------
    local allBorders = {}
    local allBordersN = 0

    local function RegisterBorder(container, frame)
        allBordersN = allBordersN + 1
        allBorders[allBordersN] = { container = container, frame = frame }
    end

    --- Re-snap every registered border. Called on scale/resolution changes.
    function PP.ResnapAllBorders()
        for i = 1, allBordersN do
            local entry = allBorders[i]
            local c, f = entry.container, entry.frame
            if c and f then
                local bd = _ppBorderData[f]
                local ok = pcall(SnapBorderTextures, c, f, bd and bd.borderSize or 1)
                if not ok then
                    -- Evict only on real failure (dead frame): while auras are secret,
                    -- rect reads in engine aura subtrees are denied but transient.
                    local AKR = EllesmereUI and EllesmereUI.AuraKit
                    if not (AKR and AKR.AurasRestricted and AKR.AurasRestricted()) then
                        entry.container = nil
                        entry.frame = nil
                    end
                end
            end
        end
    end

    --- Re-snap only borders whose parent frame descends from `root`. Tab switch uses
    --- this instead of resnapping 600+ borders when only ~30 on the page need it.
    function PP.ResnapBordersUnder(root)
        if not root then return PP.ResnapAllBorders() end
        local count = 0
        -- Shared method ref for the climb: engine aura buttons deny addon access while
        -- auras are secret. Under pcall a denied step is a chain dead-end = not under
        -- root, which is correct (aura subtrees are never inside the options panel).
        local GetParentFn = root.GetParent
        for i = 1, allBordersN do
            local entry = allBorders[i]
            local f = entry.frame
            if f and entry.container then
                -- Walk up the parent chain (max 10 levels to avoid infinite loops)
                local parent = f
                local found = false
                for _ = 1, 10 do
                    local ok, p = pcall(GetParentFn, parent)
                    if not ok or not p then break end
                    parent = p
                    if parent == root then found = true; break end
                end
                if found then
                    count = count + 1
                    local bd = _ppBorderData[f]
                    local ok = pcall(SnapBorderTextures, entry.container, f, bd and bd.borderSize or 1)
                    if not ok then
                        -- Same transient-vs-dead distinction as ResnapAllBorders.
                        local AKR = EllesmereUI and EllesmereUI.AuraKit
                        if not (AKR and AKR.AurasRestricted and AKR.AurasRestricted()) then
                            entry.container = nil
                            entry.frame = nil
                        end
                    end
                end
            end
        end
    end

    -- scaleGuard (opt-in, nameplate borders): marks a border whose PARENT has a DYNAMIC
    -- effective scale (Scale Target/Casting Nameplate ease plate:SetScale live, recycled
    -- plates snap back to 1, Blizzard rescales base plates). Two effects, flagged borders only:
    --  1. Container is scale-DECOUPLED (SetIgnoreParentScale(true) + SetScale 1): strips render
    --     in fixed scale-1 space while anchors track the plate's live rect, so thickness stays
    --     EXACTLY round(borderSize) physical pixels however the plate scales AFTER the snap.
    --     Otherwise thickness bakes in at snap-time scale and a later DOWN-scale (target lost,
    --     cast ended, mid-ease, recycled from an enlarged unit) leaves sub-1px strips that cover
    --     no pixel center at many sub-pixel positions -- border sides VANISH as the plate slides
    --     with the camera (DisablePixelSnap cannot fix this: it removes snap-to-0, not exact-geometry raster).
    --  2. SnapBorderTextures skips work while the PARENT's effective scale is degenerate (< 0.1,
    --     the SetScale(0.001) hide path). Every other caller leaves scaleGuard nil, unaffected.
    local function DecoupleBorderScale(container)
        if container._scaleDecoupled then return end
        if not container.SetIgnoreParentScale then return end
        container._scaleDecoupled = true
        container:SetIgnoreParentScale(true)
        container:SetScale(1)
    end

    function PP.CreateBorder(frame, r, g, b, a, borderSize, drawLayer, subLevel, scaleGuard)
        local bd = _ppBorderData[frame]
        if bd then
            -- A later call can opt an existing border into the guard. Decoupling changes
            -- the container's coord space, so re-snap now (stored sizes used the old one).
            if scaleGuard and not bd.container._scaleGuard then
                bd.container._scaleGuard = true
                DecoupleBorderScale(bd.container)
                SnapBorderTextures(bd.container, frame, bd.borderSize or 1)
            end
            return bd.container
        end
        r = r or 0; g = g or 0; b = b or 0; a = a or 1
        borderSize = borderSize or 1
        drawLayer = drawLayer or "OVERLAY"
        subLevel = subLevel or 0

        -- 4 strips instead of BackdropTemplate: NineSlice corner sub-frames render as black boxes on nameplates.
        local container = CreateFrame("Frame", nil, frame)
        container:SetAllPoints(frame)
        container:SetFrameLevel(frame:GetFrameLevel() + 1)

        local WHITE = "Interface\\Buttons\\WHITE8X8"
        local function MakeTex()
            local tx = container:CreateTexture(nil, drawLayer, nil, subLevel)
            tx:SetTexture(WHITE)
            -- No pixel-grid snapping: a 1px edge strip must never round to 0 and
            -- VANISH per-side at fractional scales/positions. Our textures, taint-safe.
            PP.DisablePixelSnap(tx)
            return tx
        end
        container._top    = MakeTex()
        container._bottom = MakeTex()
        container._left   = MakeTex()
        container._right  = MakeTex()

        container._bdColor = { r, g, b, a }
        container._scaleGuard = scaleGuard or nil
        if scaleGuard then DecoupleBorderScale(container) end
        bd = { container = container, borderSize = borderSize, borderColor = { r, g, b, a } }
        _ppBorderData[frame] = bd

        SnapBorderTextures(container, frame, borderSize)

        -- Re-snap for 2 frames to catch final effective scale after layout.
        -- The stop is pcall'd: a container under a tooltip that a nameplate owns
        -- inherits its forbidden layout aspect inside these two frames (Snap probes
        -- and returns; a bare SetScript raises). Refused = keep ticking; the stop
        -- lands once the restriction lifts, and a hidden container never ticks.
        local ticks = 0
        container:SetScript("OnUpdate", function(self)
            ticks = ticks + 1
            SnapBorderTextures(self, frame, bd.borderSize or 1)
            if ticks >= 2 then pcall(self.SetScript, self, "OnUpdate", nil) end
        end)

        RegisterBorder(container, frame)

        return container
    end

    function PP.GetBorders(frame)
        local bd = _ppBorderData[frame]
        return bd and bd.container
    end

    function PP.SetBorderSize(frame, borderSize)
        local bd = _ppBorderData[frame]
        if not bd then return end
        borderSize = borderSize or 1
        SnapBorderTextures(bd.container, frame, borderSize)
        bd.borderSize = borderSize
    end

    function PP.SetBorderColor(frame, r, g, b, a)
        local bd = _ppBorderData[frame]
        if not bd then return end
        a = a or 1

        -- Mutated in place, never replaced: called per-aura-per-refresh, and a fresh {r,g,b,a}
        -- table per call was the addon's largest garbage source (1.2 MB/min). container._bdColor
        -- aliases this table, so writes keep both views in sync. SECRET color components
        -- (RaidFrames dispel colors in combat) can be WRITTEN to textures but never compared or
        -- cached (the compare errors on a secret, and caching one breaks the NEXT clean call's
        -- compare too); secrets skip the guard, leave the cache on the last CLEAN color, and mark dirty so the next clean color repaints.
        local col = bd.borderColor
        local secret = issecretvalue
            and (issecretvalue(r) or issecretvalue(g) or issecretvalue(b) or issecretvalue(a))
        if secret then
            bd.colDirty = true
        elseif col then
            if not bd.colDirty
               and col[1] == r and col[2] == g and col[3] == b and col[4] == a then
                return   -- unchanged; the four texture writes below are redundant
            end
            bd.colDirty = nil
            col[1], col[2], col[3], col[4] = r, g, b, a
        else
            col = { r, g, b, a }
            bd.borderColor = col
        end
        if col then bd.container._bdColor = col end

        local c = bd.container
        if c._top then c._top:SetVertexColor(r, g, b, a) end
        if c._bottom then c._bottom:SetVertexColor(r, g, b, a) end
        if c._left then c._left:SetVertexColor(r, g, b, a) end
        if c._right then c._right:SetVertexColor(r, g, b, a) end
    end

    function PP.UpdateBorder(frame, borderSize, r, g, b, a)
        if r then PP.SetBorderColor(frame, r, g, b, a) end
        PP.SetBorderSize(frame, borderSize)
    end

    function PP.HideBorder(frame)
        local bd = _ppBorderData[frame]
        if bd then bd.container:Hide() end
    end

    function PP.ShowBorder(frame)
        local bd = _ppBorderData[frame]
        if bd then bd.container:Show() end
    end

    -- Variable-thickness border ring drawn from a single pre-shaped texture (natively
    -- 7px thick), scaled by (7 - rawBorderSize) and clipped by `mask`. Called with `:`
    -- so self.Point resolves to whichever PP module owns host's frame hierarchy
    -- (world PP vs PanelPP) -- calling with `.` shifts every argument left by one.
    function PP:ApplyMaskedShapeBorder(host, mask, texPath, rawBorderSize, r, g, b, a)
        if not host then return end
        rawBorderSize = rawBorderSize or 0
        if rawBorderSize <= 0 or not texPath then
            if host._shapeBorderShown then
                host._shapeBorderTex:Hide()
                host._shapeBorderShown = nil
            end
            return
        end
        r, g, b, a = r or 0, g or 0, b or 0, a or 1
        -- Every field guarded: callers invoke this on every restyle pass regardless
        -- of whether the border changed, and Remove/AddMaskTexture aren't cheap.
        if host._shapeBorderShown and host._sbTex == texPath and host._sbSize == rawBorderSize
            and host._sbMask == mask and host._sbR == r and host._sbG == g
            and host._sbB == b and host._sbA == a then
            return
        end
        if not host._shapeBorderTex then
            host._shapeBorderTex = host:CreateTexture(nil, "OVERLAY")
            local t = host._shapeBorderTex
            if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
        end
        local tex = host._shapeBorderTex
        local bExp = 7 - math.min(rawBorderSize, 7)
        tex:ClearAllPoints()
        self.Point(tex, "TOPLEFT", host, "TOPLEFT", -bExp, bExp)
        self.Point(tex, "BOTTOMRIGHT", host, "BOTTOMRIGHT", bExp, -bExp)
        if mask then
            pcall(tex.RemoveMaskTexture, tex, mask)
            pcall(tex.AddMaskTexture, tex, mask)
        end
        tex:SetTexture(texPath)
        tex:SetVertexColor(r, g, b, a)
        tex:Show()
        host._sbTex, host._sbSize, host._sbMask, host._sbR, host._sbG, host._sbB, host._sbA =
            texPath, rawBorderSize, mask, r, g, b, a
        host._shapeBorderShown = true
    end

    -- Callers switching away from a shaped border (to the plain-line border, or off
    -- entirely) must hide _shapeBorderTex through this, not a raw :Hide() -- the guard
    -- above trusts _shapeBorderShown, so an external hide it doesn't know about leaves
    -- a later ApplyMaskedShapeBorder call with the exact same args wrongly skipping
    -- its own Show().
    function PP:HideMaskedShapeBorder(host)
        if host and host._shapeBorderShown then
            host._shapeBorderTex:Hide()
            host._shapeBorderShown = nil
        end
    end

    ---------------------------------------------------------------------------
    --  Scale change watcher
    ---------------------------------------------------------------------------
    local scaleWatcher = CreateFrame("Frame")
    scaleWatcher:RegisterEvent("UI_SCALE_CHANGED")
    scaleWatcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
    scaleWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    scaleWatcher:SetScript("OnEvent", function(_, event)
        if event == "DISPLAY_SIZE_CHANGED" then
            -- Resolution changed -- recalculate perfect and re-apply scale
            PP.RefreshPhysical()
            -- Only auto-update if user explicitly opted into auto scale
            if EllesmereUIDB and EllesmereUIDB.ppUIScaleAuto == true then
                PP.SetUIScale(PP.PixelBestSize())
            else
                PP.UpdateMult()
            end
        else
            PP.UpdateMult()
        end
        PP.ResnapAllBorders()
        if EllesmereUI.ReapplyPxBorders then EllesmereUI.ReapplyPxBorders() end
        -- Re-sync panel scale after loading screens / resolution / UI scale changes
        local mf = EllesmereUI._mainFrame
        if mf and mf:IsShown() then
            local physW = (GetPhysicalScreenSize())
            local sw = GetScreenWidth()
            if physW and physW > 0 and sw and sw > 0 then
                local baseScale = sw / physW
                local userScale = (EllesmereUIDB and EllesmereUIDB.panelScale) or 1.0
                mf:SetScale(baseScale * userScale)
                if EllesmereUI.PanelPP then EllesmereUI.PanelPP.UpdateMult() end
            end
        end
    end)
end

-- File-level PP reference for code outside the do block
PP = EllesmereUI.PP
-------------------------------------------------------------------------------
--  Panel Pixel Perfect (PanelPP) -- the options panel runs at effective scale = baseScale *
--  userScale. At userScale 1.0, 1 unit = 1 physical pixel (integer rounding suffices); otherwise PanelPP computes its own mult (1 physical pixel in panel units) and snaps to that grid.
-------------------------------------------------------------------------------
do
    local PanelPP = {}
    EllesmereUI.PanelPP = PanelPP

    local floor, type = math.floor, type

    -- mult = 1 physical pixel in panel units (1.0 at userScale 1.0, ~0.9901 at
    -- 1.01); recalculated by UpdateMult() when the panel scale changes.
    PanelPP.mult = 1

    function PanelPP.UpdateMult()
        local userScale = (EllesmereUIDB and EllesmereUIDB.panelScale) or 1.0
        if userScale == 0 then userScale = 1 end
        -- 1 physical pixel = 1/userScale panel units
        PanelPP.mult = 1 / userScale
    end

    -- Snap a value to the nearest physical pixel boundary in panel coords
    function PanelPP.Scale(x)
        if x == 0 then return 0 end
        local m = PanelPP.mult
        if m == 1 then return floor(x + 0.5) end
        -- Same snapping algorithm as PP.Scale
        local y = m > 1 and m or -m
        return x - x % (x < 0 and y or -y)
    end

    function PanelPP.Size(frame, w, h)
        local sw = PanelPP.Scale(w)
        frame:SetSize(sw, h and PanelPP.Scale(h) or sw)
    end

    function PanelPP.Width(frame, w)
        frame:SetWidth(PanelPP.Scale(w))
    end

    function PanelPP.Height(frame, h)
        frame:SetHeight(PanelPP.Scale(h))
    end

    function PanelPP.Point(obj, arg1, arg2, arg3, arg4, arg5)
        if not arg2 then arg2 = obj:GetParent() end
        if type(arg2) == "number" then arg2 = PanelPP.Scale(arg2) end
        if type(arg3) == "number" then arg3 = PanelPP.Scale(arg3) end
        if type(arg4) == "number" then arg4 = PanelPP.Scale(arg4) end
        if type(arg5) == "number" then arg5 = PanelPP.Scale(arg5) end
        obj:SetPoint(arg1, arg2, arg3, arg4, arg5)
    end

    function PanelPP.SetInside(obj, anchor, xOff, yOff)
        if not anchor then anchor = obj:GetParent() end
        local x = PanelPP.Scale(xOff or 1)
        local y = PanelPP.Scale(yOff or 1)
        obj:ClearAllPoints()
        PanelPP.DisablePixelSnap(obj)
        obj:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, -y)
        obj:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -x, y)
    end

    function PanelPP.SetOutside(obj, anchor, xOff, yOff)
        if not anchor then anchor = obj:GetParent() end
        local x = PanelPP.Scale(xOff or 1)
        local y = PanelPP.Scale(yOff or 1)
        obj:ClearAllPoints()
        PanelPP.DisablePixelSnap(obj)
        obj:SetPoint("TOPLEFT", anchor, "TOPLEFT", -x, y)
        obj:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", x, -y)
    end

    -- DisablePixelSnap is scale-independent -- just reuse PP's version
    PanelPP.DisablePixelSnap = PP.DisablePixelSnap

    -- Panel borders delegate to the unified PP border system
    PanelPP.CreateBorder  = PP.CreateBorder
    PanelPP.GetBorders    = PP.GetBorders
    PanelPP.SetBorderSize = PP.SetBorderSize
    PanelPP.SetBorderColor = PP.SetBorderColor
    PanelPP.UpdateBorder  = PP.UpdateBorder
    PanelPP.HideBorder    = PP.HideBorder
    PanelPP.ShowBorder    = PP.ShowBorder
    PanelPP.ApplyMaskedShapeBorder = PP.ApplyMaskedShapeBorder
    PanelPP.HideMaskedShapeBorder = PP.HideMaskedShapeBorder
end

-- File-level PanelPP reference for panel layout code outside the do block
local PanelPP = EllesmereUI.PanelPP

-------------------------------------------------------------------------------
--  BORDER TEXTURE SYSTEM -- extends PP borders with BackdropTemplate textured borders.
--  borderTexture = "solid" (default) uses the PP 4-strip system unchanged; any other
--  key creates a BackdropTemplate child with the resolved edge texture, hiding the strips.
--  API:
--    EllesmereUI.GetBorderTextureList()       -- sorted {key,name} array
--    EllesmereUI.GetBorderTextureDropdown()    -- values + order for W:DualRow
--    EllesmereUI.ResolveBorderTexture(key)     -- key -> edgeFile path (nil for solid)
--    EllesmereUI.ApplyBorderStyle(frame, sz, r,g,b,a, textureKey)
--    EllesmereUI.SetBorderStyleColor(frame, r,g,b,a)
-------------------------------------------------------------------------------
do
    local _bdBorderData = setmetatable({}, { __mode = "k" })
    EllesmereUI._bdBorderData = _bdBorderData

    --- Returns usable, width, height.
    --- usable = false means EVERY widget call on this frame raises from our (always tainted)
    --- code: Enum.ForbiddenAspect.UntrustedLayoutScriptExecution propagates to a forbidden
    --- frame's children AND to anything ANCHORED to it, so a border we hung off a Blizzard
    --- frame inherits it the moment that frame anchors to a forbidden one (Blizzard UI
    --- widgets do exactly that to the tooltip they own, on hover). The size READ raises
    --- too, so pcall is the only way to ask.
    --- usable with no width = the size is SECRET: the frame is fine to touch, only the
    --- backdrop's texcoord arithmetic is not (map-pin tooltips, menus with secret text, and
    --- every frame anchored to secret aura geometry, which uses the solid path on purpose).
    local function ReadBorderSize(frame)
        local ok, w, h = pcall(frame.GetSize, frame)
        if not ok then return false end
        if issecretvalue and (issecretvalue(w) or issecretvalue(h)) then return true end
        return true, w, h
    end

    -- Per-addon border defaults registry, keyed by texture key. Each texture entry:
    --   defaultSize: size key auto-set when this texture is selected
    --   sizes: keyed by size key (addon-specific), each with offsetX, offsetY,
    --     shiftX, shiftY (all default to 0 if omitted)
    -- Register: EllesmereUI.RegisterBorderDefaults(addonKey, table);
    -- read: EllesmereUI.GetBorderDefaults(addonKey, textureKey, sizeKey).
    local _borderDefaults = {}

    function EllesmereUI.RegisterBorderDefaults(addonKey, defaults)
        _borderDefaults[addonKey] = defaults
    end

    --- Get per-addon border defaults for a texture+size combo.
    --- Returns offsetX, offsetY, shiftX, shiftY (all 0 if not registered).
    function EllesmereUI.GetBorderDefaults(addonKey, textureKey, sizeKey)
        if textureKey == "shadow" then textureKey = "glow" end  -- Shadow shares Glow's defaults
        local addon = _borderDefaults[addonKey]
        if not addon then return 0, 0, 0, 0 end
        local tex = addon[textureKey]
        if not tex or not tex.sizes then return 0, 0, 0, 0 end
        local s = tex.sizes[sizeKey]
        if not s then return 0, 0, 0, 0 end
        return s.offsetX or 0, s.offsetY or 0, s.shiftX or 0, s.shiftY or 0
    end

    --- Get the default size key for a texture in a specific addon: the addon's
    --- registry row, then the built-in entry's defaultSize, then 1 for SharedMedia.
    --- Returns nil if none applies (caller keeps current size).
    function EllesmereUI.GetBorderDefaultSize(addonKey, textureKey)
        if textureKey == "shadow" then textureKey = "glow" end  -- Shadow shares Glow's defaults
        local addon = _borderDefaults[addonKey]
        local tex = addon and addon[textureKey]
        if tex and tex.defaultSize then return tex.defaultSize end
        -- Then a built-in style's own default step (a number; label modules convert it).
        -- Only the Pixels entries carry one, so every other built-in answers nil as before.
        for _, entry in ipairs(EllesmereUI._builtinBorderTextures) do
            if entry.key == textureKey then return entry.defaultSize end
        end
        -- Any SharedMedia border ("sm:<name>") defaults to size 1 unless registered above
        -- (shared, applies to every consumer). Called only from a dropdown setValue, never load/apply, so stored sizes stay untouched until picked.
        if type(textureKey) == "string" and textureKey:sub(1, 3) == "sm:" then return 1 end
        return nil
    end

    -- Border defaults tables shared by modules with the same size keys and
    -- tuning. Read-only: modules pass them to RegisterBorderDefaults as is.
    do
        local function AllSizes(ox, oy, sx, sy)
            local t = {}
            for k = 0, 4 do t[k] = { offsetX = ox, offsetY = oy, shiftX = sx, shiftY = sy } end
            return t
        end
        EllesmereUI.BORDER_DEFAULTS_BARS = {
            ["glow"] = {
                defaultSize = 1,
                sizes = AllSizes(0, 0, 0, 0),
            },
            ["blizz"] = {
                defaultSize = 3,
                sizes = {
                    [0] = { offsetX = 0, offsetY = 0, shiftX = 0, shiftY = 0 },
                    [1] = { offsetX = 2, offsetY = 1, shiftX = 0, shiftY = 0 },
                    [2] = { offsetX = 3, offsetY = 2, shiftX = 1, shiftY = 0 },
                    [3] = { offsetX = 4, offsetY = 2, shiftX = 1, shiftY = 0 },
                    [4] = { offsetX = 4, offsetY = 2, shiftX = 1, shiftY = 0 },
                },
            },
            ["dialog"] = {
                defaultSize = 1,
                sizes = {
                    [0] = { offsetX = 0, offsetY = 0, shiftX = 0, shiftY = 0 },
                    [1] = { offsetX = 3, offsetY = 3, shiftX = 0, shiftY = 0 },
                    [2] = { offsetX = 3, offsetY = 5, shiftX = 0, shiftY = 0 },
                    [3] = { offsetX = 3, offsetY = 5, shiftX = 0, shiftY = 0 },
                    [4] = { offsetX = 5, offsetY = 10, shiftX = 0, shiftY = 0 },
                },
            },
            ["sm:Blizzard Achievement Wood"] = {
                defaultSize = 1,
                sizes = {
                    [0] = { offsetX = 0, offsetY = 0, shiftX = 0, shiftY = 0 },
                    [1] = { offsetX = 1, offsetY = 1, shiftX = 0, shiftY = 0 },
                    [2] = { offsetX = 1, offsetY = 1, shiftX = 0, shiftY = 0 },
                    [3] = { offsetX = 1, offsetY = 6, shiftX = 0, shiftY = 0 },
                    [4] = { offsetX = 1, offsetY = 8, shiftX = 0, shiftY = 0 },
                },
            },
        }
    end
    do
        local ALL_SIZES = { "none", "thin", "normal", "heavy", "strong" }
        local function AllSizes(ox, oy, sx, sy)
            local t = {}
            for _, k in ipairs(ALL_SIZES) do t[k] = { offsetX = ox, offsetY = oy, shiftX = sx, shiftY = sy } end
            return t
        end
        EllesmereUI.BORDER_DEFAULTS_BUTTONS = {
            ["glow"] = {
                defaultSize = "normal",
                sizes = AllSizes(0, 0, 0, 0),
            },
            ["blizz"] = {
                defaultSize = "heavy",
                sizes = {
                    none   = { offsetX = 0, offsetY = 0, shiftX = 0, shiftY = 0 },
                    thin   = { offsetX = 2, offsetY = 1, shiftX = 0, shiftY = 0 },
                    normal = { offsetX = 3, offsetY = 2, shiftX = 0, shiftY = 0 },
                    heavy  = { offsetX = 4, offsetY = 2, shiftX = 1, shiftY = 0 },
                    strong = { offsetX = 4, offsetY = 2, shiftX = 2, shiftY = 0 },
                },
            },
            ["dialog"] = {
                defaultSize = "normal",
                sizes = AllSizes(4, 4, 0, 0),
            },
            ["sm:Blizzard Achievement Wood"] = {
                defaultSize = "thin",
                sizes = AllSizes(1, 1, 0, 0),
            },
        }
    end
    do
        local ALL_SIZES = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true }
        local function AllSizes(ox, oy, sx, sy)
            local t = {}
            for k in pairs(ALL_SIZES) do t[k] = { offsetX = ox, offsetY = oy, shiftX = sx, shiftY = sy } end
            return t
        end
        EllesmereUI.BORDER_DEFAULTS_FRAMES = {
            ["glow"] = {
                defaultSize = 1,
                sizes = AllSizes(0, 0, 0, 0),
            },
            ["blizz"] = {
                defaultSize = 4,
                sizes = {
                    [0] = { offsetX = 0, offsetY = 0, shiftX = 0, shiftY = 0 },
                    [1] = { offsetX = 2, offsetY = 1, shiftX = 0, shiftY = 0 },
                    [2] = { offsetX = 3, offsetY = 1, shiftX = 1, shiftY = 0 },
                    [3] = { offsetX = 4, offsetY = 2, shiftX = 2, shiftY = 0 },
                    [4] = { offsetX = 5, offsetY = 3, shiftX = 2, shiftY = 0 },
                },
            },
            ["dialog"] = {
                defaultSize = 2,
                sizes = {
                    [0] = { offsetX = 0, offsetY = 0, shiftX = 0, shiftY = 0 },
                    [1] = { offsetX = 2, offsetY = 2, shiftX = 0, shiftY = 0 },
                    [2] = { offsetX = 2, offsetY = 2, shiftX = 0, shiftY = 0 },
                    [3] = { offsetX = 4, offsetY = 4, shiftX = 0, shiftY = 0 },
                    [4] = { offsetX = 8, offsetY = 8, shiftX = 0, shiftY = 0 },
                },
            },
            ["sm:Blizzard Achievement Wood"] = {
                defaultSize = 1,
                sizes = AllSizes(1, 1, 0, 0),
            },
        }
    end

    -- Icon/portrait shape art (read-only). Code that applies masks stays per module.
    -- pixelsCircle = the circle mask with the Pixels ring art; its ring draws
    -- outside the mask, which the consumer handles (Unit Frames portraits only).
    local SHAPE_MEDIA = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\"
    EllesmereUI.SHAPE_MASKS = {
        circle   = SHAPE_MEDIA .. "circle_mask.tga",
        csquare  = SHAPE_MEDIA .. "csquare_mask.tga",
        diamond  = SHAPE_MEDIA .. "diamond_mask.tga",
        hexagon  = SHAPE_MEDIA .. "hexagon_mask.tga",
        pixelsCircle = SHAPE_MEDIA .. "circle_mask.tga",
        portrait = SHAPE_MEDIA .. "portrait_mask.tga",
        shield   = SHAPE_MEDIA .. "shield_mask.tga",
        square   = SHAPE_MEDIA .. "square_mask.tga",
    }
    EllesmereUI.SHAPE_BORDERS = {
        circle   = SHAPE_MEDIA .. "circle_border.tga",
        csquare  = SHAPE_MEDIA .. "csquare_border.tga",
        diamond  = SHAPE_MEDIA .. "diamond_border.tga",
        hexagon  = SHAPE_MEDIA .. "hexagon_border.tga",
        pixelsCircle = SHAPE_MEDIA .. "pixels_circle_border.tga",
        portrait = SHAPE_MEDIA .. "portrait_border.tga",
        shield   = SHAPE_MEDIA .. "shield_border.tga",
        square   = SHAPE_MEDIA .. "square_border.tga",
    }
    -- Top pixel inset from a 128px mask's edge to its visible opening.
    EllesmereUI.SHAPE_INSETS = {
        circle = 17, csquare = 17, diamond = 14,
        hexagon = 17, pixelsCircle = 17, portrait = 17, shield = 13, square = 17,
    }

    -- Built-in border textures (always available, no SharedMedia). defaultOffset = outward extension from the content edge, tuned per-texture (internal padding differs).
    EllesmereUI._builtinBorderTextures = {
        { key = "solid",   name = "Solid" },
        { key = "glow",    name = "Glow",            path = "Interface\\AddOns\\EllesmereUI\\media\\borders\\glow-border",  defaultOffset = 0, defaultOffsetY = 0, scaleOffset = true, defaultThickness = "normal" },
        -- Shadow = the Glow texture drawn behind the frame in black; aliases to glow in default lookups, "behind + black" applied by GetBorderStyleSelectDefaults.
        { key = "shadow",  name = "Shadow",          path = "Interface\\AddOns\\EllesmereUI\\media\\borders\\glow-border",  defaultOffset = 0, defaultOffsetY = 0, scaleOffset = true, defaultThickness = "normal" },
        { key = "blizz",   name = "Blizzard",        path = "Interface\\AddOns\\EllesmereUI\\media\\borders\\blizz-border", defaultOffset = 3, defaultOffsetY = 2, scaleOffset = true, defaultThickness = "heavy" },
        { key = "lightspark", name = "Lightspark Border", path = "Interface\\AddOns\\EllesmereUI\\media\\borders\\lightspark-border", defaultOffset = 0, defaultOffsetY = 0, scaleOffset = true, defaultThickness = "normal" },
        { key = "dialog",  name = "Blizzard Dialog",  path = "Interface\\DialogFrame\\UI-DialogBox-Border",                 defaultOffset = 4, defaultOffsetY = 4, defaultThickness = "normal" },
        -- Pixels: white art that keeps its shading, so the border colour tints the face
        -- and the outline stays dark; a pick seeds selectColor (GetBorderSelectColor).
        -- Pixels Textured has its colours baked in and picks white like the others.
        -- Both centre on the frame edge (scaleOffset), land on step 2 when picked
        -- (defaultSize, read by GetBorderDefaultSize) and carry companion art read
        -- through GetBorderCompanion: sepH / sepV = separator strip / divider files,
        -- sepSize = strip thickness against the step-2 edge of 16, ring / ringShadow =
        -- portrait rings. Never give these keys a RegisterBorderDefaults row: a
        -- registry size would win over defaultSize, and its offsets add to edge/2.
        { key = "pixels", name = "Pixels", path = "Interface\\AddOns\\EllesmereUI\\media\\borders\\pixels",
          defaultOffset = 0, defaultOffsetY = 0, scaleOffset = true, defaultThickness = "normal", defaultSize = 2,
          selectColor = { r = 0.57, g = 0.57, b = 0.57 },
          sepH = "Interface\\AddOns\\EllesmereUI\\media\\borders\\pixels-sep.tga",
          sepV = "Interface\\AddOns\\EllesmereUI\\media\\borders\\pixels-vsep.tga",
          sepSize = 16,
          ring = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\pixels_ring.tga",
          ringShadow = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\pixels_ring_shadow.tga" },
        { key = "pixels-textured", name = "Pixels Textured", path = "Interface\\AddOns\\EllesmereUI\\media\\borders\\pixels-textured",
          defaultOffset = 0, defaultOffsetY = 0, scaleOffset = true, defaultThickness = "normal", defaultSize = 2,
          sepH = "Interface\\AddOns\\EllesmereUI\\media\\borders\\pixels-textured-sep.tga",
          sepV = "Interface\\AddOns\\EllesmereUI\\media\\borders\\pixels-textured-vsep.tga",
          sepSize = 16,
          ring = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\pixels_ring_textured.tga",
          ringShadow = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\pixels_ring_textured_shadow.tga" },
    }

    --- A border style's companion art, or nil for a style without it (every style
    --- but the Pixels ones). role: "sepH" (horizontal separator strip), "sepV"
    --- (vertical divider), "ring" / "ringShadow" (portrait ring, plain / shadowed)
    --- = file paths; "sepSize" = the strip's thickness against the step-2 edge of 16
    --- (draw it at sepSize x edge / 16). "separatorH" / "separatorV" / "separatorSize"
    --- are accepted as the long spellings. Tint every piece with the host's live border
    --- colour. Read at style-apply time only, never on a colour-only path or per frame.
    function EllesmereUI.GetBorderCompanion(textureKey, role)
        if not textureKey or textureKey == "" or textureKey == "solid" then return nil end
        if role == "separatorH" then role = "sepH"
        elseif role == "separatorV" then role = "sepV"
        elseif role == "separatorSize" then role = "sepSize" end
        for _, entry in ipairs(EllesmereUI._builtinBorderTextures) do
            if entry.key == textureKey then
                if role == "sepH" or role == "sepV" or role == "sepSize" or role == "ring" or role == "ringShadow" then
                    return entry[role]
                end
                return nil
            end
        end
        return nil
    end
    local DEFAULT_LSM_OFFSET = 0

    --- Build a sorted list of border texture entries for dropdown widgets.
    function EllesmereUI.GetBorderTextureList()
        local list = {}
        local seen = {}
        for _, entry in ipairs(EllesmereUI._builtinBorderTextures) do
            list[#list + 1] = { key = entry.key, name = entry.name }
            seen[entry.name] = true
        end
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        if LSM then
            local smBorders = LSM:HashTable("border")
            if smBorders then
                local LSM_BLACKLIST = {
                    ["Blizzard Tooltip"] = true,
                    ["Blizzard Chat Bubble"] = true,
                    ["Blizzard Dialog Gold"] = true,
                    ["Blizzard Party"] = true,
                    ["None"] = true,
                }
                local sorted = {}
                for name in pairs(smBorders) do
                    if not seen[name] and not LSM_BLACKLIST[name] then
                        sorted[#sorted + 1] = name
                    end
                end
                table.sort(sorted)
                local LSM_RENAME = {
                    ["Blizzard Achievement Wood"] = "Blizzard Wood",
                }
                for _, name in ipairs(sorted) do
                    list[#list + 1] = { key = "sm:" .. name, name = LSM_RENAME[name] or name }
                end
            end
        end
        return list
    end

    --- Build dropdown values/order tables from the texture list.
    function EllesmereUI.GetBorderTextureDropdown()
        local texList = EllesmereUI.GetBorderTextureList()
        local values, order = {}, {}
        for _, entry in ipairs(texList) do
            values[entry.key] = entry.name
            order[#order + 1] = entry.key
        end
        return values, order
    end

    -- Per-LSM-texture defaults (keyed by original LSM name)
    local LSM_DEFAULT_OFFSETS = {
        ["Blizzard Achievement Wood"] = { x = 1, y = 1, thickness = "thin" },
    }

    --- Get the default border thickness for a texture key.
    function EllesmereUI.GetBorderTextureDefaultThickness(key)
        if not key or key == "" or key == "solid" then return nil end
        for _, entry in ipairs(EllesmereUI._builtinBorderTextures) do
            if entry.key == key then return entry.defaultThickness end
        end
        local smName = key:match("^sm:(.+)")
        if smName and LSM_DEFAULT_OFFSETS[smName] then return LSM_DEFAULT_OFFSETS[smName].thickness end
        return nil
    end

    --- Get the default X offset for a border texture key.
    function EllesmereUI.GetBorderTextureDefaultOffset(key)
        if not key or key == "" or key == "solid" then return 0 end
        for _, entry in ipairs(EllesmereUI._builtinBorderTextures) do
            if entry.key == key then return entry.defaultOffset or DEFAULT_LSM_OFFSET end
        end
        local smName = key:match("^sm:(.+)")
        if smName and LSM_DEFAULT_OFFSETS[smName] then return LSM_DEFAULT_OFFSETS[smName].x end
        return DEFAULT_LSM_OFFSET
    end

    --- Get the default Y offset for a border texture key.
    function EllesmereUI.GetBorderTextureDefaultOffsetY(key)
        if not key or key == "" or key == "solid" then return 0 end
        for _, entry in ipairs(EllesmereUI._builtinBorderTextures) do
            if entry.key == key then return entry.defaultOffsetY or entry.defaultOffset or DEFAULT_LSM_OFFSET end
        end
        local smName = key:match("^sm:(.+)")
        if smName and LSM_DEFAULT_OFFSETS[smName] then return LSM_DEFAULT_OFFSETS[smName].y end
        return DEFAULT_LSM_OFFSET
    end

    -- Textured border edgeSize per size step (1-4).
    local EDGE_MAP = { 12, 16, 24, 32 }
    EllesmereUI.BORDER_EDGE_MAP = EDGE_MAP
    -- The None..Strong labels some modules store, as steps, and back.
    EllesmereUI.BORDER_STEP_OF_LABEL = { none = 0, thin = 1, normal = 2, heavy = 3, strong = 4 }
    EllesmereUI.BORDER_LABEL_OF_STEP = { [0] = "none", "thin", "normal", "heavy", "strong" }

    -- PRECISE BORDER SIZE. A surface's legacy size key keeps its meaning (solid:
    -- physical px; textured: a step into EDGE_MAP). Its companion key, the legacy
    -- key's name plus "Px", holds an exact size as the string "<px>|<step>|<tex>":
    -- px = whole pixels at UIParent scale (the unit every EUI pixel slider
    -- uses), step = the legacy step it was written beside, tex = the texture then.
    -- The value counts only while the surface's legacy step and texture still
    -- equal that pair, so anything that knows only the legacy key (an older
    -- build, a legacy sync icon, a spec override that captured only the legacy
    -- key, a style pick) wins by itself. false = a cleared value that still
    -- travels through mirror sync (nil would be left behind). Absent from every
    -- defaults table: an untouched profile takes the legacy path unchanged.
    -- One local: this block sits inside the main chunk near its local cap.
    local _px = {
        num = {}, step = {}, tex = {},                        -- parse memo by value string
        borders = setmetatable({}, { __mode = "k" }),        -- borderFrame -> true (backdrop path)
        secret = setmetatable({}, { __mode = "k" }),         -- borderFrame -> state (8-slice path)
        owners = setmetatable({}, { __mode = "k" }),         -- owner -> fn (RegisterPxReapply)
    }

    --- px, step, tex of a *Px value; nil for nil / false / anything else.
    function EllesmereUI.BorderPxParts(value)
        if type(value) ~= "string" then return nil end
        local px = _px.num[value]
        if px == nil then
            local p, s, t = value:match("^(%d+)|(%d+)|(.*)$")
            if not p then
                _px.num[value] = false
                return nil
            end
            px = tonumber(p)
            _px.num[value], _px.step[value], _px.tex[value] = px, tonumber(s), t
        end
        if px == false then return nil end
        return px, _px.step[value], _px.tex[value]
    end

    --- The exact size a surface renders with, or nil for the legacy path: value =
    --- its *Px key, step = the legacy step it renders with (a number), textureKey
    --- = its texture key (nil / "" = solid).
    function EllesmereUI.BorderPx(value, step, textureKey)
        if not value then return nil end
        local px, s, t = EllesmereUI.BorderPxParts(value)
        if not px or px <= 0 or s ~= step then return nil end
        if not textureKey or textureKey == "" then textureKey = "solid" end
        if t ~= textureKey then return nil end
        return px
    end

    function EllesmereUI.BorderPxString(px, step, textureKey)
        if not textureKey or textureKey == "" then textureKey = "solid" end
        return string.format("%d|%d|%s", px, step, textureKey)
    end

    --- The legacy step nearest an exact size: solid = the px themselves (capped
    --- at 4); textured = the EDGE_MAP step nearest px in UIParent units.
    function EllesmereUI.BorderPxStep(px, textureKey)
        if not textureKey or textureKey == "" or textureKey == "solid" then
            return math.min(4, math.max(0, math.floor(px + 0.5)))
        end
        local units = px * (EllesmereUI.PP and EllesmereUI.PP.mult or 1)
        local best, bestD = 1, math.huge
        for i = 1, #EDGE_MAP do
            local d = math.abs(EDGE_MAP[i] - units)
            if d < bestD then best, bestD = i, d end
        end
        return best
    end

    --- The pixels a surface shows today with no *Px value: solid = the step;
    --- textured = its EDGE_MAP edge at UIParent scale (0 = hidden, an
    --- out-of-range step = the 12 it renders, as the legacy path does).
    function EllesmereUI.BorderLegacyPx(step, textureKey)
        if not textureKey or textureKey == "" or textureKey == "solid" then
            return math.max(0, math.floor((step or 0) + 0.5))
        end
        if not step or step <= 0 then return 0 end
        local units = EDGE_MAP[step] or EDGE_MAP[1]
        return math.floor(units / (EllesmereUI.PP and EllesmereUI.PP.mult or 1) + 0.5)
    end

    --- The thickness a border style's separator strip / divider draws at beside a host
    --- border: sepSize x edge / 16 (GetBorderCompanion), edge = the host's drawn edge
    --- (edgePx = its exact size from EllesmereUI.BorderPx, else EDGE_MAP[step]), in UI
    --- units snapped to whole pixels at es (the host's effective scale, nil = UIParent's).
    --- ratio = the host border's normalizeScale factor (UIParent scale / es), nil = 1.
    --- nil when the style has no separator or the host border is off (step 0, no edgePx).
    function EllesmereUI.BorderCompanionThickness(textureKey, step, edgePx, es, ratio)
        local sepSize = EllesmereUI.GetBorderCompanion(textureKey, "sepSize")
        if not sepSize then return nil end
        local PP = EllesmereUI.PP
        local edge
        if edgePx then
            edge = math.max(1, math.floor(edgePx + 0.5)) * PP.mult
        elseif step and step > 0 then
            edge = EDGE_MAP[step] or EDGE_MAP[1]
        else
            return nil
        end
        if not (es and es > 0.01) then es = UIParent and UIParent:GetEffectiveScale() or 1 end
        return PP.SnapForES(sepSize * edge * (ratio or 1) / 16, es)
    end

    --- Places a border style's vertical divider art (GetBorderCompanion "sepV") on tex, a
    --- texture we own, along a vertical edge of anchor at its full height, as wide as
    --- BorderCompanionThickness(textureKey, step, edgePx, es) (es = the scale tex draws
    --- at). The art's line lies 2 / sepSize of that width in from its lead side, and the
    --- lead crosses the edge by that much. right = the lead side is right of the edge (the
    --- art mirrored), else left. over = the edge is anchor's side away from the lead, so
    --- the lead overlaps anchor; else it is anchor's side toward the lead and the lead
    --- hangs past anchor. Hides tex when the style has no divider or its border is off.
    --- The caller tints tex. Settings and UI-scale re-layout passes only.
    function EllesmereUI.PlaceBorderDividerV(tex, anchor, right, over, textureKey, step, edgePx, es)
        local thick = EllesmereUI.BorderCompanionThickness(textureKey, step, edgePx, es)
        if not thick or thick <= 0 then tex:Hide(); return end
        local PP = EllesmereUI.PP
        local lead = PP.SnapForES(thick * 2 / EllesmereUI.GetBorderCompanion(textureKey, "sepSize"), es)
        tex:SetTexture(EllesmereUI.GetBorderCompanion(textureKey, "sepV"))
        tex:ClearAllPoints()
        if right then
            tex:SetTexCoord(1, 0, 0, 1)
            tex:SetPoint("TOPRIGHT", anchor, over and "TOPLEFT" or "TOPRIGHT", lead, 0)
            tex:SetPoint("BOTTOMRIGHT", anchor, over and "BOTTOMLEFT" or "BOTTOMRIGHT", lead, 0)
        else
            tex:SetTexCoord(0, 1, 0, 1)
            tex:SetPoint("TOPLEFT", anchor, over and "TOPRIGHT" or "TOPLEFT", -lead, 0)
            tex:SetPoint("BOTTOMLEFT", anchor, over and "BOTTOMRIGHT" or "BOTTOMLEFT", -lead, 0)
        end
        tex:SetWidth(thick)
        tex:Show()
    end

    --- Check if a border texture uses scaled offset (edgeSize/2 base).
    function EllesmereUI.BorderTextureUsesScaleOffset(key)
        if not key or key == "" or key == "solid" then return false end
        for _, entry in ipairs(EllesmereUI._builtinBorderTextures) do
            if entry.key == key then return entry.scaleOffset == true end
        end
        return false
    end

    --- The colour a pick of this border style seeds, as a FRESH table (callers store
    --- it in the profile), or nil for a style without one (only Pixels has one).
    --- Setters that hard-code their own pick colour write this one when it answers.
    function EllesmereUI.GetBorderSelectColor(textureKey)
        if not textureKey or textureKey == "" or textureKey == "solid" then return nil end
        for _, entry in ipairs(EllesmereUI._builtinBorderTextures) do
            if entry.key == textureKey then
                local c = entry.selectColor
                if c then return { r = c.r, g = c.g, b = c.b } end
                return nil
            end
        end
        return nil
    end

    --- Border color + layer defaults to apply when a border style is selected (Shadow is the
    --- only style rendered behind both its icon and Unit Frame). Returns (colorTable, behindBool, behindUnitFrameBool).
    --- colorTable is always a fresh table: the style's select colour, else white (textured) or black.
    function EllesmereUI.GetBorderStyleSelectDefaults(textureKey)
        if textureKey == "shadow" then return { r = 0, g = 0, b = 0 }, true, true end
        if not textureKey or textureKey == "" or textureKey == "solid" then
            return { r = 0, g = 0, b = 0 }, false, false
        end
        return EllesmereUI.GetBorderSelectColor(textureKey) or { r = 1, g = 1, b = 1 }, false, false
    end

    --- Resolve a border texture key to a file path; nil for "solid" (use PP system).
    function EllesmereUI.ResolveBorderTexture(key)
        if not key or key == "" or key == "solid" then return nil end
        for _, entry in ipairs(EllesmereUI._builtinBorderTextures) do
            if entry.key == key then return entry.path end
        end
        local smName = key:match("^sm:(.+)")
        if smName then
            local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
            if LSM then
                local path = LSM:Fetch("border", smName)
                if path and path ~= "" then return path end
            end
        end
        if key:find("\\") or key:find("/") then return key end
        return nil
    end

    --- Apply border style to a border frame, managing PP vs BackdropTemplate.
    --- borderFrame must be a frame we own (not a Blizzard frame).
    --- size: border thickness in PP pixels (solid) or mapped to edgeSize (textured).
    --- textureKey: "solid"/nil for PP, anything else for BackdropTemplate.
    --- offsetOverride/offsetYOverride: optional user override (nil = use per-addon or global default).
    --- shiftX/shiftY: optional user override (nil = use per-addon default or 0).
    --- addonKey/sizeKey: optional per-addon registry lookup key pair for defaults.
    --- normalizeScale: opt-in, textured only. Cancels the frame's scale chain below UIParent
    ---   so the border matches an unscaled frame's. Pass ONLY where that scale is an
    ---   implementation detail the caller already cancels elsewhere (CDM cancels Blizzard's
    ---   per-icon scale for icon size, iS = 1/iconScale, but not its border). NEVER where the
    ---   scale is user intent (nameplate target/cast scale, buff-bar position scale): those
    ---   borders scale with the frame, and ratio is sampled once at style time so a later change would bake in a transient value.
    --- edgePx: the surface's exact size from EllesmereUI.BorderPx, or nil for the legacy
    ---   path (byte-identical to before it existed). Solid: the px themselves. Textured: the
    ---   edge is edgePx whole pixels at UIParent scale in this frame's units (still through
    ---   ratio); the registry offsets/shifts of `size`'s step scale with the edge.
    function EllesmereUI.ApplyBorderStyle(borderFrame, size, r, g, b, a, textureKey, offsetOverride, offsetYOverride, shiftX, shiftY, addonKey, sizeKey, normalizeScale, edgePx)
        local PP = EllesmereUI.PP
        if not PP or not borderFrame then return end
        a = a or 1
        -- Probe before the first widget call: a restyle can land while the owner is anchored
        -- to a forbidden frame (tooltips on UI-widget hover), and then anchoring, frame level
        -- and color would each raise in turn. Skipping leaves the last-good border; the next apply, off that anchor, restyles normally.
        if not ReadBorderSize(borderFrame) then return end

        local isSolid = not textureKey or textureKey == "" or textureKey == "solid"

        if isSolid then
            local bdFrame = _bdBorderData[borderFrame]
            if bdFrame then bdFrame:Hide() end
            if bdFrame and bdFrame._pxEdge then bdFrame._pxEdge = nil; _px.borders[borderFrame] = nil end
            local sz = edgePx or size
            -- PP system
            if sz > 0 then
                if PP.GetBorders(borderFrame) then
                    PP.UpdateBorder(borderFrame, sz, r, g, b, a)
                    PP.ShowBorder(borderFrame)
                    -- No SetAlpha "restore" after textured-mode zeroing: on Textures SetAlpha
                    -- writes the SAME state as SetVertexColor's 4th arg, so the color write above
                    -- restores it; a hardcoded SetAlpha(1) would stomp every fractional border alpha on re-apply.
                else
                    PP.CreateBorder(borderFrame, r, g, b, a, sz, "OVERLAY", 7)
                end
                borderFrame:Show()
            else
                if PP.GetBorders(borderFrame) then PP.HideBorder(borderFrame) end
                borderFrame:Hide()
            end
        else
            -- Textured border via BackdropTemplate
            local texPath = EllesmereUI.ResolveBorderTexture(textureKey)
            if not texPath or size <= 0 then
                local bdFrame = _bdBorderData[borderFrame]
                if bdFrame then bdFrame:Hide() end
                -- A hidden border must not come back from the UI-scale re-apply.
                if bdFrame and bdFrame._pxEdge then bdFrame._pxEdge = nil; _px.borders[borderFrame] = nil end
                if PP.GetBorders(borderFrame) then PP.HideBorder(borderFrame) end
                if size <= 0 then borderFrame:Hide() end
                return
            end
            -- Hide PP borders and zero their alpha so they can't flash
            if PP.GetBorders(borderFrame) then
                PP.HideBorder(borderFrame)
                local ppC = PP.GetBorders(borderFrame)
                if ppC then
                    if ppC._top then ppC._top:SetAlpha(0) end
                    if ppC._bottom then ppC._bottom:SetAlpha(0) end
                    if ppC._left then ppC._left:SetAlpha(0) end
                    if ppC._right then ppC._right:SetAlpha(0) end
                end
            end
            local bdFrame = _bdBorderData[borderFrame]
            if not bdFrame then
                bdFrame = CreateFrame("Frame", nil, borderFrame, "BackdropTemplate")
                bdFrame:EnableMouse(false)
                -- Addon-born frame: its scripts always run tainted. When the owner rides a
                -- Blizzard frame sized from secret content (map-pin tooltips, menus with secret
                -- text), GetWidth() hands the template's resize recompute a SECRET number and its
                -- texcoord math throws; a forbidden layout aspect inherited from the owner's
                -- anchor makes the read itself throw (see ReadBorderSize). Skip the recompute
                -- either way (edges keep last-good texcoords and stretch, same as the throwing path left them, minus the per-resize error).
                bdFrame:SetScript("OnSizeChanged", function(self)
                    local usable, w = ReadBorderSize(self)
                    if not usable or not w then return end
                    self:OnBackdropSizeChanged()
                end)
                _bdBorderData[borderFrame] = bdFrame
            end
            bdFrame:SetFrameLevel(borderFrame:GetFrameLevel())
            -- edgeSize is in local units: SetBackdrop renders edgeSize x effectiveScale, so a
            -- scaled frame draws a proportionally scaled border (correct by default, hence
            -- opt-in). uiES/es = 1/(scale chain below UIParent), so ratio is 1 for an unscaled
            -- frame at any resolution or UI scale; the 0.01 floor keeps a degenerate scale from exploding it.
            local ratio = 1
            if normalizeScale then
                local eok, es = pcall(bdFrame.GetEffectiveScale, bdFrame)
                local uiES = UIParent and UIParent:GetEffectiveScale() or 1
                if eok and es and es > 0.01 and uiES > 0 then ratio = uiES / es end
            end
            local edgeSize
            if edgePx then
                edgeSize = math.max(1, math.floor(edgePx + 0.5)) * PP.mult * ratio
            else
                edgeSize = (EDGE_MAP[size] or EDGE_MAP[1]) * ratio
            end
            -- Resolve offset/shift defaults: per-addon registry first, then global fallback.
            local dox, doy, dsx, dsy
            if addonKey and sizeKey then
                dox, doy, dsx, dsy = EllesmereUI.GetBorderDefaults(addonKey, textureKey, sizeKey)
            else
                dox = EllesmereUI.GetBorderTextureDefaultOffset(textureKey)
                doy = EllesmereUI.GetBorderTextureDefaultOffsetY(textureKey)
                dsx, dsy = 0, 0
            end
            if edgePx then
                -- The step's defaults follow the exact edge (the user's own offsets stay).
                local f = (edgePx * PP.mult) / (EDGE_MAP[size] or EDGE_MAP[1])
                dox, doy, dsx, dsy = PP.Snap(dox * f), PP.Snap(doy * f), PP.Snap(dsx * f), PP.Snap(dsy * f)
            end
            local adjX = offsetOverride or dox
            local adjY = offsetYOverride or doy
            local sx   = shiftX or dsx
            local sy   = shiftY or dsy
            -- Same factor as edgeSize, or a normalized edge would be positioned by offsets still in the frame's scaled units.
            adjX, adjY = adjX * ratio, adjY * ratio
            sx, sy = sx * ratio, sy * ratio
            -- scaleOffset textures: base = edgeSize/2 (border tracks the edge at any size) plus fine-tune adj; other textures: absolute offset, no base.
            -- EllesmereUI.BorderReach mirrors this placement for size matching: change the two together.
            local offsetX, offsetY
            if EllesmereUI.BorderTextureUsesScaleOffset(textureKey) then
                offsetX = (edgeSize / 2) + adjX
                offsetY = (edgeSize / 2) + adjY
            else
                offsetX = adjX
                offsetY = adjY
            end
            -- Snap the four anchor offsets to whole physical pixels at the backdrop's own
            -- scale. Offset/shift are units, and at any UI scale where a unit is not a whole
            -- pixel (1.75 px/unit: 2 units = 3.5 px) the backdrop's edges land between pixels;
            -- a rect on half pixels is rasterised with the top-left fill rule, so the top and
            -- left edges read one pixel thicker than the bottom and right. The owner is
            -- already on the grid (PP.Point/PP.Size); this keeps the border there with it.
            local sok, ses = pcall(bdFrame.GetEffectiveScale, bdFrame)
            if not (sok and ses and ses > 0.01) then ses = UIParent and UIParent:GetEffectiveScale() or 1 end
            -- Snap the offset once and mirror it (not each corner: round-half-up would put
            -- -3.5 at -3 and +3.5 at +4, one pixel more on the right/top than the left/bottom).
            offsetX, offsetY = PP.SnapForES(offsetX, ses), PP.SnapForES(offsetY, ses)
            sx, sy = PP.SnapForES(sx, ses), PP.SnapForES(sy, ses)
            bdFrame:ClearAllPoints()
            bdFrame:SetPoint("TOPLEFT", borderFrame, "TOPLEFT", -offsetX + sx, offsetY + sy)
            bdFrame:SetPoint("BOTTOMRIGHT", borderFrame, "BOTTOMRIGHT", offsetX + sx, -offsetY + sy)
            -- SetBackdrop re-runs the nine-slice texcoord math, dividing by THIS frame's current
            -- width/height, and owners' sizes can be secret (map-pin tooltips); the upstream
            -- owner-width guard can pass while this anchored rect resolves secret, so the guard
            -- must sit here. Unchanged style (tooltips re-skin every Show) skips the template; a
            -- real style change under a secret size keeps the last-good backdrop and retries next apply (the color write below is vertex-only and always safe).
            local bdKey = texPath .. "@" .. edgeSize
            if bdFrame._euiBdKey ~= bdKey then
                local bdUsable, bdW = ReadBorderSize(bdFrame)
                if not bdUsable or not bdW then
                    bdFrame._euiBdKey = nil
                else
                    bdFrame:SetBackdrop({
                        edgeFile = texPath,
                        edgeSize = edgeSize,
                        insets = { left = 0, right = 0, top = 0, bottom = 0 },
                    })
                    bdFrame._euiBdKey = bdKey
                end
            end
            bdFrame:SetBackdropBorderColor(r, g, b, a)
            bdFrame:Show()
            borderFrame:Show()
            -- An exact edge is pixels at UIParent scale, so a UI scale change must re-apply
            -- it (the legacy edge is UI units and needs nothing): keep the call's arguments
            -- on our backdrop frame (scalars, no table per apply) for ReapplyPxBorders.
            if edgePx then
                bdFrame._pxEdge, bdFrame._pxSize = edgePx, size
                bdFrame._pxR, bdFrame._pxG, bdFrame._pxB, bdFrame._pxA = r, g, b, a
                bdFrame._pxTex, bdFrame._pxOffX, bdFrame._pxOffY = textureKey, offsetOverride, offsetYOverride
                bdFrame._pxShX, bdFrame._pxShY = shiftX, shiftY
                bdFrame._pxAddon, bdFrame._pxSizeKey, bdFrame._pxNorm = addonKey, sizeKey, normalizeScale
                _px.borders[borderFrame] = true
                _px.mult = PP.mult
            elseif bdFrame._pxEdge then
                bdFrame._pxEdge = nil
                _px.borders[borderFrame] = nil
            end
        end
    end

    -- Where the line a player sees starts inside a built-in texture's edge cell, as
    -- a fraction of the cell from its outer edge (left, right, top, bottom; the
    -- first texel at alpha 64+, measured from the media files). A texture with no
    -- entry (Blizzard Dialog, SharedMedia) counts from the cell's outer edge.
    -- Value = (that texel - 2) / 28: the backdrop samples texels 2-29 of each 32-texel
    -- cell. Pixels: texel 12 on all four sides (10/28); Pixels Textured: texel 11 (9/28).
    EllesmereUI._borderInk = {
        blizz      = { 0.5,   0.607, 0.5,   0.5   },
        glow       = { 0.357, 0.357, 0.357, 0.357 },
        lightspark = { 0.071, 0.071, 0.071, 0.071 },
        pixels     = { 0.357, 0.357, 0.357, 0.357 },
        ["pixels-textured"] = { 0.321, 0.321, 0.321, 0.321 },
    }

    --- How far a textured border's visible line reaches OUTSIDE its frame, per side
    --- (l, r, t, b; negative = inside), in that frame's units, from ApplyBorderStyle's
    --- own arguments (ratio = its normalizeScale factor, nil = 1; alpha = the border
    --- color's alpha; es = the border owner's effective scale, nil = UIParent's / ratio,
    --- which is right for every owner without its own scale). Mirrors ApplyBorderStyle's
    --- placement, pixel snap included: change the two together.
    --- nil when nothing is drawn outside: solid (PP strips sit inside the frame),
    --- shadow (a shadow is not the frame's edge), size 0, no texture, alpha 0.
    --- Reads settings only, never a frame.
    function EllesmereUI.BorderReach(size, tex, offX, offY, shX, shY, addonKey, sizeKey, edgePx, ratio, alpha, es)
        if not size or size <= 0 or not tex or tex == "" or tex == "solid" or tex == "shadow" then return nil end
        if alpha and alpha <= 0 then return nil end
        if not EllesmereUI.ResolveBorderTexture(tex) then return nil end
        local PP = EllesmereUI.PP
        ratio = ratio or 1
        local edge
        if edgePx then
            edge = math.max(1, math.floor(edgePx + 0.5)) * PP.mult * ratio
        else
            edge = (EDGE_MAP[size] or EDGE_MAP[1]) * ratio
        end
        local dox, doy, dsx, dsy
        if addonKey and sizeKey then
            dox, doy, dsx, dsy = EllesmereUI.GetBorderDefaults(addonKey, tex, sizeKey)
        else
            dox = EllesmereUI.GetBorderTextureDefaultOffset(tex)
            doy = EllesmereUI.GetBorderTextureDefaultOffsetY(tex)
            dsx, dsy = 0, 0
        end
        if edgePx then
            local f = (edgePx * PP.mult) / (EDGE_MAP[size] or EDGE_MAP[1])
            dox, doy, dsx, dsy = PP.Snap(dox * f), PP.Snap(doy * f), PP.Snap(dsx * f), PP.Snap(dsy * f)
        end
        local ox, oy = (offX or dox) * ratio, (offY or doy) * ratio
        local sx, sy = (shX or dsx) * ratio, (shY or dsy) * ratio
        if EllesmereUI.BorderTextureUsesScaleOffset(tex) then
            ox, oy = edge / 2 + ox, edge / 2 + oy
        end
        -- ApplyBorderStyle puts the backdrop's anchors on whole pixels at its own
        -- effective scale; the reach snaps the same four values the same way (the
        -- ink below stays fractional: it is texture content, not an anchor).
        if not (es and es > 0.01) then
            es = (UIParent and UIParent:GetEffectiveScale() or 1) / ratio
        end
        ox, oy = PP.SnapForES(ox, es), PP.SnapForES(oy, es)
        sx, sy = PP.SnapForES(sx, es), PP.SnapForES(sy, es)
        local ink = EllesmereUI._borderInk[tex]
        local il, ir, it, ib = 0, 0, 0, 0
        if ink then il, ir, it, ib = ink[1] * edge, ink[2] * edge, ink[3] * edge, ink[4] * edge end
        return ox - sx - il, ox + sx - ir, oy + sy - it, oy - sy - ib
    end

    --- The width and height a textured border adds OUTSIDE its frame (each side
    --- clamped at 0, both sides summed) for an unlock element's getMatchPad; nil when
    --- it adds none. Same arguments as BorderReach. The anchors are snapped as
    --- ApplyBorderStyle snaps them; the match engine still snaps the sum once.
    function EllesmereUI.BorderMatchPad(size, tex, offX, offY, shX, shY, addonKey, sizeKey, edgePx, ratio, alpha, es)
        local l, r, t, b = EllesmereUI.BorderReach(size, tex, offX, offY, shX, shY, addonKey, sizeKey, edgePx, ratio, alpha, es)
        if not l then return nil end
        local w = (l > 0 and l or 0) + (r > 0 and r or 0)
        local h = (t > 0 and t or 0) + (b > 0 and b or 0)
        if w <= 0 and h <= 0 then return nil end
        return w, h
    end

    --- Re-applies every border drawn from an exact size after a UI scale change (its edge
    --- and offsets are pixels at UIParent scale). Nothing to do while no surface uses one,
    --- and nothing while the pixel grid (PP.mult) is the one the borders were applied at:
    --- the scale watcher also fires at every loading screen. A frame torn down since
    --- (no parent: a rebuilt options preview) or a border its owner hid itself (every
    --- apply shows it, so a hidden one was hidden on purpose) is dropped instead of
    --- re-applied; the owner's next apply registers it again. A frame that cannot be
    --- touched right now (ReadBorderSize) is kept for its owner's next restyle. The
    --- owner's frame level, live border colour and hidden state survive the re-apply
    --- (an owner hidden with its border still set keeps its px current for its next Show).
    function EllesmereUI.ReapplyPxBorders()
        local m = EllesmereUI.PP.mult
        if _px.mult == m then return end
        for bf in pairs(_px.borders) do
            local bd = _bdBorderData[bf]
            if ReadBorderSize(bf) then
                if not (bf:GetParent() and bd and bd._pxEdge and bd:IsShown()) then
                    if bd then bd._pxEdge = nil end
                    _px.borders[bf] = nil
                else
                    local lvl = bd:GetFrameLevel()
                    local cr, cg, cb, ca = bd:GetBackdropBorderColor()
                    local wasShown = bf:IsShown()
                    EllesmereUI.ApplyBorderStyle(bf, bd._pxSize, bd._pxR, bd._pxG, bd._pxB, bd._pxA,
                        bd._pxTex, bd._pxOffX, bd._pxOffY, bd._pxShX, bd._pxShY,
                        bd._pxAddon, bd._pxSizeKey, bd._pxNorm, bd._pxEdge)
                    -- The apply shows its owner: one its owner hid stays hidden (IsShown: a Show denied in combat needs no Hide).
                    if not wasShown and bf:IsShown() then bf:Hide() end
                    bd:SetFrameLevel(lvl)
                    if cr then bd:SetBackdropBorderColor(cr, cg, cb, ca) end
                end
            end
        end
        for bf, st in pairs(_px.secret) do
            if ReadBorderSize(bf) then
                local edges = st._secretBorderEdges
                if not (bf:GetParent() and st._pxsbEdge and edges and edges.topLeft:IsShown()) then
                    st._pxsbEdge = nil
                    _px.secret[bf] = nil
                else
                    EllesmereUI.ApplySecretSafeBorderStyle(bf, st, st._pxsbSize, st._pxsbR, st._pxsbG,
                        st._pxsbB, st._pxsbA, st._pxsbTex, st._pxsbOffX, st._pxsbOffY, st._pxsbShX,
                        st._pxsbShY, st._pxsbAddon, st._pxsbSizeKey, st._pxsbScale, st._pxsbEdge)
                end
            end
        end
        -- Art sized from an exact border px but drawn outside the two border calls
        -- (companion strips, dividers, rings) re-derives through its owner's fn.
        if next(_px.owners) then
            for owner, fn in pairs(_px.owners) do fn(owner) end
        end
        _px.mult = m
    end

    --- Registers fn(owner) for ReapplyPxBorders, which calls it after the host borders
    --- re-apply, only when the pixel grid (PP.mult) has moved. For art sized from an
    --- exact border px but drawn outside ApplyBorderStyle / ApplySecretSafeBorderStyle
    --- (companion strips, dividers, rings): the UI-scale watcher runs no module restyle.
    --- fn = nil unregisters. Register only while such a piece is shown and unregister
    --- when it goes or its style leaves the exact size. Pass one stable function per
    --- owner (a repeat call replaces it, no closure per apply). fn re-sizes only that
    --- owner's own art, and must not register a NEW owner while it runs. Weak-keyed.
    function EllesmereUI.RegisterPxReapply(owner, fn)
        if not owner then return end
        _px.owners[owner] = fn
        -- Stamp the grid the art was sized on, as an exact border apply does, so the
        -- loading-screen pass that follows (same grid) runs nothing.
        if fn then _px.mult = EllesmereUI.PP.mult end
    end

    -- BackdropTemplate does arithmetic on its owner's width/height, so it is unusable for
    -- frames anchored to secret aura geometry. This variant draws the same eight edge-file
    -- slices manually, keeping the PP path for Solid; `state` is any caller-owned table
    -- caching the eight textures (FFD, AuraKit button data). edgeScale is preview-only
    -- geometry compensation; live callers leave it nil.
    local SECRET_BORDER_UV = {
        topLeft     = { 0.5078125, 0.0625, 0.5078125, 0.9375, 0.6171875, 0.0625, 0.6171875, 0.9375 },
        topRight    = { 0.6328125, 0.0625, 0.6328125, 0.9375, 0.7421875, 0.0625, 0.7421875, 0.9375 },
        bottomLeft  = { 0.7578125, 0.0625, 0.7578125, 0.9375, 0.8671875, 0.0625, 0.8671875, 0.9375 },
        bottomRight = { 0.8828125, 0.0625, 0.8828125, 0.9375, 0.9921875, 0.0625, 0.9921875, 0.9375 },
        top         = { 0.2578125, 0.9375, 0.3671875, 0.9375, 0.2578125, 0.0625, 0.3671875, 0.0625 },
        bottom      = { 0.3828125, 0.9375, 0.4921875, 0.9375, 0.3828125, 0.0625, 0.4921875, 0.0625 },
        left        = { 0.0078125, 0.0625, 0.0078125, 0.9375, 0.1171875, 0.0625, 0.1171875, 0.9375 },
        right       = { 0.1328125, 0.0625, 0.1328125, 0.9375, 0.2421875, 0.0625, 0.2421875, 0.9375 },
    }
    -- Read-only: other eight-slice sets cut from the same edge art (AuraKit's textured
    -- dispel ring) write these texcoords once at creation.
    EllesmereUI.SECRET_BORDER_UV = SECRET_BORDER_UV

    --- edgePx: as ApplyBorderStyle's (the exact size, else the legacy EDGE_MAP path).
    function EllesmereUI.ApplySecretSafeBorderStyle(borderFrame, state, size, r, g, b, a,
        textureKey, offsetX, offsetY, shiftX, shiftY, addonKey, sizeKey, edgeScale, edgePx)
        if not borderFrame or not state then return end
        size, textureKey = size or 0, textureKey or "solid"
        local edges = state._secretBorderEdges
        -- Inlined, not a local closure: runs per-aura-per-refresh, and a closure built on entry (before the early-outs below) is pure garbage on the common path.
        if textureKey == "" or textureKey == "solid" or size <= 0 then
            if edges then for _, tex in pairs(edges) do tex:Hide() end end
            if state._pxsbEdge then state._pxsbEdge = nil; _px.secret[borderFrame] = nil end
            EllesmereUI.ApplyBorderStyle(borderFrame, size, r, g, b, a, "solid",
                nil, nil, nil, nil, nil, nil, nil, edgePx)
            return
        end
        local path = EllesmereUI.ResolveBorderTexture(textureKey)
        if not path then
            if edges then for _, tex in pairs(edges) do tex:Hide() end end
            if state._pxsbEdge then state._pxsbEdge = nil; _px.secret[borderFrame] = nil end
            EllesmereUI.ApplyBorderStyle(borderFrame, 0, 0, 0, 0, 0, "solid")
            return
        end
        -- Also hides any BackdropTemplate child already on this frame.
        EllesmereUI.ApplyBorderStyle(borderFrame, 0, 0, 0, 0, 0, "solid")
        borderFrame:Show()
        if not edges then
            edges = {}
            for key, uv in pairs(SECRET_BORDER_UV) do
                local tex = borderFrame:CreateTexture(nil, "OVERLAY", nil, 7)
                tex:SetTexCoord(unpack(uv)); edges[key] = tex
            end
            state._secretBorderEdges = edges
        end
        -- Preview surfaces can cancel their own panel scale without scaling the
        -- saved 0-4 texture-size key (a fractional key would fall through EDGE_MAP).
        -- Live aura buttons omit edgeScale and stay byte-for-byte equivalent.
        edgeScale = edgeScale or 1
        if edgePx then
            state._pxsbEdge, state._pxsbSize = edgePx, size
            state._pxsbR, state._pxsbG, state._pxsbB, state._pxsbA = r, g, b, a
            state._pxsbTex, state._pxsbOffX, state._pxsbOffY = textureKey, offsetX, offsetY
            state._pxsbShX, state._pxsbShY = shiftX, shiftY
            state._pxsbAddon, state._pxsbSizeKey, state._pxsbScale = addonKey, sizeKey, edgeScale
            _px.secret[borderFrame] = state
            _px.mult = EllesmereUI.PP.mult
        elseif state._pxsbEdge then
            state._pxsbEdge = nil
            _px.secret[borderFrame] = nil
        end
        local edgeSize, aL, aT, aR, aB = EllesmereUI.SecretBorderGeometry(borderFrame, size,
            textureKey, offsetX, offsetY, shiftX, shiftY, addonKey, sizeKey, edgeScale, edgePx)
        for _, tex in pairs(edges) do
            tex:SetTexture(path, true, true); tex:SetVertexColor(r, g, b, a or 1)
            tex:ClearAllPoints(); tex:Show()
        end
        EllesmereUI.LayoutSecretBorderEdges(edges, borderFrame, edgeSize, aL, aT, aR, aB)
    end

    --- The eight-slice geometry ApplySecretSafeBorderStyle draws a textured border with,
    --- as numbers only (no colour, no Show, no UI-scale registration): the edge in the
    --- owner's units and the four snapped anchor offsets of the corner pieces against
    --- the owner (left, top, right, bottom). Same arguments as that function; owner is
    --- read only for its effective scale. Shared with AuraKit's textured dispel ring,
    --- which must sit exactly on the aura border it recolours.
    function EllesmereUI.SecretBorderGeometry(owner, size, textureKey, offsetX, offsetY,
        shiftX, shiftY, addonKey, sizeKey, edgeScale, edgePx)
        edgeScale = edgeScale or 1
        local edgeSize
        if edgePx then
            edgeSize = math.max(1, math.floor(edgePx + 0.5)) * EllesmereUI.PP.mult * edgeScale
        else
            edgeSize = (EDGE_MAP[size] or EDGE_MAP[1]) * edgeScale
        end
        local ox, oy, sx, sy = EllesmereUI.GetBorderDefaults(addonKey, textureKey, sizeKey)
        if edgePx then
            -- The step's defaults follow the exact edge (the user's own offsets stay).
            local PPm = EllesmereUI.PP
            local f = (edgePx * PPm.mult) / (EDGE_MAP[size] or EDGE_MAP[1])
            ox, oy, sx, sy = PPm.Snap(ox * f), PPm.Snap(oy * f), PPm.Snap(sx * f), PPm.Snap(sy * f)
        end
        ox = offsetX ~= nil and offsetX or ox; oy = offsetY ~= nil and offsetY or oy
        sx = shiftX ~= nil and shiftX or sx; sy = shiftY ~= nil and shiftY or sy
        ox, oy, sx, sy = ox * edgeScale, oy * edgeScale, sx * edgeScale, sy * edgeScale
        if EllesmereUI.BorderTextureUsesScaleOffset(textureKey) then
            ox, oy = edgeSize / 2 + ox, edgeSize / 2 + oy
        end
        -- Same pixel snap as ApplyBorderStyle's backdrop anchors (see there): the
        -- corner pieces carry the outer edges, so their four anchor offsets go on the grid.
        local sok, ses = pcall(owner.GetEffectiveScale, owner)
        if not (sok and ses and ses > 0.01) then ses = UIParent and UIParent:GetEffectiveScale() or 1 end
        local PP = EllesmereUI.PP
        ox, oy = PP.SnapForES(ox, ses), PP.SnapForES(oy, ses)
        sx, sy = PP.SnapForES(sx, ses), PP.SnapForES(sy, ses)
        return edgeSize, -ox + sx, oy + sy, ox + sx, -oy + sy
    end

    --- Anchors an eight-slice set (keys as SECRET_BORDER_UV) on owner from
    --- SecretBorderGeometry's numbers. Sizes and points only: the caller clears the
    --- old points first and owns texture, colour and visibility.
    function EllesmereUI.LayoutSecretBorderEdges(edges, owner, edgeSize, aL, aT, aR, aB)
        edges.topLeft:SetSize(edgeSize, edgeSize); edges.topLeft:SetPoint("TOPLEFT", owner, "TOPLEFT", aL, aT)
        edges.topRight:SetSize(edgeSize, edgeSize); edges.topRight:SetPoint("TOPRIGHT", owner, "TOPRIGHT", aR, aT)
        edges.bottomLeft:SetSize(edgeSize, edgeSize); edges.bottomLeft:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT", aL, aB)
        edges.bottomRight:SetSize(edgeSize, edgeSize); edges.bottomRight:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", aR, aB)
        edges.top:SetHeight(edgeSize); edges.top:SetPoint("TOPLEFT", edges.topLeft, "TOPRIGHT"); edges.top:SetPoint("TOPRIGHT", edges.topRight, "TOPLEFT")
        edges.bottom:SetHeight(edgeSize); edges.bottom:SetPoint("BOTTOMLEFT", edges.bottomLeft, "BOTTOMRIGHT"); edges.bottom:SetPoint("BOTTOMRIGHT", edges.bottomRight, "BOTTOMLEFT")
        edges.left:SetWidth(edgeSize); edges.left:SetPoint("TOPLEFT", edges.topLeft, "BOTTOMLEFT"); edges.left:SetPoint("BOTTOMLEFT", edges.bottomLeft, "TOPLEFT")
        edges.right:SetWidth(edgeSize); edges.right:SetPoint("TOPRIGHT", edges.topRight, "BOTTOMRIGHT"); edges.right:SetPoint("BOTTOMRIGHT", edges.bottomRight, "TOPRIGHT")
    end

    --- Set border color on whichever system is active (PP or backdrop); used for hover highlights and other dynamic color changes.
    function EllesmereUI.SetBorderStyleColor(borderFrame, r, g, b, a)
        local PP = EllesmereUI.PP
        if not PP or not borderFrame then return end
        a = a or 1
        local ppContainer = PP.GetBorders(borderFrame)
        if ppContainer and ppContainer:IsShown() then
            PP.SetBorderColor(borderFrame, r, g, b, a)
            return
        end
        local bdFrame = _bdBorderData[borderFrame]
        if bdFrame and bdFrame:IsShown() then
            bdFrame:SetBackdropBorderColor(r, g, b, a)
        end
    end

    --- Hide whichever ApplyBorderStyle system is drawn on borderFrame (PP pixel border or
    --- BackdropTemplate texture) WITHOUT hiding borderFrame itself, for when another renderer (the dashed ants border) takes over the same frame.
    function EllesmereUI.HideBorderStyle(borderFrame)
        if not borderFrame then return end
        local PP = EllesmereUI.PP
        if PP and PP.GetBorders and PP.GetBorders(borderFrame) then PP.HideBorder(borderFrame) end
        local bdFrame = _bdBorderData[borderFrame]
        if bdFrame then bdFrame:Hide() end
        if bdFrame and bdFrame._pxEdge then bdFrame._pxEdge = nil; _px.borders[borderFrame] = nil end
    end
end

