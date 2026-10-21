if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_BlizzardSkin_HUD.lua
--
--  Tooltip progress and status bars, UI widget status bars and the extra
--  action button.
--  Reads EllesmereUIBlizzardSkin.lua through ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIBlizzardSkin.lua or an earlier EUI_BlizzardSkin_*.lua file
-- failed to load.
if not I or I.last ~= "TooltipVisibility" then return end

local GetFFD = I.GetFFD

-------------------------------------------------------------------------------
--  Blizzard HUD reskins: tooltip progress/status bars, UI widget status bar
--  covers, and the extra action button.
--
--  These are not WINDOWS -- no shell, no per-window style dropdown -- so they
--  live here rather than in a window pack.
--
--  The engine is resolved LAZILY. This file loads BEFORE
--  EllesmereUIBlizzardSkin_WindowEngine.lua (see the .toc), so ns.WSkin does
--  not exist at main-chunk time and a capture of it at the top of the file
--  would hand this block a nil engine. WS() below reads it on first use, so
--  there is no silent fallback to hand-rolled fonts and colors.
-------------------------------------------------------------------------------
;(function()
    local _WS
    local function WS()
        if _WS then return _WS end
        _WS = ns.WSkin
        -- Force the theme on first use: a tooltip bar on the very first hover
        -- can reach WSkin.Font before the engine's own PLAYER_LOGIN boot and
        -- hand SetFont a nil font path.
        if _WS and _WS.ResolveTheme and not (_WS.Theme and _WS.Theme.fontPath) then
            pcall(_WS.ResolveTheme)
        end
        return _WS
    end

    local FLAT = "Interface\\Buttons\\WHITE8X8"
    local _isSecretV = issecretvalue

    -- House font, with a REPAIR for nonsense sizes. A FontString created with
    -- no font object reports a garbage height (-1566.5 in the field), and any
    -- helper that PRESERVES the current size feeds that straight back, which
    -- surfaces as a flood of "Invalid font height (-1.000000): height must be
    -- > 0". An `or 11` fallback does NOT catch this -- the value is a number,
    -- just a nonsensical one -- so the test is on the SIGN.
    local function HouseFont(fs, white)
        if not fs or not fs.GetFont then return end
        local path, size, flags = fs:GetFont()
        if type(size) ~= "number" or size <= 0 then
            fs:SetFont(path or STANDARD_TEXT_FONT, 11, flags or "")
        end
        local W = WS()
        if W then
            if white then W.White(fs) else W.Font(fs) end
        elseif white and fs.SetTextColor then
            fs:SetTextColor(1, 1, 1)
        end
    end

    -- Tiny 1px BLACK outline. Deliberately not WSkin.AddBorder: that draws the
    -- themed accent border, which on a 15px bar is heavy chrome (the thing that
    -- kept getting rejected). Black at 1px reads as a crisp edge, not a frame.
    -- Idempotent via FFD; drawn on OVERLAY so the fill cannot cover it.
    local function ThinBorder(frame, inset)
        if not frame then return end
        local d = GetFFD(frame)
        if d.thinBorder then return end
        d.thinBorder = true
        -- Recorded as OURS: StripBarArt clears every texture on the bar, and
        -- these live on the bar.
        d.owned = d.owned or {}
        local i = inset or 0
        local edges = {
            { "TOPLEFT", -i, i, "TOPRIGHT", i, i, true },
            { "BOTTOMLEFT", -i, -i, "BOTTOMRIGHT", i, -i, true },
            { "TOPLEFT", -i, i, "BOTTOMLEFT", -i, -i, false },
            { "TOPRIGHT", i, i, "BOTTOMRIGHT", i, -i, false },
        }
        for n = 1, #edges do
            local e = edges[n]
            local t = frame:CreateTexture(nil, "OVERLAY", nil, 7)
            t:SetColorTexture(0, 0, 0, 1)
            t:SetPoint(e[1], frame, e[1], e[2], e[3])
            t:SetPoint(e[4], frame, e[4], e[5], e[6])
            if e[7] then t:SetHeight(1) else t:SetWidth(1) end
            d.owned[t] = true
        end
    end

    local function BarFill(bar)
        local W = WS()
        if W and W.ApplyBarFill then
            W.ApplyBarFill(bar)
        elseif bar.SetStatusBarColor then
            local EG = EllesmereUI.ELLESMERE_GREEN or { r = 0.047, g = 0.824, b = 0.616 }
            bar:SetStatusBarColor(EG.r * 0.8, EG.g * 0.8, EG.b * 0.8, 0.95)
        end
    end

    ---------------------------------------------------------------------------
    --  Tooltip progress + status bars.
    --
    --  Two different templates, both POOLED per tooltip, so the same bar frame
    --  comes back over and over and the skin has to survive reuse:
    --    TooltipProgressBarTemplate -- world quest / callings progress ("0%").
    --      A Frame wrapper whose .Bar is the StatusBar, with Border{Left,Mid,
    --      Right} and Left/RightDivider art and a .Bar.Label.
    --    TooltipStatusBarTemplate -- achievement category counts (the green
    --      201/295 bar). The StatusBar itself, with a .Text and one anonymous
    --      border texture. Its green comes from a SetStatusBarColor(0,1,0) in
    --      the template's OnLoad, so it MUST be re-colored per acquire.
    --
    --  Pools live on EACH tooltip (GameTooltip, EmbeddedItemTooltip, ...), so
    --  the hooks read the pool off the tooltip they were handed rather than
    --  assuming GameTooltip.
    ---------------------------------------------------------------------------
    -- `keepFill` is the live fill; OUR OWN textures are spared via FFD.
    --
    -- Without that second guard this wipes the trough and the border edges the
    -- moment a POOLED bar is reused: the first pass creates them (nothing to
    -- clear yet), the next pass clears them, and the bar renders once and then
    -- goes blank.
    local function StripBarArt(bar, keepFill)
        local owned = GetFFD(bar).owned
        -- Regions taken ONCE. select(i, bar:GetRegions()) inside the loop
        -- rebuilds the entire vararg every iteration.
        local regions = { bar:GetRegions() }
        for i = 1, #regions do
            local r = regions[i]
            if r and r ~= keepFill and not (owned and owned[r]) and r.IsObjectType then
                if r:IsObjectType("Texture") and r:GetDrawLayer() ~= "HIGHLIGHT" then
                    -- CLEARED, not alpha'd: these bars flare on change through
                    -- animations that drive alpha every frame and win over a
                    -- SetAlpha(0). An animation can animate nothing.
                    if r.SetAtlas then r:SetAtlas("") end
                    if r.SetTexture then r:SetTexture("") end
                    r:SetAlpha(0)
                end
            end
        end
    end

    local function SkinBarCommon(bar, keys)
        if not bar or bar:IsForbidden() or not bar.SetStatusBarTexture then return end
        -- Fill installed FIRST, then re-read, so the "clear everything that is
        -- not the fill" sweep below can never clear the live fill whatever art
        -- Blizzard happened to have there.
        bar:SetStatusBarTexture(FLAT)
        local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
        StripBarArt(bar, fill)
        for i = 1, #keys do
            local t = bar[keys[i]]
            if t and t.SetTexture then
                if t.SetAtlas then t:SetAtlas("") end
                t:SetTexture("")
                t:SetAlpha(0)
            end
        end
        local d = GetFFD(bar)
        if not d.hudTrough then
            -- OPAQUE and lighter than the widget covers' trough. These sit on
            -- the tooltip's own dark backplate rather than over the world, so
            -- 0.12 at 85% was invisible against it: an EMPTY bar (a world quest
            -- at 0%) read as a gap in the tooltip rather than as a bar. It
            -- needs to be legible with NO fill in it at all.
            local trough = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
            trough:SetColorTexture(0.22, 0.22, 0.22, 1)
            trough:SetAllPoints(bar)
            d.hudTrough = trough
            d.owned = d.owned or {}
            d.owned[trough] = true
            -- Same 1px black edge as the widget covers. NOT WSkin.AddBorder:
            -- the themed border is what made these read as thick chrome.
            ThinBorder(bar)
        end
        BarFill(bar)
    end

    local PROGRESS_ART = {
        "BorderLeft", "BorderRight", "BorderMid", "LeftDivider", "RightDivider",
    }

    local function SkinProgressBar(frame)
        local bar = frame and frame.Bar
        if not bar then return end
        SkinBarCommon(bar, PROGRESS_ART)
        HouseFont(bar.Label, true)
    end

    local function SkinStatusBar(bar)
        SkinBarCommon(bar, {})
        HouseFont(bar.Text, true)
    end

    local function SweepPool(pool, fn)
        if not (pool and pool.EnumerateActive) then return end
        local ok, iter = pcall(pool.EnumerateActive, pool)
        if ok and iter then
            for f in iter do pcall(fn, f) end
        end
    end

    -- Post-hooks on the ADD functions, not the SHOW ones: ShowProgressBar and
    -- ShowStatusBar both delegate to Add*, and only Add* runs for the second
    -- and later bars on one tooltip.
    if type(_G.GameTooltip_AddProgressBar) == "function" then
        hooksecurefunc("GameTooltip_AddProgressBar", function(self)
            if self then SweepPool(self.progressBarPool, SkinProgressBar) end
        end)
    end
    if type(_G.GameTooltip_AddStatusBar) == "function" then
        hooksecurefunc("GameTooltip_AddStatusBar", function(self)
            if self then SweepPool(self.statusBarPool, SkinStatusBar) end
        end)
    end

    ---------------------------------------------------------------------------
    --  UI widget status bars -- COVERS, never writes.
    --
    --  Widget values are SECRET inside instanced content. An insecure write
    --  anywhere in a widget tree resurfaces later as "attempt to compare a
    --  secret number value" out of LayoutFrame, far from the code that caused
    --  it. So Blizzard's bar is never touched: an EUI-owned StatusBar parented
    --  to UIParent is merely ANCHORED to it (a write on ours, none on theirs)
    --  and mirrors min/max/value/label through pcall. Any failed or secret read
    --  RETIRES that cover and Blizzard's own bar shows through again;
    --  retirement clears on PLAYER_ENTERING_WORLD.
    --
    --  Containers are DISCOVERED, not hardcoded: the bars in the field are
    --  mostly on NAMEPLATES (NamePlateN.UnitFrame.WidgetContainer.<anon>.Bar),
    --  not on any screen container. ObjectiveTrackerUIWidgetContainer is
    --  deliberately EXCLUDED -- its bars sit inside the tracker's clipped
    --  scrolling layout, where a UIParent-parented cover would float free.
    --
    --  PERFORMANCE (this subsystem caused a real CPU complaint once). The
    --  house standard is TWO separate promises: nothing at all while the
    --  setting is off, and event-driven -- never polled -- while it is on.
    --   - OFF means the events are never REGISTERED. The gate is at
    --     PLAYER_LOGIN, not inside the handlers: an early return in a live
    --     handler still pays for the registration and the dispatch. With the
    --     setting off, hudEv ends up with no events and no script at all.
    --   - There is NO TIMER. Sweeps run from the widget system's own events,
    --     coalesced to at most one per frame, plus a hook on each covered
    --     bar's own DisplayBarValue for the two cases that move a bar with no
    --     event to listen for (see Adopt).
    --   - children taken ONCE per frame, never select(i, f:GetChildren()) in a
    --     loop, which is O(n^2) and lethal on a container walk;
    --   - discovery is LOGIN/ZONE work and never hangs off a per-update event;
    --   - nameplates are tracked via NAME_PLATE_UNIT_ADDED/REMOVED, because
    --     C_NamePlate.GetNamePlates() allocates a fresh table on every call.
    ---------------------------------------------------------------------------
    local HUD = {
        covers   = setmetatable({}, { __mode = "k" }),  -- blizz bar -> our cover
        retired  = setmetatable({}, { __mode = "k" }),
        plates   = setmetatable({}, { __mode = "k" }),
        -- Containers a window pack handed us explicitly. Kept SEPARATE from
        -- `containers` because Discover() wipes that list on every zone, and
        -- these cannot be rediscovered -- they are nested inside a window, not
        -- children of UIParent.
        adopted  = setmetatable({}, { __mode = "k" }),
        -- OUR OWN cover frames. Load-bearing since covers became children of
        -- Blizzard's frames: a cover is itself a StatusBar sitting inside a
        -- widget container, so without this the next sweep DISCOVERS IT as a
        -- bar to cover, and does so again every tick -- the bar visibly grows
        -- forever. Nothing in this set is ever treated as a Blizzard bar.
        owned    = setmetatable({}, { __mode = "k" }),
        -- Bars whose own DisplayBarValue we have already hooked, so a re-adopt
        -- of a pooled bar cannot stack a second hook on it.
        hooked   = setmetatable({}, { __mode = "k" }),
        containers = {},
        -- Foreign-set gate state. setIds = the widgetSetIDs currently owned by
        -- containers the sweep actually walks, rebuilt as a side-read of every
        -- sweep; setHooked = containers whose RegisterForWidgetSet is hooked
        -- (a mid-life re-registration books a sweep, which re-records);
        -- setIdsExact = whether every container's set id was readable last
        -- sweep. While false the gate stands down and every widget event
        -- sweeps, exactly as before the gate existed.
        setIds   = {},
        setHooked = setmetatable({}, { __mode = "k" }),
        setIdsExact = false,
        -- Set at PLAYER_LOGIN only when the setting is on. Nothing here has
        -- run while this is false.
        installed = false,
        -- Minimum on-screen height for plate-hosted covers, cached from the
        -- setting (0 = off). Seeded at login, re-read only when the cog writes it.
        minPx = 0,
    }

    local NAMED_CONTAINERS = {
        "UIWidgetTopCenterContainerFrame",
        "UIWidgetBelowMinimapContainerFrame",
        "UIWidgetPowerBarContainerFrame",
        "UIWidgetCenterDisplayFrame",
    }

    -- Existing accounts get an EXPLICIT boolean seeded once by the
    -- blizzskin_widget_bars_seed_v1 migration (on only when Reskin Tooltips
    -- AND Reskin Popups and Menus are both on); nil survives only on fresh
    -- installs, where both of those masters default on too -- so nil = on.
    local function CoverEnabled()
        return not EllesmereUIDB or EllesmereUIDB.reskinWidgetBars ~= false
    end

    -- FORWARD DECLARATION, filled in far below. Adopt installs a hook that has
    -- to call the debounced refresh; that refresh cannot be written until
    -- Sweep exists, and Sweep cannot be written until Adopt does. A
    -- `local function Refresh` written below would NOT be in scope up here --
    -- the name would resolve to a nil global, and the pcall wrapped round the
    -- hook would swallow the failure without a word.
    local Refresh

    -- Read a value and reject it if it is secret. Returns ok, value. Reads
    -- resolve into a LOCAL before any comparison -- a getter called mid-`and`
    -- chain throws on the spot rather than being skipped.
    local function SafeRead(obj, method)
        local fn = obj and obj[method]
        if type(fn) ~= "function" then return false end
        local ok, a, b = pcall(fn, obj)
        if not ok then return false end
        if _isSecretV then
            if a ~= nil and _isSecretV(a) then return false end
            if b ~= nil and _isSecretV(b) then return false end
        end
        return true, a, b
    end

    local function RetireCover(bar)
        local c = HUD.covers[bar]
        if c then
            c:Hide()
            HUD.covers[bar] = nil
        end
        HUD.retired[bar] = true
    end

    -- Blizzard's frame art extends BEYOND the bar's own rect: in
    -- UIWidgetTemplateStatusBar, BorderLeft sits at LEFT x=-8 and BorderRight at
    -- RIGHT x=+8, both useAtlasSize (so their HEIGHT is whatever the widget
    -- style ships), and GlowLeft/Right/Center anchor to those borders and PULSE
    -- through GlowPulseAnim. A cover sized to the bar rect therefore leaves a
    -- ring of Blizzard border art visible around it -- which is exactly what
    -- turned up on nameplate bars in game.
    --
    -- The MASK is a separate texture from the trough for a reason: the cover
    -- StatusBar keeps the bar's true rect so the fill proportion stays honest,
    -- while the mask alone spreads out to swallow the frame art. Textures are
    -- not clipped to their parent's bounds, so it can extend past the cover.
    --
    -- Anchored to the border TEXTURES when they exist, so it tracks whatever
    -- atlas size the style uses instead of guessing. Anchoring OUR texture to
    -- THEIRS is still a write on ours only -- the widget tree is untouched.
    -- Ceiling on the vertical overhang the cover will absorb. Blizzard's border
    -- run is a couple of px taller than the bar; a decorative END CAP atlas can
    -- be far taller, and following that is what made the bar giant.
    --
    -- Lowered 5 -> 2 because the bar read as chunky: at 5 a bar whose art is
    -- oversized ends up bar+10, and the pad is pure thickness. The real floor is
    -- Blizzard's own bar height -- the cover cannot go under that without
    -- exposing the art it exists to hide, and shrinking their bar would mean
    -- writing into the widget tree. 2 keeps the common border covered and
    -- refuses anything decorative; a 1px sliver on an unusual style is a better
    -- trade than a permanently fat bar.
    -- ONE small pad, everywhere. THIN IS THE PRIORITY.
    --
    -- A 10px "panel" pad was tried so the cover would fully occlude Blizzard's
    -- border art (31px of texture around a 15px bar) and it made the bars
    -- chunky -- for a benefit nobody asked for. The border art is mostly
    -- transparent padding; chasing its full extent buys nothing and costs
    -- height on every bar. 2px covers the drawn edge.
    --
    -- If a sliver of Blizzard's frame ever shows, raise THIS number -- do not
    -- reintroduce a per-context split. Thin beats perfectly occluded.
    local MAX_VPAD = 2
    -- Plain indexed read, passed BY ARGUMENT to pcall (no closure allocated).
    -- Field access on a widget frame can throw, so even fetching a texture
    -- reference off one has to be guarded.
    local function HUDGet(t, k)
        return t[k]
    end

    -- Anchor the COVER ITSELF out to Blizzard's border art, not to the bar's
    -- inner rect.
    --
    -- Two earlier builds got this wrong in opposite directions. Sizing the
    -- cover to the bar rect left Blizzard's border ring showing around it.
    -- Adding a wider MASK behind the cover hid the ring but produced a dark
    -- margin all the way round, because the fill only ever reached the inner
    -- rect -- which read as an even bigger border.
    --
    -- So the cover takes the whole footprint and the fill spans it. The fill
    -- then represents value/max across a rect ~8px wider each side than
    -- Blizzard's own, but nothing is left on screen to compare it against and
    -- the scale is internally consistent (0% empty, 100% full). A clean bar
    -- beats a technically-truer one wearing a frame.
    -- How much taller Blizzard's border art is than the bar it wraps, halved
    -- (the art is centered on the bar, so the overhang is split top and bottom).
    --
    -- MEASURED, not guessed. A /framestack over a live bar showed the real
    -- shape: the cover sits at frame level 8 over a Bar at level 6, so layering
    -- was never the problem -- but `Bar.BorderCenter` is its own texture and is
    -- TALLER than the Bar, so a cover matching the Bar's height leaves a thin
    -- line of it above and below. That is the "weird small outline".
    --
    -- Capped at MAX_VPAD because BorderLeft/BorderRight are useAtlasSize end
    -- CAPS whose atlas can be far larger than the bar; taking their full height
    -- is what produced the giant-bar round.
    local function VPad(bar)
        local okB, barH = pcall(bar.GetHeight, bar)
        if not okB or type(barH) ~= "number" or barH <= 0 then return 0 end
        local tallest = barH
        for _, k in ipairs({ "BorderCenter", "BorderLeft", "BorderRight" }) do
            local okT, t = pcall(HUDGet, bar, k)
            if okT and t then
                local okH, h = pcall(t.GetHeight, t)
                if okH and type(h) == "number" and h > tallest then tallest = h end
            end
        end
        local pad = (tallest - barH) / 2
        if pad < 0 then pad = 0 end
        if pad > MAX_VPAD then pad = MAX_VPAD end
        return pad
    end

    -- Minimum on-screen cover HEIGHT (real pixels) for PLATE-HOSTED bars, the cog
    -- on "Reskin Widget Bars". A nameplate carries its own scale, so a shrunken
    -- plate drags its widget bar and label down to unreadable; below the floor
    -- the cover SCALES up (label rides along). Growing past Blizzard's rect is
    -- safe only because HideBarArt alphas their art; the "never SMALLER" floor
    -- still stands. Panel bars never scale. 0 = OFF (mirror the rect exactly),
    -- and OFF is the default: opt-in, and it keeps instances -- where the plate
    -- lane is unregistered anyway -- at zero added cost.
    local DEFAULT_MIN_BAR_PX = 0
    local MAX_MIN_BAR_PX = 24
    -- Cap on the correction: a bar mid-fade at 1px would otherwise ask for a slab.
    local MAX_UPSCALE = 3

    -- Cached on HUD, never read per bar per pass (SyncCover can run every frame
    -- while a fill animates); the options cog re-reads it through the seam.
    local function ReadMinPx()
        local v = EllesmereUIDB and EllesmereUIDB.widgetBarMinSize
        if type(v) ~= "number" then return DEFAULT_MIN_BAR_PX end
        if v < 0 then return 0 end
        if v > MAX_MIN_BAR_PX then return MAX_MIN_BAR_PX end
        return v
    end

    -- Scale factor that lifts a plate cover to the floor; 1 = leave it alone
    -- (floor off, panel bar, or plate at readable scale).
    local function CoverScale(bar, c)
        local min = HUD.minPx
        if not (c.euiPlate and type(min) == "number" and min > 0) then return 1 end
        local okH, h = pcall(bar.GetHeight, bar)
        if not okH or type(h) ~= "number" or h <= 0 then return 1 end
        local okE, es = pcall(bar.GetEffectiveScale, bar)
        if not okE or type(es) ~= "number" or es <= 0 then return 1 end
        local px = h * es
        if px <= 0 or px >= min then return 1 end
        local s = min / px
        if s > MAX_UPSCALE then s = MAX_UPSCALE end
        return s
    end

    local function AnchorCover(c, bar, pad)
        local s = CoverScale(bar, c)
        c:ClearAllPoints()
        if s <= 1 then
            -- EXACTLY the bar's rect. With their art hidden there is nothing to
            -- reach past, so no pad, no overhang, no slab.
            if c.euiScale ~= 1 then c:SetScale(1); c.euiScale = 1 end
            c.euiMin = HUD.minPx
            c:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
            c:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
            return
        end
        -- Scaled: CENTER to CENTER with an explicit size, never the two-corner
        -- anchor. Corner anchors DERIVE the size from the bar, so they would
        -- undo the scale as fast as it was applied -- the cover would render
        -- the same size as before with a bigger font in it. CENTER with zero
        -- offsets is the one anchor that needs no scale conversion, so the
        -- cover stays centred on the bar it mirrors and grows symmetrically.
        local okW, w = pcall(bar.GetWidth, bar)
        local okH, h = pcall(bar.GetHeight, bar)
        if not (okW and okH) or type(w) ~= "number" or type(h) ~= "number"
           or w <= 0 or h <= 0 then
            if c.euiScale ~= 1 then c:SetScale(1); c.euiScale = 1 end
            c.euiMin = HUD.minPx
            c:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
            c:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
            return
        end
        c:SetScale(s)
        c.euiScale = s
        c.euiMin = HUD.minPx
        c:SetSize(w, h)
        c:SetPoint("CENTER", bar, "CENTER", 0, 0)
    end

    local function BuildCover(bar, isPlate)
        -- Parented to the BAR'S OWN PARENT, not UIParent.
        --
        -- UIParent parenting was the original design ("write on ours, none on
        -- theirs") and it does not reliably draw on top: inside a toplevel
        -- window, Blizzard's subtree and a UIParent child are different
        -- branches, and matching strata + level+2 was NOT enough -- covers
        -- shown, sized and reading fine while the stock bars stayed visible
        -- underneath.
        --
        -- SetParent on OUR OWN frame is still not a write into the widget tree;
        -- nothing on a Blizzard frame is modified. It also makes the cover
        -- inherit their scale and show/hide for free.
        local okP, parent = SafeRead(bar, "GetParent")
        local c = CreateFrame("StatusBar", nil, (okP and parent) or UIParent)
        -- Anchored, never re-parented: position needs no polling because the
        -- anchor does it, including when a nameplate moves.
        c.euiPad = VPad(bar)
        c.euiScale = 1
        -- Plate-hosted covers are the only ones the size floor applies to.
        c.euiPlate = isPlate and true or false
        AnchorCover(c, bar, c.euiPad)
        c:SetStatusBarTexture(FLAT)
        -- OPAQUE trough, not the usual 0.85: this one has to hide Blizzard's
        -- bar and border underneath rather than merely sit behind our own fill.
        -- Spans the whole cover, so there is no dark margin anywhere.
        local trough = c:CreateTexture(nil, "BACKGROUND", nil, -1)
        trough:SetColorTexture(0.10, 0.10, 0.10, 1)
        trough:SetAllPoints(c)
        -- Font OBJECT, not a bare CreateFontString: a template-less string
        -- reports a garbage height that any size-preserving helper feeds back
        -- into SetFont.
        local label = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("CENTER", c, "CENTER", 0, 0)
        c.euiLabel = label
        HouseFont(label, true)
        BarFill(c)
        -- Tiny black outline on EVERY bar, by maintainer call. The earlier "no border"
        -- call was about the THEMED accent border, which is heavy on a 15px
        -- bar; a 1px black edge is what actually defines it.
        ThinBorder(c)

        return c
    end

    -- Blizzard's own bar art, alpha'd to nothing.
    --
    -- This replaces the occluder -- a dark rectangle painted over their frame,
    -- which never blended and read as a patch rather than a skin.
    --
    -- The "never write into a widget tree" rule is about VALUES: widget values
    -- are secret, and reading or comparing one throws. SetAlpha on a TEXTURE
    -- touches no value, no layout and no Lua field, so it does not put secret
    -- data anywhere near our code. Every read of theirs still goes through
    -- SafeRead, and the cover still retires on a secret value.
    --
    -- Re-asserted each sync: these bars are pooled and re-textured per widget.
    -- "Label" is in this list because the COVER draws that text itself, so
    -- Blizzard's is a duplicate sitting underneath. It only shows on strings
    -- with a DESCENDER -- "Friendly" hung a stray y below the bar while
    -- "Revered" looked clean -- because that is the only part reaching past the
    -- cover's bottom edge. Hiding a FontString is the same alpha write as a
    -- texture: no value, no layout, no Lua field.
    local ART = { "BGLeft", "BGRight", "BGCenter", "BorderLeft", "BorderRight",
                  "BorderCenter", "Spark", "BackgroundGlow",
                  "GlowLeft", "GlowRight", "GlowCenter", "Label" }
    -- Plate art on the widget FRAME (the bar's parent), outside the bar's own
    -- rect: UIWidgetTemplateStatusBar puts LabelBG and LabelBGDivider there.
    -- Stripping only the bar leaves them showing as a stray background around
    -- it. The frame-level Label is deliberately NOT touched -- it is a separate
    -- caption above the bar, not the duplicate of the bar's own text.
    local PARENT_ART = { "LabelBG", "LabelBGDivider" }
    -- Local copy: KidsOf is declared further down, and a `local function` is
    -- not in scope for code written above it -- the reference would resolve to
    -- a nil global and the pcall around it would swallow the failure silently.
    local function BarKids(f) return { f:GetChildren() } end
    local function HideBarArt(bar)
        for i = 1, #ART do
            local okT, t = pcall(HUDGet, bar, ART[i])
            if okT and t then pcall(t.SetAlpha, t, 0) end
        end
        local okP, parent = SafeRead(bar, "GetParent")
        if okP and parent then
            for i = 1, #PARENT_ART do
                local okT, t = pcall(HUDGet, parent, PARENT_ART[i])
                if okT and t then pcall(t.SetAlpha, t, 0) end
            end
        end
        -- DIVIDER TICKS. Blizzard builds these at runtime
        -- (Blizzard_UIWidgetTemplateBase.lua) as ANONYMOUS child FRAMES of the
        -- bar, each holding a .Tex with a widgetstatusbar-bordertick atlas.
        -- Nothing named, so the key sweep above can never reach them and they
        -- survive as stray marks across the bar.
        --
        -- Our cover is parented to the bar's PARENT, not the bar, so it is
        -- never in this list -- no risk of hiding ourselves.
        local okK, kids = pcall(BarKids, bar)
        if okK and kids then
            for i = 1, #kids do
                local okT, t = pcall(HUDGet, kids[i], "Tex")
                if okT and t then pcall(t.SetAlpha, t, 0) end
            end
        end
    end

    local function SyncCover(bar, isPlate)
        if HUD.retired[bar] then return false end
        local c = HUD.covers[bar]
        if not c then return false end
        -- Pooled bars can migrate between hosts; keep the plate flag current.
        c.euiPlate = isPlate and true or false

        local shownOk, shown = SafeRead(bar, "IsVisible")
        if not shownOk then RetireCover(bar); return false end
        if not shown then
            if c:IsShown() then c:Hide() end
            return false
        end

        local mmOk, mn, mx = SafeRead(bar, "GetMinMaxValues")
        local vOk, v = SafeRead(bar, "GetValue")
        if not (mmOk and vOk) then RetireCover(bar); return false end

        -- Change-guarded: a ticker re-issuing these ten times a second per bar
        -- is pure waste.
        local cn, cx = c:GetMinMaxValues()
        local changed = false
        if cn ~= mn or cx ~= mx then c:SetMinMaxValues(mn, mx); changed = true end
        if c:GetValue() ~= v then c:SetValue(v); changed = true end

        local blabel = bar.Label
        local txt
        if blabel then
            local tOk, t = SafeRead(blabel, "GetText")
            if tOk then txt = t end
        end
        txt = txt or ""
        if c.euiLabel:GetText() ~= txt then c.euiLabel:SetText(txt); changed = true end

        -- HideBarArt ONLY on change, never every tick.
        --
        -- It is by far the most expensive thing here: ~13 pcall'd field reads
        -- plus a children walk that allocates a table, and at 10Hz per bar that
        -- is pure waste in the steady state. Blizzard only re-textures a bar
        -- when its widget updates -- which is exactly when a value or label
        -- moves -- so a change IS the re-texture signal. Adopt() also hides at
        -- creation, so a bar is never left showing its own art.
        if changed then HideBarArt(bar) end

        -- Follow the bar if it is re-parented (these frames are POOLED, so a
        -- reused bar can land under a different option).
        local pOk, bp = SafeRead(bar, "GetParent")
        if pOk and bp and c:GetParent() ~= bp then c:SetParent(bp) end

        -- STRATA FIRST, THEN LEVEL. SetFrameStrata RESETS a frame's level, so
        -- the reverse order silently threw the level away on the first pass and
        -- only self-corrected on the next tick.
        local stOk, st = SafeRead(bar, "GetFrameStrata")
        if stOk and st and c:GetFrameStrata() ~= st then c:SetFrameStrata(st) end
        local lvlOk, lvl = SafeRead(bar, "GetFrameLevel")
        if lvlOk and type(lvl) == "number" then
            local want = lvl + 2
            if c:GetFrameLevel() ~= want then c:SetFrameLevel(want) end
        end

        -- Re-anchor only when the measured overhang actually changed: Blizzard
        -- re-textures these bars per widget style, and the border height can
        -- differ between one use of a pooled bar and the next.
        -- VPad re-measures four textures; the answer only moves if the bar's
        -- own height does, so it is cached against that.
        local hOk, curH = pcall(bar.GetHeight, bar)
        local pad = c.euiPad
        if not hOk or curH ~= c.euiPadH then
            pad = VPad(bar)
            c.euiPadH = hOk and curH or nil
        end
        -- Second trigger, PLATE covers with the size floor ON only: the bar's
        -- effective scale moves with the plate while its local height does not.
        -- Panel bars and the floor-off default skip the probe entirely (this
        -- runs per bar per sweep, per frame while a fill animates). Thresholded:
        -- plate distance-scaling drifts continuously and an exact compare would
        -- re-anchor every frame.
        local es
        if c.euiPlate and HUD.minPx > 0 then
            local esOk, curES = pcall(bar.GetEffectiveScale, bar)
            if esOk and type(curES) == "number" then es = curES end
        end
        local esMoved = (es ~= nil) ~= (c.euiES ~= nil)
            or (es and c.euiES and math.abs(es - c.euiES) > 0.01)
        -- Third trigger: the floor itself (the cog's slider re-anchors live covers).
        if pad ~= c.euiPad or esMoved or c.euiMin ~= HUD.minPx then
            c.euiPad = pad
            c.euiES = es
            AnchorCover(c, bar, pad)
        end

        if not c:IsShown() then c:Show() end
        return true
    end

    -- The hook body runs INSIDE Blizzard's call stack, so anything thrown here
    -- surfaces as an error in THEIR widget update rather than ours. Every read
    -- inside Sweep is already pcall'd, but the wrapper is the cheap guarantee.
    --
    -- It asks for the DEBOUNCED refresh rather than syncing the bar on the
    -- spot, and that is load-bearing. DisplayBarValue is called from the
    -- middle of UIWidgetTemplateStatusBarMixin:Setup, which AFTERWARDS puts
    -- the glow textures back with SetAlpha(1). Syncing here would consume the
    -- value change -- and with it the HideBarArt trigger, which is
    -- change-guarded -- one step before the art that has to be hidden is
    -- restored, leaving the glows on show with nothing left to re-fire the
    -- hide. Next frame sees the finished widget, which is exactly where the
    -- old ticker saw it.
    local function OnBarValueDisplayed()
        pcall(Refresh)
    end

    local function Adopt(bar, isPlate)
        if not bar or HUD.retired[bar] then return end
        if HUD.covers[bar] then return end
        -- Never cover one of our own covers (see HUD.owned).
        if HUD.owned[bar] then return end
        if bar.IsForbidden and bar:IsForbidden() then return end
        -- Immediately, before the cover has values to show. Otherwise their bar
        -- is what you watch for the first few ticks while it animates in, which
        -- reads as the skin taking half a second to appear.
        HideBarArt(bar)
        local c = BuildCover(bar, isPlate)
        HUD.owned[c] = true
        HUD.covers[bar] = c

        -- FOLLOW THE BAR'S OWN UPDATE. This is what replaced the 0.1s ticker.
        --
        -- Two things move a widget bar with no event we could ever listen for,
        -- both visible in Blizzard_UIWidget* source:
        --   - a widget with hasTimer is re-processed by its own CONTAINER off
        --     a 1s C_Timer (UIWidgetContainerMixin:RegisterTimerWidget).
        --     UPDATE_UI_WIDGET does not fire for those ticks.
        --   - a fillMotionType other than Instant makes the bar set its OWN
        --     OnUpdate and walk displayedValue toward value over several
        --     frames (UIWidgetBaseStatusBarTemplateMixin:UpdateBar).
        -- Both funnel through DisplayBarValue, the single place the bar calls
        -- SetValue, so that is the update event the widget system actually
        -- has. Hooking it costs nothing when nothing moves and follows a
        -- smooth fill frame by frame when it does -- which is the whole shape
        -- a poll was faking.
        --
        -- hooksecurefunc on ONE FRAME'S method, not a write into the widget
        -- tree: no value is read, compared or stored, and it is the same call
        -- this addon already makes on GameTooltipStatusBar. pcall'd because a
        -- field access on a widget frame can throw on its own.
        if not HUD.hooked[bar] and type(bar.DisplayBarValue) == "function" then
            HUD.hooked[bar] = true
            pcall(hooksecurefunc, bar, "DisplayBarValue", OnBarValueDisplayed)
        end
    end

    -- Children as a TABLE, passed by argument to pcall. The obvious spelling,
    -- pcall(function() return { f:GetChildren() } end), allocates a closure on
    -- every frame of every walk.
    local function KidsOf(f)
        return { f:GetChildren() }
    end

    -- Walk a container for StatusBars. Depth-capped and children taken once.
    local function CollectBars(frame, depth, out, seen)
        if not frame or depth > 4 then return end
        if seen[frame] then return end
        seen[frame] = true
        if not frame.GetChildren then return end
        local okKids, kids = pcall(KidsOf, frame)
        if not okKids or not kids then return end
        for i = 1, #kids do
            local ch = kids[i]
            -- Skip OUR OWN covers entirely -- not collected, not descended
            -- into. They are StatusBars living inside Blizzard's frames, so
            -- without this the sweep covers its own covers, every tick.
            if ch and HUD.owned[ch] then
                ch = nil
            end
            if ch and ch.GetObjectType and not (ch.IsForbidden and ch:IsForbidden()) then
                local okT, t = pcall(ch.GetObjectType, ch)
                if okT and t == "StatusBar" then
                    out[#out + 1] = ch
                else
                    CollectBars(ch, depth + 1, out, seen)
                end
            end
        end
    end

    -- Login / zone work ONLY. Never call this from a per-update event.
    local function Discover()
        wipe(HUD.containers)
        for i = 1, #NAMED_CONTAINERS do
            local f = _G[NAMED_CONTAINERS[i]]
            if f then HUD.containers[#HUD.containers + 1] = f end
        end
        -- Any other UIParent child that is a widget container. Children taken
        -- ONCE; UIParent has a few hundred of them. GetChildren returns every
        -- child as its own value, so a UIParent holding thousands of frames
        -- (something in the session creating them without end) overflows the
        -- Lua stack: past the cap, or if the call fails anyway, only the named
        -- containers above and the adopted ones below are swept.
        local up = _G.UIParent
        local okC, numKids = false, nil
        if up and up.GetNumChildren then okC, numKids = pcall(up.GetNumChildren, up) end
        local okK, kids = false, nil
        if okC and type(numKids) == "number" and numKids <= 4000 then
            okK, kids = pcall(KidsOf, up)
        end
        if okK and kids then
            for i = 1, #kids do
                local ch = kids[i]
                if ch and ch.GetName and not (ch.IsForbidden and ch:IsForbidden()) then
                    local okN, n = pcall(ch.GetName, ch)
                    local okP, pools = pcall(HUDGet, ch, "widgetPools")
                    local isWidget = (okN and type(n) == "string" and n:find("^UIWidget"))
                                     or (okP and pools ~= nil)
                    -- The tracker's own widget container is excluded on
                    -- purpose: its bars live inside a clipped scrolling layout,
                    -- so a UIParent-parented cover would float free of it.
                    if isWidget and not (okN and n == "ObjectiveTrackerUIWidgetContainer") then
                        HUD.containers[#HUD.containers + 1] = ch
                    end
                end
            end
        end
        -- Re-add anything a window pack adopted: the wipe above would otherwise
        -- drop them on the first zone change and they can never be rediscovered.
        for f in pairs(HUD.adopted) do
            HUD.containers[#HUD.containers + 1] = f
        end
    end

    -- Scratch tables reused across passes: a sweep can run every frame while a
    -- smooth fill animates, and two fresh tables per pass is needless churn
    -- for the GC.
    HUD.scratchBars, HUD.scratchSeen = {}, {}

    -- Mid-life set changes on a container we sweep (vigor set arming when the
    -- player mounts, a pooled plate container re-targeted) book a sweep, and
    -- that sweep re-records the registry. Named function, created once.
    local function OnWidgetSetRegistered()
        HUD.setIdsExact = false
        Refresh()
    end

    -- Record one container's widget-set id into the gate registry and make
    -- sure its re-registrations are hooked. Returns the running exactness:
    -- an unreadable id (or a secret one) means the registry cannot prove a
    -- foreign event foreign, so the gate must stand down. A container with NO
    -- set (nil id) stays exact -- no widget event can belong to it.
    local function NoteContainerSet(c, exact)
        if not HUD.setHooked[c] then
            local okR, reg = pcall(HUDGet, c, "RegisterForWidgetSet")
            if okR then
                HUD.setHooked[c] = true
                if type(reg) == "function" then
                    pcall(hooksecurefunc, c, "RegisterForWidgetSet", OnWidgetSetRegistered)
                end
            end
        end
        local okS, sid = pcall(HUDGet, c, "widgetSetID")
        if not okS then return false end
        if sid == nil then return exact end
        if (_isSecretV and _isSecretV(sid)) or type(sid) ~= "number" then return false end
        HUD.setIds[sid] = true
        return exact
    end

    -- No CoverEnabled() check here on purpose. The setting is read ONCE, at
    -- login, and decides whether any of this is wired up at all; re-testing it
    -- per pass would only produce a half-state where the covers are still on
    -- screen but have stopped following their bars.
    local function Sweep()
        local live = 0
        local seen, bars = HUD.scratchSeen, HUD.scratchBars
        wipe(seen); wipe(bars)
        wipe(HUD.setIds)
        local exact = true
        for i = 1, #HUD.containers do
            exact = NoteContainerSet(HUD.containers[i], exact)
            CollectBars(HUD.containers[i], 0, bars, seen)
        end
        -- Everything collected past this index came from a plate container.
        local nStatic = #bars
        -- WIDGET CONTAINERS ONLY, never the whole plate. A nameplate base
        -- frame also hosts unit-frame trees (EllesmereUI's own health and cast
        -- bars are StatusBars parented under it), and a full walk adopts and
        -- art-strips those. The container is found by the same widgetPools
        -- probe Discover uses; with EUI nameplates off it sits one level down,
        -- under the Blizzard unit frame's WidgetContainer key instead.
        for plate in pairs(HUD.plates) do
            local okKids, kids = pcall(KidsOf, plate)
            if okKids and kids then
                for i = 1, #kids do
                    local ch = kids[i]
                    if ch and not (ch.IsForbidden and ch:IsForbidden()) then
                        local okP, pools = pcall(HUDGet, ch, "widgetPools")
                        if okP and pools ~= nil then
                            exact = NoteContainerSet(ch, exact)
                            CollectBars(ch, 0, bars, seen)
                        else
                            local okW, wc = pcall(HUDGet, ch, "WidgetContainer")
                            if okW and wc and not (wc.IsForbidden and wc:IsForbidden()) then
                                exact = NoteContainerSet(wc, exact)
                                CollectBars(wc, 0, bars, seen)
                            end
                        end
                    end
                end
            else
                -- A plate whose children could not be read holds containers
                -- the registry cannot see: gate stands down.
                exact = false
            end
        end
        HUD.setIdsExact = exact
        for i = 1, #bars do
            local isPlate = i > nStatic
            Adopt(bars[i], isPlate)
            if SyncCover(bars[i], isPlate) then live = live + 1 end
        end
        -- Covers whose bar has gone away this pass.
        for bar, c in pairs(HUD.covers) do
            if not seen[bar] then
                local ok, vis = SafeRead(bar, "IsVisible")
                if not ok or not vis then
                    if c:IsShown() then c:Hide() end
                end
            end
        end
        return live
    end

    -- ONE sweep per frame, on the TRAILING edge. This is what the 0.1s ticker
    -- turned into.
    --
    -- Deferred rather than immediate for two independent reasons:
    --   - UPDATE_UI_WIDGET fires once per widget and several times in a frame
    --     when a set refreshes. Every one of those asking for a full container
    --     walk is the CPU complaint all over again; the flag collapses a burst
    --     into a single pass.
    --   - our handler and the widget container's own are both plain event
    --     registrations, so the order between them is registration order.
    --     Sweeping on the spot can read the value that is ABOUT to change,
    --     and the same event will not come round again to correct it. Landing
    --     after the frame's handlers have all run removes the race.
    --
    -- Flush is created once and reused: no closure is allocated per fire, so a
    -- burst of events costs one boolean test each. Written with `function
    -- Refresh` and no `local` because it FILLS IN the forward declaration far
    -- above -- adding `local` here would create a second, different upvalue
    -- and leave the hook in Adopt calling a nil.
    local pending = false
    local function Flush()
        pending = false
        Sweep()
    end
    function Refresh()
        if pending then return end
        pending = true
        if C_Timer then C_Timer.After(0, Flush) else Flush() end
    end

    -- Seam for window packs. Discover() only walks UIParent's DIRECT children,
    -- so a widget container nested inside a window is invisible to it -- and
    -- every PlayerChoice OPTION owns one (that is where the reputation bars on
    -- the weekly cartel picker come from). The pack that knows the frame hands
    -- it over here rather than the sweep guessing at window internals.
    --
    -- Defined AFTER Refresh on purpose: a `local function` is not in scope for
    -- a closure written above it, so declaring this any earlier would capture
    -- a nil global instead of the real Refresh.
    --
    -- PUBLISHED at login and only when the feature is on. The caller in
    -- WindowPacks already tests `type(adopt) ~= "function"`, so leaving it nil
    -- is the honest way to say the system is not running.
    local function HUDWidgetAdopt(container)
        if not container or HUD.adopted[container] then return end
        HUD.adopted[container] = true
        HUD.containers[#HUD.containers + 1] = container
        Refresh()
    end

    -- ONE frame, and at load it listens for PLAYER_LOGIN and nothing else.
    --
    -- The setting is not safe to read while this file is executing.
    -- EllesmereUIDB is a saved variable of the EllesmereUI addon, not this
    -- one, so what is in it at our main-chunk time depends on that addon's
    -- load order and on whatever defaults or migrations it applies at login --
    -- which is exactly why CoverEnabled() has to treat a nil DB as "on". The
    -- window packs have the same problem and answer it the same way: the
    -- engine's boot frame waits for PLAYER_LOGIN, and a pack whose style is
    -- "off" simply never installs.
    --
    -- So the gate is at LOGIN and it gates the REGISTRATION, not the handler.
    -- With the feature off this frame is left with no events and no OnEvent
    -- script, the window-pack seam is never published, and not one cover is
    -- built. That makes the toggle reload-bound, and the options panel asks
    -- for the reload.
    local hudEv = CreateFrame("Frame")
    hudEv:RegisterEvent("PLAYER_LOGIN")
    hudEv:SetScript("OnEvent", function(self, event, unit)
        if event == "PLAYER_LOGIN" then
            if not CoverEnabled() then
                -- Inert from here on: nothing left to fire, nothing to skip.
                self:UnregisterAllEvents()
                self:SetScript("OnEvent", nil)
                return
            end
            HUD.installed = true
            self:UnregisterEvent("PLAYER_LOGIN")
            self:RegisterEvent("PLAYER_ENTERING_WORLD")
            self:RegisterEvent("NAME_PLATE_UNIT_ADDED")
            self:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
            self:RegisterEvent("UPDATE_UI_WIDGET")
            -- The full-refresh partner of UPDATE_UI_WIDGET: the container
            -- mixin registers BOTH, and re-processes every widget it owns on
            -- this one. Missing it left a whole set of bars unswept until
            -- something else happened to fire.
            self:RegisterEvent("UPDATE_ALL_UI_WIDGETS")
            EllesmereUI._HUDWidgetAdopt = HUDWidgetAdopt
            -- The options cog's write-through. Published on the same terms as
            -- the adopt seam -- at login, only with the feature on -- so with
            -- the reskin off it is nil and the cog is greyed out anyway.
            -- Re-reads the setting and books one refresh; SyncCover notices the
            -- floor moved and re-anchors every live cover.
            HUD.minPx = ReadMinPx()
            EllesmereUI._HUDWidgetSetMinSize = function()
                HUD.minPx = ReadMinPx()
                Refresh()
            end
            -- Looks redundant next to PLAYER_ENTERING_WORLD, which follows
            -- login and does the same two calls. Kept because it makes the
            -- install complete on its own: if the event order ever surprises
            -- us, the cost of being wrong here is the feature silently doing
            -- nothing until the first zone change, against one container walk
            -- per session for keeping it.
            Discover()
            Refresh()
        elseif event == "PLAYER_ENTERING_WORLD" then
            -- Retirement is per-instance: a bar that handed back secret data
            -- in a delve is fine again in the open world.
            wipe(HUD.retired)
            -- Plate-hosted widget bars are an OPEN-WORLD surface by decision
            -- (2026-08-16): inside instanced content the plate lane is fully
            -- off -- both plate events unregistered (they never enter Lua),
            -- the plate set empty (sweeps walk no plates), and unwalked plate
            -- containers never reach the set registry, so their widget events
            -- die at the foreign-set gate. The rare over-a-plate mechanic bar
            -- simply renders Blizzard-default in instances. Re-registering on
            -- the way out is complete on its own: every plate fires ADDED
            -- after the loading screen, so the set repopulates naturally.
            if IsInInstance() then
                self:UnregisterEvent("NAME_PLATE_UNIT_ADDED")
                self:UnregisterEvent("NAME_PLATE_UNIT_REMOVED")
                wipe(HUD.plates)
            else
                self:RegisterEvent("NAME_PLATE_UNIT_ADDED")
                self:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
            end
            Discover()
            Refresh()
        elseif event == "NAME_PLATE_UNIT_ADDED" then
            local plate = unit and C_NamePlate and C_NamePlate.GetNamePlateForUnit
                          and C_NamePlate.GetNamePlateForUnit(unit)
            if plate then
                HUD.plates[plate] = true
                Refresh()
            end
        elseif event == "NAME_PLATE_UNIT_REMOVED" then
            -- No refresh: the cover is a child of the bar's parent, so it
            -- leaves the screen with the plate on its own.
            local plate = unit and C_NamePlate and C_NamePlate.GetNamePlateForUnit
                          and C_NamePlate.GetNamePlateForUnit(unit)
            if plate then HUD.plates[plate] = nil end
        else
            -- UPDATE_UI_WIDGET / UPDATE_ALL_UI_WIDGETS. Discovery is NOT run
            -- from here: the first build of this system did, and that is
            -- precisely what caused the CPU complaint. Refresh is a flag test
            -- once the frame's pass is already booked.
            --
            -- Foreign-set gate: UPDATE_UI_WIDGET fires for EVERY widget
            -- update anywhere in the UI (tracker timers, scenario widgets,
            -- score frames), and most of those live in frames the sweep never
            -- walks -- each one bought a full container walk that could not
            -- find anything. The payload names its widget set, and Blizzard's
            -- own container gates on exactly this field, so an event whose
            -- set no swept container owns is skipped outright. Every doubt
            -- path (registry inexact, payload missing, unreadable or secret
            -- id) falls through to Refresh -- worst case is today's sweep.
            if event == "UPDATE_UI_WIDGET" and HUD.setIdsExact and unit ~= nil then
                local okS, sid = pcall(HUDGet, unit, "widgetSetID")
                if okS and sid ~= nil and not (_isSecretV and _isSecretV(sid))
                   and type(sid) == "number" and not HUD.setIds[sid] then
                    return
                end
            end
            Refresh()
        end
    end)

    ---------------------------------------------------------------------------
    --  Extra action button (ExtraActionButton1).
    --
    --  A SECURE action button: TEXTURES AND TEXCOORDS ONLY. Never Show, Hide,
    --  SetParent or SetPoint the button itself, and never write a field onto
    --  it -- all state goes in the external FFD table.
    --
    --  Blizzard's `style` texture is ~256px of brass ring around a 52px icon,
    --  and it is RE-ASSIGNED for every ability granted (each carries its own
    --  frame art), so the strip runs on OnShow, on UPDATE_EXTRA_ACTIONBAR, and
    --  on a short sweep after each. It CLEARS rather than alphas, because the
    --  button's flash animation drives alpha and would restore it.
    ---------------------------------------------------------------------------
    -- Detach every mask from a texture. ExtraActionButtonTemplate binds an
    -- IconMask to the icon, and a masked texture REJECTS SetTexCoord (hard
    -- error, swallowed by the pcall'd crop -- the icon stayed uncropped). Mask
    -- removal writes to the icon's own mask list, never the secure button.
    -- GetNumMaskTextures is SecretReturnsForAspect: reject before looping.
    local function Unmask(tex)
        if not tex or type(tex.GetNumMaskTextures) ~= "function" then return end
        local okN, n = pcall(tex.GetNumMaskTextures, tex)
        if not okN then return end
        if _isSecretV and n ~= nil and _isSecretV(n) then return end
        if type(n) ~= "number" or n <= 0 then return end
        for i = n, 1, -1 do
            local okM, m = pcall(tex.GetMaskTexture, tex, i)
            if okM and m then pcall(tex.RemoveMaskTexture, tex, m) end
        end
    end

    local function StripExtraAction()
        local btn = _G.ExtraActionButton1
        if not btn or btn:IsForbidden() then return end

        -- SCALE FIRST, ABOVE THE SKIN GATE. "Extra Action Button Size" is its
        -- own setting, and it used to sit below this gate -- so once the reskin
        -- defaulted OFF the slider would have silently done nothing for anyone
        -- on defaults. The two are independent settings and now behave that way.
        -- DEFAULT OFF (`== true`, not `~= false`): opt-in, by request. Nil means
        -- the user has never chosen, and that now means "leave Blizzard's
        -- button alone".
        if not (EllesmereUIDB and EllesmereUIDB.reskinExtraActionButton == true) then return end
        if EllesmereUI.BlizzSkinPadStandDown() then return end

        local d = GetFFD(btn)
        local style = btn.style
        if style then
            if style.SetAtlas then style:SetAtlas("") end
            if style.SetTexture then style:SetTexture("") end
            style:SetAlpha(0)
        end
        if btn.icon then
            -- Square the icon and stretch it corner to corner: with the brass
            -- ring gone the 52px art would otherwise float inside a ~256px
            -- frame. These are writes on the icon TEXTURE, never on the secure
            -- button. Re-asserted every pass (Blizzard re-arts the button per
            -- granted ability; a one-shot anchor gets clobbered silently).
            btn.icon:ClearAllPoints()
            btn.icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
            btn.icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
            -- Before the crop, never after: SetTexCoord on a masked texture
            -- throws, and the pcall around it would hide that it did nothing.
            Unmask(btn.icon)
            pcall(btn.icon.SetTexCoord, btn.icon, 0.08, 0.92, 0.08, 0.92)
        end
        if not d.border then
            -- 1px black edge on its own host frame above the icon, the same
            -- stacking every squared item tile uses. NOT AddBorder: its border
            -- container renders below same-level ARTWORK regions, and the icon
            -- stretched over the full button rect would hide the edge entirely.
            local W = WS()
            if W and W.QualityBorder then
                W.QualityBorder(btn, btn.icon or btn, 0, 0, 0)
                d.border = true
            end
        end
        -- Keybind and charge count are deliberately left in Blizzard's outlined
        -- number font: they sit over the icon, where the panel font is unreadable.
    end

    local eabEv = CreateFrame("Frame")
    local _eabUpdateHooked = false
    eabEv:RegisterEvent("PLAYER_LOGIN")
    eabEv:RegisterEvent("UPDATE_EXTRA_ACTIONBAR")
    eabEv:SetScript("OnEvent", function()
        -- Hook install is unconditional so a mid-session enable takes effect on
        -- the button's next show; the strip and its catch-up timers are gated
        -- here so the default-off state never allocates per event.
        local btn = _G.ExtraActionButton1
        if btn and not GetFFD(btn).showHook then
            GetFFD(btn).showHook = true
            btn:HookScript("OnShow", StripExtraAction)
        end
        -- ExtraActionBar_Update is where Blizzard re-arts the button (runs from
        -- ActionBarController's own UPDATE_EXTRA_ACTIONBAR handler); hooking it
        -- runs after it by construction instead of racing registration order.
        -- StripExtraAction gates on the setting at its head, so this costs one
        -- call per grant while off.
        if not _eabUpdateHooked and type(_G.ExtraActionBar_Update) == "function" then
            _eabUpdateHooked = true
            hooksecurefunc("ExtraActionBar_Update", StripExtraAction)
        end
        if not (EllesmereUIDB and EllesmereUIDB.reskinExtraActionButton == true) then return end
        if EllesmereUI.BlizzSkinPadStandDown() then return end
        StripExtraAction()
        if C_Timer then
            C_Timer.After(0, StripExtraAction)
            C_Timer.After(0.3, StripExtraAction)
        end
    end)

    ---------------------------------------------------------------------------
    --  Zone ability button (ZoneAbilityFrame).
    --
    --  Same secure rules as the extra action button: TEXTURES AND TEXCOORDS
    --  ONLY, no field writes onto the button. Three differences that matter:
    --   - the frame art is `.Style` (capital S, not `style`) and is driven by a
    --     per-zone TEXTURE KIT, so it is re-atlased on every ZONE CHANGE, not
    --     only when an ability is granted;
    --   - the buttons are POOLED into .SpellButtonContainer, so there can be
    --     several and they must be walked with EnumerateActive;
    --   - each button also carries a UI-Quickslot2 NORMAL texture -- a ~64px
    --     bevel around a 40px icon. Clearing .Style alone leaves that socket
    --     ring behind, which is most of the chrome in the screenshot.
    ---------------------------------------------------------------------------
    local function StripZoneAbility()
        local f = _G.ZoneAbilityFrame
        if not f or f:IsForbidden() then return end

        -- Shares the extra action button's toggle: both are granted-ability
        -- buttons and get identical treatment, so two settings was a
        -- distinction without a difference. DEFAULT OFF, by request.
        if not (EllesmereUIDB and EllesmereUIDB.reskinExtraActionButton == true) then return end
        if EllesmereUI.BlizzSkinPadStandDown() then return end

        local style = f.Style
        if style then
            if style.SetAtlas then style:SetAtlas("") end
            if style.SetTexture then style:SetTexture("") end
            style:SetAlpha(0)
        end

        local sc = f.SpellButtonContainer
        if not (sc and sc.EnumerateActive) then return end
        local okIter, iter = pcall(sc.EnumerateActive, sc)
        if not (okIter and iter) then return end
        for btn in iter do
            if btn and btn.IsForbidden and not btn:IsForbidden() then
                local d = GetFFD(btn)
                -- Both spellings: .NormalTexture is the parentKey, and
                -- GetNormalTexture() is the button's own accessor. They are
                -- normally the same object, but clearing whichever exists costs
                -- nothing and covers a template that only has one.
                local nt = btn.NormalTexture
                    or (btn.GetNormalTexture and btn:GetNormalTexture())
                if nt then
                    if nt.SetAtlas then nt:SetAtlas("") end
                    if nt.SetTexture then nt:SetTexture("") end
                    nt:SetAlpha(0)
                end
                if btn.Icon then
                    if not d.iconAnchored then
                        d.iconAnchored = true
                        btn.Icon:ClearAllPoints()
                        btn.Icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
                        btn.Icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
                    end
                    pcall(btn.Icon.SetTexCoord, btn.Icon, 0.08, 0.92, 0.08, 0.92)
                end
                if not d.border then
                    -- Same border as the extra action button, so the two
                    -- granted-ability buttons match. Guarded by d.border, which
                    -- matters here because these buttons are POOLED and this
                    -- runs per zone change.
                    local W = WS()
                    if W and W.QualityBorder then
                        W.QualityBorder(btn, btn.Icon or btn, 0, 0, 0)
                        d.border = true
                    end
                end
            end
        end
    end

    local zaEv = CreateFrame("Frame")
    zaEv:RegisterEvent("PLAYER_ENTERING_WORLD")
    -- The texture kit is per zone, so every zone crossing re-applies .Style.
    for _, e in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA",
                         "ZONE_CHANGED_INDOORS", "SPELLS_CHANGED" }) do
        pcall(zaEv.RegisterEvent, zaEv, e)
    end
    zaEv:SetScript("OnEvent", function()
        -- Same shape as the extra action button's handler: hooks install
        -- unconditionally (the strip self-gates at near-zero cost), the strip
        -- and its catch-up timers only run with the feature ON -- zone changes
        -- are frequent, and default-off must not allocate on every one.
        local f = _G.ZoneAbilityFrame
        if f and not GetFFD(f).zaHooks then
            GetFFD(f).zaHooks = true
            f:HookScript("OnShow", StripZoneAbility)
            -- The authoritative hook: this is the method that re-atlases
            -- .Style and refills the button pool.
            if type(f.UpdateDisplayedZoneAbilities) == "function" then
                hooksecurefunc(f, "UpdateDisplayedZoneAbilities", StripZoneAbility)
            end
        end
        if not (EllesmereUIDB and EllesmereUIDB.reskinExtraActionButton == true) then return end
        if EllesmereUI.BlizzSkinPadStandDown() then return end
        StripZoneAbility()
        if C_Timer then
            C_Timer.After(0, StripZoneAbility)
            C_Timer.After(0.3, StripZoneAbility)
        end
    end)
end)()

I.last = "HUD"
