if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Nameplates_Options\DisplayLayout_Options.lua
--  Nameplates options: the Style, Core Positions and Core Text Positions
--  sections of the Display page. Called by BuildDisplayPage; returns y, the
--  rows and text cells its click navigation maps to, and the cog popup and
--  texture helpers DisplayBars_Options.lua uses. The Core Text Coloring
--  section under Core Text Positions lives in CoreTextColoring_Options.lua
--  (called from here; it reads the text slot table defined below). Shared
--  helpers come from ns._NPO_OptEnv, the per-build slot helpers from ctx.
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUINameplates"]
if not ns then return end  -- module disabled: no options page

-- The options page frame pool (EllesmereUI_FramePool.lua): frames made under a
-- pooled page part are handed back to the page's next build.
local CreateFrame = EllesmereUI._Pool.CreateFrame
local PoolGen = EllesmereUI._Pool.Gen

-- Core Text Positions. KNOWN: the elements a text position draws; any other
-- saved value (None, unset, one this build does not know) shows nothing and
-- leaves the position free.
local KNOWN = { enemyName = true, levelName = true, nameLevel = true, level = true, targetOfTarget = true,
    healthPercent = true, healthPercentNoSign = true, healthNumber = true, healthPctNum = true,
    healthNumPct = true, healthPctNumDash = true, healthNumPctDash = true, healthNumMax = true,
    custom = true }
-- Add Text Slot's text: the first of these whose font string no shown text
-- uses (one per font string: name, health %, level, health #, Target of
-- Target).
local ADD_ORDER = { "enemyName", "healthPercent", "level", "healthNumber", "targetOfTarget" }
-- Keys a moved text takes along: as saved (MOVE_RAW), and as the difference
-- from each position's default (MOVE_OFFSETS). Its Size and colour mode go
-- along through MoveText too.
local MOVE_RAW = { "Strata", "Color", "NameColorOn", "NameColor", "LevelColorOn", "LevelColor", "LevelDiffOn",
                   "WidthPct", "Wrap", "PctDecimal", "NameFormat", "CustomFormat" }
local MOVE_OFFSETS = { "XOffset", "YOffset" }

-- The eight text positions, in the order of the Core Text Positions list, its
-- position menus and the Core Text Coloring section (CoreTextColoring_Options.lua
-- reads this table at build time).
ns.NPO_TEXT_SLOTS = {
    { key = "textSlotTop",         label = "Top Text",          menu = "Top",          coloring = "Top Text Coloring" },
    { key = "textSlotTopLeft",     label = "Top Left Text",     menu = "Top Left",     coloring = "Top Left Text Coloring" },
    { key = "textSlotTopRight",    label = "Top Right Text",    menu = "Top Right",    coloring = "Top Right Text Coloring" },
    { key = "textSlotRight",       label = "Right Text",        menu = "Right",        coloring = "Right Text Coloring" },
    { key = "textSlotLeft",        label = "Left Text",         menu = "Left",         coloring = "Left Text Coloring" },
    { key = "textSlotCenter",      label = "Center Text",       menu = "Center",       coloring = "Center Text Coloring" },
    { key = "textSlotBottomLeft",  label = "Bottom Left Text",  menu = "Bottom Left",  coloring = "Bottom Left Text Coloring" },
    { key = "textSlotBottomRight", label = "Bottom Right Text", menu = "Bottom Right", coloring = "Bottom Right Text Coloring" },
}
local POS_ORDER, POS_VALUES = {}, {}
for i = 1, #ns.NPO_TEXT_SLOTS do
    local s = ns.NPO_TEXT_SLOTS[i]
    POS_ORDER[i] = s.key
    POS_VALUES[s.key] = s.menu
end

-- Custom text popup for a text position: the template is stored in
-- <slot>CustomFormat, then onSave selects Custom for the position.
function ns.NPO_EditCustomText(slotKey, onSave)
    local env = ns._NPO_OptEnv
    local key = slotKey .. "CustomFormat"
    -- The slot's colour as the nameplate preview paints it (Text Coloring mode),
    -- copied: the level colour is a reused table.
    local c = ns.NPO_PreviewSlotColor(slotKey)
    EllesmereUI.TextTags.EditPopup({
        cat = ns.NP_TextTags, color = c and { r = c.r, g = c.g, b = c.b }, onSave = onSave,
        tagNotes = { hp = EllesmereUI.L("shows DEAD") },
        get = function() return env.DB()[key] end,
        set = function(txt) env.DB()[key] = txt end,
    })
end

-- A copy of the text dropdown's values whose Custom entry is an action that opens
-- the popup (edit), its pencil at full alpha while getValue() is "custom" (the menu
-- reads it when built; a selection rebuilds the page); Remove in the house red.
function ns.NPO_CustomTextValues(values, getValue, edit)
    return EllesmereUI.TextTags.MenuValues(values, edit,
        { removeKey = "none", selected = function() return getValue() == "custom" end })
end

-- A position shows a text while its element is a KNOWN one.
function ns.NPO_TextSlotShown(slotKey) return KNOWN[ns._NPO_OptEnv.DBVal(slotKey)] == true end

-- The texts' structure: each position's element and, for a shown text, its
-- colour mode (which decides its Core Text Coloring controls). Taken at each
-- page build; a cached Display page whose structure changed behind it is
-- rebuilt on restore (EUI_Nameplates_Options.lua, onPageCacheRestore).
function ns.NPO_TextStructureFP()
    local env = ns._NPO_OptEnv
    local DBVal, db = env.DBVal, env.DB()
    local parts = {}
    for i = 1, #POS_ORDER do
        local key = POS_ORDER[i]
        local el = DBVal(key)
        parts[#parts + 1] = tostring(el)
        if KNOWN[el] then parts[#parts + 1] = ns.NP_SlotColorMode(key, db) end
    end
    return table.concat(parts, "\31")
end

-- The Display page cog popup and the cog icon that owns it: built on the first
-- cog click and kept across page builds (ShowCogPopup below). cogPopupOwnerGen:
-- the owner's dress when it opened the popup (page reuse dresses the same button
-- again for a later build, which then is a new owner).
local cogPopup, cogPopupOwner, cogPopupOwnerGen

-- The cog that opened the popup, while it is still the dress that opened it.
local function LiveCogOwner()
    if cogPopupOwner and PoolGen(cogPopupOwner) == cogPopupOwnerGen then return cogPopupOwner end
end

-- True once the cog that opened the popup no longer stands for it: a later
-- page build dressed it again (for its element or another one), left it idle
-- or dropped the row it sits in. The popup would edit one element from
-- another one's control, or hang off a hidden frame, so it closes. A cog made
-- outside the page pool (every page while page reuse is off) has no
-- generation and never closes here.
local function CogOwnerGone()
    local owner = cogPopupOwner
    if not owner then return false end
    local g = PoolGen(owner)
    if g == nil and cogPopupOwnerGen == nil then return false end
    return g ~= cogPopupOwnerGen or not owner:IsVisible()
end

local function BuildDisplayLayout(parent, y, ctx)
    local env = ns._NPO_OptEnv
    local DB, DBVal, defaults, GetNPOptOutline = env.DB, env.DBVal, env.defaults, env.GetNPOptOutline
    local hbtOrder, hbtValues, optState, pairs = env.hbtOrder, env.hbtValues, env.optState, env.pairs
    local plates, PP, UpdatePreview, RefreshAllPlates = env.plates, env.PP, env.UpdatePreview, env.RefreshAllPlates
    local GetElementAtPosition, RefreshAllSlots, SetElementAtPosition, SetTextElementAtSlot = ctx.GetElementAtPosition, ctx.RefreshAllSlots, ctx.SetElementAtPosition, ctx.SetTextElementAtSlot
    local W = ctx.W
    local _, h
    -- This build of the page (the serial moves after every page pass; page reuse
    -- keeps one wrapper, so the wrapper cannot tell two builds apart).
    local buildSerial = EllesmereUI._pageBuildSerial or 0

    -----------------------------------------------------------------------
    --  STYLE
    -----------------------------------------------------------------------
    local styleHeader
    styleHeader, h = W:SectionHeader(parent, "STYLE", y);  y = y - h
    y = EllesmereUI.BlizzStyle.Note(parent, y, "nameplates")

    local function RefreshAllTextures()
        ns.RefreshAllSettings()
        for _, plate in pairs(ns.friendlyPlates or {}) do
            if ns.ApplyHealthBarTexture then ns.ApplyHealthBarTexture(plate) end
            if ns.ApplyCastBarTexture then ns.ApplyCastBarTexture(plate) end
        end
    end

    -- Row 1: Border (None/Basic/Custom) | Border Size. Pure VIEW over showBorder + customBorderEnabled: None=off, Basic=standard border, Custom=custom border engine (reveals the Custom Border row below via page rebuild; None/Basic collapse it).
    -- Both stock styles gate both slots: they draw their own art (the stock background, the vanilla border sheets) and stand every EUI border down.
    local borderStyleRow
    borderStyleRow, h = W:DualRow(parent, y,
        EllesmereUI.BlizzStyle.Gate("nameplates", { type="dropdown", text="Border",
          values={ none = "None", basic = "Basic", custom = "Custom" },
          order={ "none", "basic", "custom" },
          getValue=function()
            if DBVal("customBorderEnabled") then return "custom" end
            local sb = DBVal("showBorder")
            if sb == nil then sb = defaults.showBorder end
            return sb and "basic" or "none"
          end,
          setValue=function(v)
            if v == "custom" then
              DB().customBorderEnabled = true
            elseif v == "basic" then
              DB().customBorderEnabled = false
              DB().showBorder = true
            else
              DB().customBorderEnabled = false
              DB().showBorder = false
            end
            ns.RefreshBorder()
            ns.RefreshBorderColor()
            UpdatePreview()
            -- Force rebuild so the Custom Border row shows/hides and rows below reflow.
            EllesmereUI:RefreshPage(true)
          end }, EllesmereUI.BlizzStyle.Active("nameplates") == "classic"),
        EllesmereUI.BlizzStyle.Gate("nameplates", { type="slider", text="Border Size", min=1, max=4, step=1,
          -- Only Basic uses this size (None has no border; Custom uses its own Custom Border Size below).
          disabled=function()
            if DBVal("customBorderEnabled") then return true end
            local v = DBVal("showBorder")
            if v == nil then return not defaults.showBorder end
            return not v
          end,
          disabledTooltip="This option is only used by the Basic border.",
          rawTooltip=true,
          getValue=function() return DBVal("borderSize") or defaults.borderSize end,
          setValue=function(v)
            DB().borderSize = v
            ns.RefreshBorder()
            UpdatePreview()
          end }))
    y = y - h
    -- Corner Radius (EllesmereUI_RoundedCorners.lua): an inline cog on the
    -- border size control. The stock styles keep every plate square, and so
    -- does Wrap Around Castbar (the plates stand rounding down while it is on).
    if not EllesmereUI._prebuilding then
        EllesmereUI.BuildInlineCog(borderStyleRow._rightRegion, {
            title = "Corner Radius", tip = "Corner Radius",
            disabled = function()
                if EllesmereUI.BlizzStyle.Get("nameplates") then return true end
                if DBVal("wrapBorderCastbar") == true then return true end
                return DBVal("customBorderEnabled") and not EllesmereUI.RoundedStyleOK(DBVal("customBorderTexture") or defaults.customBorderTexture)
            end,
            disabledTooltip = function()
                if EllesmereUI.BlizzStyle.Get("nameplates") then return EllesmereUI.BlizzStyle.Label("nameplates") end
                if DBVal("wrapBorderCastbar") == true then return "Wrap Around Castbar" end
                return "This option requires the Solid, Glow or Shadow border style."
            end,
            requireState = "disabled",
            rows = EllesmereUI.RoundedJoinRow(EllesmereUI.RoundedCornerRows({
                { type = "slider", label = "Corner Radius", min = 0, max = EllesmereUI.ROUNDED_MAX_RADIUS, step = 1,
                  get = function() return DBVal("cornerRadius") or 0 end,
                  set = function(v) DB().cornerRadius = v; ns.RefreshBorder(); ns.RefreshCastBorder(); UpdatePreview() end },
            }, function() return DBVal("cornerMask") end,
               function(v) DB().cornerMask = v; ns.RefreshBorder(); ns.RefreshCastBorder(); UpdatePreview() end),
                "Join Cast Bar", "While a cast shows, rounds the health bar and the cast bar under it as one shape.",
                function() return DBVal("cornerJoinCast") end,
                function(v) DB().cornerJoinCast = v; ns.RefreshBorder(); ns.RefreshCastBorder(); UpdatePreview() end),
        })
    end
    -- Inline cog on the Border region: opt-in "Wrap Around Castbar" (beside the control; the colour swatch sits left of it); dimmed only for "None" mode (wrap applies to both Basic and Custom).
    if not EllesmereUI._prebuilding then
        local leftRgn = borderStyleRow._leftRegion
        local function wrapCogOff()
            -- Only "None" disables it; Basic and Custom both support the wrap.
            -- Neither stock style has an EUI border to wrap: Blizzard Style
            -- draws the stock background art, Classic WoW UI the vanilla
            -- border sheets, and both stand the EUI borders down.
            if ns.NP_Blizz() then return true end
            if DBVal("customBorderEnabled") then return false end
            local v = DBVal("showBorder")
            if v == nil then v = defaults.showBorder end
            return not v
        end
        local wrapRows = {
            { type="toggle", label="Wrap Around Castbar",
              -- Classic WoW UI draws the vanilla borders: nothing to wrap.
              disabled=function() return EllesmereUI.BlizzStyle.Active("nameplates") == "classic" end,
              disabledTooltip=function() return EllesmereUI.BlizzStyle.Label("nameplates") end,
              requireState="disabled",
              get=function()
                local v = DBVal("wrapBorderCastbar")
                if v == nil then return defaults.wrapBorderCastbar end
                return v
              end,
              set=function(v)
                DB().wrapBorderCastbar = v
                -- Unconditional re-apply so toggling OFF also unwraps any plate mid-cast and wrapped.
                ns.ApplyBorderWrapToAll()
                -- Corner Radius stands down while the wrap is on: square or re-round the plates.
                if (DBVal("cornerRadius") or 0) > 0 then ns.RefreshBorder(); ns.RefreshCastBorder() end
                UpdatePreview()
                -- Show Seam Line's and Corner Radius's disabled states follow this toggle.
                EllesmereUI:RefreshPage()
              end },
        }
        -- Show Seam Line: the custom border's wrap only, so it is built only while
        -- Border = Custom (the Border setter rebuilds the page).
        if DBVal("customBorderEnabled") then
            wrapRows[#wrapRows + 1] = { type="toggle", label="Show Seam Line",
              tooltip="Draws the border style's seam line between the health and cast bars.",
              disabled=function()
                return DBVal("wrapBorderCastbar") ~= true
                    or not ns.NP_CanShowWrapSeam(DBVal("customBorderTexture") or defaults.customBorderTexture)
              end,
              -- Wrap off: the standard requirement line; wrap on: the style is the lock.
              disabledTooltip=function()
                if DBVal("wrapBorderCastbar") ~= true then return "Wrap Around Castbar" end
                return "This option requires the Pixels or Pixels Textured border style."
              end,
              rawTooltip=function() return DBVal("wrapBorderCastbar") == true end,
              get=function() return DBVal("wrapBorderSeam") == true end,
              set=function(v)
                DB().wrapBorderSeam = v
                ns.ApplyBorderWrapToAll()
                UpdatePreview()
              end }
        end
        EllesmereUI.BuildInlineCog(leftRgn, {
            disabled = wrapCogOff,
            disabledTooltip = "This option requires a Border to be selected",
            title = "Castbar Border",
            rows = wrapRows,
        })
    end

    -- Inline swatch on the Border dropdown: standard (Basic) border color, dimmed unless mode is Basic.
    if not EllesmereUI._prebuilding then
        local leftRgn = borderStyleRow._leftRegion
        local function isBorderOff()
            -- Off for None and Custom (standard border/color is inert then) -- only Basic uses it.
            if EllesmereUI.BlizzStyle.Get("nameplates") then return true end
            if DBVal("customBorderEnabled") then return true end
            local v = DBVal("showBorder")
            if v == nil then return not defaults.showBorder end
            return not v
        end
        local borderColorGet = function()
            local c = (DB() and DB().borderColor) or defaults.borderColor
            return c.r, c.g, c.b
        end
        local borderColorSet = function(r, g, b)
            DB().borderColor = { r = r, g = g, b = b }
            ns.RefreshBorderColor()
            UpdatePreview()
        end
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, borderColorGet, borderColorSet, nil, 20)
        PP.Point(swatch, "RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -8, 0)
        leftRgn._lastInline = swatch
        EllesmereUI.RegisterWidgetRefresh(function()
            local off = isBorderOff()
            swatch:SetAlpha(off and 0.15 or 1)
            swatch:EnableMouse(not off)
            updateSwatch()
        end)
        local off = isBorderOff()
        swatch:SetAlpha(off and 0.15 or 1)
        swatch:EnableMouse(not off)
    end

    -- Classic WoW UI only: the level, and the icon that replaces it on a
    -- boss, both seated in the health border's own plate. Each follows
    -- the bar's height until sized here, and each carries its X/Y nudges
    -- on an inline cog. Not built at all on the other styles, where there
    -- is no plate to fill; the if-body scopes its locals.
    if EllesmereUI.BlizzStyle.Active("nameplates") == "classic" then
        local classicPlateRow
        classicPlateRow, h = W:DualRow(parent, y,
            { type="slider", text="Level Size", min=0, max=40, step=1,
              tooltip="Size of the level in the border's plate. 0 follows the bar height.",
              getValue=function() return DBVal("classicLevelSize") or 0 end,
              setValue=function(v)
                DB().classicLevelSize = v
                ns.RefreshAllSettings()
                UpdatePreview()
              end },
            { type="slider", text="Elite Icon Size", min=0, max=40, step=1,
              tooltip="Size of the icon that replaces the level on a boss. 0 follows the bar height.",
              getValue=function() return DBVal("classicSkullSize") or 0 end,
              setValue=function(v)
                DB().classicSkullSize = v
                ns.RefreshAllSettings()
                UpdatePreview()
              end })
        y = y - h
        -- Reached by the preview's click navigation (the level in the
        -- border's plate scrolls here), which is built further down.
        parent._classicPlateRow = classicPlateRow
        if not EllesmereUI._prebuilding then
            local function PlateOffsetCog(rgn, title, xKey, yKey)
                EllesmereUI.BuildInlineCog(rgn, {
                    title = title,
                    rows = {
                        { type="slider", label="X Offset", min=-50, max=50, step=1,
                          get=function() return DBVal(xKey) or 0 end,
                          set=function(v)
                            DB()[xKey] = v
                            ns.RefreshAllSettings()
                            UpdatePreview()
                          end },
                        { type="slider", label="Y Offset", min=-50, max=50, step=1,
                          get=function() return DBVal(yKey) or 0 end,
                          set=function(v)
                            DB()[yKey] = v
                            ns.RefreshAllSettings()
                            UpdatePreview()
                          end },
                    },
                })
            end
            PlateOffsetCog(classicPlateRow._leftRegion, "Level Position", "classicLevelX", "classicLevelY")
            PlateOffsetCog(classicPlateRow._rightRegion, "Elite Icon Position", "classicSkullX", "classicSkullY")
        end
    end

    -- Custom Border row: only built when Border dropdown = "Custom" (selecting it triggers a page rebuild that reveals this row and reflows rows below;
    -- None/Basic collapse it). Uses the shared border engine (identical to Unit Frames, full SharedMedia support); the if-body scopes its locals to avoid growing this builder's local count.
    if DBVal("customBorderEnabled") then
        -- Custom Border Style dropdown (+ options cog) | Custom Border Size (+ color swatch)
        local cbTexValues, cbTexOrder = EllesmereUI.GetBorderTextureDropdown()
        local customBorderRow
        customBorderRow, h = W:DualRow(parent, y,
            EllesmereUI.BlizzStyle.Gate("nameplates", { type="dropdown", text="Custom Border Style",
              values=cbTexValues, order=cbTexOrder,
              getValue=function() return DBVal("customBorderTexture") or defaults.customBorderTexture end,
              setValue=function(v)
                DB().customBorderTexture = v
                DB().customBorderOffset  = nil
                DB().customBorderOffsetY = nil
                DB().customBorderShiftX  = nil
                DB().customBorderShiftY  = nil
                local _bcol, _bbehind = EllesmereUI.GetBorderStyleSelectDefaults(v)
                DB().customBorderColor  = _bcol
                DB().customBorderAlpha  = 1
                DB().customBorderBehind = _bbehind
                local defSz = EllesmereUI.GetBorderDefaultSize("nameplates", v)
                if defSz then DB().customBorderSize = defSz end
                if DB().customBorderSizePx then DB().customBorderSizePx = false end
                ns.RefreshBorder()
                UpdatePreview()
                -- Full rebuild: the Width/Height Offset row below exists only for a textured style.
                EllesmereUI:RefreshPage(true)
              end }),
            EllesmereUI.BlizzStyle.Gate("nameplates", EllesmereUI.BorderPxSliderCfg({
              -- Narrower track: the slot also carries the colour swatch and the Icon Borders cog.
              text="Custom Border Size", trackWidth=120,
              getStep=function() return DBVal("customBorderSize") or defaults.customBorderSize end,
              setStep=function(step) DB().customBorderSize = step end,
              getTex=function() return DBVal("customBorderTexture") or defaults.customBorderTexture end,
              getPx=function() return DB() and DB().customBorderSizePx end,
              setPx=function(v) DB().customBorderSizePx = v end,
              apply=function()
                ns.RefreshBorder()
                UpdatePreview()
              end })))
        y = y - h

        -- Width Offset | Height Offset: the textured border's outward offsets, shown only while a
        -- textured style is selected (Solid has none). Built during prebuild too so the y advance matches.
        do
            local cbTexNow = DBVal("customBorderTexture") or defaults.customBorderTexture
            if cbTexNow and cbTexNow ~= "" and cbTexNow ~= "solid" then
                local ocfgL, ocfgR = EllesmereUI.BorderOffsetRowCfgs({
                    addonKey   = "nameplates",
                    getTex     = function() return DBVal("customBorderTexture") or defaults.customBorderTexture end,
                    getStep    = function() return DBVal("customBorderSize") or defaults.customBorderSize end,
                    getSizeKey = function() return DBVal("customBorderSize") or defaults.customBorderSize end,
                    getPx      = function() return DB() and DB().customBorderSizePx end,
                    getX       = function() return DB() and DB().customBorderOffset end,
                    setX       = function(v) DB().customBorderOffset = v end,
                    getY       = function() return DB() and DB().customBorderOffsetY end,
                    setY       = function(v) DB().customBorderOffsetY = v end,
                    apply      = function() ns.RefreshBorder(); UpdatePreview() end,
                })
                _, h = W:DualRow(parent, y,
                    EllesmereUI.BlizzStyle.Gate("nameplates", ocfgL),
                    EllesmereUI.BlizzStyle.Gate("nameplates", ocfgR))
                y = y - h
            end
        end

        -- Inline "Border Options" cog on the Custom Border Style region (shifts + Show Behind)
        if not EllesmereUI._prebuilding then
            local leftRgn = customBorderRow._leftRegion
            -- Shift offsets only apply to textured styles (row only exists when Custom is selected, so no enable gate needed).
            local function cbCogOff() return (DBVal("customBorderTexture") or defaults.customBorderTexture) == "solid" end
            EllesmereUI.BuildInlineCog(leftRgn, {
                disabled = cbCogOff,
                disabledTooltip = "This option requires a textured border style",
                title = "Border Options",
                rows = {
                    { type="slider", label="Shift X", min=-10, max=10, step=1,
                      get=function()
                        local v = DB() and DB().customBorderShiftX
                        if v then return v end
                        local tex = DBVal("customBorderTexture") or defaults.customBorderTexture
                        local sz  = DBVal("customBorderSize") or defaults.customBorderSize
                        local _, _, dsx = EllesmereUI.GetBorderDefaults("nameplates", tex, sz)
                        return dsx
                      end,
                      set=function(v) DB().customBorderShiftX = (v == 0 and nil or v); ns.RefreshBorder(); UpdatePreview() end },
                    { type="slider", label="Shift Y", min=-10, max=10, step=1,
                      get=function()
                        local v = DB() and DB().customBorderShiftY
                        if v then return v end
                        local tex = DBVal("customBorderTexture") or defaults.customBorderTexture
                        local sz  = DBVal("customBorderSize") or defaults.customBorderSize
                        local _, _, _, dsy = EllesmereUI.GetBorderDefaults("nameplates", tex, sz)
                        return dsy
                      end,
                      set=function(v) DB().customBorderShiftY = (v == 0 and nil or v); ns.RefreshBorder(); UpdatePreview() end },
                    { type="toggle", label="Show Behind",
                      get=function()
                        local v = DBVal("customBorderBehind")
                        if v == nil then return defaults.customBorderBehind end
                        return v
                      end,
                      set=function(v) DB().customBorderBehind = v; ns.RefreshBorder(); UpdatePreview() end },
                },
            })
        end

        -- "Icon Borders" cog on the Custom Border Size region, beside the control (the colour
        -- swatch below chains left of it): the custom border on the aura icons and on the
        -- cast spell icon. A cog, not a row: both are niche, and the whole block exists
        -- only while Border = Custom. The if-body scopes its locals (builder budget).
        if not EllesmereUI._prebuilding then
            local rightRgn = customBorderRow._rightRegion
            EllesmereUI.BuildInlineCog(rightRgn, {
                title = "Icon Borders",
                captureRegion = rightRgn,
                rows = {
                    { type="toggle", label="Custom Border on Aura Icons",
                      tooltip="Gives debuff, buff and crowd control icons the custom border instead of the 1-pixel border.",
                      disabled=function()
                        return DBVal("hideDebuffIconBorder") == true and DBVal("hideBuffIconBorder") == true
                            and DBVal("hideCCIconBorder") == true
                      end,
                      disabledTooltip="This option requires at least one aura type to show its border.",
                      rawTooltip=true,
                      get=function() return DBVal("auraIconCustomBorder") == true end,
                      set=function(v)
                        DB().auraIconCustomBorder = v
                        -- Fingerprint-gated aura restyle (the cast-lockout icon included).
                        ns.NPC_ReloadAll()
                        UpdatePreview()
                      end },
                    { type="toggle", label="Custom Border on Spell Icon",
                      tooltip="Gives the cast bar spell icon the custom border instead of its 1-pixel border.",
                      disabled=function()
                        return DBVal("showCastIcon") == false or DBVal("hideCastIconBorder") == true
                            or DBVal("castbarIconInWidth") == true
                      end,
                      disabledTooltip=function()
                        if DBVal("castbarIconInWidth") == true then
                            return "This option is disabled while Make Icon Part of the Bar is enabled."
                        end
                        return "This option requires the spell icon and its border to be shown."
                      end,
                      rawTooltip=true,
                      get=function() return DBVal("castIconCustomBorder") == true end,
                      set=function(v)
                        DB().castIconCustomBorder = v
                        -- Re-applies every plate's appearance (pooled plates too), which
                        -- builds or turns off the icon border.
                        ns.RefreshAllSettings()
                        UpdatePreview()
                      end },
                    { type="toggle", label="Vertical Separator",
                      tooltip="Draws a divider between the integrated spell icon and the cast bar using the custom border appearance.",
                      disabled=function() return not ns.NP_CanShowCastIconSeparator(DB()) end,
                      disabledTooltip="Requires Make Icon Part of the Bar, a shown non-full-sized icon, and a Solid or Pixels border with size above 0.",
                      rawTooltip=true,
                      get=function() return DBVal("castIconSeparator") == true end,
                      set=function(v)
                        DB().castIconSeparator = v
                        ns.RefreshAllSettings()
                        UpdatePreview()
                      end },
                },
            })
        end

        -- Inline color swatch (with alpha) on the Custom Border Size region
        if not EllesmereUI._prebuilding then
            local rightRgn = customBorderRow._rightRegion
            local cbColGet = function()
                local c = (DB() and DB().customBorderColor) or defaults.customBorderColor
                return c.r, c.g, c.b, (DBVal("customBorderAlpha") or defaults.customBorderAlpha or 1)
            end
            local cbColSet = function(r, g, b, a)
                DB().customBorderColor = { r = r, g = g, b = b }
                if a ~= nil then DB().customBorderAlpha = a end
                ns.RefreshBorderColor()
                UpdatePreview()
            end
            local cbSwatch, cbUpdateSwatch = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5, cbColGet, cbColSet, true, 20)
            PP.Point(cbSwatch, "RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -8, 0)
            rightRgn._lastInline = cbSwatch
            EllesmereUI.RegisterWidgetRefresh(function() cbUpdateSwatch() end)
        end
    end

    -- Row 2: Background (+swatch) | Absorb Style (+cog, preview eye) -- placed here so the section fills sequentially, no blank middle slot. Absorb Style options: Blizzard + the stripe overlay set (shared with Focus Texture) + Clean; stripe keys resolve via ns.ResolveOverlayTexPath.
    local absorbStyleValues = {
        ["blizzard"]="Blizzard",
        ["striped"]="Striped",
        ["striped-v2"]="Stripes",
        ["striped-wide-v2"]="Wide Stripes",
        ["stripes-medium"]="Medium Stripes",
        ["stripes-small-close"]="Small Dense Stripes",
        ["stripes-small-spread"]="Small Spread Stripes",
        ["striped-tiny"]="Tiny Stripes",
        ["clean"]="Clean (Flat)",
        ["pixelsShield"]="Pixels Shield",
        ["pixelsShieldEdge"]="Pixels Shield Edge",
        ["pixelsShieldFill"]="Pixels Shield Fill",
    }
    local absorbStyleOrder = {
        "blizzard", "striped",
        "striped-v2", "striped-wide-v2", "stripes-medium",
        "stripes-small-close", "stripes-small-spread", "striped-tiny",
        "clean", "pixelsShield", "pixelsShieldEdge", "pixelsShieldFill",
    }
    -- Append SharedMedia statusbar textures after a divider (mirrors Bar Texture). SM keys ("sm:") were added to the shared health-bar tables by AppendSharedMediaTextures; resolution flows via ns.ResolveOverlayTexPath -> health-bar lookup, so SM keys paint correctly here.
    do
        local sepAdded = false
        for _, k in ipairs(hbtOrder) do
            if k ~= "---" and k:find("^sm:") then
                if not sepAdded then
                    absorbStyleOrder[#absorbStyleOrder + 1] = "---"
                    sepAdded = true
                end
                absorbStyleOrder[#absorbStyleOrder + 1] = k
                absorbStyleValues[k] = hbtValues[k]
            end
        end
        -- Preview swatch behind each menu row resolves exactly like the render path: NP_ABSORB_STYLE_TEX for blizzard/striped/clean, then ns.ResolveOverlayTexPath for stripe overlays/SM keys.
        absorbStyleValues._menuOpts = {
            itemHeight = 28,
            background = function(key)
                if not key or key == "---" then return nil end
                return ns.NP_ABSORB_STYLE_TEX[key] or ns.ResolveOverlayTexPath(key)
            end,
        }
    end
    local bgHoverRow
    bgHoverRow, h = W:DualRow(parent, y,
        ns.NP_BlizzOnlyGate({ type="slider", text="Background", min=0, max=100, step=1,
          getValue=function()
            return math.floor(((DBVal("bgAlpha") or defaults.bgAlpha) * 100) + 0.5)
          end,
          setValue=function(v)
            DB().bgAlpha = v / 100
            local c = (DB() and DB().bgColor) or defaults.bgColor
            for _, plate in pairs(plates) do
                plate.healthBG:SetColorTexture(c.r, c.g, c.b, v / 100)
            end
            UpdatePreview()
          end }),
        { type="dropdown", text="Absorb Style", values=absorbStyleValues, order=absorbStyleOrder,
          getValue=function() return DBVal("absorbStyle") or "blizzard" end,
          setValue=function(v)
            DB().absorbStyle = v
            -- Selecting a style sets opacity to that style's default (Blizzard/Stripes 80%, Clean 30%); slider tweaks from there.
            DB().absorbAlpha = math.floor(((ns.NP_ABSORB_STYLE_ALPHA[v] or 0.8) * 100) + 0.5)
            ns.ApplyAbsorbStyleAll()
            UpdatePreview()
            -- Refresh so the color swatch enables/disables (Blizzard = off).
            EllesmereUI:RefreshPage()
          end })
    y = y - h
    -- Inline color swatch on Background (left region)
    if not EllesmereUI._prebuilding then
        local leftRgn = bgHoverRow._leftRegion
        local cbColorGet = function()
            local c = (DB() and DB().bgColor) or defaults.bgColor
            return c.r, c.g, c.b
        end
        local cbColorSet = function(r, g, b)
            DB().bgColor = { r = r, g = g, b = b }
            local a = DBVal("bgAlpha") or defaults.bgAlpha
            for _, plate in pairs(plates) do
                plate.healthBG:SetColorTexture(r, g, b, a)
            end
            UpdatePreview()
        end
        local cbSwatch, cbUpdateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, cbColorGet, cbColorSet, nil, 20)
        PP.Point(cbSwatch, "RIGHT", leftRgn._control, "LEFT", -12, 0)
        leftRgn._lastInline = cbSwatch
        EllesmereUI.RegisterWidgetRefresh(function() cbUpdateSwatch() end)
        if ns.NP_BlizzOnly() then EllesmereUI.BlizzStyle.BlockInline("nameplates", cbSwatch) end
    end

    -- Inline "Absorb Settings" cog on the Absorb Style region (right of Row 2)
    if not EllesmereUI._prebuilding then
        local rgn = bgHoverRow._rightRegion
        EllesmereUI.BuildInlineCog(rgn, {
            title = "Absorb Settings",
            rows = {
                { type = "slider", label = "Opacity", min = 5, max = 100, step = 1,
                  get = function()
                    local v = DBVal("absorbAlpha")
                    if v then return v end
                    -- Untouched profiles: show the active style's default.
                    local style = DBVal("absorbStyle") or "blizzard"
                    if style == "clean" then return DBVal("absorbCleanAlpha") or 30 end
                    return math.floor(((ns.NP_ABSORB_STYLE_ALPHA[style] or 0.8) * 100) + 0.5)
                  end,
                  set = function(v)
                    DB().absorbAlpha = v
                    ns.ApplyAbsorbStyleAll()
                    UpdatePreview()
                  end },
                -- Same placements as the unit frames' Absorb Rendering cog, except
                -- that Overlay Reverse here keeps a shield larger than current
                -- health, as their Overlay Reverse (Full) does (their plain
                -- Overlay Reverse clips that excess).
                { type = "dropdown", label = "Placement",
                  tooltip = "Overlay fills empty health first, then draws any excess over current health. Overlay Reverse draws the shield back over current health; a shield larger than current health spans from the bar's left end. From Right Edge and From Left Edge grow the whole shield from that end of the bar.",
                  values = { overlay = "Overlay", overlayReverse = "Overlay Reverse",
                             right = "From Right Edge", left = "From Left Edge" },
                  order = { "overlay", "overlayReverse", "right", "left" },
                  get = function() return DBVal("absorbEdgeMode") or "overlay" end,
                  set = function(v)
                    DB().absorbEdgeMode = v
                    ns.ApplyAbsorbStyleAll()
                    UpdatePreview()
                  end },
            },
        })
    end

    -- Inline absorb color swatch (right of Row 2): white by default, tints every style except Blizzard (disabled there since Blizzard keeps its own coloring); mirrors the Focus Texture swatch's disabled pattern.
    if not EllesmereUI._prebuilding then
        local rgn = bgHoverRow._rightRegion
        local acColorGet = function()
            local c = (DB() and DB().absorbColor) or defaults.absorbColor or { r = 1, g = 1, b = 1 }
            return c.r, c.g, c.b
        end
        local acColorSet = function(r, g, b)
            DB().absorbColor = { r = r, g = g, b = b }
            ns.ApplyAbsorbStyleAll()
            UpdatePreview()
        end
        local acSwatch, acUpdateSwatch = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, acColorGet, acColorSet, nil, 20)
        PP.Point(acSwatch, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = acSwatch
        local function absorbColorOff() return (DBVal("absorbStyle") or "blizzard") == "blizzard" end
        EllesmereUI.RegisterWidgetRefresh(function()
            local off = absorbColorOff()
            acSwatch:SetAlpha(off and 0.15 or 1)
            acSwatch:EnableMouse(not off)
            acUpdateSwatch()
        end)
        local off0 = absorbColorOff()
        acSwatch:SetAlpha(off0 and 0.15 or 1)
        acSwatch:EnableMouse(not off0)
    end

    -- Eye icon: toggle absorb preview on the preview nameplate
    if not EllesmereUI._prebuilding then
        local EYE_VISIBLE   = EllesmereUI.EYE_VISIBLE_ICON
        local EYE_INVISIBLE = EllesmereUI.EYE_INVISIBLE_ICON
        local rgn = bgHoverRow._rightRegion
        local eyeBtn = CreateFrame("Button", nil, rgn)
        eyeBtn:SetSize(26, 26)
        eyeBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = eyeBtn
        eyeBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
        EllesmereUI.SetGlyphAlpha(eyeBtn, 0.4)
        local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
        eyeTex:SetAllPoints()
        local function RefreshAbsorbEye()
            if optState.showAbsorbPreview then
                eyeTex:SetTexture(EYE_INVISIBLE)
            else
                eyeTex:SetTexture(EYE_VISIBLE)
            end
        end
        RefreshAbsorbEye()
        eyeBtn:SetScript("OnClick", function()
            optState.showAbsorbPreview = not optState.showAbsorbPreview
            RefreshAbsorbEye()
            UpdatePreview()
        end)
        eyeBtn:SetScript("OnEnter", function(self) EllesmereUI.SetGlyphAlpha(self, 0.7) end)
        eyeBtn:SetScript("OnLeave", function(self) EllesmereUI.SetGlyphAlpha(self, 0.4) end)
    end

    -- Row 3: Bar Texture | Cast Bar Texture -- share the same texture set (EUI built-ins + SharedMedia) and resolve identically; Bar Texture drives the health bar, Cast Bar Texture drives the cast bar.
    local texRow
    texRow, h = W:DualRow(parent, y,
        -- Bar Texture stays live under Blizzard Style: the health fill is the
        -- user's own texture under the stock background art.
        { type="dropdown", text="Bar Texture", values=hbtValues, order=hbtOrder,
          getValue=function() return DBVal("healthBarTexture") or "none" end,
          setValue=function(v)
            DB().healthBarTexture = v
            RefreshAllTextures()
            UpdatePreview()
          end },
        ns.NP_BlizzOnlyGate({ type="dropdown", text="Cast Bar Texture", values=hbtValues, order=hbtOrder,
          getValue=function() return DBVal("castBarTexture") or "none" end,
          setValue=function(v)
            DB().castBarTexture = v
            RefreshAllTextures()
            UpdatePreview()
          end }));  y = y - h
    -- Textured Background cogs on the two texture dropdowns, greyed while
    -- Blizzard Style draws its stock backgrounds (as Global Settings > Textures).
    if not EllesmereUI._prebuilding then
        local function TexBgApply() RefreshAllTextures(); UpdatePreview() end
        local blizz = ns.NP_BlizzOnly()
        local function TexBgCog(rgn, kind)
            EllesmereUI.BuildInlineCog(rgn, {
                disabled = blizz and function() return true end or nil,
                disabledTooltip = blizz and EllesmereUI.BlizzStyle.Label("nameplates") or nil,
                requireState = blizz and "disabled" or nil,
                title = "Texture Settings", rows = { env.TexBgRowCfg(kind, TexBgApply) } })
        end
        TexBgCog(texRow._leftRegion, "health")
        TexBgCog(texRow._rightRegion, "cast")
    end

    -- WoW Forever variant only (the Forever client): Show Level Box, the
    -- opt-out for the level box right of the health bar (nil = shown),
    -- last in the section so its blank slot is the odd last one. Off, the
    -- plates lay out as plain Blizzard Style; Left Text stays the user's
    -- to set to Level. Not built on any other look.
    if EllesmereUI.BlizzStyle.Forever("nameplates") then
        local foreverBoxRow
        foreverBoxRow, h = W:DualRow(parent, y,
            { type="toggle", text="Show Level Box",
              tooltip="Shows the level box right of the health bar; with it off, Left Text can show the level instead.",
              getValue=function() return not DBVal("foreverHideLevelBox") end,
              setValue=function(v)
                DB().foreverHideLevelBox = (not v) or nil
                ns.RefreshAllSettings()
                UpdatePreview()
              end },
            EllesmereUI.BlankRowCfg())
        y = y - h
        -- Reached by the preview's click navigation (the level box).
        parent._foreverBoxRow = foreverBoxRow
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    -----------------------------------------------------------------------
    --  CORE POSITIONS
    -----------------------------------------------------------------------
    local coreHeader
    coreHeader, h = W:SectionHeader(parent, "CORE POSITIONS", y);  y = y - h

    -- Subtitle hint next to the section header's title (the header's own label:
    -- a page built again keeps its earlier dresses' font strings, idle, among
    -- the header's regions)
    do
        local rgn = coreHeader._label
        if rgn and EllesmereUI.EnKey(rgn:GetText()) == "CORE POSITIONS" then
            local sub = coreHeader:CreateFontString(nil, "OVERLAY")
            sub:SetFont(rgn:GetFont())
            sub:SetTextColor(1, 1, 1, 0.25)
            sub:SetText(EllesmereUI.L("(one slot per element)"))
            sub:SetPoint("LEFT", rgn, "RIGHT", 6, 0)
        end
    end

    local coreElementValues = {
        debuffs        = "Debuffs",
        buffs          = "Buffs",
        ccs            = "Crowd Control",
        debuffsccs     = "Debuffs + CC",
        raidmarker     = "Raid Marker",
        classification = "Rare/Quest Indicator",
        faction        = "Faction",
        classfaction   = "Rare/Quest + Faction",
        none           = "None",
    }
    local coreElementOrder = { "debuffs", "buffs", "ccs", "debuffsccs", "raidmarker", "classification", "faction", "classfaction", "none" }

    local coreRow1, coreRow2, coreRow3
    local _refreshCoreEyePos

    -- Never from the search pre-build: it builds no eye, and the shown page's
    -- Core Positions rows call this to move it.
    if not EllesmereUI._prebuilding then
        optState.RefreshCoreEyes = function()
            if _refreshCoreEyePos then _refreshCoreEyePos() end
        end
    end

    -- Each slot's control is a checkbox dropdown with drag-to-reorder rows, one
    -- row per element: a view over the same stored keys the single-choice
    -- dropdowns wrote (each element's slot key, debuffIncludeCC and
    -- classificationIncludeFaction for the two pairs that merge into one
    -- element) plus classificationHideRare / classificationHideQuest, the two
    -- halves of the Rare/Quest indicator. The halves are one frame, so they
    -- always share a slot and move together. Any elements can share a slot:
    -- they sit one after another in the rows' order, saved per slot as
    -- <pos>SlotOrder (the row keys joined by commas; unset = the default order)
    -- and laid out by the Core Positions chain (ns.NP_CoreChain),
    -- <pos>SlotElementSpacing apart (the Element Spacing row of the slot's cog).
    -- Debuffs with Crowd Control still merge into one row, and the Elite/Rare
    -- and Quest Indicators with Faction into one stacked pair, as the old
    -- combined elements did. Quest Objective Text is an element of its own
    -- (questTextSlot), read through the runtime's view over the
    -- replaceQuestIconWithObjective key (ns.NP_GetQuestTextSlot,
    -- ns.NP_QuestIconOn) until one of its inputs is changed here, which first
    -- settles the view into its own keys (ns.NP_MaterializeQuestText). The
    -- single-choice dropdowns stay built, hidden, under the checkbox dropdowns
    -- (the row label's empty-slot state).
    local CORE_ORDER = { "debuffs", "buffs", "ccs", "raidmarker", "rare", "quest", "questtext", "faction" }
    local CORE_LABEL = {
        debuffs = "Debuffs", buffs = "Buffs", ccs = "Crowd Control", raidmarker = "Raid Marker",
        rare = "Elite/Rare Indicator", quest = "Quest Indicator", questtext = "Quest Objective Text",
        faction = "Faction",
    }
    local CORE_TIP = {
        rare  = "Elite and rare marks. Always in the same slot as the Quest Indicator.",
        quest = "Marks mobs for your active quests. Always in the same slot as the Elite/Rare Indicator.",
        questtext = "Shows quest progress such as 2/6 on quest mobs.",
    }

    local function CoreHas(pos, k)
        if k == "debuffs" then return DBVal("debuffSlot") == pos end
        if k == "buffs" then return DBVal("buffSlot") == pos end
        if k == "ccs" then
            return DBVal("ccSlot") == pos
                or (DBVal("debuffIncludeCC") == true and DBVal("debuffSlot") == pos)
        end
        if k == "raidmarker" then return DBVal("raidMarkerPos") == pos end
        if k == "rare" then
            return DBVal("classificationSlot") == pos and not DBVal("classificationHideRare")
        end
        if k == "quest" then
            return DBVal("classificationSlot") == pos and ns.NP_QuestIconOn(DB())
        end
        if k == "questtext" then return ns.NP_GetQuestTextSlot(DB()) == pos end
        if k == "faction" then
            -- While Rare/Quest + Faction is on, a leftover faction slot is ignored.
            if DBVal("classificationIncludeFaction") == true then
                return DBVal("classificationSlot") == pos
            end
            return DBVal("factionSlot") == pos
        end
        return false
    end

    -- The slot's row order: its saved order first, then every row it lacks in
    -- the default order. A saved order without Quest Objective Text takes it
    -- right after the Quest Indicator (the runtime chain reads it the same way).
    local function CoreOrderKeys(pos)
        local keys, seen = {}, {}
        local src = DBVal(pos .. "SlotOrder")
        if type(src) == "string" then
            local qtAfterQuest = not string.find("," .. src .. ",", ",questtext,", 1, true)
            for k in string.gmatch(src, "[^,]+") do
                if CORE_LABEL[k] and not seen[k] then
                    seen[k] = true
                    keys[#keys + 1] = k
                    if k == "quest" and qtAfterQuest then
                        seen.questtext = true
                        keys[#keys + 1] = "questtext"
                    end
                end
            end
        end
        for i = 1, #CORE_ORDER do
            local k = CORE_ORDER[i]
            if not seen[k] then
                seen[k] = true
                keys[#keys + 1] = k
            end
        end
        return keys
    end
    -- The default order saves as unset.
    local function CoreSaveOrder(pos, keys)
        local s = table.concat(keys, ",")
        if s == table.concat(CORE_ORDER, ",") then s = nil end
        DB()[pos .. "SlotOrder"] = s
    end

    local function CoreSet(pos, k, v)
        local db = DB()
        -- The Elite/Rare and Quest Indicators and Quest Objective Text are the
        -- view's inputs: the view settles into its own keys before any of them
        -- changes, so what the slots show stays as it was.
        if k == "rare" or k == "quest" or k == "questtext" then ns.NP_MaterializeQuestText(db) end
        if k == "debuffs" then
            if v then
                local old = DBVal("debuffSlot")
                local merged = DBVal("debuffIncludeCC") == true
                if DBVal("ccSlot") == pos then
                    -- CC already here on its own: the two become Debuffs + CC.
                    db.ccSlot = "none"
                    merged = true
                elseif merged and old ~= pos then
                    -- Leaving a Debuffs + CC slot: CC stays there on its own
                    -- unless it already has a slot elsewhere.
                    if old ~= "none" and DBVal("ccSlot") == "none" then db.ccSlot = old end
                    merged = false
                end
                db.debuffSlot = pos
                db.debuffIncludeCC = merged
            else
                if DBVal("debuffIncludeCC") == true and DBVal("ccSlot") == "none" then
                    db.ccSlot = pos
                end
                db.debuffSlot = "none"
                db.debuffIncludeCC = false
            end
        elseif k == "ccs" then
            if v then
                if DBVal("debuffSlot") == pos then
                    db.debuffIncludeCC = true
                    db.ccSlot = "none"
                else
                    db.debuffIncludeCC = false
                    db.ccSlot = pos
                end
            else
                if DBVal("debuffSlot") == pos then db.debuffIncludeCC = false end
                if DBVal("ccSlot") == pos then db.ccSlot = "none" end
            end
        elseif k == "buffs" then
            if v then db.buffSlot = pos
            elseif DBVal("buffSlot") == pos then db.buffSlot = "none" end
        elseif k == "raidmarker" then
            if v then db.raidMarkerPos = pos
            elseif DBVal("raidMarkerPos") == pos then db.raidMarkerPos = "none" end
        elseif k == "rare" or k == "quest" then
            local hideKey = (k == "rare") and "classificationHideRare" or "classificationHideQuest"
            local otherKey = (k == "rare") and "classificationHideQuest" or "classificationHideRare"
            if v then
                local old = DBVal("classificationSlot")
                if old ~= pos then
                    -- Moving: a Faction badge riding along stays behind on its own.
                    if DBVal("classificationIncludeFaction") == true then
                        db.classificationIncludeFaction = false
                        if old ~= "none" then db.factionSlot = old end
                    end
                    -- Brought back from None: only the half that was checked.
                    if old == "none" then db[otherKey] = true end
                    db.classificationSlot = pos
                    -- Faction already here on its own joins them.
                    if DBVal("factionSlot") == pos then
                        db.classificationIncludeFaction = true
                        db.factionSlot = "none"
                    end
                end
                db[hideKey] = false
            elseif DBVal(otherKey) then
                -- The last half goes: the indicator leaves the slot, a Faction
                -- badge riding along stays there on its own.
                if DBVal("classificationIncludeFaction") == true then
                    db.classificationIncludeFaction = false
                    db.factionSlot = pos
                end
                db.classificationSlot = "none"
                db.classificationHideRare = false
                db.classificationHideQuest = false
            else
                db[hideKey] = true
            end
        elseif k == "faction" then
            if v then
                if DBVal("classificationSlot") == pos then
                    db.classificationIncludeFaction = true
                    db.factionSlot = "none"
                else
                    db.classificationIncludeFaction = false
                    db.factionSlot = pos
                end
            else
                if DBVal("classificationSlot") == pos then db.classificationIncludeFaction = false end
                if DBVal("factionSlot") == pos then db.factionSlot = "none" end
            end
        elseif k == "questtext" then
            if v then db.questTextSlot = pos
            elseif ns.NP_GetQuestTextSlot(db) == pos then db.questTextSlot = "none" end
        end
    end

    local function InstallCoreCB(rgn, pos)
        local ctrl = rgn._control
        local ddW = ctrl and ctrl:GetWidth() or 0
        if ddW < 50 then ddW = 170 end
        -- The rows in the slot's saved order, so the button's label reads in
        -- that order before the list is first opened.
        local items = {}
        local keys = CoreOrderKeys(pos)
        for i = 1, #keys do
            local k = keys[i]
            items[i] = { key = k, label = CORE_LABEL[k], tooltip = CORE_TIP[k] }
        end
        local cbDD, cbDDRefresh = EllesmereUI.BuildReorderCBDropdown(
            rgn, ddW, rgn:GetFrameLevel() + 2, items,
            function(k) return CoreHas(pos, k) end,
            function(k, v)
                CoreSet(pos, k, v)
                -- The quest scan's caches are built for the quest elements
                -- shown: dropped, and every plate's indicators run again.
                if k == "rare" or k == "quest" or k == "questtext" then ns.RefreshQuestObjective() end
                RefreshAllSlots()
                optState.RefreshCoreEyes()
            end,
            {
                grip = true,
                openOrder = function() return CoreOrderKeys(pos) end,
                setOrder = function(order)
                    CoreSaveOrder(pos, order)
                    RefreshAllSlots()
                end,
            })
        local p1, rel, p2, ax, ay
        if ctrl then
            p1, rel, p2, ax, ay = ctrl:GetPoint(1)
            ctrl:Hide()
        end
        if p1 then cbDD:SetPoint(p1, rel, p2, ax, ay)
        else PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0) end
        rgn._control = cbDD
        rgn._lastInline = nil
        EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
    end

    -- Slot-based offsets: pos .. "SlotXOffset" / "SlotYOffset"

    local function CorePosXGet(pos)
        return DBVal(pos .. "SlotXOffset") or 0
    end
    local function CorePosYGet(pos)
        return DBVal(pos .. "SlotYOffset") or 0
    end
    local function CorePosXSet(pos, v)
        DB()[pos .. "SlotXOffset"] = v
        RefreshAllSlots()
    end
    local function CorePosYSet(pos, v)
        DB()[pos .. "SlotYOffset"] = v
        RefreshAllSlots()
    end
    -- A slot is empty while it holds none of the checkbox dropdown's elements
    -- (Quest Objective Text alone fills it; the Rare/Quest frame with both of
    -- its halves unchecked does not).
    local function CorePosOffDisabled(pos)
        for i = 1, #CORE_ORDER do
            if CoreHas(pos, CORE_ORDER[i]) then return false end
        end
        return true
    end
    -- The hidden single-choice dropdowns (SetElementAtPosition settles the
    -- Quest Objective Text view before it writes).
    local function CoreSingleSet(pos, v)
        SetElementAtPosition(pos, v)
        ns.RefreshQuestObjective()
        RefreshAllSlots()
        optState.RefreshCoreEyes()
    end

    -------------------------------------------------------------------
    --  Combined Settings Popup  (singleton, slide-up, pos + optional size)
    --  The Core Text Positions cogs below and the cast text and class
    --  resource cogs of DisplayBars_Options.lua open it.
    -------------------------------------------------------------------
    local function CogPopupOpen(btn) return LiveCogOwner() == btn and cogPopup:IsShown() end

    -- opts = { title, xGet, xSet, yGet, ySet,
    --   sizeGet, sizeSet, sizeMin, sizeMax, sizeStep, sizeLabel, sizeFirst (Size heads the rows),
    --   widthGet/Set (Width %), toggleLabel/Get/Set, wrapGet/Set (Wrap),
    --   dropdown2Label/Get/Set/Tooltip (Name Format), strataGet/Set (Strata) };
    -- a row shows while its getter is set.
    local function ShowCogPopup(anchorBtn, opts)
        if not cogPopup then
            -- The refreshes the popup's sliders register while it is built.
            local refreshList = EllesmereUI._widgetRefreshList
            local firstRefresh = #refreshList + 1
            local SolidTex = EllesmereUI.SolidTex
            local MakeFont = EllesmereUI.MakeFont
            local BuildSliderCore = EllesmereUI.BuildSliderCore
            local BORDER_COLOR = EllesmereUI.BORDER_COLOR
            local SL_INPUT_A = EllesmereUI.SL_INPUT_A

            local SIDE_PAD   = 14
            local INPUT_W    = 34; local SLIDER_INPUT_GAP = 8; local LABEL_SLIDER_GAP = 12
            local TOP_PAD    = 14
            local TITLE_H    = 11
            local TITLE_GAP  = 10
            local GAP        = 10
            local SLIDER_H   = 24

            -- Max height: title + X + Y + Size = 4 rows
            local MAX_H = TOP_PAD + TITLE_H + TITLE_GAP + GAP + SLIDER_H + GAP + SLIDER_H + GAP + SLIDER_H + TOP_PAD

            local pf = CreateFrame("Frame", nil, UIParent)
            pf:SetSize(260, MAX_H)
            pf:SetFrameStrata("DIALOG")
            pf:SetFrameLevel(200)
            pf:EnableMouse(true)
            pf:Hide()

            -- Match the panel/popup scale so this popup renders at the same size as the shared BuildCogPopup popups (else it stays scale 1.0 and looks oversized); registering it also tracks the panel scale slider.
            pf:SetScale((EllesmereUI.GetPopupScale()) or 1)
            if EllesmereUI._popupFrames then
                EllesmereUI._popupFrames[#EllesmereUI._popupFrames + 1] = { popup = pf }
            end

            local bg = SolidTex(pf, "BACKGROUND", 0.077, 0.068, 0.058, 0.95)
            bg:SetAllPoints()
            EllesmereUI.MakeRoundedBorder(pf, BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.15, bg)

            local titleFS = MakeFont(pf, 11, "", 1, 1, 1)
            titleFS:SetAlpha(0.7)
            titleFS:SetPoint("TOP", pf, "TOP", 0, -TOP_PAD)
            pf._titleFS = titleFS

            -- The slider column starts past the widest of a fixed set of labels,
            -- so every cog that opens this popup lines its sliders up alike.
            local tmpFS = pf:CreateFontString(nil, "OVERLAY")
            tmpFS:SetFont(EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 12, GetNPOptOutline())
            local labelTexts = {"X Offset", "Y Offset", "Size", "Width %", "Spacing", "Opacity", "Text Size"}
            local maxLblW = 0
            for _, txt in ipairs(labelTexts) do
                tmpFS:SetText(EllesmereUI.L(txt))
                local w = tmpFS:GetStringWidth()
                if w > maxLblW then maxLblW = w end
            end
            tmpFS:Hide()
            if maxLblW < 10 then maxLblW = 28 end

            local SLIDER_LEFT = SIDE_PAD + maxLblW + LABEL_SLIDER_GAP
            local SLIDER_W = math.max(80, 260 - SLIDER_LEFT - SLIDER_INPUT_GAP - INPUT_W - SIDE_PAD)
            local POPUP_W = SLIDER_LEFT + SLIDER_W + SLIDER_INPUT_GAP + INPUT_W + SIDE_PAD
            if POPUP_W < 180 then POPUP_W = 180 end
            pf:SetSize(POPUP_W, pf:GetHeight())

            -- X slider row
            local X_ROW_Y = -(TOP_PAD + TITLE_H + TITLE_GAP + GAP)
            local xLabel = MakeFont(pf, 12, nil, 1, 1, 1)
            xLabel:SetAlpha(0.6); xLabel:SetText(EllesmereUI.L("X Offset"))
            xLabel:SetPoint("LEFT", pf, "TOPLEFT", SIDE_PAD, X_ROW_Y - SLIDER_H / 2)
            local xTrack, xValBox = BuildSliderCore(pf, SLIDER_W, 4, 12, INPUT_W, SLIDER_H, 11, SL_INPUT_A,
                -300, 300, 1,
                function() return pf._xGet and pf._xGet() or 0 end,
                function(v) if pf._xSet then pf._xSet(v) end end, true)
            xTrack:SetPoint("TOPLEFT", pf, "TOPLEFT", SLIDER_LEFT, X_ROW_Y - 2)
            xValBox:ClearAllPoints(); xValBox:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -SIDE_PAD, X_ROW_Y)

            pf._xTrack = xTrack; pf._xValBox = xValBox; pf._xLabel = xLabel

            -- Y slider row
            local Y_ROW_Y = X_ROW_Y - SLIDER_H - GAP
            local yLabel = MakeFont(pf, 12, nil, 1, 1, 1)
            yLabel:SetAlpha(0.6); yLabel:SetText(EllesmereUI.L("Y Offset"))
            yLabel:SetPoint("LEFT", pf, "TOPLEFT", SIDE_PAD, Y_ROW_Y - SLIDER_H / 2)
            local yTrack, yValBox = BuildSliderCore(pf, SLIDER_W, 4, 12, INPUT_W, SLIDER_H, 11, SL_INPUT_A,
                -300, 300, 1,
                function() return pf._yGet and pf._yGet() or 0 end,
                function(v) if pf._ySet then pf._ySet(v) end end, true)
            yTrack:SetPoint("TOPLEFT", pf, "TOPLEFT", SLIDER_LEFT, Y_ROW_Y - 2)
            yValBox:ClearAllPoints(); yValBox:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -SIDE_PAD, Y_ROW_Y)

            pf._yTrack = yTrack; pf._yValBox = yValBox; pf._yLabel = yLabel

            -- Size slider row (hidden when not needed)
            local S_ROW_Y = Y_ROW_Y - SLIDER_H - GAP
            local sLabel = MakeFont(pf, 12, nil, 1, 1, 1)
            sLabel:SetAlpha(0.6); sLabel:SetText(EllesmereUI.L("Size"))
            sLabel:SetPoint("LEFT", pf, "TOPLEFT", SIDE_PAD, S_ROW_Y - SLIDER_H / 2)
            pf._sLabel = sLabel

            -- Width % slider row (hidden unless a width-fit text element: enemy name, cast spell name, cast target); fixed range built once, reordered/repositioned per show via the seq block below.
            local W_ROW_Y = S_ROW_Y - SLIDER_H - GAP
            local wLabel = MakeFont(pf, 12, nil, 1, 1, 1)
            wLabel:SetAlpha(0.6); wLabel:SetText(EllesmereUI.L("Width %"))
            wLabel:SetPoint("LEFT", pf, "TOPLEFT", SIDE_PAD, W_ROW_Y - SLIDER_H / 2)
            wLabel:Hide()
            pf._wLabel = wLabel
            -- Invisible hover region for the label's tooltip (FontStrings aren't mouse-interactive); SetAllPoints tracks the label through repositioning, shown/hidden with the row.
            local wHover = CreateFrame("Frame", nil, pf)
            wHover:SetFrameLevel(pf:GetFrameLevel() + 10)
            wHover:SetAllPoints(wLabel)
            wHover:EnableMouse(true)
            wHover:Hide()
            wHover:SetScript("OnEnter", function(self)
                EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L("Maximum width the text can fill before it truncates, as a percentage of the bar."), { width = 230 })
            end)
            wHover:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            pf._wHover = wHover
            local wTrack, wValBox = BuildSliderCore(pf, SLIDER_W, 4, 12, INPUT_W, SLIDER_H, 11, SL_INPUT_A,
                10, 150, 1,
                function() return pf._wGet and pf._wGet() or 0 end,
                function(v) if pf._wSet then pf._wSet(v) end end, true)
            wTrack:SetPoint("TOPLEFT", pf, "TOPLEFT", SLIDER_LEFT, W_ROW_Y - 2)
            wValBox:ClearAllPoints(); wValBox:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -SIDE_PAD, W_ROW_Y)
            wTrack:Hide(); wValBox:Hide()
            pf._wTrack = wTrack; pf._wValBox = wValBox

            -- Store layout values for dynamic size slider rebuild + reorder
            pf._SLIDER_LEFT = SLIDER_LEFT
            pf._SLIDER_W = SLIDER_W
            pf._X_ROW_Y = X_ROW_Y
            pf._Y_ROW_Y = Y_ROW_Y
            pf._S_ROW_Y = S_ROW_Y
            pf._ROW0 = X_ROW_Y
            pf._ROW_STEP = SLIDER_H + GAP

            -- The toggle and dropdown rows: shorter than a slider row, placed
            -- below the slider rows at layout time (T_ROW_Y: their first spot).
            local TOGGLE_ROW_H = 22
            local T_ROW_Y = S_ROW_Y - SLIDER_H - GAP
            pf._TOGGLE_ROW_H = TOGGLE_ROW_H

            -- Standard cog-popup dropdown sizing (matches BuildCogPopup's dropdown rows): 130px wide, rendered 10% smaller, right-aligned at layout time.
            -- Each menu parents to UIParent; its OnShow scales it to the control's
            -- whole scale chain (this 0.9, the popup, the Window Scale).
            local DD_W = 130
            local DD_SCALE = 0.9
            pf._DD_SCALE = DD_SCALE
            -- The Name Format list: one control for every text slot, built on
            -- first need; its getValue/setValue delegate to the per-show getter
            -- and setter. Its Character Count entry saves through the per-show
            -- setter, as a pick does. Enemy names show here, so retail warns
            -- that the game keeps them whole in restricted content.
            local nameFormatDD
            pf._NameFormatDD = function()
                if not nameFormatDD then
                    local values, order, getValue, setValue = EllesmereUI.NameFormatMenu(
                        function() return pf._dd2Get and pf._dd2Get() or "" end,
                        function(v) if pf._dd2Set then pf._dd2Set(v) end end, {
                        onSaved = function() nameFormatDD._refreshLabel() end,
                        enemies = true,
                    })
                    nameFormatDD = EllesmereUI.BuildDropdownControl(pf, EllesmereUI.NAME_FORMAT_MENU_W, pf:GetFrameLevel() + 6,
                        values, order, getValue, setValue)
                    nameFormatDD:SetScale(DD_SCALE)
                    nameFormatDD:Hide()
                end
                return nameFormatDD
            end

            -- Optional toggle row, anchored at layout time directly after the slider rows. Wired via pf._toggleGet/Set.
            local tLabel = MakeFont(pf, 12, nil, 1, 1, 1)
            tLabel:SetAlpha(0.6)
            tLabel:SetPoint("LEFT", pf, "TOPLEFT", SIDE_PAD, T_ROW_Y - TOGGLE_ROW_H / 2)
            tLabel:Hide()
            pf._tLabel = tLabel
            local tToggle, _, tToggleSnap = EllesmereUI.BuildToggleControl(pf, pf:GetFrameLevel() + 5,
                function() return pf._toggleGet and pf._toggleGet() or false end,
                function(v) if pf._toggleSet then pf._toggleSet(v) end end,
                { sizeRatio = 0.8, noAnim = true })
            tToggle:SetPoint("RIGHT", pf, "TOPRIGHT", -SIDE_PAD, T_ROW_Y - TOGGLE_ROW_H / 2)
            tToggle:Hide()
            pf._tToggle = tToggle
            pf._toggleSnap = tToggleSnap

            -- Optional "Strata" dropdown row (Core Text slots): the standard
            -- strata dropdown, static option set, positioned below the toggle
            -- row at layout time; wired via pf._strataGetFn/SetFn.
            local stLabel = MakeFont(pf, 12, nil, 1, 1, 1)
            stLabel:SetAlpha(0.6)
            stLabel:SetText(EllesmereUI.L("Strata"))
            stLabel:SetPoint("LEFT", pf, "TOPLEFT", SIDE_PAD, T_ROW_Y - TOGGLE_ROW_H / 2)
            stLabel:Hide()
            pf._stLabel = stLabel
            local stDD = EllesmereUI.BuildDropdownControl(pf, DD_W, pf:GetFrameLevel() + 6,
                EllesmereUI.FRAME_STRATA_LABELS, EllesmereUI.FRAME_STRATA_ORDER_BASE,
                function() return pf._strataGetFn and pf._strataGetFn() or "MEDIUM" end,
                function(v) if pf._strataSetFn then pf._strataSetFn(v) end end)
            stDD:SetScale(DD_SCALE)
            stDD:Hide()
            pf._stDD = stDD

            -- Optional "Wrap" toggle row (own row), used by truncating text elements so it coexists with the generic toggle (e.g. health text keeps Decimal there, Wrap here); wired via pf._wrapGet/Set.
            local wrapLabel = MakeFont(pf, 12, nil, 1, 1, 1)
            wrapLabel:SetAlpha(0.6)
            wrapLabel:SetText(EllesmereUI.L("Wrap"))
            wrapLabel:SetPoint("LEFT", pf, "TOPLEFT", SIDE_PAD, T_ROW_Y - TOGGLE_ROW_H / 2)
            wrapLabel:Hide()
            pf._wrapLabel = wrapLabel
            -- Invisible hover region over the Wrap label for its tooltip (see the Width % hover above); tracks the label, shown/hidden with the row.
            local wrapHover = CreateFrame("Frame", nil, pf)
            wrapHover:SetFrameLevel(pf:GetFrameLevel() + 10)
            wrapHover:SetAllPoints(wrapLabel)
            wrapHover:EnableMouse(true)
            wrapHover:Hide()
            wrapHover:SetScript("OnEnter", function(self)
                EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L("Lets long text wrap onto a second line instead of being cut off."), { width = 230 })
            end)
            wrapHover:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            pf._wrapHover = wrapHover
            local wrapToggle, _, wrapToggleSnap = EllesmereUI.BuildToggleControl(pf, pf:GetFrameLevel() + 5,
                function() return pf._wrapGet and pf._wrapGet() or false end,
                function(v) if pf._wrapSet then pf._wrapSet(v) end end,
                { sizeRatio = 0.8, noAnim = true })
            wrapToggle:SetPoint("RIGHT", pf, "TOPRIGHT", -SIDE_PAD, T_ROW_Y - TOGGLE_ROW_H / 2)
            wrapToggle:Hide()
            pf._wrapToggle = wrapToggle
            pf._wrapToggleSnap = wrapToggleSnap

            -- Optional Name Format dropdown row (own row, below Wrap), its control
            -- from pf._NameFormatDD; label per show, via pf._dd2Get/Set.
            local d2Label = MakeFont(pf, 12, nil, 1, 1, 1)
            d2Label:SetAlpha(0.6)
            d2Label:SetPoint("LEFT", pf, "TOPLEFT", SIDE_PAD, T_ROW_Y - TOGGLE_ROW_H / 2)
            d2Label:Hide()
            pf._d2Label = d2Label

            -- Layout constants stored for height calc
            pf._TOP_PAD = TOP_PAD; pf._TITLE_H = TITLE_H; pf._TITLE_GAP = TITLE_GAP
            pf._GAP = GAP; pf._SLIDER_H = SLIDER_H; pf._SIDE_PAD = SIDE_PAD
            pf._POPUP_W = POPUP_W

            -- Close on click outside
            local wasDown = false
            pf._clickOutside = function(self, dt)
                if CogOwnerGone() then
                    self:Hide()
                    return
                end
                local down = IsMouseButtonDown("LeftButton")
                if down and not wasDown then
                    -- The Strata and Name Format menus float outside this popup's rect; a click there must not count as click-outside.
                    local m2 = self._stDD and self._stDD._ddMenu
                    local m3 = self._d2DD and self._d2DD._ddMenu
                    local overMenu = (m2 and m2:IsShown() and m2:IsMouseOver())
                        or (m3 and m3:IsShown() and m3:IsMouseOver())
                    local owner = LiveCogOwner()
                    if not self:IsMouseOver() and not (owner and owner:IsMouseOver()) and not overMenu then
                        self:Hide()
                    end
                end
                wasDown = down
            end

            pf:SetScript("OnHide", function(self)
                self:SetScript("OnUpdate", nil)
                local owner = LiveCogOwner()
                cogPopupOwner, cogPopupOwnerGen = nil, nil
                -- Every cog that opens this popup is a BuildInlineCog: its own
                -- state pass dims it again.
                if owner and owner._euiCogState then owner._euiCogState() end
            end)

            if EllesmereUI._mainFrame then
                EllesmereUI._mainFrame:HookScript("OnHide", function()
                    if pf:IsShown() then pf:Hide() end
                end)
            end

            pf._refreshFns = {}
            for i = firstRefresh, #refreshList do pf._refreshFns[#pf._refreshFns + 1] = refreshList[i] end
            pf._refreshSerial = buildSerial
            cogPopup = pf
        end
        -- Each page build starts a fresh refresh list: the first cog shown from
        -- a build the popup was not built on registers the popup's sliders there.
        if cogPopup._refreshSerial ~= buildSerial then
            for i = 1, #cogPopup._refreshFns do EllesmereUI.RegisterWidgetRefresh(cogPopup._refreshFns[i]) end
            cogPopup._refreshSerial = buildSerial
        end

        -- Toggle off if same icon clicked again
        if LiveCogOwner() == anchorBtn and cogPopup:IsShown() then
            cogPopup:Hide()
            return
        end

        -- Wire getters/setters
        cogPopup._xGet = opts.xGet; cogPopup._xSet = opts.xSet
        cogPopup._yGet = opts.yGet; cogPopup._ySet = opts.ySet
        cogPopup._titleFS:SetText(EllesmereUI.L(opts.title))
        local prevOwner = LiveCogOwner()
        cogPopupOwner, cogPopupOwnerGen = anchorBtn, PoolGen(anchorBtn)
        if prevOwner and prevOwner._euiCogState then prevOwner._euiCogState() end

        -- Show/hide size row and adjust height
        local hasSize = opts.sizeGet ~= nil
        local hasWidth = opts.widthGet ~= nil
        local hasToggle = opts.toggleGet ~= nil
        local hasWrap = opts.wrapGet ~= nil
        local hasDropdown2 = opts.dropdown2Get ~= nil
        local hasStrata = opts.strataGet ~= nil
        if hasSize then
            -- One size slider per range, built the first time a cog needs it and
            -- kept: a range change shows that range's slider and hides the last.
            local sStep = opts.sizeStep or 1
            if cogPopup._curMin ~= opts.sizeMin or cogPopup._curMax ~= opts.sizeMax or cogPopup._curStep ~= sStep then
                if cogPopup._sTrack then cogPopup._sTrack:Hide() end
                if cogPopup._sValBox then cogPopup._sValBox:Hide() end
                local sliders = cogPopup._sSliders
                if not sliders then sliders = {}; cogPopup._sSliders = sliders end
                local key = tostring(opts.sizeMin) .. "/" .. tostring(opts.sizeMax) .. "/" .. tostring(sStep)
                local entry = sliders[key]
                if not entry then
                    -- Registers itself with this page; later pages get it through
                    -- the popup's refresh list.
                    local sTrack, sValBox, sRefresh = EllesmereUI.BuildSliderCore(cogPopup, cogPopup._SLIDER_W, 4, 12, 34, 24, 11, EllesmereUI.SL_INPUT_A,
                        opts.sizeMin, opts.sizeMax, sStep,
                        function() return cogPopup._sGet and cogPopup._sGet() or 0 end,
                        function(v) if cogPopup._sSet then cogPopup._sSet(v) end end, true)
                    sTrack:ClearAllPoints(); sTrack:SetPoint("TOPLEFT", cogPopup, "TOPLEFT", cogPopup._SLIDER_LEFT, cogPopup._S_ROW_Y - (cogPopup._SLIDER_H - 20) / 2)
                    sValBox:ClearAllPoints(); sValBox:SetPoint("TOPRIGHT", cogPopup, "TOPRIGHT", -cogPopup._SIDE_PAD, cogPopup._S_ROW_Y)
                    entry = { track = sTrack, valBox = sValBox }
                    sliders[key] = entry
                    cogPopup._refreshFns[#cogPopup._refreshFns + 1] = sRefresh
                end
                cogPopup._sTrack = entry.track; cogPopup._sValBox = entry.valBox
                cogPopup._curMin = opts.sizeMin; cogPopup._curMax = opts.sizeMax; cogPopup._curStep = sStep
            end
            cogPopup._sGet = opts.sizeGet; cogPopup._sSet = opts.sizeSet
            cogPopup._sLabel:SetText(EllesmereUI.L(opts.sizeLabel or "Size"))
            cogPopup._sLabel:Show()
            if cogPopup._sTrack then cogPopup._sTrack:Show() end
            if cogPopup._sValBox then cogPopup._sValBox:Show() end
        else
            cogPopup._sLabel:Hide()
            if cogPopup._sTrack then cogPopup._sTrack:Hide() end
            if cogPopup._sValBox then cogPopup._sValBox:Hide() end
        end

        -- Show/hide width % row
        if hasWidth then
            cogPopup._wGet = opts.widthGet
            cogPopup._wSet = opts.widthSet
            cogPopup._wLabel:Show()
            cogPopup._wTrack:Show()
            cogPopup._wValBox:Show()
            if cogPopup._wHover then cogPopup._wHover:Show() end
        else
            cogPopup._wGet = nil
            cogPopup._wSet = nil
            cogPopup._wLabel:Hide()
            cogPopup._wTrack:Hide()
            cogPopup._wValBox:Hide()
            if cogPopup._wHover then cogPopup._wHover:Hide() end
        end

        -- Show/hide toggle row
        if hasToggle then
            cogPopup._toggleGet = opts.toggleGet
            cogPopup._toggleSet = opts.toggleSet
            cogPopup._tLabel:SetText(EllesmereUI.L(opts.toggleLabel or ""))
            cogPopup._tLabel:Show()
            cogPopup._tToggle:Show()
            if cogPopup._toggleSnap then cogPopup._toggleSnap() end
        else
            cogPopup._toggleGet = nil
            cogPopup._toggleSet = nil
            cogPopup._tLabel:Hide()
            cogPopup._tToggle:Hide()
        end

        -- Show/hide Wrap row (its own row)
        if hasWrap then
            cogPopup._wrapGet = opts.wrapGet
            cogPopup._wrapSet = opts.wrapSet
            cogPopup._wrapLabel:Show()
            cogPopup._wrapToggle:Show()
            if cogPopup._wrapToggleSnap then cogPopup._wrapToggleSnap() end
            if cogPopup._wrapHover then cogPopup._wrapHover:Show() end
        else
            cogPopup._wrapGet = nil
            cogPopup._wrapSet = nil
            cogPopup._wrapLabel:Hide()
            cogPopup._wrapToggle:Hide()
            if cogPopup._wrapHover then cogPopup._wrapHover:Hide() end
        end

        -- Show/hide the Name Format dropdown row
        if hasDropdown2 then
            cogPopup._dd2Get = opts.dropdown2Get
            cogPopup._dd2Set = opts.dropdown2Set
            local d2DD = cogPopup._NameFormatDD()
            cogPopup._d2DD = d2DD
            -- The Name Format control is shared by every slot: its tooltip is
            -- set again on each show.
            d2DD._ttText = opts.dropdown2Tooltip
            d2DD._refreshLabel()
            d2DD:Show()
            cogPopup._d2Label:SetText(EllesmereUI.L(opts.dropdown2Label or ""))
            cogPopup._d2Label:Show()
        else
            cogPopup._dd2Get = nil
            cogPopup._dd2Set = nil
            cogPopup._d2Label:Hide()
            if cogPopup._d2DD then cogPopup._d2DD:Hide() end
        end

        -- Show/hide Strata row (standard strata dropdown, its own row)
        if hasStrata then
            cogPopup._strataGetFn = opts.strataGet
            cogPopup._strataSetFn = opts.strataSet
            if cogPopup._stDD then
                -- Static option set: the kept menu stays; the selected-value label
                -- follows this cog's getter.
                cogPopup._stDD._refreshLabel()
                cogPopup._stDD:Show()
            end
            cogPopup._stLabel:Show()
        else
            cogPopup._strataGetFn = nil
            cogPopup._strataSetFn = nil
            cogPopup._stLabel:Hide()
            if cogPopup._stDD then cogPopup._stDD:Hide() end
        end

        -- Row order: cogs passing sizeFirst put Size at the top; others keep X, Y, Size. The toggle, Strata, Wrap and Name Format rows follow the slider rows in that order, Width % last.
        do
            local p = cogPopup
            local SH, SLEFT, SPAD = p._SLIDER_H, p._SLIDER_LEFT, p._SIDE_PAD
            local TRH = p._TOGGLE_ROW_H
            local DS = p._DD_SCALE or 1
            local function rowY(i) return p._ROW0 - (i - 1) * p._ROW_STEP end
            local function anchorRow(lbl, track, valBox, ry)
                lbl:ClearAllPoints();  lbl:SetPoint("LEFT", p, "TOPLEFT", SPAD, ry - SH / 2)
                if track  then track:ClearAllPoints();  track:SetPoint("TOPLEFT", p, "TOPLEFT", SLEFT, ry - 2) end
                if valBox then valBox:ClearAllPoints(); valBox:SetPoint("TOPRIGHT", p, "TOPRIGHT", -SPAD, ry) end
            end
            -- Width % is intentionally NOT in this data-row sequence -- it's repositioned to the very bottom (below Wrap) further down, so it never sits between Size and X/Y.
            local seq = {}
            if hasSize and opts.sizeFirst then
                seq[#seq + 1] = { p._sLabel, p._sTrack, p._sValBox }
                seq[#seq + 1] = { p._xLabel, p._xTrack, p._xValBox }
                seq[#seq + 1] = { p._yLabel, p._yTrack, p._yValBox }
            else
                seq[#seq + 1] = { p._xLabel, p._xTrack, p._xValBox }
                seq[#seq + 1] = { p._yLabel, p._yTrack, p._yValBox }
                if hasSize then seq[#seq + 1] = { p._sLabel, p._sTrack, p._sValBox } end
            end
            for i, r in ipairs(seq) do
                anchorRow(r[1], r[2], r[3], rowY(i))
            end
            -- The toggle row sits directly after the data rows.
            local toggleY = rowY(#seq + 1)
            p._tLabel:ClearAllPoints()
            p._tLabel:SetPoint("LEFT", p, "TOPLEFT", SPAD, toggleY - TRH / 2)
            p._tToggle:ClearAllPoints()
            p._tToggle:SetPoint("RIGHT", p, "TOPRIGHT", -SPAD, toggleY - TRH / 2)
            -- Strata dropdown row: below the toggle row. Right-aligned like standard cog dropdowns; offsets divided by the control's scale so the scaled frame lands flush-right and vertically centered.
            local strataY = rowY(#seq + 1 + (hasToggle and 1 or 0))
            p._stLabel:ClearAllPoints()
            p._stLabel:SetPoint("LEFT", p, "TOPLEFT", SPAD, strataY - TRH / 2)
            if p._stDD then
                p._stDD:ClearAllPoints()
                p._stDD:SetPoint("RIGHT", p, "TOPRIGHT", -SPAD / DS, (strataY - TRH / 2) / DS)
            end
            -- Rows consumed by the toggle and Strata rows (0-2).
            local extraRows = (hasToggle and 1 or 0) + (hasStrata and 1 or 0)
            -- Wrap sits in its own row, below the toggle and Strata rows when present, else after the data rows.
            local wrapY = rowY(#seq + 1 + extraRows)
            p._wrapLabel:ClearAllPoints()
            p._wrapLabel:SetPoint("LEFT", p, "TOPLEFT", SPAD, wrapY - TRH / 2)
            p._wrapToggle:ClearAllPoints()
            p._wrapToggle:SetPoint("RIGHT", p, "TOPRIGHT", -SPAD, wrapY - TRH / 2)
            -- Name Format dropdown: its own row below Wrap.
            local d2RowIndex = #seq + 1 + extraRows + (hasWrap and 1 or 0)
            local d2Y = rowY(d2RowIndex)
            p._d2Label:ClearAllPoints()
            p._d2Label:SetPoint("LEFT", p, "TOPLEFT", SPAD, d2Y - TRH / 2)
            if p._d2DD then
                p._d2DD:ClearAllPoints()
                p._d2DD:SetPoint("RIGHT", p, "TOPRIGHT", -SPAD / DS, (d2Y - TRH / 2) / DS)
            end
            -- Width % is the very last row, below Wrap and Name Format; stays a slider row, so anchorRow handles label+track+box.
            if hasWidth then
                anchorRow(p._wLabel, p._wTrack, p._wValBox, rowY(d2RowIndex + (hasDropdown2 and 1 or 0)))
            end
        end

        -- Compute height based on visible rows
        do
            local p = cogPopup
            local rowH = p._SLIDER_H
            local gap  = p._GAP
            local h = p._TOP_PAD + p._TITLE_H + p._TITLE_GAP
                + gap + rowH   -- X
                + gap + rowH   -- Y
            if hasSize    then h = h + gap + rowH end
            if hasWidth   then h = h + gap + rowH end
            -- The toggle, Wrap, Name Format and Strata rows each occupy their own row.
            if hasToggle then h = h + gap + p._TOGGLE_ROW_H end
            if hasWrap then h = h + gap + p._TOGGLE_ROW_H end
            if hasDropdown2 then h = h + gap + p._TOGGLE_ROW_H end
            if hasStrata then h = h + gap + p._TOGGLE_ROW_H end
            h = h + p._TOP_PAD
            cogPopup:SetHeight(h)
        end

        -- Anchor above the icon
        cogPopup:ClearAllPoints()
        cogPopup:SetPoint("BOTTOM", anchorBtn, "TOP", 0, 6)

        -- Slide-up animation
        cogPopup:SetAlpha(0)
        cogPopup:Show()
        local elapsed = 0
        local ANIM_DUR = 0.15
        cogPopup:SetScript("OnUpdate", function(self, dt)
            -- A build dressed the anchor again mid-slide.
            if CogOwnerGone() then
                self:Hide()
                return
            end
            elapsed = elapsed + dt
            local t = math.min(elapsed / ANIM_DUR, 1)
            self:SetAlpha(t)
            self:ClearAllPoints()
            self:SetPoint("BOTTOM", anchorBtn, "TOP", 0, 6 + (-8 * (1 - t)))
            if t >= 1 then
                self:SetScript("OnUpdate", self._clickOutside)
            end
        end)

        EllesmereUI:RefreshPage()
    end

    local DISABLED_TIP = "This option requires an aura or indicator to be assigned"

    -- Per-kind slot Tracked Auras popup (12.1). Filter composition is INTERNAL (debuffs=Default, dcc=CC+Default, cc=CC; Default is Blizzard's
    -- nameplateShowPersonal curation): holds only Show All Debuffs (debuffs only) + INCLUDED/EXCLUDED lists (debuff side shared by debuffs/dcc; cc has its own pair). Storage/engine groups live in the containers file (ns.NPF_Root/Include/Exclude, NPC_ReloadAll).
    local NPF_KIND_TITLES = {
        debuffs = "Debuff Custom Spell IDs", cc = "CC Custom Spell IDs", dcc = "Debuffs + CC Custom Spell IDs",
    }
    local function ShowFilterPopup(kind)
        local root = ns.NPF_Root and ns.NPF_Root()
        if not root then return end
        -- List side + Show All availability: only debuffs has Show All; dcc is always CC+Default, cc is always CC.
        local side = (kind == "cc") and "cc" or "debuff"
        -- Any-caster OPT-OUTS for INCLUDED entries: default is Only My Casts (npincmine); flagged ids ride npinc.
        local function AnyMap()
            return ns.NPF_IncludeAny and ns.NPF_IncludeAny(side)
        end
        local function Reload()
            if ns.NPC_ReloadAll then ns.NPC_ReloadAll() end
        end
        EllesmereUI.ShowTrackedAurasPopup({
            eyebrow = EllesmereUI.L("NAMEPLATE AURA FILTERS"),
            title = NPF_KIND_TITLES[kind] or "Filters",
            fontPath = (EllesmereUI.GetFontPath("nameplates")) or DBVal("font"),
            includeGet = function() return ns.NPF_Include and ns.NPF_Include(side) end,
            excludeGet = function() return ns.NPF_Exclude and ns.NPF_Exclude(side) end,
            includePrompt = EllesmereUI.L("Enter the spell ID to always show on nameplates."),
            excludePrompt = EllesmereUI.L("Enter the spell ID to exclude from nameplates."),
            includeMine = { anyGet = AnyMap },
            -- Fresh adds default to Only My Casts; a spell migrating to the exclude list drops any stale flag.
            onAdd = function(id)
                local am = AnyMap()
                if am then am[id] = nil end
            end,
            onChanged = Reload,
            showAll = (kind == "debuffs") and {
                label = EllesmereUI.L("Show All Debuffs"),
                get = function() return root.debuffs and root.debuffs.all end,
                set = function(v)
                    root.debuffs = root.debuffs or {}
                    root.debuffs.all = v
                    Reload()
                end,
            } or nil,
        })
    end

    -- The Core Positions cogs' shared tables: each aura row's own keys (by
    -- checkbox dropdown row), the corner slots' Grow lists, the faction badge's
    -- PvP Flag and Icon Style lists.
    local CoreCog = {
        AURA = {
            debuffs = { slot = "debuffSlot", spacing = "debuffSpacing", crop = "debuffCropIcons",
                        cropPct = "debuffCropPercent", border = "hideDebuffIconBorder" },
            buffs   = { slot = "buffSlot", spacing = "buffSpacing", crop = "buffCropIcons",
                        cropPct = "buffCropPercent", border = "hideBuffIconBorder" },
            ccs     = { slot = "ccSlot", spacing = "ccSpacing", crop = "ccCropIcons",
                        cropPct = "ccCropPercent", border = "hideCCIconBorder" },
        },
        GROW = {
            topleft  = { values = { left = "Left", right = "Right", up = "Up" }, order = { "left", "right", "up" } },
            topright = { values = { right = "Right", left = "Left", up = "Up" }, order = { "right", "left", "up" } },
        },
        PVP_VALUES = { dim = "Dim Unflagged", only = "Flagged Only", ignore = "Ignore" },
        PVP_ORDER = { "dim", "only", "ignore" },
        STYLE_VALUES = {},
    }
    for _, k in ipairs(EllesmereUI.FACTION_ART_ORDER) do
        CoreCog.STYLE_VALUES[k] = EllesmereUI.FACTION_ART_LABELS[k]
    end
    -- The first aura row in the slot's order that is a row of its own (Crowd
    -- Control inside the debuff row is that row's): the row the Auras section
    -- reads.
    function CoreCog.FirstAura(pos)
        local keys = CoreOrderKeys(pos)
        for i = 1, #keys do
            local a = CoreCog.AURA[keys[i]]
            if a and DBVal(a.slot) == pos then return keys[i] end
        end
        return "debuffs"
    end
    -- An Auras section value (field: "size" or a key of CoreCog.AURA's rows),
    -- read from the slot's first aura row.
    function CoreCog.AuraGet(pos, field)
        local k = CoreCog.FirstAura(pos)
        if field == "size" then return ns.NP_ElementSize(k, DB()) end
        return DBVal(CoreCog.AURA[k][field])
    end
    -- Written to every aura row the slot holds.
    function CoreCog.AuraSet(pos, field, v)
        local db = DB()
        for k, a in pairs(CoreCog.AURA) do
            if CoreHas(pos, k) then
                db[(field == "size") and ns.NP_CORE_SIZE_KEY[k] or a[field]] = v
            end
        end
    end

    -- A slot cog's sections: the slot's own rows and one section per unique
    -- element it holds, in a fixed order (Slot, Auras, Raid Marker, Elite/Rare
    -- Indicator, Quest Indicator, Quest Objective Text, Faction). An element's
    -- section shows while the slot holds it; with three or more showing they
    -- sit side by side as columns under their headers, else their rows stack
    -- in one column, the Slot rows last. Every aura row shares the Auras
    -- section, which reads the slot's first aura row and writes them all.
    function CoreCog.Sections(posKey)
        local function refresh()
            RefreshAllSlots()
            UpdatePreview()
        end
        local function Lacks(k) return function() return not CoreHas(posKey, k) end end
        local function SizeRow(elem)
            local key = ns.NP_CORE_SIZE_KEY[elem]
            return { type = "slider", label = "Size", min = 10, max = 50, step = 1,
                get = function() return ns.NP_ElementSize(elem, DB()) end,
                set = function(v) DB()[key] = v; refresh() end }
        end
        -- Show In Instances: the quest scan's caches follow it, so they are
        -- dropped and every plate's indicators run again.
        local function InstancesRow(kind)
            local key = ns.NP_SHOW_IN_INSTANCES_KEY[kind]
            return { type = "toggle", label = "Show In Instances",
                tooltip = "Also shows inside dungeons, raids and other instances.",
                get = function() return ns.NP_ShowInInstances(kind, DB()) end,
                set = function(v)
                    DB()[key] = v and true or false
                    ns.RefreshQuestObjective()
                    refresh()
                end }
        end

        local slotRows = {
            { type = "slider", label = "X Offset", min = -300, max = 300, step = 1,
              get = function() return CorePosXGet(posKey) end,
              set = function(v) CorePosXSet(posKey, v) end },
            { type = "slider", label = "Y Offset", min = -300, max = 300, step = 1,
              get = function() return CorePosYGet(posKey) end,
              set = function(v) CorePosYSet(posKey, v) end },
        }
        local grow = CoreCog.GROW[posKey]
        if grow then
            local growthKey = posKey .. "SlotGrowth"
            slotRows[#slotRows + 1] = { type = "dropdown", label = "Grow", values = grow.values, order = grow.order,
                get = function() return DBVal(growthKey) end,
                set = function(v) DB()[growthKey] = v; refresh() end }
        end
        -- Element Spacing: the gap between the slot's elements, following the
        -- slot's Spacing (the first aura row's) until set.
        local esKey = posKey .. "SlotElementSpacing"
        slotRows[#slotRows + 1] = { type = "slider", label = "Element Spacing", min = -5, max = 20, step = 1,
            tooltip = "Space between the elements sharing this slot. Follows the slot's Spacing until you change it.",
            hidden = function() return ns.NP_CoreMemberCount(posKey) < 2 end,
            get = function() return ns.NP_CoreElementSpacing(posKey) end,
            set = function(v) DB()[esKey] = v; refresh() end }
        -- Raise Strata: bumps the slot's elements one strata level up so they
        -- render above the rest of the plate.
        local rsKey = posKey .. "SlotRaiseStrata"
        slotRows[#slotRows + 1] = { type = "toggle", label = "Raise Strata",
            tooltip = "Renders this slot's element above the rest of the nameplate.",
            get = function() return DBVal(rsKey) and true or false end,
            set = function(v) DB()[rsKey] = v and true or false; refresh() end }

        return {
            { title = "Slot", stackLast = true, rows = slotRows },
            { title = "Auras",
              hidden = function()
                  return not (CoreHas(posKey, "debuffs") or CoreHas(posKey, "buffs") or CoreHas(posKey, "ccs"))
              end,
              rows = {
                { type = "slider", label = "Size", min = 10, max = 50, step = 1,
                  get = function() return CoreCog.AuraGet(posKey, "size") end,
                  set = function(v) CoreCog.AuraSet(posKey, "size", v); refresh() end },
                { type = "slider", label = "Spacing", min = -5, max = 20, step = 1,
                  get = function() return CoreCog.AuraGet(posKey, "spacing") end,
                  set = function(v) CoreCog.AuraSet(posKey, "spacing", v); refresh() end },
                -- Blizzard Style: the stock aura ring replaces the 1px border.
                { type = "toggle", label = "Hide Border",
                  hidden = function() return EllesmereUI.BlizzStyle.Get("nameplates") and true or false end,
                  get = function() return CoreCog.AuraGet(posKey, "border") == true end,
                  set = function(v)
                      CoreCog.AuraSet(posKey, "border", v and true or false)
                      -- The live slot borders only catch up through a full settings pass.
                      ns.RefreshAllSettings()
                      refresh()
                  end },
                { type = "toggle", label = "Cropped Icons",
                  get = function() return CoreCog.AuraGet(posKey, "crop") == true end,
                  set = function(v) CoreCog.AuraSet(posKey, "crop", v and true or false); refresh() end },
                -- Adjust Crop: per-side trim percentage for the cropped mode.
                { type = "slider", label = "Adjust Crop", min = 5, max = 25, step = 1,
                  tooltip = "How much is trimmed from the icon's top and bottom, as a percentage per side. 10% is the classic cropped look.",
                  disabled = function() return CoreCog.AuraGet(posKey, "crop") ~= true end,
                  disabledTooltip = "Cropped Icons",
                  get = function() return CoreCog.AuraGet(posKey, "cropPct") or 10 end,
                  set = function(v) CoreCog.AuraSet(posKey, "cropPct", v); refresh() end },
              } },
            { title = "Raid Marker", hidden = Lacks("raidmarker"), rows = { SizeRow("raidmarker") } },
            { title = "Elite/Rare Indicator", hidden = Lacks("rare"),
              rows = { SizeRow("rare"), InstancesRow("rare") } },
            { title = "Quest Indicator", hidden = Lacks("quest"),
              rows = { SizeRow("quest"), InstancesRow("quest") } },
            { title = "Quest Objective Text", hidden = Lacks("questtext"), rows = {
                { type = "toggle", label = "Objective Type Icon",
                  tooltip = "Shows a sword for kill objectives, a bag for item objectives, and the generic quest icon when the type cannot be matched exactly.",
                  get = function() return DBVal("showQuestObjectiveTypeIcon") == true end,
                  set = function(v)
                      DB().showQuestObjectiveTypeIcon = v
                      ns.RefreshQuestObjective()
                      refresh()
                  end },
                { type = "slider", label = "Icon Scale", min = 50, max = 200, step = 5,
                  hidden = function() return DBVal("showQuestObjectiveTypeIcon") ~= true end,
                  get = function() return DBVal("questObjectiveTypeIconScale") or 100 end,
                  set = function(v)
                      DB().questObjectiveTypeIconScale = v
                      refresh()
                  end },
                { type = "slider", label = "Text Size", min = 6, max = 24, step = 1,
                  tooltip = "Size of the quest progress text.",
                  get = function() return ns.NP_QuestTextSize(DB()) end,
                  set = function(v)
                      DB().questObjectiveTextSize = v
                      ns.RefreshQuestObjective()
                      refresh()
                  end },
                InstancesRow("questtext"),
            } },
            { title = "Faction", hidden = Lacks("faction"), rows = {
                SizeRow("faction"),
                { type = "dropdown", label = "PvP Flag", values = CoreCog.PVP_VALUES, order = CoreCog.PVP_ORDER,
                  get = function() return DBVal("factionPvP") end,
                  set = function(v) DB().factionPvP = v; refresh() end },
                { type = "dropdown", label = "Icon Style",
                  values = CoreCog.STYLE_VALUES, order = EllesmereUI.FACTION_ART_ORDER,
                  get = function() return DBVal("factionStyle") end,
                  set = function(v) DB().factionStyle = v; refresh() end },
                { type = "toggle", label = "Opposite Faction Only",
                  get = function() return DBVal("factionOppositeOnly") == true end,
                  set = function(v) DB().factionOppositeOnly = v and true or false; refresh() end },
                { type = "toggle", label = "Players Only",
                  tooltip = "Hide the faction badge on faction NPCs such as guards.",
                  get = function() return DBVal("factionPlayersOnly") == true end,
                  set = function(v) DB().factionPlayersOnly = v and true or false; refresh() end },
            } },
        }
    end

    local function MakeCogIcon(row, regionKey, posKey, slotLabel)
        local rgn = row[regionKey]
        -- The shared cog popup, sectioned per element (CoreCog.Sections).
        local btn = EllesmereUI.BuildInlineCog(rgn, {
            anchorTo = rgn._control,
            title = EllesmereUI.Lf("%1$s Slot Settings", EllesmereUI.L(slotLabel)),
            disabled = function() return CorePosOffDisabled(posKey) end,
            disabledTooltip = DISABLED_TIP, rawTooltip = true,
            sections = CoreCog.Sections(posKey),
            columnsFrom = 3,
        })
        -- The core eyes anchor to THIS, not _lastInline: the tracked-auras
        -- link below becomes _lastInline but is HIDDEN for the raid marker,
        -- Rare/Quest and Quest Objective Text slots (the only slots the eyes
        -- land on), and a hidden frame keeps its width, so an eye left of it
        -- would sit far from the cog.
        rgn._coreCogBtn = btn

        -- Edit Tracked Auras (slot filters): accent link left of the cog when this row holds a debuff-side aura element, opens the per-kind filter popup; refreshes on the same widget-refresh channel as the cog alpha.
            local link = CreateFrame("Button", nil, rgn)
            link:SetFrameLevel(rgn:GetFrameLevel() + 5)
            local lfp = (EllesmereUI.GetFontPath("nameplates")) or DBVal("font")
            local lfs = link:CreateFontString(nil, "OVERLAY")
            lfs:SetFont(lfp, 12, "")
            lfs:SetTextColor(EllesmereUI.GetAccentColor())
            -- Keyed by the font string: the page pool forgets the entry when it resets it.
            EllesmereUI.RegAccent({ type = "callback", obj = lfs, fn = function(r, g, b) lfs:SetTextColor(r, g, b) end })
            lfs:SetAlpha(0.85)
            lfs:SetPoint("CENTER")
            lfs:SetText(EllesmereUI.L("Edit Tracked Auras"))
            link:SetSize(lfs:GetStringWidth() + 6, 16)
            link:SetPoint("RIGHT", btn, "LEFT", -6, 0)
            rgn._lastInline = link
            -- The core eyes hang left of this link while it shows.
            rgn._coreLink = link
            -- The debuff side's filters whenever the slot holds the debuff row (with
            -- Crowd Control inside it: both), else Crowd Control's own.
            local function LinkKind()
                if CoreHas(posKey, "debuffs") then
                    return (DBVal("debuffIncludeCC") == true) and "dcc" or "debuffs"
                elseif CoreHas(posKey, "ccs") then
                    return "cc"
                end
            end
            local function UpdLink()
                local k = LinkKind()
                link:SetShown(k ~= nil)
                if k then
                    -- CC slots track only CC, so the link says so.
                    lfs:SetText(EllesmereUI.L(k == "cc" and "Edit Tracked CC" or "Edit Tracked Auras"))
                    link:SetSize(lfs:GetStringWidth() + 6, 16)
                end
            end
            link:SetScript("OnEnter", function() lfs:SetAlpha(1) end)
            link:SetScript("OnLeave", function() lfs:SetAlpha(0.85) end)
            link:SetScript("OnClick", function()
                local k = LinkKind()
                if k then ShowFilterPopup(k) end
            end)
            EllesmereUI.RegisterWidgetRefresh(UpdLink)
            UpdLink()
        return btn
    end

    parent._showRowDivider = true

    -- Row 1: Top | Right
    coreRow1, h = W:DualRow(parent, y,
        { type="dropdown", text="Top",
          values = coreElementValues, order = coreElementOrder,
          getValue = function() return GetElementAtPosition("top") end,
          setValue = function(v) CoreSingleSet("top", v) end,
          disabled = function() return CorePosOffDisabled("top") end,
          disabledTooltip = "This option requires an aura or indicator to be assigned", rawTooltip = true,
          labelOnlyDisabled = true },
        { type="dropdown", text="Right",
          values = coreElementValues, order = coreElementOrder,
          getValue = function() return GetElementAtPosition("right") end,
          setValue = function(v) CoreSingleSet("right", v) end,
          disabled = function() return CorePosOffDisabled("right") end,
          disabledTooltip = "This option requires an aura or indicator to be assigned", rawTooltip = true,
          labelOnlyDisabled = true });  y = y - h
    if not EllesmereUI._prebuilding then
    InstallCoreCB(coreRow1._leftRegion,  "top")
    InstallCoreCB(coreRow1._rightRegion, "right")
    MakeCogIcon(coreRow1, "_leftRegion",  "top",      "Top")
    MakeCogIcon(coreRow1, "_rightRegion", "right",    "Right")
    end

    -- Row 2: Left | Top Right
    coreRow2, h = W:DualRow(parent, y,
        { type="dropdown", text="Left",
          values = coreElementValues, order = coreElementOrder,
          getValue = function() return GetElementAtPosition("left") end,
          setValue = function(v) CoreSingleSet("left", v) end,
          disabled = function() return CorePosOffDisabled("left") end,
          disabledTooltip = "This option requires an aura or indicator to be assigned", rawTooltip = true,
          labelOnlyDisabled = true },
        { type="dropdown", text="Top Right",
          values = coreElementValues, order = coreElementOrder,
          getValue = function() return GetElementAtPosition("topright") end,
          setValue = function(v) CoreSingleSet("topright", v) end,
          disabled = function() return CorePosOffDisabled("topright") end,
          disabledTooltip = "This option requires an aura or indicator to be assigned", rawTooltip = true,
          labelOnlyDisabled = true });  y = y - h
    if not EllesmereUI._prebuilding then
    InstallCoreCB(coreRow2._leftRegion,  "left")
    InstallCoreCB(coreRow2._rightRegion, "topright")
    MakeCogIcon(coreRow2, "_leftRegion",  "left",     "Left")
    MakeCogIcon(coreRow2, "_rightRegion", "topright", "Top Right")
    end

    -- Row 3: Top Left | Bottom
    coreRow3, h = W:DualRow(parent, y,
        { type="dropdown", text="Top Left",
          values = coreElementValues, order = coreElementOrder,
          getValue = function() return GetElementAtPosition("topleft") end,
          setValue = function(v) CoreSingleSet("topleft", v) end,
          disabled = function() return CorePosOffDisabled("topleft") end,
          disabledTooltip = "This option requires an aura or indicator to be assigned", rawTooltip = true,
          labelOnlyDisabled = true },
        { type="dropdown", text="Bottom",
          values = coreElementValues, order = coreElementOrder,
          getValue = function() return GetElementAtPosition("bottom") end,
          setValue = function(v) CoreSingleSet("bottom", v) end,
          disabled = function() return CorePosOffDisabled("bottom") end,
          disabledTooltip = "This option requires an aura or indicator to be assigned", rawTooltip = true,
          labelOnlyDisabled = true });  y = y - h
    if not EllesmereUI._prebuilding then
    InstallCoreCB(coreRow3._leftRegion,  "topleft")
    InstallCoreCB(coreRow3._rightRegion, "bottom")
    MakeCogIcon(coreRow3, "_leftRegion", "topleft", "Top Left")
    MakeCogIcon(coreRow3, "_rightRegion", "bottom", "Bottom")
    end

    -- Map each position to { row, regionKey } for eye icon anchoring
    local posToRegion = {
        top      = { coreRow1, "_leftRegion" },
        right    = { coreRow1, "_rightRegion" },
        left     = { coreRow2, "_leftRegion" },
        topright = { coreRow2, "_rightRegion" },
        topleft  = { coreRow3, "_leftRegion" },
        bottom   = { coreRow3, "_rightRegion" },
    }
    ctx.corePosToRegion = posToRegion

    -- Where the Core Positions eye hangs: left of the slot's cog, past its Edit
    -- Tracked Auras link while that shows (never while hidden: the link keeps
    -- its width, so the eye would sit far left).
    local function EyeAnchor(rgn)
        local link = rgn._coreLink
        if link and link:IsShown() then return link end
        return rgn._coreCogBtn or rgn._control
    end

    -- One eye for every Core Positions element the preview hides until asked
    -- (the raid marker, the Elite/Rare and Quest Indicators, Quest Objective
    -- Text): a click shows or hides them all together. It hangs on the first
    -- slot, in the rows' reading order, that holds one of them.
    if not EllesmereUI._prebuilding then
        local EYE_VISIBLE   = EllesmereUI.EYE_VISIBLE_ICON
        local EYE_INVISIBLE = EllesmereUI.EYE_INVISIBLE_ICON
        local EYE_SLOTS = { "top", "right", "left", "topright", "topleft", "bottom" }
        local eyeBtn = CreateFrame("Button", nil, parent)
        eyeBtn:SetSize(26, 26)
        eyeBtn:SetFrameLevel(parent:GetFrameLevel() + 10)
        EllesmereUI.SetGlyphAlpha(eyeBtn, 0.4)
        local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
        eyeTex:SetAllPoints()
        local function PreviewShown()
            return optState.showRaidMarkerPreview or optState.showClassificationPreview
                or optState.showQuestTextPreview
        end
        local function RefreshIcon()
            eyeTex:SetTexture(PreviewShown() and EYE_INVISIBLE or EYE_VISIBLE)
        end
        RefreshIcon()
        eyeBtn:SetScript("OnClick", function()
            local show = not PreviewShown()
            optState.showRaidMarkerPreview = show
            optState.showClassificationPreview = show
            optState.showQuestTextPreview = show
            RefreshIcon()
            UpdatePreview()
        end)
        eyeBtn:SetScript("OnEnter", function(self)
            EllesmereUI.SetGlyphAlpha(self, 0.7)
            EllesmereUI.ShowWidgetTooltip(self, "Show/Hide on Preview", { width = 155 })
        end)
        eyeBtn:SetScript("OnLeave", function(self)
            EllesmereUI.SetGlyphAlpha(self, 0.4)
            EllesmereUI.HideWidgetTooltip()
        end)
        _refreshCoreEyePos = function()
            for i = 1, #EYE_SLOTS do
                local pos = EYE_SLOTS[i]
                if CoreHas(pos, "raidmarker") or CoreHas(pos, "rare") or CoreHas(pos, "quest")
                    or CoreHas(pos, "questtext") then
                    local info = posToRegion[pos]
                    local rgn = info[1][info[2]]
                    eyeBtn:ClearAllPoints()
                    eyeBtn:SetParent(rgn)
                    eyeBtn:SetPoint("RIGHT", EyeAnchor(rgn), "LEFT", -8, 0)
                    eyeBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
                    eyeBtn:Show()
                    return
                end
            end
            eyeBtn:Hide()
        end
        _refreshCoreEyePos()
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    -----------------------------------------------------------------------
    --  CORE TEXT POSITIONS
    -----------------------------------------------------------------------
    local coreTextHeader
    coreTextHeader, h = W:SectionHeader(parent, "CORE TEXT POSITIONS", y);  y = y - h

    -- Subtitle hint next to the section header's title (same style as Core Positions)
    do
        local rgn = coreTextHeader._label
        if rgn and EllesmereUI.EnKey(rgn:GetText()) == "CORE TEXT POSITIONS" then
            local sub = coreTextHeader:CreateFontString(nil, "OVERLAY")
            sub:SetFont(rgn:GetFont())
            sub:SetTextColor(1, 1, 1, 0.25)
            sub:SetText(EllesmereUI.L("(one per slot)"))
            sub:SetPoint("LEFT", rgn, "RIGHT", 6, 0)
        end
    end

    local textElementValues = {
        enemyName            = "Enemy Name",
        levelName            = "Level | Name",
        nameLevel            = "Name | Level",
        level                = "Level",
        targetOfTarget       = "Target of Target",
        healthPercent        = "Health %",
        healthPercentNoSign  = "Health % (No Sign)",
        healthNumber         = "Health #",
        healthPctNum         = "Health % | #",
        healthNumPct         = "Health # | %",
        healthPctNumDash     = "Health % - #",
        healthNumPctDash     = "Health # - %",
        healthNumMax         = "Health # / Max #",
        custom               = "Custom",
        none                 = "Remove",
    }
    local textElementOrder = { "none", "---", "custom", "---", "enemyName", "levelName", "nameLevel", "level", "targetOfTarget", "healthPercent", "healthPercentNoSign", "healthNumber", "healthPctNum", "healthNumPct", "healthPctNumDash", "healthNumPctDash", "healthNumMax" }

    local function TextSlotSetValue(slotKey, v)
        -- Target of Target starts in Class mode whenever a slot newly takes it;
        -- the slot's Text Coloring dropdown still switches it back. The mode is
        -- saved only when the slot would not already derive Class.
        local newToT = v == "targetOfTarget" and DBVal(slotKey) ~= "targetOfTarget"
        SetTextElementAtSlot(slotKey, v)
        if newToT then
            local db = DB()
            db[slotKey .. "ColorMode"] = nil
            if ns.NP_SlotColorMode(slotKey, db) ~= "class" then
                db[slotKey .. "ColorMode"] = "class"
            end
        end
        ns.RefreshAllSettings()
        -- Rebuild: the list and the Core Text Coloring section follow the
        -- slotted elements (a slot change can also clear another slot).
        UpdatePreview(); EllesmereUI:RefreshPage(true)
    end

    local function TextOffsetRefresh()
        ns.RefreshAllSettings()
        UpdatePreview()
    end

    -- Text slot X/Y offset helpers (parallel to CorePosXGet etc.)
    local function TextPosXGet(slotKey)
        return DBVal(slotKey .. "XOffset") or 0
    end
    local function TextPosYGet(slotKey)
        return DBVal(slotKey .. "YOffset") or 0
    end
    local function TextPosXSet(slotKey, v)
        DB()[slotKey .. "XOffset"] = v; TextOffsetRefresh()
    end
    local function TextPosYSet(slotKey, v)
        DB()[slotKey .. "YOffset"] = v; TextOffsetRefresh()
    end
    local function TextPosDisabled(slotKey)
        return DBVal(slotKey) == "none"
    end

    local TEXT_DISABLED_TIP = "This option requires a text to be assigned"

    local function MakeTextCogIcon(row, regionKey, slotKey, slotLabel)
        local rgn = row[regionKey]
        -- The shared boxed cog; its click opens this page's popup (OpenCog below).
        local OpenCog
        local btn = EllesmereUI.BuildInlineCog(rgn, {
            disabled = function() return TextPosDisabled(slotKey) end,
            disabledTooltip = TEXT_DISABLED_TIP, rawTooltip = true,
            isOpen = CogPopupOpen,
            show = function(self) OpenCog(self) end,
        })
        OpenCog = function(self)
            if TextPosDisabled(slotKey) then return end
            local sizeKey = slotKey .. "Size"
            local cogOpts = {
                title = EllesmereUI.Lf("%1$s Settings", EllesmereUI.L(slotLabel)),
                xGet = function() return TextPosXGet(slotKey) end,
                xSet = function(v) TextPosXSet(slotKey, v) end,
                yGet = function() return TextPosYGet(slotKey) end,
                ySet = function(v) TextPosYSet(slotKey, v) end,
                sizeGet = function() return DBVal(sizeKey) or defaults[sizeKey] end,
                sizeSet = function(v) DB()[sizeKey] = v; TextOffsetRefresh() end,
                sizeMin = 6, sizeMax = 30,
                sizeLabel = "Size",
                sizeFirst = true,
            }
            -- Both name and health text here get Width % + Wrap (dedicated Wrap row). Name-family variants use the GLOBAL enemyName keys (one slot holds the name FontString at a time); health text uses PER-SLOT keys (100% = no clip) and keeps "Show % Decimal". The corner slots never truncate, so they get neither.
            local cornerSlot = slotKey == "textSlotBottomLeft" or slotKey == "textSlotBottomRight"
                or slotKey == "textSlotTopLeft" or slotKey == "textSlotTopRight"
            if ns.IsNameElement(DBVal(slotKey)) then
                if not cornerSlot then
                    cogOpts.widthGet = function() return DBVal("enemyNameWidthPct") or defaults.enemyNameWidthPct end
                    cogOpts.widthSet = function(v) DB().enemyNameWidthPct = v; ns.RefreshAllSettings(); UpdatePreview() end
                    cogOpts.wrapGet = function() return DBVal("enemyNameWrap") == true end
                    cogOpts.wrapSet = function(v) DB().enemyNameWrap = v; ns.RefreshAllSettings(); UpdatePreview() end
                end
            else
                if not cornerSlot then
                    local widthKey = slotKey .. "WidthPct"
                    local wrapKey = slotKey .. "Wrap"
                    cogOpts.widthGet = function() return DBVal(widthKey) or 100 end
                    cogOpts.widthSet = function(v) DB()[widthKey] = v; ns.RefreshAllSettings(); UpdatePreview() end
                    cogOpts.wrapGet = function() return DBVal(wrapKey) == true end
                    cogOpts.wrapSet = function(v) DB()[wrapKey] = v; ns.RefreshAllSettings(); UpdatePreview() end
                end
                cogOpts.toggleLabel = "Show % Decimal"
                cogOpts.toggleGet = function() return DBVal(slotKey .. "PctDecimal") == true end
                cogOpts.toggleSet = function(v)
                    DB()[slotKey .. "PctDecimal"] = v
                    ns.RefreshAllSettings()
                    UpdatePreview()
                end
            end
            -- Target of Target, the standalone level and Custom (its template writes the
            -- percent) have no use for "Show % Decimal".
            local slotEl = DBVal(slotKey)
            if slotEl == "targetOfTarget" or slotEl == "level" or slotEl == "custom" then
                cogOpts.toggleLabel, cogOpts.toggleGet, cogOpts.toggleSet = nil, nil, nil
            end
            -- Name Format, while this slot shows a name, the Target of Target
            -- name, or a custom template that reads one. Full name is stored as
            -- nil (the runtime's unchanged path).
            local parsed = slotEl == "custom" and ns.NP_CustomParse(slotKey, DB())
            if ns.IsNameElement(slotEl) or slotEl == "targetOfTarget"
                or (parsed and (parsed.has.name or parsed.has.target)) then
                local nfKey = slotKey .. "NameFormat"
                cogOpts.dropdown2Label = "Name Format"
                -- WoW Forever: First / Last Name skip non-players there
                -- (EllesmereUI.UnitNameFormat), the other modes do not.
                if EllesmereUI.IS_FOREVER == true then
                    cogOpts.dropdown2Tooltip = "First Name and Last Name only change players' names; Abbreviated and Character Count change every name."
                end
                cogOpts.dropdown2Get = function() return DBVal(nfKey) or "full" end
                cogOpts.dropdown2Set = function(v)
                    DB()[nfKey] = (v ~= "full") and v or nil
                    ns.RefreshAllSettings(); UpdatePreview()
                end
            end
            -- Per-slot strata (partner request): standard strata dropdown,
            -- defaulting to the shared text tier's MEDIUM.
            cogOpts.strataGet = function() return DBVal(slotKey .. "Strata") or "MEDIUM" end
            cogOpts.strataSet = function(v)
                DB()[slotKey .. "Strata"] = v
                ns.RefreshAllSettings(); UpdatePreview()
            end
            ShowCogPopup(self, cogOpts)
        end
        return btn
    end

    parent._showRowDivider = true

    -- The list: one cell per position that shows a text, two to a row in
    -- position order, then Add Text Slot. A text's name opens the positions it
    -- can move to, its dropdown picks what it shows (Remove takes it off; the
    -- position keeps its other settings) and its cog holds Size, offsets and
    -- the rest. Every check runs at click time, so a menu that outlived a
    -- change writes nothing stale; each structure change rebuilds the page.
    local function IsAssigned(slotKey) return KNOWN[DBVal(slotKey)] == true end
    local function IsFree(slotKey) return not IsAssigned(slotKey) end

    -- Add Text Slot's text: the first of ADD_ORDER whose font string no shown
    -- text uses, so adding never takes one off (nil when every one is used).
    local function FontStringUsed(fsKey)
        for i = 1, #POS_ORDER do
            local s = POS_ORDER[i]
            if IsAssigned(s) and ns.NP_ElementFSKey(DBVal(s)) == fsKey then return true end
        end
        return false
    end
    local function AddCandidate()
        for i = 1, #ADD_ORDER do
            local el = ADD_ORDER[i]
            if not FontStringUsed(ns.NP_ElementFSKey(el)) then return el end
        end
    end
    -- Why Add Text Slot is greyed (nil while a text can be added).
    local function AddBlocked()
        local full = true
        for i = 1, #POS_ORDER do
            if IsFree(POS_ORDER[i]) then full = false end
        end
        if full then return "Every text position is full." end
        if not AddCandidate() then return "Every text is already shown." end
    end
    -- Adds AddCandidate's text at the free position P, exactly as picking that
    -- element in an empty slot (TextSlotSetValue rebuilds the page, where the
    -- new text's cell reports the write to Spec Overrides). A position taken
    -- or every font string used since the menu opened only resyncs the page.
    local function AddText(P)
        local cand = AddCandidate()
        if not IsFree(P) or not cand then EllesmereUI:RefreshPage(true); return end
        optState._npNotifySlot = P
        TextSlotSetValue(P, cand)
        optState._npNotifySlot = nil
    end

    -- Moves the text at S to the free position T with its look: its element,
    -- its effective Size, its offsets (the tweak from S's default, added to
    -- T's default), the MOVE_RAW keys as saved and its colour mode (saved only
    -- when T would derive another, as the coloring dropdown does). T's old
    -- keys are replaced; S keeps its other keys, unused. A cell gone stale
    -- since its menu opened only resyncs the page.
    local function MoveText(S, T)
        if S == T then return end
        if not IsAssigned(S) or not IsFree(T) then EllesmereUI:RefreshPage(true); return end
        local db = DB()
        local mode = ns.NP_SlotColorMode(S, db)   -- read before any write
        local el = DBVal(S)
        local size = DBVal(S .. "Size")
        local tSize = DBVal(T .. "Size")
        for i = 1, #MOVE_OFFSETS do
            local suf = MOVE_OFFSETS[i]
            local sDef = defaults[S .. suf] or 0
            local sv = db[S .. suf]
            if sv == nil then sv = sDef end
            local v = (defaults[T .. suf] or 0) + (sv - sDef)
            if db[T .. suf] ~= v then db[T .. suf] = v end
        end
        for i = 1, #MOVE_RAW do
            local suf = MOVE_RAW[i]
            -- The template moves only with Custom; otherwise T keeps its own.
            if suf ~= "CustomFormat" or el == "custom" then
                local v = db[S .. suf]
                if type(v) == "table" then v = CopyTable(v) end
                db[T .. suf] = v
            end
        end
        if size ~= tSize then db[T .. "Size"] = size end
        db[T] = el
        db[S] = "none"
        db[T .. "ColorMode"] = nil
        if ns.NP_SlotColorMode(T, db) ~= mode then db[T .. "ColorMode"] = mode end
        ns.RefreshAllSettings(); UpdatePreview()
        -- The moved text's new cell reports the write to Spec Overrides.
        optState._npNotifySlot = T; EllesmereUI:RefreshPage(true); optState._npNotifySlot = nil
    end

    -- A combined health text cannot sit Left or Right while a name is centered
    -- on the health bar (the texts would overlap).
    local function COMBO_VS_CENTER_NAME(k)
        if ns.IsComboHealthText(k) and ns.IsNameElement(DBVal("textSlotCenter")) then
            return "Disabled when the Name/Level text is centered on the health bar due to overlapping text"
        end
    end
    -- A text's position menu: its own position selected (picking it does
    -- nothing), a taken one greyed, Left / Right greyed by the rule above;
    -- every item greyed on a cell gone stale.
    local function MoveDisabled(S)
        return function(v)
            if not IsAssigned(S) then return true end
            if v == S then return nil end
            if IsAssigned(v) then return true end
            if v == "textSlotLeft" or v == "textSlotRight" then return COMBO_VS_CENTER_NAME(DBVal(S)) end
        end
    end

    local function TextCellCfg(s)
        local function get() return DBVal(s.key) end
        -- Custom opens its popup; a saved template selects it (the new cell reports
        -- the write to Spec Overrides, as Add Text Slot does).
        local values = ns.NPO_CustomTextValues(textElementValues, get, function()
            ns.NPO_EditCustomText(s.key, function()
                optState._npNotifySlot = s.key
                TextSlotSetValue(s.key, "custom")
                optState._npNotifySlot = nil
            end)
        end)
        return { type="dropdown", text=s.label, values=values, order=textElementOrder,
          getValue=get,
          setValue=function(v) TextSlotSetValue(s.key, v) end,
          disabledValues = (s.key == "textSlotLeft" or s.key == "textSlotRight") and COMBO_VS_CENTER_NAME or nil }
    end
    local addOpen   -- the Add Text Slot menu's toggle, once its row is built
    local addCfg = { type="button", text="+ Add Text Slot", width=220,
          onClick=function() if addOpen then addOpen() end end,
          disabled=function() return AddBlocked() ~= nil end,
          disabledTooltip=function() return AddBlocked() end, rawTooltip=true }

    local cells = {}
    for i = 1, #ns.NPO_TEXT_SLOTS do
        local s = ns.NPO_TEXT_SLOTS[i]
        if IsAssigned(s.key) then cells[#cells + 1] = s end
    end
    cells[#cells + 1] = addCfg
    local function CellCfg(c)
        if c == nil then return EllesmereUI.BlankRowCfg() end
        if c == addCfg then return addCfg end
        return TextCellCfg(c)
    end
    -- After its row: a text cell is recorded for the preview's click
    -- navigation (search pre-build too). Row chrome, never on the pre-build's
    -- rows: Add Text Slot's position menu, and a text's name menu, cog and
    -- Spec Overrides report.
    local textSlotCells, textFirstRow = {}, nil
    local function FinishCell(row, side, c)
        if c == nil then return end
        textFirstRow = textFirstRow or row
        local rgn = row[side]
        if c == addCfg then
            if not EllesmereUI._prebuilding then
                addOpen = EllesmereUI.AttachButtonMenu(rgn._control, { width = 220, order = POS_ORDER,
                    values = POS_VALUES, setValue = AddText,
                    itemDisabled = function(v) if IsAssigned(v) or not AddCandidate() then return true end end })
            end
            return
        end
        textSlotCells[c.key] = { row = row, side = side }
        if EllesmereUI._prebuilding then return end
        EllesmereUI.BuildRowLabelMenu(rgn, { order = POS_ORDER, values = POS_VALUES,
            getValue = function() return c.key end,
            setValue = function(v) MoveText(c.key, v) end,
            itemDisabled = MoveDisabled(c.key),
            tooltip = "Choose this text's slot position." })
        MakeTextCogIcon(row, side, c.key, c.label)
        -- The popup writes the template directly: Spec Overrides reads it through
        -- an accessor, on a Custom text or one holding a template an override may
        -- switch back to.
        local fk = c.key .. "CustomFormat"
        if DBVal(c.key) == "custom" or type(DBVal(fk)) == "string" then
            EllesmereUI.TextTags.AddFormatAccessor(rgn, c.label,
                function() return DBVal(fk) end,
                function(v) DB()[fk] = v; ns.RefreshAllSettings(); UpdatePreview() end)
        end
        if optState._npNotifySlot == c.key then
            optState._npNotifySlot = nil
            -- The slot read now, while this build's cell is its dress.
            local snap = EllesmereUI._SOAttribution(rgn)
            EllesmereUI._NotifySettingWrite(rgn, snap)
        end
    end
    for k = 1, #cells, 2 do
        local row
        row, h = W:DualRow(parent, y, CellCfg(cells[k]), CellCfg(cells[k + 1]));  y = y - h
        FinishCell(row, "_leftRegion", cells[k])
        FinishCell(row, "_rightRegion", cells[k + 1])
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    y = ns.NPO_BuildCoreTextColoring(parent, y, W)
    -- The structure this build shows, for the cached page's restore check.
    if not EllesmereUI._prebuilding then optState._npTextFP = ns.NPO_TextStructureFP() end

    return y, styleHeader, coreHeader, coreRow1, coreRow2, coreRow3, coreTextHeader, textSlotCells,
        textFirstRow, ShowCogPopup, CogPopupOpen, RefreshAllTextures
end

-- Used by EUI_Nameplates_Options.lua
ns.NPO_BuildDisplayLayout = BuildDisplayLayout
