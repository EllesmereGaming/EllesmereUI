if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- EUI_Nameplates_AuraContainers.lua
-- 12.1 aura containers for nameplates. Three engine-driven groups per
-- plate (player debuffs, enemy important buffs, crowd control), rendered
-- through a PRE-CREATED pool of container bundles: plates spawn lazily in
-- combat, but containers can only be created out of combat, so bundles are
-- built at login and attached/detached as plates come and go.
--
-- Importance: Blizzard's per-plate debuffList/buffList are taint-locked in
-- 12.1 (unreadable), but their build rule (Blizzard_NamePlateAuras) is
-- fetch HARMFUL|INCLUDE_NAME_PLATE_ONLY then keep nameplateShowPersonal
-- auras -- reproduced on the debuff group as the same fetch tokens plus a
-- { nameplateShowPersonal = true } candidate filter. "Show All Debuffs"
-- clears the candidate filter live and switches the sort to Default.
--
-- V1 deferred (documented): purge/dispel glow on buffs, pandemic glow
-- (engine has no duration-driven texture alpha -- wishlist), cast-lockout
-- offset interplay with the CC row (lockout renders independently), target
-- arrows relative to aura rows, per-slot Raise Strata on containers.

local _, ns = ...
local EllesmereUI = _G.EllesmereUI
local PP = EllesmereUI.PP

ns.NPC_OwnsAuras = true
-- Born in this module's main chunk, so the aura containers it builds bill this
-- module (AuraKit's shared build scheduler).
local AKWorker = EllesmereUI.AuraKit.NewBuildWorker()

local AK
-- Warm-cache size only, no longer a hard ceiling: container creation is
-- combat-legal since 68914 (/euit3 field PASS), so pool exhaustion queues
-- an on-demand bundle per waiting plate instead of degrading to no-auras.
-- 16 covers 5-man content with margin; raids grow within a few worker
-- frames on first exposure and the grown bundles stay pooled.
local POOL_SIZE = 16
-- Instanced-content pre-warm target: M+ trash pulls are the heaviest
-- sustained plate counts in the game (raid add waves close behind), so
-- zoning into a dungeon or raid tops the pool up to this in advance --
-- the growth ramp runs while zoning instead of on the first big pull.
local POOL_TARGET_INSTANCE = 25
local queuedBundles = 0 -- total trios ever queued (login + growth + pre-warm)
local QueueBundleBuild -- forward-declared: the attach path below grows the pool on demand

local pool = {}      -- free bundles (stack)
local active = {}    -- [plate] = bundle
local KINDS = { "debuffs", "buffs", "cc" }

-- Layout generation: bumped whenever the geometry fingerprint changes. Containers stamp
-- the generation (plus the slot they were laid out for) when their engine layout config
-- is driven; a matching stamp means the bundle-local layout state is already correct,
-- so plate attach/re-anchor passes skip the engine layout setters (each one is a dirty
-- mark that costs real engine work) and only re-run the plate-dependent SetPoint.
local geoGen = 1
local lastTargetPlate

local FP_JOIN = {}
local function FP(...)
    local n = select("#", ...)
    for i = 1, n do
        local v = select(i, ...)
        if type(v) == "number" then
            FP_JOIN[i] = string.format("%.2f", v)
        else
            FP_JOIN[i] = tostring(v)
        end
    end
    for i = n + 1, #FP_JOIN do FP_JOIN[i] = nil end
    return table.concat(FP_JOIN, "|")
end

local function PVal(key)
    local p = ns.NP_GetProfile and ns.NP_GetProfile()
    if p and p[key] ~= nil then return p[key] end
    local d = ns.NP_GetDefaults and ns.NP_GetDefaults()
    return d and d[key]
end

------------------------------------------------------------------------------
-- Styles. Duration text = our formatter-driven FontString styled like the
-- legacy cooldown countdown text; stacks mirror the legacy count strings.
-- Cropped icons are shorter than wide (legacy crop system): height and
-- vertical texcoords derive from the shared crop math.
------------------------------------------------------------------------------

local function CropCoords(cropped, zoom)
    -- Horizontal zoom 0.08 (Blizzard Style passes 0: the stock item draws the
    -- whole icon under its rounded mask, same as PAB and the unit frames).
    local z = zoom or 0.08
    if cropped then
        -- Vertical span scaled to the cropped aspect so the artwork never
        -- squishes (same math as ns.SetAuraIconCrop).
        -- `cropped` carries the height factor from GetAuraCrop (Adjust Crop
        -- slider); plain true from a legacy caller falls back to the classic
        -- 0.80, which reproduces the old fixed coords exactly (0.164/0.836).
        local factor = (type(cropped) == "number") and cropped or 0.80
        local vSpan = (1 - 2 * z) * factor
        local v0 = 0.5 - vSpan / 2
        return { z, 1 - z, v0, 1 - v0 }
    end
    return { z, 1 - z, z, 1 - z }
end

local function NPSize(kind)
    if kind == "debuffs" then return (ns.GetDebuffIconSize and ns.GetDebuffIconSize()) or 26 end
    if kind == "buffs" then return (ns.GetBuffIconSize and ns.GetBuffIconSize()) or 24 end
    return (ns.GetCCIconSize and ns.GetCCIconSize()) or 24
end

local function NPHeight(kind, size)
    local cropped = ns.GetAuraCrop and ns.GetAuraCrop(kind == "cc" and "ccs" or kind)
    if cropped and ns.GetAuraCropHeight then
        -- Second return is GetAuraCrop's value itself (the height factor,
        -- truthy) so CropCoords can derive matching texcoords; truth-testing
        -- callers behave exactly as with the old literal `true`.
        return ns.GetAuraCropHeight(cropped, size), cropped
    end
    return size, false
end

-- Legacy settings resolution for aura text -- the EXACT fallback chains
-- ApplyAppearance uses (per-kind key -> shared legacy aura* key -> defaults),
-- so 12.0 and 12.1 render identical text for any profile state.
-- kindKey = "debuff" | "buff" | "cc".
local function ProfOnly(key)
    local prof = ns.NP_GetProfile and ns.NP_GetProfile()
    return prof and prof[key]
end
local function Dflt(key)
    local d = ns.NP_GetDefaults and ns.NP_GetDefaults()
    return d and d[key]
end
local function AuraDurCfg(kindKey)
    return {
        size = ProfOnly(kindKey .. "DurationTextSize") or ProfOnly("auraDurationTextSize")
            or Dflt("auraDurationTextSize") or 11,
        x = ProfOnly(kindKey .. "DurationTextX") or ProfOnly("auraDurationTextX")
            or Dflt("auraDurationTextX") or 0,
        y = ProfOnly(kindKey .. "DurationTextY") or ProfOnly("auraDurationTextY")
            or Dflt("auraDurationTextY") or 0,
        color = ProfOnly(kindKey .. "DurationTextColor") or ProfOnly("auraDurationTextColor")
            or Dflt("auraDurationTextColor") or { r = 1, g = 1, b = 1 },
        pos = ProfOnly(kindKey .. "TimerPosition") or ProfOnly("auraTextPosition")
            or Dflt(kindKey .. "TimerPosition") or "topleft",
    }
end
local function StackCfg()
    return {
        size = PVal("auraStackTextSize") or 11,
        color = PVal("auraStackTextColor") or { r = 1, g = 1, b = 1 },
        x = PVal("auraStackTextX") or 0,
        y = PVal("auraStackTextY") or 0,
        pos = PVal("auraStackTextPosition") or "bottomright",
    }
end

-- Position -> corner/nudge/justify: a baked edge nudge per corner, the user's
-- X/Y on top.
local TEXT_POS = {
    center      = { point = "CENTER",      nx = 0,  ny = 0,  justify = "CENTER" },
    topright    = { point = "TOPRIGHT",    nx = 3,  ny = 4,  justify = "RIGHT" },
    bottomleft  = { point = "BOTTOMLEFT",  nx = -3, ny = -4, justify = "LEFT" },
    bottomright = { point = "BOTTOMRIGHT", nx = 3,  ny = -4, justify = "RIGHT" },
    topleft     = { point = "TOPLEFT",     nx = -3, ny = 4,  justify = "LEFT" },
}

-- Text pass shared by the three styles; anchors/sizes carried per style.
local function ApplyNPText(button, d, style)
    if button.SetMouseMotionEnabled then
        local motion = not style.noTooltips
        if d.npMotion ~= motion then
            d.npMotion = motion
            button:SetMouseMotionEnabled(motion)
        end
    end
    local path = (EllesmereUI.GetFontPath("nameplates")) or "Fonts\\FRIZQT__.TTF"
    if d.duration then
        local fontKey = path .. "|" .. (style.durSize or 11)
        if d.npDurFont ~= fontKey then
            d.npDurFont = fontKey
            EllesmereUI.ApplyIconTextFont(d.duration, path, style.durSize or 11, "nameplates")
        end
        local c = style.durColor
        d.duration:SetTextColor(c and c.r or 1, c and c.g or 1, c and c.b or 1)
        local m = TEXT_POS[style.durPos] or TEXT_POS.topleft
        -- Anchor change-guarded (stamp AFTER the calls): SetPoint with the
        -- button as the relative frame is policed by the 12.1 button access
        -- restriction while auras are secret; unchanged anchors must make
        -- zero button-involving calls so restyles stay live in-instance.
        local aKey = m.point .. "|" .. (m.nx + (style.durOffX or 0)) .. "|" .. (m.ny + (style.durOffY or 0))
        if d.npDurAnchor ~= aKey then
            d.duration:ClearAllPoints()
            d.duration:SetPoint(m.point, button, m.point,
                m.nx + (style.durOffX or 0), m.ny + (style.durOffY or 0))
            d.npDurAnchor = aKey
        end
        d.duration:SetJustifyH(m.justify)
        d.duration:SetShown(not style.hideDurationText)
    end
    if d.stack then
        d.stack:SetShown(style.showStacks ~= false)
        local fontKey = path .. "|" .. (style.stackSize or 11)
        if d.npStackFont ~= fontKey then
            d.npStackFont = fontKey
            EllesmereUI.ApplyIconTextFont(d.stack, path, style.stackSize or 11, "nameplates")
        end
        local sc = style.stackColor
        d.stack:SetTextColor(sc and sc.r or 1, sc and sc.g or 1, sc and sc.b or 1)
        local m = TEXT_POS[style.stackPos] or TEXT_POS.bottomright
        local sKey = m.point .. "|" .. (m.nx + (style.stackOffX or 0)) .. "|" .. (m.ny + (style.stackOffY or 0))
        if d.npStackAnchor ~= sKey then
            d.stack:ClearAllPoints()
            d.stack:SetPoint(m.point, button, m.point,
                m.nx + (style.stackOffX or 0), m.ny + (style.stackOffY or 0))
            d.npStackAnchor = sKey
        end
        d.stack:SetJustifyH(m.justify)
    end
end

-- Buffs pass: shared text styling + the purge glow. Dispellability of a SPECIFIC shown buff
-- is unreadable in restricted content -- the engine aura border that used to signal it is a
-- button call the client denies while auras are secret, so in instanced PvP a per-aura glow
-- never lit. The GROUP answers the question instead: the row renders as two engine groups
-- (see BuffFilterGlow/BuffFilterPlain) and this glow style belongs only to the dispellable
-- group, so every buff carrying it is purgeable by construction and no per-aura signal is
-- needed under any filter mode. Style and color come from the Dispel Glow options.

-- Engine tokens, declared up here because PurgeGlowActive reads DISPELLABLE
-- (a file-scope local is invisible to functions defined above it).
-- DISPELLABLE = "dispellable regardless of whether the player's raid can
-- dispel them" (Blizzard's own comment); the sibling RAID_PLAYER_DISPELLABLE
-- comment names helpful enrages on enemies as dispellable, so enrages are in.
local DISPELLABLE = AuraUtil and AuraUtil.AuraFilters and AuraUtil.AuraFilters.Dispellable
-- "helpful auras that show on enemy nameplates even if non-stealable" -- the
-- purpose-built enemy-buff curation token (source-verified 2026-08-16).
local IMPORTANT = AuraUtil and AuraUtil.AuraFilters and AuraUtil.AuraFilters.Important

-- Effective glow state: the Dispel Glow setting AND the player's offensive
-- dispel capability (the option promises "you can dispel this", and the
-- engine's class-independent DISPELLABLE token cannot answer that alone).
-- The glow stays INDEPENDENT of the Enemy Buff Filter: it styles the
-- dispellable GROUP, so under any filter mode only dispellable buffs carry
-- it. A character with no offensive dispel gets no glow; without the
-- DISPELLABLE token nothing can be claimed dispellable by anyone.
local function PurgeGlowActive()
    if not (ns.GetDispelGlow and ns.GetDispelGlow()) then return false end
    if not DISPELLABLE then return false end
    local magic, enrage = false, false
    if ns.GetOffensiveDispelTypes then magic, enrage = ns.GetOffensiveDispelTypes() end
    return magic or enrage
end

-- Buff row capability split (one table = one file-scope local; GlowSpec and
-- Apply are filled in near AddBundleBuffs, below the locals they read).
-- DISPELLABLE admits Magic buffs AND enrages, and the player rarely removes
-- both, so the glow group is cut into exact complements: "np" carries Magic
-- (includeDispelTypes), "np2" carries everything else -- which on an enemy
-- buff means an enrage (no dispelName: include rejects it, exclude keeps
-- it). Nothing is hidden by the split; only glow and color follow capability.
local NPB = {
    MAGIC = { includeDispelTypes = { Magic = true } },
    NONMAGIC = { excludeDispelTypes = { Magic = true } },
}

-- The split costs an extra engine group per plate, so take it only when the
-- halves must differ: one dispel type known and not the other, or both known
-- with per-type colors on (never for Blizzard Pandemic Border, which takes no
-- color). AND ONLY UNRESTRICTED: candidate filters read
-- auraData.dispelName, and enemy aura data is REDACTED in restricted content
-- (the documented isStealable incident above BuffCand) -- there the
-- include-Magic candidate matches nothing and every buff would fall into the
-- non-Magic group. Restricted content runs the single blanket-glow group
-- instead (exactly the unsplit behavior); the boot's PEW lane reloads when
-- restriction flips across a zone edge.
function NPB.Split()
    if not PurgeGlowActive() then return false end
    if AK and AK.AurasRestricted and AK.AurasRestricted() then return false end
    local magic, enrage = ns.GetOffensiveDispelTypes()
    if magic ~= enrage then return true end
    if ns.GetDispelGlowStyle() == EllesmereUI.Glows.PANDEMIC_BORDER then return false end
    return (ns.GetDispelGlowUseTypeColor and ns.GetDispelGlowUseTypeColor()) or false
end

-- Glow state and dispel type for glow group idx (1 = Magic, or the whole row
-- while unsplit; 2 = non-Magic). The type passes on unconditionally --
-- GetDispelGlowColor ignores it unless per-type colors are on.
function NPB.GroupGlow(idx)
    if not PurgeGlowActive() then return false, nil end
    if not NPB.Split() then return idx ~= 2, nil end
    local magic, enrage = ns.GetOffensiveDispelTypes()
    if idx == 2 then return enrage == true, "enrage" end
    return magic == true, "magic"
end

-- The glow host of an engine aura button in d[key], made on first use (in the
-- button's creation window, or by a restyle out of restriction): a child of
-- the engine button (cross-tree anchoring TO engine buttons is disallowed --
-- the dependent would inherit their forbidden aspects) covering it. Just above
-- the border, below the duration/stack text: the text carrier sits one level
-- over the border host, so slot in at carrier-1 (equal level with the border
-- host still draws the glow on top of the border, created later). Bound to
-- the button (EllesmereUI.Glows.BindEngineHost): the button itself plays the
-- glow's animations while it shows an aura and stops them whenever it has
-- none, so the hosts on hidden pooled buttons cost nothing. No prewarm:
-- StartSpecGlow makes the regions of the style it draws, so a default host
-- holds just the static border, and a later style makes its own. Made only on
-- buttons that can ever show an aura (NPGlowable).
local function NPGlowHost(button, d, key)
    local host = d[key]
    if host then return host end
    host = CreateFrame("Frame", nil, button)
    host:SetAllPoints(button)
    if d.stackCarrier then
        host:SetFrameLevel(d.stackCarrier:GetFrameLevel() - 1)
    else
        host:SetFrameLevel(button:GetFrameLevel() + 1)
    end
    host:EnableMouse(false)
    d[key] = host
    -- NPB.bound: some button plays a glow itself, so a pooled bundle's
    -- buttons are worth releasing (NPB.ReleaseGlowButtons).
    if EllesmereUI.Glows.BindEngineHost(host, button, d) then NPB.bound = true end
    return host
end

-- Whether a button gets a glow at all: only the buttons that can ever show an
-- aura (AuraKit.ButtonCanShow). Each group builds a 10-button batch but shows
-- at most its cap (5 debuffs, 1 for a one-icon group), so most pooled buttons
-- never show; skipping their glow setup keeps it out of the login build. The
-- others are dressed again when their group's cap grows (AuraKit re-runs the
-- style on them), the path an unbound host (a client whose buttons cannot run
-- animations themselves) has always taken.
local function NPGlowable(button)
    return EllesmereUI.AuraKit.ButtonCanShow(button)
end

-- Draws spec on the glow host, sized to the icon (the height follows cropped
-- icons); unchanged, StartSpecGlow returns at once. Callers pass only glowable
-- buttons; a bound host's button decides when the animations play.
local function NPStartGlow(host, spec, style)
    host:SetAlpha(1)
    local sz = style.width or 24
    EllesmereUI.Glows.StartSpecGlow(host, spec, sz, style.height or sz, "engine")
end

-- Dispel Glow on the buff row: every buff in the glow group is dispellable (the
-- group filter says so), so the glow rides the button's own visibility -- no
-- readback of per-aura state. purgeSpec is the dispel glow's full spec
-- (ns.GetDispelGlowSpec), built once per style pass. The static Blizzard
-- Border and Blizzard Pandemic Border render through the same call.
local function ApplyNPBuffExtra(button, d, style)
    ApplyNPText(button, d, style)
    if style.purgeGlow and style.purgeSpec and NPGlowable(button) then
        NPStartGlow(NPGlowHost(button, d, "npGlowHost"), style.purgeSpec, style)
    elseif d.npGlowHost then
        local host = d.npGlowHost
        if host._euiGlowActive then EllesmereUI.Glows.StopGlow(host) end
        host:SetAlpha(0)
    end
end

-- Pandemic Glow on debuff icons. The glow host is a PANDEMIC REGION of the
-- engine button: the client shows it only while the aura is in its pandemic
-- window, also under restriction, and its shown state is secret -- nothing
-- here reads it. Its animations run while the button shows an aura (the host
-- binding above) and are seen only inside the window. Off, the region is
-- cleared, so the button no longer checks the window. Blizzard's aura code
-- runs in its own environment (no global mixin to test), so the button's own
-- method is the one capability check.
local function ApplyNPDebuffExtra(button, d, style)
    ApplyNPText(button, d, style)
    local host = d.npPanHost
    if style.pandemicGlow and style.pandemicSpec and button.AddPandemicRegion and NPGlowable(button) then
        host = NPGlowHost(button, d, "npPanHost")
        if not d.npPanRegion then
            button:AddPandemicRegion(host)
            d.npPanRegion = true
        end
        NPStartGlow(host, style.pandemicSpec, style)
    elseif host then
        if d.npPanRegion then
            button:ClearPandemicRegions()
            d.npPanRegion = nil
        end
        if host._euiGlowActive then EllesmereUI.Glows.StopGlow(host) end
        host:SetAlpha(0)
    end
end

-- Custom Border on Aura Icons (auraIconCustomBorder, Border = Custom): true while the
-- aura icons wear the plate's custom border. The toggle is read first, so off it costs
-- one field read.
local function NPIconCustomBorderOn()
    return PVal("auraIconCustomBorder") == true and ns.IsCustomBorderEnabled()
end

-- The plate's custom border as an AuraKit border table. Solid sets no texture key, so
-- it rides the plain PP lane at its size or exact px; a textured style rides the
-- eight-slice lane with the nameplate registry offsets (addonKey), its step (sizeKey)
-- and exact px. Show Behind is not carried: behind the opaque icon it would vanish.
local function NPCustomIconBorder()
    local tex = PVal("customBorderTexture")
    local sz = PVal("customBorderSize") or 1
    local col = PVal("customBorderColor")
    local t = { col.r, col.g, col.b, PVal("customBorderAlpha") or 1, size = sz,
        edgePx = EllesmereUI.BorderPx(PVal("customBorderSizePx"), sz, tex) }
    if tex and tex ~= "" and tex ~= "solid" then
        t.texture, t.sizeKey, t.addonKey = tex, sz, "nameplates"
        t.offsetX, t.offsetY = PVal("customBorderOffset"), PVal("customBorderOffsetY")
        t.shiftX, t.shiftY = PVal("customBorderShiftX"), PVal("customBorderShiftY")
    end
    return t
end

local function BuildNPStyle(kind, variant)
    local size = NPSize(kind)
    local height, cropped = NPHeight(kind, size)
    -- User text settings, resolved through the legacy fallback chains, so
    -- every Duration/Stacks option (size, color, position, X/Y) renders
    -- exactly like the 12.0 aura pools.
    local kindKey = (kind == "debuffs" and "debuff") or (kind == "buffs" and "buff") or "cc"
    local dur = AuraDurCfg(kindKey)
    local stk = StackCfg()
    -- Stock styles: the whole icon (zoom 0), no EUI border (GetIconBorderEnabled
    -- is false for every kind under them). Blizzard Style: the stock nameplate
    -- aura item -- the rounded mask with the ring overlay (AuraKit
    -- blizzRoundArt). Classic WoW UI: square icons, buffs borderless, debuffs
    -- and crowd control on the engine-stamped stock dispel-type border (AuraKit
    -- blizzBorder). Text, stacks, sizes and the dispel glow all stay the user's.
    local blizz = ns.NP_Blizz()
    local classic = blizz and ns.NP_Classic()
    local harmfulClassic = (classic and kind ~= "buffs") or nil
    local style = {
        width = size,
        height = height,
        texCoord = CropCoords(cropped, blizz and 0 or nil),
        -- Off: the plain 1px black edge (plain lane); a per-kind Hide
        -- Border still wins over the custom border.
        border = (not ns.GetIconBorderEnabled or ns.GetIconBorderEnabled(kind))
            and (NPIconCustomBorderOn() and NPCustomIconBorder() or { 0, 0, 0, 1, size = 1 }) or false,
        blizzRoundArt = (blizz and not classic) or nil,
        -- The WoW Forever variant keeps that client's own ring (AuraKit
        -- paints the retail one through EllesmereUI.StockAtlas otherwise).
        blizzRoundNative = ns.NP_Forever() or nil,
        dispelBorder = harmfulClassic,
        blizzBorder = harmfulClassic,
        cooldownReverse = true,
        noDefaultFonts = true,
        noTooltips = PVal("showAuraTooltips") ~= true,
        applyExtra = ApplyNPText,
        durSize = dur.size,
        durColor = dur.color,
        durPos = dur.pos,
        durOffX = dur.x,
        durOffY = dur.y,
        -- "None" is the duration text's show/hide switch (legacy semantics:
        -- position dropdown "None" = hidden).
        hideDurationText = (dur.pos == "none"),
        -- CC icons never render stacks (legacy parity); the shared Aura
        -- Stacks position "None" hides them everywhere else.
        showStacks = (kind ~= "cc") and (stk.pos ~= "none"),
        stackSize = stk.size,
        stackColor = stk.color,
        stackPos = stk.pos,
        stackOffX = stk.x,
        stackOffY = stk.y,
    }
    -- variant: nil/1 = the dispellable glow group ("np" -- the Magic half
    -- while split), 2 = the non-Magic half ("np2", enrages), "plain" = the
    -- npnb remainder: identical text styling, NEVER the glow. Per-aura
    -- dispel type is unreadable under 12.1 secrecy, so the type is a
    -- property of the GROUP and resolves once, here, at style-build time.
    if kind == "buffs" and variant ~= "plain" then
        local glow, dispelType = NPB.GroupGlow(variant == 2 and 2 or 1)
        style.purgeGlow = glow
        style.purgeSpec = ns.GetDispelGlowSpec and ns.GetDispelGlowSpec(dispelType) or nil
        style.applyExtra = ApplyNPBuffExtra
    elseif kind == "debuffs" then
        -- Your debuffs only: the pandemic window is the time a recast keeps.
        style.pandemicGlow = ns.GetPandemicGlow()
        style.pandemicSpec = style.pandemicGlow and ns.GetPandemicGlowSpec() or nil
        style.applyExtra = ApplyNPDebuffExtra
    end
    return style
end

------------------------------------------------------------------------------
-- Bundle pool
------------------------------------------------------------------------------

local SORT_IMPORTANT, SORT_DEFAULT, SORT_DIR

-------------------------------------------------------------------------------
-- Slot filter model (Tracked Auras popup). Filter COMPOSITION is fixed
-- per aura CONTENT KIND -- debuffs = Default, dcc ("Debuffs + CC") =
-- CC + Default, cc = CC -- with no user-facing category selection. The
-- stored knobs at p.npAuraFilters: debuffs.all (the debuffs slot's Show All Debuffs
-- toggle; dcc/cc have no such mode), the debuff-side spell lists (exclude/include --
-- shared by the debuffs and dcc kinds, i.e. the debuff container), and the cc slot's
-- own lists (ccExclude/ ccInclude). The debuff container renders the dcc composition
-- when p.debuffIncludeCC is set (kind resolution is a selector; both slots can
-- coexist). debuffs.all seeds ONCE from the legacy showAllDebuffs key, which is left
-- untouched after seeding.
-------------------------------------------------------------------------------
-- Category vocabulary is deliberately just Important + Crowd Control;
-- explicit per-spell tracking goes through the include list instead.
-- Stored flags from retired categories (boss/role/raid/raidcombat/
-- dispel) persist harmlessly in old profiles -- nothing reads them.
local NPF_ORDER = { "cc" } -- token-category ownership order (DM parity)
local NPF_TOKENS = {
    cc = { "HARMFUL", "CROWD_CONTROL" }, -- any caster, matching the cc feed
}
local NPF_NEG = { cc = "!CROWD_CONTROL" }
-- Boolean categories: Important = nameplateShowPersonal (nameplate-native
-- importance -- the pre-filter default display, NOT the raid-frame
-- isPriorityAura list; user-confirmed zero-drift mapping).
local NPF_BOOL = { priority = "nameplateShowPersonal" }

-- The internal per-kind composition (see the model comment above).
local NPF_VIEW = {
    debuffs = { all = false, f = { priority = true } },
    dcc     = { all = false, f = { cc = true, priority = true } },
    cc      = { all = false, f = { cc = true } },
}

function ns.NPF_Root()
    local p = ns.NP_GetProfile and ns.NP_GetProfile()
    if not p then return nil end
    local t = p.npAuraFilters
    if not t then
        t = { debuffs = { all = PVal("showAllDebuffs") == true }, fv3 = true }
        p.npAuraFilters = t
    elseif not t.fv3 then
        -- One-shot (per profile, first touch): category selections moved
        -- from stored per-kind sets to the internal composition above --
        -- clear them, keep Show All and both spell lists (existing lists
        -- become the debuff side; the cc side starts empty).
        t.debuffs = { all = (t.debuffs and t.debuffs.all == true) or false }
        t.cc = nil
        t.dcc = nil
        t.fv2 = nil
        t.fv3 = true
    end
    return t
end

-- Read-only per-kind VIEW (static tables, no per-call allocation):
-- callers treat the result as immutable and never retain it across
-- frames. Show All writes go through ns.NPF_Root().debuffs.all -- only
-- the debuffs kind has that mode, so the view pins all = false for
-- dcc/cc.
function ns.NPF_Config(kind)
    local t = ns.NPF_Root()
    local v = t and NPF_VIEW[kind]
    if not v then return nil end
    v.all = (kind == "debuffs") and (t.debuffs and t.debuffs.all == true) or false
    return v
end

-- Record synthesis for one kind config: token categories own overlaps in NPF_ORDER
-- order (each negates the ENABLED tokens above it -- negating disabled ones would eat
-- their auras); boolean categories negate every enabled token. Show All returns no
-- records: the plain "np" group is the whole display then. Booleans can never be
-- negated (engine positive-only history); a boolean x boolean overlap double-renders
-- -- accepted, DM precedent.
local function NPF_Records(cfg)
    local recs = {}
    if not cfg or cfg.all then return recs end
    local f = cfg.f or {}
    for i = 1, #NPF_ORDER do
        local cat = NPF_ORDER[i]
        if f[cat] then
            local toks = {}
            for k = 1, #NPF_TOKENS[cat] do toks[#toks + 1] = NPF_TOKENS[cat][k] end
            for j = 1, i - 1 do
                local hc = NPF_ORDER[j]
                if f[hc] then toks[#toks + 1] = NPF_NEG[hc] end
            end
            recs[#recs + 1] = { cat = cat, tokens = toks }
        end
    end
    for cat, boolField in pairs(NPF_BOOL) do
        if f[cat] then
            local toks = { "HARMFUL", "PLAYER", "INCLUDE_NAME_PLATE_ONLY", "!CROWD_CONTROL" }
            for i = 2, #NPF_ORDER do
                local tc = NPF_ORDER[i]
                if f[tc] then toks[#toks + 1] = NPF_NEG[tc] end
            end
            recs[#recs + 1] = { cat = cat, tokens = toks, cand = { [boolField] = true } }
        end
    end
    return recs
end

-- Stable per-record group key: category + a hash of the negation-relevant
-- enabled set. A filter edit that changes the chain declares the NEW
-- variant and parks the old one at 0 (group filter strings are fixed).
local function NPF_GKey(cat, cfg)
    local f = cfg.f or {}
    return "npf:" .. cat .. "|" .. (f.cc and 1 or 0)
end

-- Filter-state fingerprint for the reload cfg pass. The per-kind compositions are
-- internal constants now, so the ONLY inputs are the debuffs slot's Show All flag and
-- the four spell lists (list edits must re-drive every group's candidates).
function ns.NPF_FP()
    local t = ns.NPF_Root()
    local parts = {}
    parts[1] = (t and t.debuffs and t.debuffs.all == true) and "A" or "-"
    local function ListPart(prefix, list)
        if list and next(list) ~= nil then
            local o = {}
            for id, v in pairs(list) do
                -- Disabled entries prefix "-" (all strings: mixed-type sort errors)
                o[#o + 1] = (v and "" or "-") .. id
            end
            table.sort(o)
            parts[#parts + 1] = prefix .. table.concat(o, ",")
        end
    end
    ListPart("x", ns.NPF_Exclude("debuff"))
    ListPart("n", ns.NPF_Include("debuff"))
    ListPart("cx", ns.NPF_Exclude("cc"))
    ListPart("cn", ns.NPF_Include("cc"))
    -- Any-caster opt-outs are re-drive inputs too: they move ids between
    -- the npinc and npincmine groups (a memo missing an input is a
    -- correctness bug -- toggling MINE must not no-op the reload).
    ListPart("na", ns.NPF_IncludeAny("debuff"))
    ListPart("cna", ns.NPF_IncludeAny("cc"))
    return table.concat(parts, ";")
end

-- The debuff container renders the dcc config when the combined
-- "Debuffs + CC" element is assigned (p.debuffIncludeCC), else debuffs.
local function NPF_DebuffKind()
    return PVal("debuffIncludeCC") and "dcc" or "debuffs"
end

local function DebuffSort()
    local c = ns.NPF_Config(NPF_DebuffKind())
    local all = c and c.all
    if all == nil then all = PVal("showAllDebuffs") end -- pre-seed fallback
    if all then return SORT_DEFAULT end
    return SORT_IMPORTANT
end

-- Debuff importance: Blizzard's 12.1 nameplate rule (Blizzard_NamePlateAuras
-- AddAura) is fetch HARMFUL|INCLUDE_NAME_PLATE_ONLY, then keep only auras
-- flagged nameplateShowPersonal -- that flag IS the "useful debuff" gate that
-- fed the legacy debuffList. INCLUDE_NAME_PLATE_ONLY alone is INCLUSIVE
-- (adds nameplate-only auras to candidacy, does not restrict); the candidate
-- boolean does the narrowing and toggles live. "Show All Debuffs" clears it
-- (empty table, never nil: the setter must REPLACE the stored filter).
-- Nameplate debuff blacklists (Tracked Auras popup, EXCLUDED column):
-- one list per SIDE -- the debuff container's (shared by the debuffs
-- and dcc kinds, so a slot flipping between Debuffs and Debuffs + CC
-- keeps its exclusions) and the cc slot's own. spellID excludes are
-- identity-legal on hostile units (harmful-on-attackable passes the
-- gate), so these are real engine filters, not Lua scans.
function ns.NPF_Exclude(side)
    local t = ns.NPF_Root()
    if not t then return nil end
    local key = (side == "cc") and "ccExclude" or "exclude"
    if not t[key] then t[key] = {} end
    return t[key]
end

-- Include lists (Tracked Auras popup, INCLUDED column): same tri-state
-- shape and side split as the exclude lists (true = active, false =
-- kept but disabled, nil = deleted). Included spells render through
-- their side's own groups ("npinc" any-caster, "npincmine" own-cast for
-- entries flagged Only My Casts; NPF_ApplyContainer) and are excluded from
-- every other group's candidates on that container, so a spell that also matches the
-- slot's composition (or Show All) can never double-render.
function ns.NPF_Include(side)
    local t = ns.NPF_Root()
    if not t then return nil end
    local key = (side == "cc") and "ccInclude" or "include"
    if not t[key] then t[key] = {} end
    return t[key]
end

-- Any-caster OPT-OUTS for include entries (default is Only My Casts): a
-- SIBLING map keyed by spell id, not a fourth tri-state value -- every
-- `v == true` reader of the include list stays valid, and the flag
-- survives disable/re-enable cycles.
function ns.NPF_IncludeAny(side)
    local t = ns.NPF_Root()
    if not t then return nil end
    local key = (side == "cc") and "ccIncludeAnyCaster" or "includeAnyCaster"
    if not t[key] then t[key] = {} end
    return t[key]
end

-- Debuffs the player can stack MANY copies of on one target under one spell
-- id (Blood Plague from weapon copies / guardians): the debuff container shows
-- each of them at most ONCE. The engine has no dedup primitive and Lua cannot
-- see auras under restriction, so each id gets its own single-frame group
-- (includeSpellIDs = that id, maxFrameCount 1: the engine keeps the top sorted
-- candidate) and is excluded from every other debuff-side group. Hardcoded
-- exception list, PLAYER-cast only, debuff container only.
local NPF_ONCE_DEBUFFS = {
    [55078] = true,   -- Blood Plague
}

-- WoW Forever: Sunder Armor is one debuff per target that every warrior's
-- casts stack onto, so it renders from any caster. Each rank is its own id.
local NPF_SUNDER_IDS = {
    [7386] = true, [7405] = true, [8380] = true, [11596] = true, [11597] = true,
}
local _, playerClass = UnitClass("player")
local function NPF_SunderOn()
    return EllesmereUI.IS_FOREVER and playerClass == "WARRIOR"
        and PVal("showSunderArmor") == true
end

-- Active-only include maps for engine candidates (false entries stay
-- stored but must never reach the C validator). Two maps: any-caster
-- opt-outs feed the npinc group, everything else (the default) feeds
-- npincmine (its filter string carries the PLAYER token -- the caster
-- restriction lives in the token vocabulary, not in candidate booleans).
local function NPF_ActiveIncludes(side)
    local inc = ns.NPF_Include(side)
    if not inc then return nil, nil end
    local anym = ns.NPF_IncludeAny(side)
    local m, mm
    for id, v in pairs(inc) do
        if v then
            if anym and anym[id] then
                m = m or {}; m[id] = true
            else
                mm = mm or {}; mm[id] = true
            end
        end
    end
    return m, mm
end

-- Candidate-table builder: the blacklist rides EVERY debuff-side group
-- (records and Show All alike) as excludeSpellIDs; extra = a record's own
-- boolean fields, copied so the stored config never aliases engine tables.
-- Exclude entries are tri-state now (true = active, false = kept but
-- disabled via the popup checkbox, nil = deleted): the engine map gets an
-- ACTIVE-ONLY copy -- a false value must not reach the C validator.
local function NPF_Cand(extra, side)
    local cand = {}
    if extra then
        for k, v in pairs(extra) do cand[k] = v end
    end
    local m
    local ex = ns.NPF_Exclude(side)
    if ex then
        for id, v in pairs(ex) do
            if v then
                m = m or {}
                m[id] = true
            end
        end
    end
    -- Active INCLUDES are excluded here too: the npinc/npincmine groups own
    -- their display (active in every mode), so every category / Show All
    -- group must not render its own copy.
    local incm, incmm = NPF_ActiveIncludes(side)
    if incm then
        m = m or {}
        for id in pairs(incm) do m[id] = true end
    end
    if incmm then
        m = m or {}
        for id in pairs(incmm) do m[id] = true end
    end
    -- Show-once exceptions render through their own single-frame groups
    -- (debuff side only, while the option is on), so no other group may
    -- render a copy. Option off = the id is an ordinary debuff again.
    if side ~= "cc" and PVal("hideBloodPlagueCopies") ~= false then
        for id in pairs(NPF_ONCE_DEBUFFS) do
            m = m or {}
            m[id] = true
        end
    end
    if side ~= "cc" and NPF_SunderOn() then
        for id in pairs(NPF_SUNDER_IDS) do
            m = m or {}
            m[id] = true
        end
    end
    if m then cand.excludeSpellIDs = m end
    return cand
end

-- The "np" debuff group is the SHOW ALL group only now: filtered display renders
-- through the NPF record groups (priority included -- the fixed np filter string cannot
-- carry the dedup negation chains). Its candidate set carries only the blacklist; the
-- all-flag drives its COUNT in the ensure pass.
local function DebuffCand()
    return NPF_Cand(nil, "debuff")
end

-- Declares/parks one container's NPF record groups per its kind config.
-- Declares are combat-legal (68914); stale variants park at 0 (group
-- strings are fixed; frames are never freed -- parked groups are the
-- cheap state). On the CC container the cc CATEGORY rides the existing
-- "np" group -- its filter string (HARMFUL|CROWD_CONTROL) is identical,
-- so the default config costs zero extra groups.
local function NPF_ApplyContainer(container, kindKey, styleKey, cap)
    if not container then return end
    local cfg = ns.NPF_Config(kindKey)
    if not cfg then return end
    local f = cfg.f or {}
    -- List side: the cc container has its own lists; the debuff
    -- container (kinds debuffs/dcc) shares the debuff-side pair.
    local side = (kindKey == "cc") and "cc" or "debuff"
    local declared = container._npfGroups
    if not declared then declared = {}; container._npfGroups = declared end
    -- Mid-session declares on a container already bound to a live unit need an
    -- explicit parse request at the end: FinishContainer's UpdateAllAuras ran
    -- long ago, and a group added after it renders nothing until the next
    -- SetUnit (pooled re-attach) otherwise.
    local declaredNew = false
    local wanted = {}
    if not cfg.all then
        local recs = NPF_Records(cfg)
        for i = 1, #recs do
            local rec = recs[i]
            if not (kindKey == "cc" and rec.cat == "cc") then
                local gkey = NPF_GKey(rec.cat, cfg)
                wanted[gkey] = true
                if not declared[gkey] then
                    AK.AddGroupToContainer(container, {
                        key = gkey, filter = rec.tokens, maxFrameCount = cap,
                        candidateFilters = NPF_Cand(rec.cand, side), sortMethod = SORT_IMPORTANT,
                        style = styleKey,
                        layout = { elementWidth = 24, elementHeight = 24,
                                   elementSpacing = 4, lineSpacing = 4 },
                    })
                    declared[gkey] = true
                    declaredNew = true
                else
                    EllesmereUI.AuraKit.SetGroupCap(container, gkey, cap)
                    container:SetAuraGroupCandidateFilters(gkey, NPF_Cand(rec.cand, side))
                end
            end
        end
    end
    -- Show-once exceptions (NPF_ONCE_DEBUFFS): one single-frame PLAYER-cast
    -- group per id ("nponce:<id>"), includeSpellIDs = that id, maxFrameCount 1
    -- -- the engine keeps the top sorted candidate and drops the rest, which
    -- is the whole dedup. Debuff container only, and only while the option is
    -- on and the id is not blacklisted in Tracked Auras -- otherwise the group
    -- is simply not wanted (an existing one parks to 0 in the loop below; a
    -- never-declared one costs nothing). Every other debuff-side group
    -- excludes these ids while on (NPF_Cand), so this group is the sole renderer.
    if side ~= "cc" and PVal("hideBloodPlagueCopies") ~= false then
        local ex = ns.NPF_Exclude(side)
        for id in pairs(NPF_ONCE_DEBUFFS) do
            if not (ex and ex[id]) then
                local gkey = "nponce:" .. id
                wanted[gkey] = true
                if not declared[gkey] then
                    AK.AddGroupToContainer(container, {
                        key = gkey, filter = { "HARMFUL", "PLAYER", "INCLUDE_NAME_PLATE_ONLY" },
                        maxFrameCount = 1,
                        candidateFilters = { includeSpellIDs = { [id] = true } },
                        sortMethod = SORT_IMPORTANT, style = styleKey,
                        layout = { elementWidth = 24, elementHeight = 24,
                                   elementSpacing = 4, lineSpacing = 4 },
                    })
                    declared[gkey] = true
                    declaredNew = true
                else
                    EllesmereUI.AuraKit.SetGroupCap(container, gkey, 1)
                end
            end
        end
    end
    -- Sunder Armor (Forever warriors, opt-in): any caster, one icon. Ids the
    -- user already lists in Tracked Auras keep going through those lists.
    if side ~= "cc" and NPF_SunderOn() then
        local ex, inc = ns.NPF_Exclude(side), ns.NPF_Include(side)
        local ids
        for id in pairs(NPF_SUNDER_IDS) do
            if not (ex and ex[id]) and not (inc and inc[id]) then
                ids = ids or {}
                ids[id] = true
            end
        end
        if ids then
            wanted.npsunder = true
            if not declared.npsunder then
                AK.AddGroupToContainer(container, {
                    key = "npsunder", filter = { "HARMFUL", "INCLUDE_NAME_PLATE_ONLY" },
                    maxFrameCount = 1,
                    candidateFilters = { includeSpellIDs = ids },
                    sortMethod = SORT_IMPORTANT, style = styleKey,
                    layout = { elementWidth = 24, elementHeight = 24,
                               elementSpacing = 4, lineSpacing = 4 },
                })
                declared.npsunder = true
                declaredNew = true
            else
                container:SetAuraGroupCandidateFilters("npsunder", { includeSpellIDs = ids })
                EllesmereUI.AuraKit.SetGroupCap(container, "npsunder", 1)
            end
        end
    end
    for gkey in pairs(declared) do
        if gkey ~= "npinc" and gkey ~= "npincmine" and not wanted[gkey] then
            EllesmereUI.AuraKit.SetGroupCap(container, gkey, 0)
        end
    end
    local npOn
    if kindKey == "cc" then
        npOn = cfg.all or f.cc or false
    else
        npOn = cfg.all or false
    end
    -- Blacklist on the np group too (both containers; the debuff cfg pass
    -- also re-drives this -- same values, dirty-mark cheap).
    container:SetAuraGroupCandidateFilters("np", NPF_Cand(nil, side))
    EllesmereUI.AuraKit.SetGroupCap(container, "np", npOn and cap or 0)
    -- Include list (Tracked Auras popup): the side's own groups on this
    -- container. They stay ACTIVE in every mode, Show All included -- the
    -- np group's fixed filter string is PLAYER-cast (and !CROWD_CONTROL on
    -- the debuff container), so an included spell cast by someone else or
    -- flagged CC can only render here; every other group excludes the
    -- included ids via NPF_Cand. Candidates re-drive live; count follows
    -- whether any entry is active. Two groups because caster scope lives
    -- in the filter STRING (fixed at declaration): npinc = any caster,
    -- npincmine = PLAYER token for entries flagged Only My Casts.
    local incm, incmm = NPF_ActiveIncludes(side)
    if incm and not declared.npinc then
        AK.AddGroupToContainer(container, {
            key = "npinc", filter = { "HARMFUL", "INCLUDE_NAME_PLATE_ONLY" },
            maxFrameCount = cap,
            candidateFilters = { includeSpellIDs = incm },
            sortMethod = SORT_IMPORTANT, style = styleKey,
            layout = { elementWidth = 24, elementHeight = 24,
                       elementSpacing = 4, lineSpacing = 4 },
        })
        declared.npinc = true
        declaredNew = true
    elseif declared.npinc then
        if incm then
            container:SetAuraGroupCandidateFilters("npinc", { includeSpellIDs = incm })
        end
        EllesmereUI.AuraKit.SetGroupCap(container, "npinc", incm and cap or 0)
    end
    if incmm and not declared.npincmine then
        AK.AddGroupToContainer(container, {
            key = "npincmine",
            filter = { "HARMFUL", "PLAYER", "INCLUDE_NAME_PLATE_ONLY" },
            maxFrameCount = cap,
            candidateFilters = { includeSpellIDs = incmm },
            sortMethod = SORT_IMPORTANT, style = styleKey,
            layout = { elementWidth = 24, elementHeight = 24,
                       elementSpacing = 4, lineSpacing = 4 },
        })
        declared.npincmine = true
        declaredNew = true
    elseif declared.npincmine then
        if incmm then
            container:SetAuraGroupCandidateFilters("npincmine", { includeSpellIDs = incmm })
        end
        EllesmereUI.AuraKit.SetGroupCap(container, "npincmine", incmm and cap or 0)
    end
    -- One parse covers every group declared this pass. Only for containers
    -- bound to a live unit (BindContainer's stamp): at pool build the unit
    -- is "none" and the attach-time SetUnit/UpdateAllAuras pair owns it.
    if declaredNew and container._npcBoundUnit then
        container:UpdateAllAuras()
    end
end

local function NPF_EnsureRecords(b)
    NPF_ApplyContainer(b.containers.debuffs, NPF_DebuffKind(), "np:debuffs",
        PVal("maxDebuffs") or 5)
    NPF_ApplyContainer(b.containers.cc, "cc", "np:cc", 2)
end

-- Bundle construction is split into one job per container for the shared AuraKit build
-- scheduler: each container's group is a 10-button engine batch (~4-6ms), and a whole
-- bundle in one gulp was a per-frame spike during the post-login pool build.
local function CreateBundleShell()
    local holder = CreateFrame("Frame", nil, UIParent)
    holder:Hide()
    holder:SetSize(1, 1)
    holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", -200, -200)

    return { holder = holder, containers = {} }
end

-- Builds one bundle container from a pre-born shell when available (group add + finish
-- are combat-legal -- probe T1/T1b), else creates fresh (OOC only; the callers guard).
local function BundleContainer(b, kind, groupSpec)
    -- Single spec (has .key) or an ARRAY of specs (the buffs container's
    -- glow/plain group pair).
    local specs = groupSpec[1] and groupSpec or { groupSpec }
    local shell = b.shells and b.shells[kind]
    if shell then
        b.shells[kind] = nil
        for i = 1, #specs do AK.AddGroupToContainer(shell, specs[i]) end
        AK.FinishContainer(shell, "none")
        return shell
    end
    return (AK.CreateContainer(b.holder, "none", {
        point = { "CENTER", b.holder, "CENTER" },
        groups = specs,
    }))
end

-- Enemy buff narrowing belongs in the FILTER STRING, not in candidateFilters. A candidate
-- filter is a Lua compare against auraData.isStealable, and aura data on an enemy unit is
-- SECRET in instanced PvP: there "isStealable ~= true" is true for every buff, so the group
-- renders nothing. (Blizzard's own nameplate rule survives the same secrecy only because it
-- tests "== false" -- an unreadable aura is kept, not dropped.) DISPELLABLE is evaluated by
-- the engine in C, like every filter string, so it stays plain under restriction -- which is
-- also why the debuff row never broke. Clients predating the token keep the old candidate
-- filter: no worse than before, and PvE is unaffected either way.
-- DISPELLABLE and IMPORTANT are declared up top, next to PurgeGlowActive --
-- which reads DISPELLABLE and is defined far above this point (a file-scope
-- local would be invisible to it down here).

-- Enemy Buff Filter mode (npEnemyBuffFilter): "important" is the retail
-- DEFAULT (the retired showAllEnemyBuffs key is an inert orphan, never
-- migrated and never read; the removed "all" value normalizes to important
-- the same way), "showall" the WoW Forever one (defaults table).
-- UNION SEMANTICS: a single filter string ANDs its tokens, so the OR lives in
-- the group split. TWO groups render the row:
-- "np" = ALL dispellable buffs (purgeables AND enrages -- the engine's
-- DISPELLABLE token is class-independent; this group carries the dispel glow
-- style), "npnb" = the non-dispellable remainder (plain style; !DISPELLABLE
-- keeps the union overlap-free), narrowed to IMPORTANT in Important mode and
-- whole in Show All mode, parked at 0 in Dispellable mode. Important mode
-- therefore shows important OR dispellable, Show All every buff, and
-- Dispellable the glow group alone. All are composed filter STRINGS with
-- INCLUDE_NAME_PLATE_ONLY (matches Blizzard's own buffFilterString) --
-- C-evaluated, so the split holds on secret enemy data in instanced PvP and
-- the glow needs no per-aura signal (the machinery #1509 deleted). The
-- Dispel Glow setting never touches these filters -- it is only the style
-- the "np" group wears, so every shown dispellable buff glows.
local function BuffMode()
    local m = PVal("npEnemyBuffFilter")
    if m == "dispellable" or m == "showall" then return m end
    return "important"
end

local function BuffFilterGlow()
    local t = { "HELPFUL", "INCLUDE_NAME_PLATE_ONLY" }
    -- Stale-client shape only: without the DISPELLABLE token the union cannot
    -- be expressed, so Important mode keeps the old curated single group.
    if BuffMode() == "important" and IMPORTANT and not DISPELLABLE then t[#t + 1] = IMPORTANT end
    if DISPELLABLE then t[#t + 1] = DISPELLABLE end
    return t
end

-- nil = the plain group has nothing to show (Dispellable mode, or a client
-- without the DISPELLABLE token, where no complement can be expressed).
-- Important narrows the remainder to IMPORTANT; Show All keeps all of it.
local function BuffFilterPlain()
    local mode = BuffMode()
    if mode == "dispellable" or not DISPELLABLE then return nil end
    local t = { "HELPFUL", "INCLUDE_NAME_PLATE_ONLY" }
    if mode == "important" and IMPORTANT then t[#t + 1] = IMPORTANT end
    t[#t + 1] = "!" .. DISPELLABLE
    return t
end

-- Stale-client fallback only (no DISPELLABLE token): the old isStealable
-- candidate approximates the glow group's narrowing.
local function BuffCand()
    if DISPELLABLE then return nil end
    return { isStealable = true }
end

local function AddBundleDebuffs(b)
    b.containers.debuffs = BundleContainer(b, "debuffs", {
        key = "np",
        filter = { "HARMFUL", "PLAYER", "INCLUDE_NAME_PLATE_ONLY", "!CROWD_CONTROL" },
        maxFrameCount = PVal("maxDebuffs") or 5,
        sortMethod = DebuffSort(),
        candidateFilters = DebuffCand(),
        style = "np:debuffs",
        layout = { elementWidth = 26, elementHeight = 26, elementSpacing = 4, lineSpacing = 4 },
    })
end

-- One glow-group spec. idx 1 is the whole dispellable row while unsplit and
-- the Magic half while split; idx 2 is the non-Magic (enrage) half, declared
-- only while the split is on (it parks at 0 frames afterwards -- groups are
-- never removed). Both halves share the mode's filter STRING; only the
-- candidate differs.
function NPB.GlowSpec(idx)
    local styleKey = (idx == 2) and "np:buffs2" or "np:buffs"
    local cand
    if NPB.Split() then
        cand = (idx == 2) and NPB.NONMAGIC or NPB.MAGIC
    else
        cand = BuffCand()
    end
    return {
        key = (idx == 2) and "np2" or "np",
        filter = BuffFilterGlow(),
        maxFrameCount = 4,
        sortMethod = SORT_IMPORTANT,
        candidateFilters = cand,
        style = styleKey,
        -- Purge glow: built on first paint so a button born while the glow
        -- is already on does not wait for the next style pass.
        extraInit = function(btn, dd)
            local style = AK.styles[styleKey]
            if style and style.purgeGlow then
                ApplyNPBuffExtra(btn, dd, style)
            end
        end,
        layout = { elementWidth = 24, elementHeight = 24, elementSpacing = 4, lineSpacing = 4 },
    }
end

-- Declares or parks the non-Magic glow group to match the current split, on
-- containers that already existed when capability / restriction / the type
-- color option / the dispel glow style changed.
function NPB.Apply(container)
    if not container then return end
    local split = NPB.Split()
    if split and not container._npbSplit then
        AK.AddGroupToContainer(container, NPB.GlowSpec(2))
        container._npbSplit = true
        -- The new group carries the declaration's placeholder sizing until an
        -- anchor pass reaches it, and that pass skips containers whose layout
        -- stamp is current -- so drop the stamp.
        container._npcGeoGen = nil
        -- A group added after FinishContainer's parse renders nothing until
        -- the next SetUnit unless this container is asked to re-parse now.
        if container._npcBoundUnit then container:UpdateAllAuras() end
    elseif container._npbSplit then
        EllesmereUI.AuraKit.SetGroupCap(container, "np2", split and 4 or 0)
    end
end

local function AddBundleBuffs(b)
    -- Glow group(s) + plain remainder (BuffMode doctrine above): the
    -- dispellable set carries the dispel glow style (split by dispel type
    -- while NPB.Split holds), the important remainder renders plain.
    -- Declaration is add-only, so the plain group is ALWAYS declared (a mode
    -- flip needs it live) and parked at 0 while the mode has no remainder.
    -- Display order: Magic, then enrages, then plain; important-sorted
    -- within each group.
    local plainToks = BuffFilterPlain()
    local plainDecl = plainToks
    if not plainDecl then
        plainDecl = { "HELPFUL", "INCLUDE_NAME_PLATE_ONLY" }
        if DISPELLABLE then plainDecl[#plainDecl + 1] = "!" .. DISPELLABLE end
    end
    local specs = { NPB.GlowSpec(1) }
    if NPB.Split() then specs[#specs + 1] = NPB.GlowSpec(2) end
    specs[#specs + 1] = {
        key = "npnb",
        filter = plainDecl,
        maxFrameCount = plainToks and 4 or 0,
        sortMethod = SORT_IMPORTANT,
        style = "np:buffsplain",
        layout = { elementWidth = 24, elementHeight = 24, elementSpacing = 4, lineSpacing = 4 },
    }
    b.containers.buffs = BundleContainer(b, "buffs", specs)
    if #specs > 2 then b.containers.buffs._npbSplit = true end
end

local function AddBundleCC(b)
    b.containers.cc = BundleContainer(b, "cc", {
        key = "np",
        filter = { "HARMFUL", "CROWD_CONTROL" },
        maxFrameCount = 2,
        sortMethod = SORT_DEFAULT,
        style = "np:cc",
        layout = { elementWidth = 24, elementHeight = 24, elementSpacing = 4, lineSpacing = 4 },
    })
end

-- A skeleton = holder + three bare container shells, born in the early
-- load window (PLAYER_LOGIN precedes combat re-engagement on every reload
-- path -- the suite's positioning trick). All later bundle work is then
-- combat-legal group adds/finishes.
local function CreateBundleSkeleton()
    local b = CreateBundleShell()
    b.shells = {
        debuffs = AK.CreateContainerShell(b.holder, { point = { "CENTER", b.holder, "CENTER" } }),
        buffs   = AK.CreateContainerShell(b.holder, { point = { "CENTER", b.holder, "CENTER" } }),
        cc      = AK.CreateContainerShell(b.holder, { point = { "CENTER", b.holder, "CENTER" } }),
    }
    return b
end
local skeletons = {}

local function SafeClearUnit(container)
    if not pcall(container.SetUnit, container, "none") then
        pcall(container.SetUnit, container, nil)
    end
end

-- Unit binding follows the SLOT setting: a container whose slot is "none" stays parked
-- on unit "none" and costs nothing -- SetUnit/UpdateAllAuras are synchronous engine
-- parses billed to this addon, and plates churn constantly in combat, so binding all
-- three containers unconditionally charged the full parse three times per spawn
-- regardless of how many rows are actually displayed. Detach clears the flag, so a
-- pooled bundle always re-binds fresh at its next attach.
local function BindContainer(c, unit, slotVal)
    if not c then return end -- conditional bundles: row disabled at build time
    if slotVal and slotVal ~= "none" then
        if not c._npcBoundUnit then
            c._npcBoundUnit = true
            c:SetUnit(unit)
            c:UpdateAllAuras()
        end
    elseif c._npcBoundUnit then
        c._npcBoundUnit = nil
        SafeClearUnit(c)
    end
end

------------------------------------------------------------------------------
-- Anchoring: each aura slot's placement, with container flow.
-- top/bottom center-pin (self-centering rows); left/right chain outward
-- from the health bar; topleft/topright corner-pin with per-slot growth.
------------------------------------------------------------------------------

local function FlowDir(token)
    local FD = AnchorUtil.FlowDirection
    if token == "LEFT" then return FD.Left end
    if token == "UP" then return FD.Up end
    if token == "DOWN" then return FD.Down end
    return FD.Right
end

local function TopAnchorFor(plate)
    local topElement = (ns.GetTextSlot and ns.GetTextSlot("textSlotTop")) or "none"
    if ns.IsNameElement and ns.IsNameElement(topElement) then return plate.name or plate.health end
    if topElement == "healthNumber" then return plate.hpNumber or plate.health end
    if topElement == "level" then return plate.levelText or plate.health end
    if topElement == "targetOfTarget" then return plate.totText or plate.health end
    if topElement ~= "none" then return plate.hpText or plate.health end
    return plate.health, true -- health-anchored: add class power push
end

local function AnchorNPContainer(container, kind, plate, slotVal)
    if not container then return end
    container:ClearAllPoints()
    if not slotVal or slotVal == "none" then
        container:SetShown(false)
        return
    end
    container:SetShown(kind ~= "buffs" or container._npcAttackable ~= false)

    local size = NPSize(kind)
    local height = NPHeight(kind, size)
    local spacing = (ns.GetAuraSpacing and ns.GetAuraSpacing(kind == "cc" and "ccs" or kind)) or 4
    local xOff, yOff = 0, 0
    if ns.GetAuraSlotOffsets then
        xOff, yOff = ns.GetAuraSlotOffsets(kind == "debuffs" and "debuffSlot"
            or kind == "buffs" and "buffSlot" or "ccSlot")
    end

    local anchorPoint, gH, gV, rowWidth
    if slotVal == "top" then
        local anchor, healthAnchored = TopAnchorFor(plate)
        local debuffY = (ns.GetDebuffYOffset and ns.GetDebuffYOffset()) or 2
        local cpPush = (healthAnchored and ns.NP_ClassPowerTopPush) and ns.NP_ClassPowerTopPush(plate) or 0
        container:SetPoint("BOTTOM", anchor, "TOP", xOff, debuffY + cpPush + yOff)
        anchorPoint, gH, gV = "BOTTOMLEFT", "RIGHT", "UP"
    elseif slotVal == "bottom" then
        container:SetPoint("TOP", plate.cast or plate.health, "BOTTOM", xOff, -2 + yOff)
        anchorPoint, gH, gV = "TOPLEFT", "RIGHT", "DOWN"
    elseif slotVal == "left" or slotVal == "right" then
        -- Classic WoW UI: gap off the border art, not the bare bar edge; WoW
        -- Forever's level box on the right (ns.NP_ClassicSide, 0 on every other
        -- style). During a cast the full-size spell icon pushes the row out past
        -- it where the two meet (the row spans its Y offset up by one icon);
        -- the push is kept for NPC_PlaceSideRows.
        local push = ns.NP_FullIconPush(plate, slotVal, yOff, yOff + height)
        container._npcPush = push
        local sideOff = ((ns.GetSideAuraXOffset and ns.GetSideAuraXOffset()) or 2)
            + ((ns.NP_ClassicSide and ns.NP_ClassicSide(slotVal)) or 0) + push
        if slotVal == "left" then
            container:SetPoint("BOTTOMRIGHT", plate.health, "BOTTOMLEFT", -sideOff + xOff, yOff)
            anchorPoint, gH, gV = "BOTTOMRIGHT", "LEFT", "UP"
        else
            container:SetPoint("BOTTOMLEFT", plate.health, "BOTTOMRIGHT", sideOff + xOff, yOff)
            anchorPoint, gH, gV = "BOTTOMLEFT", "RIGHT", "UP"
        end
    elseif slotVal == "topleft" or slotVal == "topright" then
        local debuffY = (ns.GetDebuffYOffset and ns.GetDebuffYOffset()) or 2
        local cpPush = ns.NP_ClassPowerTopPush and ns.NP_ClassPowerTopPush(plate) or 0
        local growth = PVal(slotVal .. "SlotGrowth")
            or (slotVal == "topleft" and "left" or "right")
        local corner = (slotVal == "topleft") and "BOTTOMLEFT" or "BOTTOMRIGHT"
        local healthCorner = (slotVal == "topleft") and "TOPLEFT" or "TOPRIGHT"
        container:SetPoint(corner, plate.health, healthCorner, xOff, debuffY + cpPush + yOff)
        anchorPoint = corner
        if growth == "up" then
            gH = (slotVal == "topleft") and "RIGHT" or "LEFT"
            gV = "UP"
            rowWidth = size + 0.4
        else
            gH = (growth == "left") and "LEFT" or "RIGHT"
            gV = "UP"
        end
    else
        container:SetShown(false)
        return
    end

    -- Active cast lockout: the lockout icon holds the CC row's first position, so the
    -- CC container chains off its far edge instead of the health anchor (top/bottom
    -- rows trade their centering for the lockout's few seconds -- accepted).
    if kind == "cc" then
        local lk = plate.npcLockout
        if lk and lk:IsShown() then
            container:ClearAllPoints()
            if slotVal == "left" then
                container:SetPoint("BOTTOMRIGHT", lk, "BOTTOMLEFT", -spacing, 0)
            elseif slotVal == "topleft" or slotVal == "topright" then
                local growth = PVal(slotVal .. "SlotGrowth")
                    or (slotVal == "topleft" and "left" or "right")
                if growth == "up" then
                    local side = (slotVal == "topleft") and "LEFT" or "RIGHT"
                    container:SetPoint("BOTTOM" .. side, lk, "TOP" .. side, 0, spacing)
                elseif growth == "left" then
                    container:SetPoint("BOTTOMRIGHT", lk, "BOTTOMLEFT", -spacing, 0)
                else
                    container:SetPoint("BOTTOMLEFT", lk, "BOTTOMRIGHT", spacing, 0)
                end
            else -- top, bottom, right: chain rightward
                container:SetPoint("BOTTOMLEFT", lk, "BOTTOMRIGHT", spacing, 0)
            end
        end
    end

    -- Everything below derives from slot/geometry settings alone (never
    -- from the plate), so a bundle whose stamp matches the current layout
    -- generation already carries this exact engine state from its last
    -- attach -- skip the setters (plate churn re-attaches bundles
    -- constantly; unconditional re-drives were per-spawn dirty marks).
    if container._npcGeoGen ~= geoGen or container._npcSlotVal ~= slotVal then
        container._npcGeoGen = geoGen
        container._npcSlotVal = slotVal

        AK.SetContainerAnchor(container, anchorPoint)
        AK.SetContainerGrowth(container, FlowDir(gH), FlowDir(gV))
        AK.SetContainerRowWidth(container, rowWidth)
        local gLayout = {
            elementWidth = size, elementHeight = height,
            elementSpacing = spacing, lineSpacing = spacing,
        }
        container:SetAuraGroupLayout("np", gLayout)
        -- The buff row's non-Magic glow group shares the row's element sizing.
        if container._npbSplit then
            container:SetAuraGroupLayout("np2", gLayout)
        end
        -- NPF record groups share the row's element sizing.
        if container._npfGroups then
            for gkey in pairs(container._npfGroups) do
                container:SetAuraGroupLayout(gkey, gLayout)
            end
        end

        -- Aura tier of the flattened plate render order (text 900 > auras 800),
        -- honoring the per-slot Raise Strata toggle like the legacy pools.
        local raise = ns.GetSlotRaiseStrata and ns.GetSlotRaiseStrata(slotVal)
        container:SetFrameStrata(raise and "HIGH" or "MEDIUM")
        container:SetFrameLevel(800)
    end

    -- Elements sharing the slot: with the row at its own spot, the chain places them (and
    -- the row itself, unless it is the slot's first shown element). One count for a slot
    -- that holds nothing else.
    ns.NP_CoreChain(plate, slotVal)
end

-- Cast-lockout pseudo-aura (kick lockout displayed as a CC icon): armed by
-- the core's cast machinery (ShowCastLockout -- readable, cast-driven, no
-- aura reads), rendered here since the legacy CC row is gone. The frame is
-- OUR child of OUR plate object; positioned exactly at the CC slot pin.
local function PositionLockout(plate, f, slotVal)
    f:ClearAllPoints()
    local xOff, yOff = ns.GetAuraSlotOffsets("ccSlot")
    if slotVal == "top" then
        local anchor, healthAnchored = TopAnchorFor(plate)
        local debuffY = (ns.GetDebuffYOffset and ns.GetDebuffYOffset()) or 2
        local cpPush = (healthAnchored and ns.NP_ClassPowerTopPush) and ns.NP_ClassPowerTopPush(plate) or 0
        f:SetPoint("BOTTOM", anchor, "TOP", xOff, debuffY + cpPush + yOff)
    elseif slotVal == "bottom" then
        f:SetPoint("TOP", plate.cast or plate.health, "BOTTOM", xOff, -2 + yOff)
    elseif slotVal == "left" or slotVal == "right" then
        -- Classic WoW UI's border and the full-size spell icon push it out, as
        -- the containers above.
        local sideOff = ((ns.GetSideAuraXOffset and ns.GetSideAuraXOffset()) or 2)
            + ((ns.NP_ClassicSide and ns.NP_ClassicSide(slotVal)) or 0)
            + ns.NP_FullIconPush(plate, slotVal, yOff, yOff + (NPHeight("cc", NPSize("cc"))))
        if slotVal == "left" then
            f:SetPoint("BOTTOMRIGHT", plate.health, "BOTTOMLEFT", -sideOff + xOff, yOff)
        else
            f:SetPoint("BOTTOMLEFT", plate.health, "BOTTOMRIGHT", sideOff + xOff, yOff)
        end
    else -- topleft / topright
        local debuffY = (ns.GetDebuffYOffset and ns.GetDebuffYOffset()) or 2
        local cpPush = ns.NP_ClassPowerTopPush and ns.NP_ClassPowerTopPush(plate) or 0
        local corner = (slotVal == "topleft") and "BOTTOMLEFT" or "BOTTOMRIGHT"
        local hc = (slotVal == "topleft") and "TOPLEFT" or "TOPRIGHT"
        f:SetPoint(corner, plate.health, hc, xOff, debuffY + cpPush + yOff)
    end
end

------------------------------------------------------------------------------
-- Core Positions chains: the elements sharing one slot (the raid marker, the Rare/Quest
-- indicator, the faction badge, the three aura rows), laid out one after another in the
-- slot's order (<pos>SlotOrder: the option keys joined by commas; unset = the default
-- order), <pos>SlotElementSpacing apart (unset = the first aura row's Spacing in that
-- order, else the global aura spacing). A slot holding fewer than two of them costs one
-- count, and every element keeps the placement its own pass gave it. With two or more,
-- every pass that places a member (UpdateRaidIcon / UpdateClassification / UpdateFaction
-- in Name.lua; AnchorNPContainer: attach, re-anchors, the lockout, the cast icon push)
-- ends here, and the chain places every shown member again: the first by its own rule
-- (the pivot), each later one off the one before it. Left and Right grow outward, the
-- corners by the slot's Grow, Top and Bottom around the first shown aura row, which keeps
-- its centred spot: the members before it in the order hang off its left edge, the ones
-- after off its right. Every element keeps its own height (an icon centred on the bar, a
-- row on the bar's bottom), so alone or chained it sits where it always did. A hidden
-- member (no marker, no mark, no badge) is skipped, so the chain closes up; an empty row
-- keeps its spacing (its width is engine-secret). The cast-lockout icon leads the Crowd
-- Control row, which chains off it in the chain's direction. A member after a row hangs
-- from the row's engine-sized corner, which only an aspect-born frame may (plate.coreHost,
-- PlatePool): without the host it keeps its own spot. NPC_SideRow hands the target arrows
-- and the Kick Tracker the chain's outermost element on a side.
------------------------------------------------------------------------------
local Chain = {
    DEFAULT = "debuffs,buffs,ccs,raidmarker,rare,quest,faction",
    -- Option key -> member (rare and quest are one frame).
    MEMBER = { debuffs = "debuffs", buffs = "buffs", ccs = "cc", raidmarker = "raid",
        rare = "class", quest = "class", faction = "faction" },
    orderMemo = {},   -- [pos] = { src = the saved string, list = { member, ... } }
    keys = {},        -- [pos] = the slot's setting keys (no string building per pass)
    m = {},           -- the slot's members in order (ChainMembers)
    -- The plate's shown members (ChainShown): the frame the chain places, the frame the
    -- next member hangs off, the bottom edge of the member's own placement, row or icon,
    -- the member id.
    lead = {}, trail = {}, base = {}, row = {}, id = {},
    busy = false,
}

local function ChainKeys(pos)
    local k = Chain.keys[pos]
    if not k then
        k = { order = pos .. "SlotOrder", spacing = pos .. "SlotElementSpacing", growth = pos .. "SlotGrowth" }
        Chain.keys[pos] = k
    end
    return k
end

-- The slot's order: its saved string parsed once per value; members a saved order lacks
-- follow in the default order.
local function ChainOrder(pos)
    local src = PVal(ChainKeys(pos).order)
    if type(src) ~= "string" then src = Chain.DEFAULT end
    local memo = Chain.orderMemo[pos]
    if memo and memo.src == src then return memo.list end
    local list, seen = {}, {}
    local function take(s)
        for key in string.gmatch(s, "[^,]+") do
            local id = Chain.MEMBER[key]
            if id and not seen[id] then
                seen[id] = true
                list[#list + 1] = id
            end
        end
    end
    take(src)
    take(Chain.DEFAULT)
    Chain.orderMemo[pos] = { src = src, list = list }
    return list
end

-- The members the slot holds, in its order, into Chain.m; returns their count. A member
-- counts while its own position key names the slot: the badge riding the Rare/Quest
-- indicator is part of that member, Crowd Control inside the debuff row is the debuff row's.
local function ChainMembers(pos)
    local m = Chain.m
    local n = 0
    local ds, bs, cs = ns.GetAuraSlots()
    local raid, class = ns.GetRaidMarkerPos(), ns.GetClassificationSlot()
    local fac = (PVal("classificationIncludeFaction") ~= true) and ns.NP_GetFactionSlot() or "none"
    local order = ChainOrder(pos)
    for i = 1, #order do
        local id = order[i]
        local at
        if id == "debuffs" then at = ds
        elseif id == "buffs" then at = bs
        elseif id == "cc" then at = cs
        elseif id == "raid" then at = raid
        elseif id == "class" then at = class
        else at = fac end
        if at == pos then
            n = n + 1
            m[n] = id
        end
    end
    for i = n + 1, #m do m[i] = nil end
    return n
end

-- Whether the slot holds two or more members (the chain places its elements).
function ns.NP_CoreChained(pos)
    return pos ~= nil and pos ~= "none" and ChainMembers(pos) >= 2
end
-- The slot's member count (the options show Element Spacing from two).
function ns.NP_CoreMemberCount(pos)
    if not pos or pos == "none" then return 0 end
    return ChainMembers(pos)
end

-- The spacing between the slot's elements: its own, else the first aura row's Spacing in
-- the slot's order, else the global aura spacing. ChainMembers has filled Chain.m.
local function ChainSpacing(pos)
    local v = PVal(ChainKeys(pos).spacing)
    if type(v) == "number" then return v end
    local m = Chain.m
    for i = 1, #m do
        local id = m[i]
        if id == "debuffs" or id == "buffs" or id == "cc" then
            return ns.GetAuraSpacing((id == "cc") and "ccs" or id) or 4
        end
    end
    return ns.GetAuraSpacing() or 4
end
-- The options' Element Spacing row reads the same rule.
function ns.NP_CoreElementSpacing(pos)
    if not pos or pos == "none" then return 0 end
    ChainMembers(pos)
    return ChainSpacing(pos)
end

-- A member's bottom edge over the slot's reference, as its own placement puts it: a row's
-- Y offset, an icon's centred on the bar at Left and Right; at the corners the row sits a
-- Debuff Y Offset up, the raid marker on the corner, the indicators 2 up (the class power
-- push, shared, cancels). Top and Bottom align every member to the one before it.
local function ChainBase(pos, id, isRow, sz, yOff, barH)
    if pos == "left" or pos == "right" then
        if isRow then return yOff end
        return yOff + barH / 2 - sz / 2
    elseif pos == "topleft" or pos == "topright" then
        if isRow then return ns.GetDebuffYOffset() + yOff end
        if id == "raid" then return yOff end
        return 2 + yOff
    end
    return 0
end

-- The plate's shown members of the slot, in order, into Chain.lead / trail / base / row /
-- id; returns their count. A row counts only while shown and last placed in this very
-- slot (IsSideRow); the Crowd Control row behind its lockout icon is led by the icon.
local function ChainShown(plate, pos, n)
    local b = active[plate]
    local _, yOff = ns.GetSlotOffsets(pos)
    local barH = ns.GetHealthBarHeight()
    local sz = ns.GetSlotSize(pos)
    local k = 0
    for i = 1, n do
        local id = Chain.m[i]
        local lead, trail, isRow
        if id == "raid" then
            lead = plate.raidFrame
        elseif id == "class" then
            lead = plate.classFrame
            -- Rare/Quest + Faction with no mark: the badge stands in for the pair.
            if not (lead and lead:IsShown()) and PVal("classificationIncludeFaction") == true then
                lead = plate.factionFrame
            end
        elseif id == "faction" then
            lead = plate.factionFrame
        else
            local c = b and b.containers[id]
            if c and c._npcSlotVal == pos then
                lead, isRow = c, true
                if id == "cc" then
                    local lk = plate.npcLockout
                    if lk and lk:IsShown() then
                        trail = c
                        lead = lk
                    end
                end
            end
        end
        if lead and lead:IsShown() then
            k = k + 1
            Chain.lead[k], Chain.trail[k], Chain.row[k], Chain.id[k] = lead, trail or lead, isRow or false, id
            Chain.base[k] = ChainBase(pos, id, isRow, sz, yOff, barH)
        end
    end
    for i = k + 1, #Chain.lead do
        Chain.lead[i], Chain.trail[i], Chain.base[i], Chain.row[i], Chain.id[i] = nil, nil, nil, nil, nil
    end
    return k
end

-- The chain's direction at the slot: outward from the bar at Left and Right, the slot's
-- Grow at the corners, rightward from the pivot at Top and Bottom (the members before the
-- pivot run leftward).
local function ChainDir(pos)
    if pos == "left" then return "left" end
    if pos == "topleft" or pos == "topright" then
        local g = PVal(ChainKeys(pos).growth) or ((pos == "topleft") and "left" or "right")
        if g == "up" or g == "left" then return g end
    end
    return "right"
end

-- Places member i by its own rule: an icon by the slot icon placer (Name.lua), a row by
-- AnchorNPContainer, behind its lockout icon where one shows (PositionLockout).
local function ChainPlaceOwn(plate, pos, i)
    local id, lead = Chain.id[i], Chain.lead[i]
    if Chain.row[i] then
        local c = Chain.trail[i]
        if lead ~= c then PositionLockout(plate, lead, pos) end
        AnchorNPContainer(c, id, plate, pos)
    else
        local xOff, yOff = ns.GetSlotOffsets(pos)
        ns.NP_PlaceSlotIcon(plate, lead, pos, xOff, yOff, (id == "raid") and 0 or 2, ns.GetSlotSize(pos))
    end
end

-- An icon keeps its own placement's units (PP.Point); a row or the lockout icon the
-- containers' plain ones.
local function ChainPoint(f, raw, point, rel, relPoint, x, y)
    if raw then f:SetPoint(point, rel, relPoint, x, y)
    else PP.Point(f, point, rel, relPoint, x, y) end
end

-- Places member i off prev, the outer frame of member j (the one before it along the
-- chain), s apart, dir the chain's direction: the member's own height kept (base), at
-- Top and Bottom the two sharing their bottom (top) edge. A plain icon after a row keeps
-- its own spot (no aspect host). The Crowd Control row then chains off its lockout icon,
-- sp apart, in the same direction.
local function ChainPlaceAfter(plate, pos, i, j, prev, s, dir, sp)
    local lead, c = Chain.lead[i], Chain.trail[i]
    local raw = Chain.row[i] or lead ~= c
    if Chain.row[j] and not plate.coreHost and (lead ~= c or not Chain.row[i]) then
        ChainPlaceOwn(plate, pos, i)
        return
    end
    local dy = Chain.base[i] - Chain.base[j]
    lead:ClearAllPoints()
    if dir == "up" then
        local side = (pos == "topleft") and "LEFT" or "RIGHT"
        ChainPoint(lead, raw, "BOTTOM" .. side, prev, "TOP" .. side, 0, s)
    elseif pos == "bottom" then
        if dir == "left" then ChainPoint(lead, raw, "TOPRIGHT", prev, "TOPLEFT", -s, 0)
        else ChainPoint(lead, raw, "TOPLEFT", prev, "TOPRIGHT", s, 0) end
    elseif dir == "left" then
        ChainPoint(lead, raw, "BOTTOMRIGHT", prev, "BOTTOMLEFT", -s, dy)
    else
        ChainPoint(lead, raw, "BOTTOMLEFT", prev, "BOTTOMRIGHT", s, dy)
    end
    if Chain.row[i] and c ~= lead then
        c:ClearAllPoints()
        if dir == "up" then
            local side = (pos == "topleft") and "LEFT" or "RIGHT"
            c:SetPoint("BOTTOM" .. side, lead, "TOP" .. side, 0, sp)
        elseif dir == "left" then
            c:SetPoint("BOTTOMRIGHT", lead, "BOTTOMLEFT", -sp, 0)
        else
            c:SetPoint("BOTTOMLEFT", lead, "BOTTOMRIGHT", sp, 0)
        end
    end
end

-- One pass over the plate's shown members of the slot (Chain.busy set: the passes it
-- runs end in ns.NP_CoreChain again).
local function ChainRun(plate, pos, k)
    local centred = (pos == "top" or pos == "bottom")
    local pivot = 1
    if centred then
        for i = 1, k do
            if Chain.row[i] then pivot = i; break end
        end
    end
    local s = ChainSpacing(pos)
    local sp = ns.GetAuraSpacing("ccs") or 4
    local dir = ChainDir(pos)
    ChainPlaceOwn(plate, pos, pivot)
    for i = pivot + 1, k do
        ChainPlaceAfter(plate, pos, i, i - 1, Chain.trail[i - 1], s, dir, sp)
    end
    if centred then
        -- Leftward from the pivot, whose left edge is its lead (its lockout icon, where the
        -- Crowd Control row is the pivot: the row chains rightward off it).
        for i = pivot - 1, 1, -1 do
            local prev = (i + 1 == pivot) and Chain.lead[i + 1] or Chain.trail[i + 1]
            ChainPlaceAfter(plate, pos, i, i + 1, prev, s, "left", sp)
        end
    end
end

function ns.NP_CoreChain(plate, pos)
    if Chain.busy or not pos or pos == "none" then return end
    local n = ChainMembers(pos)
    if n < 2 then return end
    local k = ChainShown(plate, pos, n)
    if k == 0 then return end
    Chain.busy = true
    local ok, err = pcall(ChainRun, plate, pos, k)
    Chain.busy = false
    if not ok then error(err, 0) end
    -- A side chain's outermost element is what the target arrows hug.
    if pos == "left" or pos == "right" then ns.PositionArrowsOutsideAuras(plate) end
end

-- The cast-lockout icon is hand-built outside AuraKit, so Custom Border on Aura Icons
-- reaches it through its own child frame (the icon inset drops to 0 while that draws);
-- off, the plain 1px edge. Runs on every lockout show, so the restyle is
-- skipped while its inputs (shown state, level, texture, size step, exact px, colour,
-- alpha, offsets, shifts) are unchanged; the child turns off through
-- ApplyBorderStyle(frame, 0) so the UI scale re-apply cannot bring it back.
local function NPLockoutBorder(f)
    local on = ns.GetIconBorderEnabled("ccs")
    local cb = f._npCB
    if on and NPIconCustomBorderOn() then
        if not cb then
            cb = CreateFrame("Frame", nil, f)
            cb:SetAllPoints(f)
            cb:EnableMouse(false)
            f._npCB = cb
        end
        local tex = PVal("customBorderTexture")
        local sz = PVal("customBorderSize") or 1
        local px = EllesmereUI.BorderPx(PVal("customBorderSizePx"), sz, tex)
        local col = PVal("customBorderColor")
        local a = PVal("customBorderAlpha") or 1
        local ox, oy = PVal("customBorderOffset"), PVal("customBorderOffsetY")
        local sx, sy = PVal("customBorderShiftX"), PVal("customBorderShiftY")
        -- Above the swipe, as AuraKit seats its aura borders.
        local lvl = f.cd:GetFrameLevel() + 1
        if not cb:IsShown() or cb:GetFrameLevel() ~= lvl
            or cb._sTex ~= tex or cb._sSz ~= sz or cb._sPx ~= px
            or cb._sR ~= col.r or cb._sG ~= col.g or cb._sB ~= col.b or cb._sA ~= a
            or cb._sOX ~= ox or cb._sOY ~= oy or cb._sSX ~= sx or cb._sSY ~= sy then
            cb:SetFrameLevel(lvl)
            EllesmereUI.ApplyBorderStyle(cb, sz, col.r, col.g, col.b, a, tex, ox, oy, sx, sy,
                "nameplates", sz, nil, px)
            local PP = EllesmereUI.PP
            if PP.GetBorders(cb) then PP.CreateBorder(cb, nil, nil, nil, nil, nil, nil, nil, true) end
            cb._sTex, cb._sSz, cb._sPx = tex, sz, px
            cb._sR, cb._sG, cb._sB, cb._sA = col.r, col.g, col.b, a
            cb._sOX, cb._sOY, cb._sSX, cb._sSY = ox, oy, sx, sy
        end
        if not f._npCBInset0 then
            f._npCBInset0 = true
            f.icon:ClearAllPoints()
            f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
            f.icon:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
        end
        ns.ApplyFrameIconBorder(f, false)
        return
    end
    if cb and cb:IsShown() then
        EllesmereUI.ApplyBorderStyle(cb, 0)
        cb:Hide()
    end
    if f._npCBInset0 then
        -- Back to the creation inset (0 under the stock styles, else 1).
        f._npCBInset0 = nil
        local px = ns.NP_Blizz() and 0 or 1
        f.icon:ClearAllPoints()
        f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", px, -px)
        f.icon:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -px, px)
    end
    ns.ApplyFrameIconBorder(f, on)
end

function ns.NPC_UpdateLockout(plate)
    if not plate then return end
    local _, _, cs = ns.GetAuraSlots()
    local lockout = (cs and cs ~= "none") and ns.GetActiveCastLockout
        and ns.GetActiveCastLockout(plate)
    local f = plate.npcLockout
    if lockout and plate.health then
        if not f then
            -- Born in the plate's aspect holder like the slot icons (PlatePool, coreHost),
            -- so a Core Positions chain can hang it off an aura row.
            f = CreateFrame("Frame", nil, plate.coreHost or plate)
            f:SetFrameStrata("MEDIUM")
            f:SetFrameLevel(800)
            f.icon = f:CreateTexture(nil, "ARTWORK")
            -- Stock styles: no border, so the icon fills the cell; Blizzard
            -- Style also takes the stock rounded swipe under its ring (the
            -- classic square icon keeps the default swipe).
            local px = ns.NP_Blizz() and 0 or 1
            f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", px, -px)
            f.icon:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -px, px)
            f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
            f.cd:SetAllPoints(f)
            f.cd:SetReverse(true)
            f.cd:SetDrawEdge(false)
            local kit = AK or EllesmereUI.AuraKit
            local swipe = px == 0 and not ns.NP_Classic() and kit and kit.BLIZZ_ROUND_SWIPE
            if swipe and f.cd.SetSwipeTexture then f.cd:SetSwipeTexture(swipe) end
            -- scaleGuard: a plate child, as every Basic nameplate border
            EllesmereUI.PP.CreateBorder(f, 0, 0, 0, 1, 1, nil, nil, true)
            NPLockoutBorder(f)
            plate.npcLockout = f
        end
        local size = NPSize("cc")
        local height, cropped = NPHeight("cc", size)
        f:SetSize(size, height)
        local blizz = ns.NP_Blizz()
        local tc = CropCoords(cropped, blizz and 0 or nil)
        f.icon:SetTexture(lockout.icon)
        f.icon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
        f.cd:SetCooldown(lockout.start, lockout.duration)
        -- Blizzard Style: the stock rounded mask and ring, sized with the cell.
        -- Classic WoW UI: the stock debuff border round the square icon.
        if blizz then
            if ns.NP_Classic() then
                if ns.NP_ApplyClassicIconArt then ns.NP_ApplyClassicIconArt(f, size, height) end
            elseif ns.NP_ApplyBlizzIconArt then
                ns.NP_ApplyBlizzIconArt(f, f.icon, size, height)
            end
        end
        PositionLockout(plate, f, cs)
        NPLockoutBorder(f)
        f:Show()
    elseif f then
        f:Hide()
    end
    -- Re-anchor the CC container: chains off the lockout while shown.
    local b = active[plate]
    if b then
        AnchorNPContainer(b.containers.cc, "cc", plate, cs)
    end
end

-- The target arrows (ns.PositionArrowsOutsideAuras) hug the outer edge of a side aura row
-- they meet: shown counts are engine-secret, so only the engine knows a row's width (an empty
-- row brings the arrow back to the bar's edge).
-- 68914: AddAuraGroup stamps UntrustedLayoutScriptExecution on the container, and only
-- aspect-bearing objects may anchor to one. Aspects cannot be conferred after creation
-- (SetParent/SetPoint inheritance is deliberately blocked -- a reparent-into-holder
-- attempt hard-errored in the field), so EnsureArrows births the arrows inside a
-- DisableUntrustedLayoutScriptsTemplate holder: they inherit the aspect at creation and
-- anchor to containers and readable frames alike.
-- A row counts only while shown and last placed in this very slot: the buff row hides itself
-- for units you cannot attack but keeps its stale layout, and AnchorNPContainer's
-- _npcSlotVal stamp lags a slot change until the plate is placed again.
local function IsSideRow(b, kind, slotVal, side)
    local c = b.containers[kind]
    return slotVal == side and c ~= nil and c:IsShown() and c._npcSlotVal == side
end

-- This plate's aura row on `side` ("left"/"right"): the first shown row in that slot
-- (debuffs, buffs, crowd control), with its slot's Y offset and its icons' height. A side
-- that chains two or more elements answers with the outermost shown one instead (an icon
-- too: its bottom over the bar's bottom and its size), the outermost that meets the span
-- a0..a1 over the bar's bottom when one is given (the target arrows' own).
function ns.NPC_SideRow(plate, side, a0, a1)
    if not Chain.busy and ns.NP_CoreChained(side) then
        local k = ChainShown(plate, side, #Chain.m)
        for i = k, 1, -1 do
            local id = Chain.id[i]
            local y = Chain.base[i]
            local h = Chain.row[i] and (NPHeight(id, NPSize(id))) or ns.GetSlotSize(side)
            if not a0 or (y < a1 and a0 < y + h) then return Chain.trail[i], y, h end
        end
        return nil
    end
    local b = active[plate]
    if not b then return nil end
    local ds, bs, cs = ns.GetAuraSlots()
    local kind, key
    if IsSideRow(b, "debuffs", ds, side) then
        kind, key = "debuffs", "debuffSlot"
    elseif IsSideRow(b, "buffs", bs, side) then
        kind, key = "buffs", "buffSlot"
    elseif IsSideRow(b, "cc", cs, side) then
        kind, key = "cc", "ccSlot"
    else
        return nil
    end
    local _, y = ns.GetAuraSlotOffsets(key)
    return b.containers[kind], y or 0, (NPHeight(kind, NPSize(kind)))
end

-- Whether the full-size spell icon's push on a side row moved since AnchorNPContainer last
-- placed it (container._npcPush).
local function SidePushMoved(c, kind, key, plate, side)
    if not c then return false end
    local _, yOff = ns.GetAuraSlotOffsets(key)
    return ns.NP_FullIconPush(plate, side, yOff, yOff + (NPHeight(kind, NPSize(kind)))) ~= c._npcPush
end

-- The full-size spell icon shows only during a cast, and a side row it meets steps out past it
-- (AnchorNPContainer, PositionLockout): on every cast show and hide, re-place this plate's
-- rows on the icon's side whose push moved. Called only while the full-size icon is on
-- (RefreshCastIconSideReserve).
function ns.NPC_PlaceSideRows(plate)
    local b = active[plate]
    if not b then return end
    local side = ns.GetCastIconOnRight() and "right" or "left"
    local ds, bs, cs = ns.GetAuraSlots()
    local c = b.containers
    if ds == side and SidePushMoved(c.debuffs, "debuffs", "debuffSlot", plate, side) then
        AnchorNPContainer(c.debuffs, "debuffs", plate, ds)
    end
    if bs == side and SidePushMoved(c.buffs, "buffs", "buffSlot", plate, side) then
        AnchorNPContainer(c.buffs, "buffs", plate, bs)
    end
    if cs == side and SidePushMoved(c.cc, "cc", "ccSlot", plate, side) then
        local lk = plate.npcLockout
        if lk and lk:IsShown() then PositionLockout(plate, lk, cs) end
        AnchorNPContainer(c.cc, "cc", plate, cs)
    end
end

------------------------------------------------------------------------------
-- Attach / detach
------------------------------------------------------------------------------

-- Plates that arrive while the pool is empty (login trickle window, or genuine
-- exhaustion) wait here; freshly built or freed bundles service them immediately.
local waiting = setmetatable({}, { __mode = "k" })

local function ServiceWaiting()
    for plate in pairs(waiting) do
        waiting[plate] = nil
        if plate.unit and #pool > 0 then
            ns.NPC_AttachPlate(plate, plate.unit)
        end
        if #pool == 0 then return end
    end
end

function ns.NPC_AttachPlate(plate, unit)
    AK = AK or EllesmereUI.AuraKit
    if not AK then return end
    if not unit or UnitIsUnit(unit, "player") then return end -- personal plate: no aura rows

    local b = active[plate]
    if not b then
        b = table.remove(pool)
        if not b then
            waiting[plate] = true -- serviced when a bundle builds or frees
            -- Grow the pool by one bundle per waiting plate (combat-legal
            -- since 68914). A plate that detaches before service just
            -- leaves its bundle pooled for the next spawn.
            if QueueBundleBuild then QueueBundleBuild() end
            return
        end
        waiting[plate] = nil
        active[plate] = b
    end

    b.holder:SetParent(plate)
    b.holder:ClearAllPoints()
    b.holder:SetPoint("CENTER", plate, "CENTER")
    b.holder:Show()

    local ds, bs, cs = ns.GetAuraSlots()
    if b.containers.buffs then
        b.containers.buffs._npcAttackable = not not UnitCanAttack("player", unit)
    end
    -- A plate spawning for the CURRENT target picks up the class-power push right here,
    -- so it must be tracked as the plate to re-anchor when the target changes away.
    if UnitIsUnit(unit, "target") then lastTargetPlate = plate end
    AnchorNPContainer(b.containers.debuffs, "debuffs", plate, ds)
    AnchorNPContainer(b.containers.buffs, "buffs", plate, bs)
    AnchorNPContainer(b.containers.cc, "cc", plate, cs)

    BindContainer(b.containers.debuffs, unit, ds)
    BindContainer(b.containers.buffs, unit, bs)
    BindContainer(b.containers.cc, unit, cs)
    ns.PositionArrowsOutsideAuras(plate)
end

-- True while a built glow spec plays animations: everything but the static
-- Blizzard Pandemic Border and Blizzard Border.
function NPB.Animated(on, spec)
    if not (on and spec) then return false end
    local G = EllesmereUI.Glows
    return spec.style ~= G.PANDEMIC_BORDER and spec.style ~= G.STEALABLE_BORDER
end

-- Switches an enabled group off and straight back on: off releases its buttons
-- at once (each clears its aura and stops the animations it plays), on keeps
-- the group live for the next attach. A group already off is left alone.
function NPB.CycleGroup(c, key)
    local ok, on = pcall(c.IsAuraGroupEnabled, c, key)
    if ok and on == true and pcall(c.SetAuraGroupEnabled, c, key, false) then
        pcall(c.SetAuraGroupEnabled, c, key, true)
    end
end

-- A pooled bundle's holder is hidden, and a hidden container runs no aura
-- pass: its next parse waits for the next attach, so every button that
-- showed an aura at detach keeps it, and a bound glow on it keeps playing. Released here instead, after the hide (the group switches then
-- register no events), only for the groups whose style draws an animated
-- glow, and only once a host is bound: default (static) plates pay nothing.
-- force: the style pass (NPC_ReloadAll), whose restyle may bind the hosts.
function NPB.ReleaseGlowButtons(b, force)
    if not ((force or NPB.bound) and AK and AK.styles) then return end
    local st = AK.styles
    local c = b.containers.debuffs
    local s = st["np:debuffs"]
    if c and s and NPB.Animated(s.pandemicGlow, s.pandemicSpec) then
        NPB.CycleGroup(c, "np")
        if c._npfGroups then
            for key in pairs(c._npfGroups) do NPB.CycleGroup(c, key) end
        end
    end
    c = b.containers.buffs
    if not c then return end
    s = st["np:buffs"]
    if s and NPB.Animated(s.purgeGlow, s.purgeSpec) then NPB.CycleGroup(c, "np") end
    s = st["np:buffs2"]
    if c._npbSplit and s and NPB.Animated(s.purgeGlow, s.purgeSpec) then
        NPB.CycleGroup(c, "np2")
    end
end

function ns.NPC_DetachPlate(plate)
    waiting[plate] = nil
    if lastTargetPlate == plate then lastTargetPlate = nil end
    if plate.npcLockout then plate.npcLockout:Hide() end
    local b = active[plate]
    if not b then return end
    active[plate] = nil
    -- Unbound only: the next attach binds its unit afresh (SetUnit +
    -- UpdateAllAuras). A unit cleared here would change nothing, since the
    -- holder hides next and a hidden container neither listens nor parses.
    for i = 1, #KINDS do
        local c = b.containers[KINDS[i]]
        if c then c._npcBoundUnit = nil end
    end
    b.holder:Hide()
    NPB.ReleaseGlowButtons(b)
    b.holder:SetParent(UIParent)
    b.holder:ClearAllPoints()
    b.holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", -200, -200)
    pool[#pool + 1] = b
    ServiceWaiting()
end

------------------------------------------------------------------------------
-- Settings reload: style + geometry + config fingerprints (one set,
-- containers share settings globally).
------------------------------------------------------------------------------

local npFP = {}

local PURGE_FP_SPEC = {}
local PAN_FP_SPEC = {}
local function StyleFPFor(kind, idx)
    local size = NPSize(kind)
    local height = NPHeight(kind, size)
    -- Text settings feed BuildNPStyle, so every input must flip this
    -- fingerprint or a live change never restyles the engine buttons.
    local kindKey = (kind == "debuffs" and "debuff") or (kind == "buffs" and "buff") or "cc"
    local dur = AuraDurCfg(kindKey)
    local stk = StackCfg()
    local purge = "-"
    if kind == "buffs" and ns.GetDispelGlow then
        -- Capability and the per-type color toggle both feed BuildNPStyle,
        -- so they have to reach this fingerprint or a talent swap / toggle
        -- never restyles the engine buttons.
        local glow, dispelType = NPB.GroupGlow(idx or 1)
        local sp = ns.GetDispelGlowSpec and ns.GetDispelGlowSpec(dispelType, PURGE_FP_SPEC)
        if sp then
            purge = FP(idx or 1, glow, sp.style, sp.r, sp.g, sp.b, sp.lines, sp.thickness,
                sp.speed, sp.bg, sp.bgR, sp.bgG, sp.bgB)
        end
    end
    -- Pandemic Glow (debuffs): every input of BuildNPStyle's pandemic fields,
    -- a constant "-" while off so a glow edit never restyles default users.
    if kind == "debuffs" and ns.GetPandemicGlow() then
        local sp = ns.GetPandemicGlowSpec(PAN_FP_SPEC)
        purge = FP("pan", sp.style, sp.r, sp.g, sp.b, sp.lines, sp.thickness,
            sp.speed, sp.bg, sp.bgR, sp.bgG, sp.bgB)
    end
    local durFP = FP(dur.size, dur.x, dur.y, dur.pos, dur.color.r, dur.color.g, dur.color.b)
    local stkFP = FP(stk.size, stk.x, stk.y, stk.pos, stk.color.r, stk.color.g, stk.color.b)
    -- Custom Border on Aura Icons: every input of NPCustomIconBorder, folded in only
    -- while it is on (a constant "-" otherwise, so a border edit never restyles default
    -- users' icons): the toggle and Border = Custom (the gate), texture, size step, the
    -- exact-size value, colour, alpha, both offsets and both shifts. Colour and alpha go
    -- in as exact strings, not FP's two-decimal numbers.
    local cbFP = "-"
    if NPIconCustomBorderOn() then
        local col = PVal("customBorderColor")
        cbFP = FP(PVal("customBorderTexture"), PVal("customBorderSize"),
            tostring(PVal("customBorderSizePx")),
            tostring(col.r), tostring(col.g), tostring(col.b), tostring(PVal("customBorderAlpha")),
            PVal("customBorderOffset"), PVal("customBorderOffsetY"),
            PVal("customBorderShiftX"), PVal("customBorderShiftY"))
    end
    return FP(kind, size, height, durFP, stkFP, purge,
        EllesmereUI.GetFontPath("nameplates") or "",
        -- NOT `fn(kind) or true`: the getter legitimately returns false, and
        -- `false or true` would pin this fingerprint input to a constant so
        -- the toggle never restyles (the ternary-falsy trap).
        (not ns.GetIconBorderEnabled) or ns.GetIconBorderEnabled(kind), cbFP,
        PVal("showAuraTooltips") == true)
end

local function GeoFP()
    local ds, bs, cs = ns.GetAuraSlots()
    local dx, dy = ns.GetAuraSlotOffsets("debuffSlot")
    local bx, by = ns.GetAuraSlotOffsets("buffSlot")
    local cx, cy = ns.GetAuraSlotOffsets("ccSlot")
    return FP(ds, bs, cs, dx, dy, bx, by, cx, cy,
        NPSize("debuffs"), NPSize("buffs"), NPSize("cc"),
        ns.GetAuraSpacing and ns.GetAuraSpacing("debuffs") or 0,
        ns.GetAuraSpacing and ns.GetAuraSpacing("buffs") or 0,
        ns.GetAuraSpacing and ns.GetAuraSpacing("ccs") or 0,
        ns.GetAuraCrop and tostring(ns.GetAuraCrop("debuffs")) or "-",
        ns.GetAuraCrop and tostring(ns.GetAuraCrop("buffs")) or "-",
        ns.GetAuraCrop and tostring(ns.GetAuraCrop("ccs")) or "-",
        ns.GetDebuffYOffset and ns.GetDebuffYOffset() or 0,
        ns.GetSideAuraXOffset and ns.GetSideAuraXOffset() or 0,
        PVal("textSlotTop"), PVal("topleftSlotGrowth"), PVal("toprightSlotGrowth"),
        -- Raise Strata feeds the (generation-guarded) layout pass, so its
        -- toggles must flip the geometry fingerprint like everything else.
        ns.GetSlotRaiseStrata and ns.GetSlotRaiseStrata(ds) or false,
        ns.GetSlotRaiseStrata and ns.GetSlotRaiseStrata(bs) or false,
        ns.GetSlotRaiseStrata and ns.GetSlotRaiseStrata(cs) or false,
        -- The Core Positions chains (order and spacing per slot) and the other members'
        -- slots: ReanchorActive runs every chain again.
        PVal("topSlotOrder"), PVal("rightSlotOrder"), PVal("leftSlotOrder"),
        PVal("toprightSlotOrder"), PVal("topleftSlotOrder"), PVal("bottomSlotOrder"),
        PVal("topSlotElementSpacing"), PVal("rightSlotElementSpacing"), PVal("leftSlotElementSpacing"),
        PVal("toprightSlotElementSpacing"), PVal("topleftSlotElementSpacing"), PVal("bottomSlotElementSpacing"),
        PVal("raidMarkerPos"), PVal("classificationSlot"), PVal("factionSlot"),
        PVal("classificationIncludeFaction"))
end

local function CfgFP()
    -- NPB.Split decides how many groups the buff row runs, so it belongs
    -- with the container config rather than with the styles.
    return FP(PVal("maxDebuffs"), PVal("showAllDebuffs"), BuffMode(), NPB.Split(),
        PVal("debuffIncludeCC"), ns.NPF_FP(), PVal("hideBloodPlagueCopies") ~= false,
        NPF_SunderOn())
end

local function ReanchorActive()
    local ds, bs, cs = ns.GetAuraSlots()
    for plate, b in pairs(active) do
        AnchorNPContainer(b.containers.debuffs, "debuffs", plate, ds)
        AnchorNPContainer(b.containers.buffs, "buffs", plate, bs)
        AnchorNPContainer(b.containers.cc, "cc", plate, cs)
        -- Slot settings may have flipped between "none" and displayed;
        -- BindContainer no-ops when the binding already matches.
        if plate.unit then
            BindContainer(b.containers.debuffs, plate.unit, ds)
            BindContainer(b.containers.buffs, plate.unit, bs)
            BindContainer(b.containers.cc, plate.unit, cs)
        end
        ns.PositionArrowsOutsideAuras(plate)
    end
end

-- Rewires freshly-ensured containers on active plates (attackability,
-- purge watch) and re-anchors/binds everything. Debounced: each ensure
-- job calls this at its tail, so one pass covers a burst of builds.
local npEnsurePending = false
local function NpEnsureWireSoon()
    if npEnsurePending then return end
    npEnsurePending = true
    C_Timer.After(0.05, function()
        npEnsurePending = false
        for plate, b in pairs(active) do
            if plate.unit and b.containers.buffs then
                b.containers.buffs._npcAttackable = not not UnitCanAttack("player", plate.unit)
            end
        end
        ReanchorActive()
    end)
end

-- Builds any row containers that a bundle is missing for the CURRENT slot
-- settings (a row enabled after the pool was built). Rows disabled at
-- pool-build time leave their skeleton shell UNCONSUMED in b.shells, so a
-- later enable is a combat-legal group add onto that shell; only a bundle
-- whose shell for the row is already gone holds until regen.
local function QueueBundleEnsure(b)
    if b.npcEnsurePending then return end
    b.npcEnsurePending = true
    AKWorker:Queue(function()
        local ds, bs, cs = ns.GetAuraSlots()
        -- Combat-legal since 68914: AddBundle* consume a pre-born shell when
        -- one exists and create fresh otherwise, in any combat state.
        local function ensure(kind, slot, add)
            if not (slot and slot ~= "none") or b.containers[kind] then return end
            add(b)
        end
        ensure("debuffs", ds, AddBundleDebuffs)
        ensure("buffs", bs, AddBundleBuffs)
        ensure("cc", cs, AddBundleCC)
        -- Capability split: declare or park the non-Magic glow group on
        -- containers that already existed when the split state changed.
        NPB.Apply(b.containers.buffs)
        -- NPF record groups (Tracked Auras): declare missing variants,
        -- park stale ones, drive the np groups' counts by the configs.
        NPF_EnsureRecords(b)
        NpEnsureWireSoon()
        b.npcEnsurePending = nil
    end, "np:ensure")
end

-- Class mode on an aura glow (Dispel or Pandemic) that takes a color: the style
-- prints hold the palette colour, kept here for the colours-changed hook below
-- NPC_ReloadAll. Any other state clears it, so later colour edits never reload.
function NPB.SnapClassColor()
    local PB = EllesmereUI.Glows.PANDEMIC_BORDER
    local class = (PurgeGlowActive() and PVal("dispelGlowColorMode") == "class"
            and ns.GetDispelGlowStyle() ~= PB)
        or (ns.GetPandemicGlow() and PVal("pandemicGlowMode") == "class"
            and ns.GetPandemicGlowStyle() ~= PB)
    if class then
        NPB.ccR, NPB.ccG, NPB.ccB = EllesmereUI.Glows.ResolveColor("class")
    else
        NPB.ccR = nil
    end
end

function ns.NPC_ReloadAll()
    AK = AK or EllesmereUI.AuraKit
    if not AK then return end

    -- Conditional-bundle ensure: rows enabled after the pool was built get
    -- their containers on demand (cheap scan: 3 nil-checks per bundle).
    do
        local ds, bs, cs = ns.GetAuraSlots()
        local needD = ds and ds ~= "none"
        local needB = bs and bs ~= "none"
        local needC = cs and cs ~= "none"
        local function scan(b)
            if (needD and not b.containers.debuffs)
                or (needB and not b.containers.buffs)
                or (needC and not b.containers.cc) then
                QueueBundleEnsure(b)
            end
        end
        for i = 1, #pool do scan(pool[i]) end
        for _, b in pairs(active) do scan(b) end
    end

    local v = StyleFPFor("debuffs") .. ";" .. StyleFPFor("buffs") .. ";"
        .. StyleFPFor("buffs", 2) .. ";" .. StyleFPFor("cc")
    NPB.SnapClassColor()
    if npFP.style ~= v then
        npFP.style = v
        for i = 1, #KINDS do
            local kind = KINDS[i]
            AK.styles["np:" .. kind] = BuildNPStyle(kind)
            AK.RestyleSoon("np:" .. kind)
        end
        -- The buffs row's style twins restyle in lockstep: the non-Magic
        -- glow half and the plain (non-glow) remainder.
        AK.styles["np:buffs2"] = BuildNPStyle("buffs", 2)
        AK.RestyleSoon("np:buffs2")
        AK.styles["np:buffsplain"] = BuildNPStyle("buffs", "plain")
        AK.RestyleSoon("np:buffsplain")
        -- A bundle pooled while its glow was static (or off) kept the auras
        -- it showed; release those buttons before the restyle above hands
        -- them an animated glow, or it would play on the pooled bundle.
        for i = 1, #pool do NPB.ReleaseGlowButtons(pool[i], true) end
    end

    v = CfgFP()
    if npFP.cfg ~= v then
        npFP.cfg = v
        local maxDbf = PVal("maxDebuffs") or 5
        local sort = DebuffSort()
        local dbfCand = DebuffCand()
        -- Empty table (not nil) when nothing narrows: guarantees the setter
        -- REPLACES the stored filter rather than risking a nil no-op. While
        -- split, group "np" narrows to Magic; NPB.Apply owns group "np2".
        local buffSplit = NPB.Split()
        local buffCand = (buffSplit and NPB.MAGIC) or BuffCand() or {}
        local buffFilter = AK.Filter(unpack(BuffFilterGlow()))
        local plainToks = BuffFilterPlain()
        local buffFilterPlain = plainToks and AK.Filter(unpack(plainToks)) or nil
        local function apply(b)
            -- Conditional bundles: a row's container may not exist.
            if b.containers.debuffs then
                -- np COUNT is owned by NPF_ApplyContainer now (Show All
                -- flag); the cand re-drive stays -- it wipes any stale
                -- narrowing left by pre-filter-feature sessions.
                b.containers.debuffs:SetAuraGroupCandidateFilters("np", dbfCand)
                -- Enum values can be 0: compare against nil, and the direct
                -- setter (unlike AddAuraGroup) requires an explicit direction.
                if sort ~= nil and SORT_DIR ~= nil then
                    b.containers.debuffs:SetAuraGroupSortMethod("np", sort, SORT_DIR)
                end
            end
            if b.containers.buffs then
                b.containers.buffs:SetAuraGroupCandidateFilters("np", buffCand)
                -- The Enemy Buff Filter mode swaps filter-string tokens, so a
                -- flip has to re-drive BOTH group strings (the setter no-ops
                -- when unchanged) and park/unpark the plain remainder group.
                if b.containers.buffs.SetAuraGroupFilterString then
                    b.containers.buffs:SetAuraGroupFilterString("np", buffFilter)
                    if b.containers.buffs._npbSplit then
                        b.containers.buffs:SetAuraGroupFilterString("np2", buffFilter)
                    end
                    if buffFilterPlain then
                        b.containers.buffs:SetAuraGroupFilterString("npnb", buffFilterPlain)
                    end
                end
                if b.containers.buffs.SetAuraGroupMaxFrameCount then
                    EllesmereUI.AuraKit.SetGroupCap(b.containers.buffs, "npnb", buffFilterPlain and 4 or 0)
                end
            end
            -- NPF record groups + np counts: declares run on the queued,
            -- budgeted ensure path (npcEnsurePending dedupes).
            QueueBundleEnsure(b)
        end
        for _, b in pairs(active) do apply(b) end
        for i = 1, #pool do apply(pool[i]) end
    end

    v = GeoFP()
    if npFP.geo ~= v then
        npFP.geo = v
        -- Invalidate every bundle's layout stamp (pooled ones re-drive at
        -- their next attach; active ones right now).
        geoGen = geoGen + 1
        ReanchorActive()
    end
    -- Cast-lockout is a hand-built CC icon, not an AuraKit style, so it
    -- has to pick up Show Border (and the custom icon border) here rather
    -- than through RestyleSoon.
    for plate in pairs(active) do
        if plate.npcLockout then NPLockoutBorder(plate.npcLockout) end
    end
end

-- Colors page edits (swatches, darken, resets, profile switches) all end in
-- ApplyColorsToOUF. Once a Class-mode aura glow was printed, a changed class
-- colour re-runs the reload; the glow prints carry the colour, so only the
-- glow styles restyle. Calls in one frame (a profile switch can make two)
-- collapse into one check on the next frame: the flush frame stays hidden
-- until a call and hides itself before working.
do
    local flush = CreateFrame("Frame")
    flush:Hide()
    flush:SetScript("OnUpdate", function(self)
        self:Hide()
        local r0 = NPB.ccR
        if r0 == nil then return end
        local r, g, b = EllesmereUI.Glows.ResolveColor("class")
        if r ~= r0 or g ~= NPB.ccG or b ~= NPB.ccB then ns.NPC_ReloadAll() end
    end)
    hooksecurefunc(EllesmereUI, "ApplyColorsToOUF", function()
        if NPB.ccR ~= nil then flush:Show() end
    end)
end

------------------------------------------------------------------------------
-- Pool build at login (containers must be created out of combat).
------------------------------------------------------------------------------

-- Pool builds INCREMENTALLY through the shared AuraKit build scheduler: a
-- full synchronous build is ~1200 aura buttons (40 bundles x 3 containers
-- x 10-button batches) and measurably extends the loading screen; even a
-- bundle-per-frame trickle spiked frames. One job per CONTAINER keeps each
-- build step ~4-6ms inside the scheduler's frame budget (combat-paused;
-- never ticks during loading screens). Plates that attach before the pool
-- catches up wait in `waiting` and are serviced as bundles complete.
local built = 0
-- CONDITIONAL bundles: each row's container (a 10-button batch for debuffs/buffs,
-- 2-batch for cc) only builds when its aura slot is actually displayed -- rows set to
-- "none" cost zero frames across the whole pool. Enabling a row later builds the
-- missing containers through the ensure pass in NPC_ReloadAll.
function QueueBundleBuild() -- forward-declared local (pool growth + login build)
    queuedBundles = queuedBundles + 1
    do
        local nb
        -- Fully combat-legal since 68914 (skeleton creation included), so
        -- after an in-combat /reload the whole pool builds WHILE fighting.
        AKWorker:Queue(function()
            nb = table.remove(skeletons)
            if not nb then nb = CreateBundleSkeleton() end
            local ds = ns.GetAuraSlots()
            if ds and ds ~= "none" then AddBundleDebuffs(nb) end
        end, "np:debuffs")
        AKWorker:Queue(function()
            if not nb then return end -- bundle lost to a hard error upstream
            local _, bs = ns.GetAuraSlots()
            if bs and bs ~= "none" then AddBundleBuffs(nb) end
        end, "np:buffs")
        -- Two stages under one label: the bundle build and the plate attach must
        -- not share a watchdog attempt (a reconnect mid-pull retried the combined
        -- cost to its third strike). "again" front-requeues, so the attach still
        -- follows its own bundle before any newer work.
        local pooled = false
        AKWorker:Queue(function()
            if not nb then return end -- bundle lost to a hard error upstream
            if not pooled then
                local _, _, cs = ns.GetAuraSlots()
                if cs and cs ~= "none" then AddBundleCC(nb) end
                -- NPF record groups apply at BUILD: growth bundles (pre-warm,
                -- attach growth) never see the one-shot reload or a config-FP
                -- flip, and without this their np group renders unfiltered.
                NPF_EnsureRecords(nb)
                -- Mark before the insert: a watchdog between the two loses one
                -- bundle (growth rebuilds it) rather than pooling it twice.
                pooled = true
                pool[#pool + 1] = nb
                built = built + 1
                return "again"
            end
            ServiceWaiting()
            if built == POOL_SIZE then ns.NPC_ReloadAll() end
        end, "np:cc+pool")
    end
end

local function QueuePoolBuild()
    for i = 1, POOL_SIZE do
        QueueBundleBuild()
    end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:RegisterEvent("PLAYER_TARGET_CHANGED")
boot:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        AK = AK or EllesmereUI.AuraKit
        if not AK then return end
        if AuraContainerSortMethod then
            SORT_IMPORTANT = AuraContainerSortMethod.ImportantOnly
            SORT_DEFAULT = AuraContainerSortMethod.Default
        end
        if AuraContainerSortDirection then
            SORT_DIR = AuraContainerSortDirection.Normal
        end
        for i = 1, #KINDS do
            AK.styles["np:" .. KINDS[i]] = BuildNPStyle(KINDS[i])
        end
        AK.styles["np:buffs2"] = BuildNPStyle("buffs", 2)
        AK.styles["np:buffsplain"] = BuildNPStyle("buffs", "plain")
        -- No skeleton pre-birth: creation is combat-legal since 68914, so pool jobs
        -- birth their skeletons inline whenever they run. Plates that spawn before the
        -- first bundles land wait in `waiting` and are serviced as bundles complete.
        QueuePoolBuild()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Capability-split restriction edge: NPB.Split reads AurasRestricted,
        -- which flips on zone edges -- a changed answer re-drives the split
        -- (CfgFP carries it) and the affected styles.
        local nowRestricted = (AK and AK.AurasRestricted and AK.AurasRestricted()) and true or false
        if NPB.lastRestricted ~= nowRestricted then
            NPB.lastRestricted = nowRestricted
            if ns.NPC_ReloadAll then ns.NPC_ReloadAll() end
        end
        -- Content-aware pre-warm (idempotent: queuedBundles only grows, so
        -- repeated zone-ins are no-ops once the target is met; the pool
        -- never shrinks -- engine frames are never freed anyway). The
        -- zone-in drain rides the login turbo window, not combat frames.
        local _, instanceType = IsInInstance()
        if AK and (instanceType == "party" or instanceType == "raid") then
            for _ = queuedBundles + 1, POOL_TARGET_INSTANCE do
                QueueBundleBuild()
            end
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        -- Class power on the target plate pushes top-anchored rows up. Only the
        -- outgoing and incoming target plates can change, so re-anchor exactly those
        -- two -- a full-pool ReanchorActive here re-drove the layout setters on every
        -- plate on every target swap (target churn is constant in combat).
        local ds, bs, cs = ns.GetAuraSlots()
        local prev = lastTargetPlate
        lastTargetPlate = nil
        for plate, b in pairs(active) do
            local isNew = plate.unit and UnitIsUnit(plate.unit, "target")
            if isNew then lastTargetPlate = plate end
            if isNew or plate == prev then
                AnchorNPContainer(b.containers.debuffs, "debuffs", plate, ds)
                AnchorNPContainer(b.containers.buffs, "buffs", plate, bs)
                AnchorNPContainer(b.containers.cc, "cc", plate, cs)
                ns.PositionArrowsOutsideAuras(plate)
            end
        end
    end
end)

