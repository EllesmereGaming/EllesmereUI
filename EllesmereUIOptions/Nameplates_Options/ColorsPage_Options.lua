if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Nameplates_Options\ColorsPage_Options.lua
--  Nameplates options: the Colors page (BuildColorsPage) and the mini preview
--  bars of its color rows (MakeColorPreviewBar, built lazily through
--  LazyColorPreviewBar in EUI_Nameplates_Options.lua). Definitions only; the
--  shared helpers come from ns._NPO_OptEnv.
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUINameplates"]
if not ns then return end  -- module disabled: no options page

-- Mini preview bar builder for color swatches. type: "health"/"cast"/"castLocked". colorKey: DB key for the bar color (read live). parentRow: frame to attach to. anchorFrame: optional override anchor (e.g. DualRow half-region).
local function MakeColorPreviewBar(parentRow, colorType, colorKey, anchorFrame)
    local env = ns._NPO_OptEnv
    local DB, DBVal, defaults, GetFocusLetterAnchor = env.DB, env.DBVal, env.defaults, env.GetFocusLetterAnchor
    local GetNPOptOutline, NextCastFill, NextCastIcon, PP = env.GetNPOptOutline, env.NextCastFill, env.NextCastIcon, env.PP
    local SetPVFont = env.SetPVFont
    local MEDIA = "Interface\\AddOns\\EllesmereUINameplates\\Media\\"
    local isHalf = anchorFrame and true or false
    local BAR_W = isHalf and 161 or 180
    local BAR_H = 20
    local SWATCH_SZ = 24
    local SWATCH_GAP = isHalf and 27 or 52
    local fontPath = (EllesmereUI.GetFontPath("nameplates")) or DBVal("font")
    local anchor = anchorFrame or parentRow

    local container = CreateFrame("Frame", nil, parentRow)
    PP.Size(container, BAR_W + 2, BAR_H + 2)  -- +2 for border
    -- Position: to the left of the swatch (swatch is at RIGHT -SIDE_PAD, 24px wide)
    PP.Point(container, "RIGHT", anchor, "RIGHT", -(20 + SWATCH_SZ + SWATCH_GAP), 0)
    container:SetFrameLevel(parentRow:GetFrameLevel() + 2)

    -- Simple 1px solid border using the user's nameplate border color; two-point anchoring for pixel-perfect rendering inside the scroll frame.
    local function MakePreviewBorder(parent)
        local bc = (DB() and DB().borderColor) or defaults.borderColor
        local edges = {}
        local function mkE()
            local t = parent:CreateTexture(nil, "OVERLAY", nil, 7)
            t:SetColorTexture(bc.r, bc.g, bc.b, 1)
            edges[#edges + 1] = t
            return t
        end
        local t = mkE(); t:SetPoint("TOPLEFT"); t:SetPoint("TOPRIGHT"); t:SetHeight(1)
        local b = mkE(); b:SetPoint("BOTTOMLEFT"); b:SetPoint("BOTTOMRIGHT"); b:SetHeight(1)
        local l = mkE(); l:SetPoint("TOPLEFT", t, "BOTTOMLEFT"); l:SetPoint("BOTTOMLEFT", b, "TOPLEFT"); l:SetWidth(1)
        local r = mkE(); r:SetPoint("TOPRIGHT", t, "BOTTOMRIGHT"); r:SetPoint("BOTTOMRIGHT", b, "TOPRIGHT"); r:SetWidth(1)
        return edges
    end

    if colorType == "health" then
        -- Health bar preview: random fill 60-75%, colored by the swatch color
        local FAKE_MAX_HP = 10000
        local healthPct = math.floor(60 + math.random() * 15)
        local healthVal = math.floor(FAKE_MAX_HP * healthPct / 100)

        local health = CreateFrame("StatusBar", nil, container)
        health:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        health:SetMinMaxValues(0, 100)
        health:SetValue(healthPct)
        health:SetAllPoints()

        local bg = health:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.20, 0.20, 0.20, 1.0)

        -- 1px solid border on a dedicated frame ABOVE the health StatusBar (child frames cover parent textures); parented to container, not health, so it stays full opacity when the bar dims via SetDisabled.
        local brdFrame = CreateFrame("Frame", nil, container)
        brdFrame:SetAllPoints()
        brdFrame:SetFrameLevel(health:GetFrameLevel() + 2)
        local brdEdges = MakePreviewBorder(brdFrame)
        container._brdEdges = brdEdges
        container._health = health  -- exposed for proxy color override / dimming

        -- Always create both FontStrings (shown/hidden dynamically), parented to a text frame ABOVE the overlay clips so focus texture never covers the health numbers.
        local textFrame = CreateFrame("Frame", nil, health)
        textFrame:SetAllPoints()
        textFrame:SetFrameLevel(health:GetFrameLevel() + 3)

        local pctFS = textFrame:CreateFontString(nil, "OVERLAY")
        local initHpSz = 10
        SetPVFont(pctFS, fontPath, initHpSz, GetNPOptOutline())
        pctFS:Hide()

        local numFS = textFrame:CreateFontString(nil, "OVERLAY")
        SetPVFont(numFS, fontPath, initHpSz, GetNPOptOutline())
        numFS:Hide()

        -- Full refresh: re-reads DB settings, repositions, updates text & values
        local function RefreshHealthText()
            local hpFS = 10
            -- Use the largest text slot size (capped at 13 for mini bars)
            for _, sk in ipairs({"textSlotRight", "textSlotLeft", "textSlotCenter"}) do
                local el = DBVal(sk) or defaults[sk]
                if el and el ~= "none" and not ns.IsNameElement(el) then
                    hpFS = math.min(DBVal(sk .. "Size") or defaults[sk .. "Size"] or 10, 13)
                    break
                end
            end
            local curFont = (EllesmereUI.GetFontPath("nameplates")) or DBVal("font")
            local curOutline = GetNPOptOutline()

            -- Hide both FontStrings first
            SetPVFont(pctFS, curFont, hpFS, curOutline)
            pctFS:ClearAllPoints()
            pctFS:Hide()
            SetPVFont(numFS, curFont, hpFS, curOutline)
            numFS:ClearAllPoints()
            numFS:Hide()

            -- Bar slots: show health text based on slot assignments
            local barSlots = {
                { key = "textSlotRight",  anchor = "RIGHT",  xOff = -2 },
                { key = "textSlotLeft",   anchor = "LEFT",   xOff = 2 },
                { key = "textSlotCenter", anchor = "CENTER", xOff = 0 },
            }
            for _, slot in ipairs(barSlots) do
                local element = DBVal(slot.key) or defaults[slot.key]
                local sc = (DB() and DB()[slot.key .. "Color"]) or defaults[slot.key .. "Color"]
                -- This bar stands for a hostile NPC at the player's level: Hostility /
                -- Class shows the Hostile name colour, Level Difficulty that level's
                -- colour, as the plate would.
                local mode = ns.NP_SlotColorMode(slot.key, DB())
                if mode == "class" then
                    sc = (DB() and DB().enemyNameHostileColor) or defaults.hostile
                elseif mode == "level" then
                    local r, g, b = ns.NP_UnitLevelColor("player")
                    if r then sc = { r = r, g = g, b = b } end
                end
                if element == "healthPercent" or element == "healthPercentNoSign" then
                    pctFS:SetTextColor(sc.r, sc.g, sc.b, 1)
                    pctFS:SetText(element == "healthPercentNoSign" and tostring(healthPct) or (healthPct .. "%"))
                    pctFS:SetPoint(slot.anchor, health, slot.anchor, slot.xOff, 0)
                    pctFS:Show()
                elseif element == "healthNumber" then
                    numFS:SetTextColor(sc.r, sc.g, sc.b, 1)
                    local valStr = tostring(healthVal):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
                    numFS:SetText(valStr)
                    numFS:SetPoint(slot.anchor, health, slot.anchor, slot.xOff, 0)
                    numFS:Show()
                elseif ns.IsComboHealthText(element) then
                    local valStr = tostring(healthVal):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
                    pctFS:SetTextColor(sc.r, sc.g, sc.b, 1)
                    ns.SetCombinedHealthText(pctFS, element, healthPct .. "%", valStr)
                    pctFS:SetPoint(slot.anchor, health, slot.anchor, slot.xOff, 0)
                    pctFS:Show()
                end
            end
        end

        -- Run initial layout
        RefreshHealthText()

        -- Color the bar from the swatch's DB value
        local c = (DB() and DB()[colorKey]) or defaults[colorKey]
        health:SetStatusBarColor(c.r, c.g, c.b, 1)

        -- Focus overlay on the focus preview bar: clip frames for non-overlapping fixed-size textures
        local overlayFillClip, overlayFillTex, overlayBgClip, overlayBgTex

        -- Helper: create a clipped overlay frame+texture pair for the focus bar
        local function MakeOverlayClip(tlAnchor, tlRelPoint, brAnchor, brRelPoint, sublayer)
            local clip = CreateFrame("Frame", nil, health)
            clip:SetClipsChildren(true)
            -- Full bar height (top/bottom from the bar) with horizontal edges from the passed fill/health anchors, matching the live nameplate overlay (same full-height stripes).
            clip:SetPoint("TOP", health, "TOP", 0, 0)
            clip:SetPoint("BOTTOM", health, "BOTTOM", 0, 0)
            clip:SetPoint("LEFT", tlAnchor, tlRelPoint, 0, 0)
            clip:SetPoint("RIGHT", brAnchor, brRelPoint, 0, 0)
            clip:SetFrameLevel(health:GetFrameLevel() + 1)
            local tex = clip:CreateTexture(nil, "ARTWORK", nil, sublayer)
            tex:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
            tex:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 0, 0)
            tex:SetWidth(BAR_W)
            return clip, tex
        end

        local _overlayTexKey   = (colorKey == "target") and "targetOverlayTexture"  or "focusOverlayTexture"
        local _overlayAlphaKey = (colorKey == "target") and "targetOverlayAlpha"   or "focusOverlayAlpha"
        local _overlayColorKey = (colorKey == "target") and "targetOverlayColor"   or "focusOverlayColor"
        local _overlayFullBgKey = (colorKey == "target") and "targetOverlayFullBgAlpha" or "focusOverlayFullBgAlpha"
        -- Empty-portion (bg) opacity: full when "Full alpha on empty part of bar" is on, else dimmed to 30% (matches live plates).
        local function _overlayBgAlpha(oAlpha)
            local full = DBVal(_overlayFullBgKey)
            if full == nil then full = defaults[_overlayFullBgKey] end
            if full then return oAlpha end
            return oAlpha * 0.3
        end
        if colorKey == "focus" or colorKey == "target" then
            local tex = DBVal(_overlayTexKey) or defaults[_overlayTexKey]
            if tex ~= "none" then
                local fillRef = health:GetStatusBarTexture()
                local oAlpha = DBVal(_overlayAlphaKey) or defaults[_overlayAlphaKey]
                local oc = (DB() and DB()[_overlayColorKey]) or defaults[_overlayColorKey]
                overlayFillClip, overlayFillTex = MakeOverlayClip(fillRef, "TOPLEFT", fillRef, "BOTTOMRIGHT", 2)
                overlayFillTex:SetTexture(ns.ResolveOverlayTexPath and ns.ResolveOverlayTexPath(tex) or (MEDIA .. tex .. ".png"))
                overlayFillTex:SetAlpha(oAlpha)
                overlayFillTex:SetVertexColor(oc.r, oc.g, oc.b)
                overlayBgClip, overlayBgTex = MakeOverlayClip(fillRef, "TOPRIGHT", health, "BOTTOMRIGHT", 1)
                overlayBgTex:SetTexture(ns.ResolveOverlayTexPath and ns.ResolveOverlayTexPath(tex) or (MEDIA .. tex .. ".png"))
                overlayBgTex:SetAlpha(_overlayBgAlpha(oAlpha))
                overlayBgTex:SetVertexColor(oc.r, oc.g, oc.b)
            end
        end

        local focusLetterFS
        local function RefreshFocusLetter()
            if colorKey ~= "focus" then return end
            if DBVal("focusLetterEnabled") ~= true then
                if focusLetterFS then focusLetterFS:Hide() end
                return
            end
            if not focusLetterFS then
                focusLetterFS = textFrame:CreateFontString(nil, "OVERLAY")
                focusLetterFS:SetJustifyH("CENTER")
                focusLetterFS:SetJustifyV("MIDDLE")
            end
            local size = DBVal("focusLetterSize") or defaults.focusLetterSize
            local anchor = GetFocusLetterAnchor()
            local x = DBVal("focusLetterX") or defaults.focusLetterX
            local y = DBVal("focusLetterY") or defaults.focusLetterY
            local curFont = (EllesmereUI.GetFontPath("nameplates")) or DBVal("font")
            SetPVFont(focusLetterFS, curFont, size, GetNPOptOutline())
            focusLetterFS:SetText("F")
            focusLetterFS:ClearAllPoints()
            focusLetterFS:SetPoint(anchor, health, anchor, x, y)
            focusLetterFS:SetTextColor(1, 1, 1, 1)
            focusLetterFS:Show()
        end
        RefreshFocusLetter()

        -- Live update hook: re-color when swatch changes
        container.UpdateColor = function()
            local cc = (DB() and DB()[colorKey]) or defaults[colorKey]
            health:SetStatusBarColor(cc.r, cc.g, cc.b, 1)
        end
        -- Live update hook: refresh overlay texture from DB
        container.UpdateOverlay = function()
            if colorKey ~= "focus" and colorKey ~= "target" then return end
            local tex = DBVal(_overlayTexKey) or defaults[_overlayTexKey]
            if tex == "none" then
                if overlayFillClip then overlayFillClip:Hide() end
                if overlayBgClip then overlayBgClip:Hide() end
            else
                local fillRef = health:GetStatusBarTexture()
                local oAlpha = DBVal(_overlayAlphaKey) or defaults[_overlayAlphaKey]
                local oc = (DB() and DB()[_overlayColorKey]) or defaults[_overlayColorKey]
                if not overlayFillClip then
                    overlayFillClip, overlayFillTex = MakeOverlayClip(fillRef, "TOPLEFT", fillRef, "BOTTOMRIGHT", 2)
                end
                overlayFillTex:SetTexture(ns.ResolveOverlayTexPath and ns.ResolveOverlayTexPath(tex) or (MEDIA .. tex .. ".png"))
                overlayFillTex:SetAlpha(oAlpha)
                overlayFillTex:SetVertexColor(oc.r, oc.g, oc.b)
                overlayFillClip:Show()
                if not overlayBgClip then
                    overlayBgClip, overlayBgTex = MakeOverlayClip(fillRef, "TOPRIGHT", health, "BOTTOMRIGHT", 1)
                end
                overlayBgTex:SetTexture(ns.ResolveOverlayTexPath and ns.ResolveOverlayTexPath(tex) or (MEDIA .. tex .. ".png"))
                overlayBgTex:SetAlpha(_overlayBgAlpha(oAlpha))
                overlayBgTex:SetVertexColor(oc.r, oc.g, oc.b)
                overlayBgClip:Show()
            end
            RefreshFocusLetter()
        end
        container.Randomize = function()
            healthPct = math.floor(60 + math.random() * 15)
            healthVal = math.floor(FAKE_MAX_HP * healthPct / 100)
            health:SetValue(healthPct)
            RefreshHealthText()
        end
        -- Exposed so cache-restore / refresh-all can update text from current DB
        container.RefreshHealthText = RefreshHealthText
        container.RefreshBorderStyle = function() end  -- no style toggle needed for 1px solid
        container.RefreshBorderColor = function()
            local bc = (DB() and DB().borderColor) or defaults.borderColor
            for _, tex in ipairs(container._brdEdges) do
                tex:SetColorTexture(bc.r, bc.g, bc.b, 1)
            end
        end

    elseif colorType == "cast" or colorType == "castLocked" then
        PP.Size(container, BAR_W + 2, BAR_H + 2)

        local cast = CreateFrame("StatusBar", nil, container)
        cast:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        cast:SetMinMaxValues(0, 1)
        cast:SetValue(NextCastFill())
        cast:SetAllPoints()

        local castBG = cast:CreateTexture(nil, "BACKGROUND")
        castBG:SetAllPoints()
        castBG:SetColorTexture(0.20, 0.20, 0.20, 0.9)


        local spark = cast:CreateTexture(nil, "OVERLAY", nil, 1)
        spark:SetTexture(MEDIA .. "cast_spark.tga")
        spark:SetSize(8, BAR_H)
        spark:SetPoint("CENTER", cast:GetStatusBarTexture(), "RIGHT", 0, 0)
        spark:SetBlendMode("ADD")
        -- Show Spark (Cast Color cog): default on; explicit false hides it.
        spark:SetShown(DBVal("castBarSparkEnabled") ~= false)

        -- Cast icon frame (to the left) no border for Colors tab previews
        local iconFrame = CreateFrame("Frame", nil, cast)
        iconFrame:SetSize(BAR_H + 2, BAR_H + 2)
        iconFrame:SetPoint("RIGHT", cast, "LEFT", 0, 0)
        iconFrame:SetFrameLevel(cast:GetFrameLevel() + 1)
        local icon = iconFrame:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetTexture(NextCastIcon())

        -- Cast text
        local cns = math.min(DBVal("castNameSize") or defaults.castNameSize, 13)
        local cts = math.min(DBVal("castTargetSize") or defaults.castTargetSize, 13)
        local cnc = (DB() and DB().castNameColor) or defaults.castNameColor

        local dbRef = DB()
        local colShowTimer = defaults.showCastTimer
        if dbRef and dbRef.showCastTimer ~= nil then colShowTimer = dbRef.showCastTimer end
        local colCtmSz = math.min((dbRef and dbRef.castTimerSize) or defaults.castTimerSize, 13)
        local colCtmC = (dbRef and dbRef.castTimerColor) or defaults.castTimerColor
        local colNameSide   = (dbRef and dbRef.castNameSide)   or defaults.castNameSide
        local colTargetSide = (dbRef and dbRef.castTargetSide) or defaults.castTargetSide
        local colTimerSide  = (dbRef and dbRef.castTimerSide)  or defaults.castTimerSide
        local colCombine = dbRef and dbRef.castCombineNameTarget == true
        local colTimerW = colCtmSz * 2.2
        -- Per-element cast text truncation (% of bar width + wrap), mirroring runtime.
        local colNameW = BAR_W * ((dbRef and dbRef.castNameWidthPct) or defaults.castNameWidthPct) / 100
        local colTgtW  = BAR_W * ((dbRef and dbRef.castTargetWidthPct) or defaults.castTargetWidthPct) / 100
        local colNameWrap = (dbRef and dbRef.castNameWrap) == true
        local colTgtWrap  = (dbRef and dbRef.castTargetWrap) == true

        -- Spell name
        local nameFS = cast:CreateFontString(nil, "OVERLAY")
        SetPVFont(nameFS, fontPath, cns, GetNPOptOutline())
        nameFS:SetWordWrap(colNameWrap)
        nameFS:SetMaxLines(colNameWrap and 2 or 1)
        nameFS:SetText(EllesmereUI.L("Spell Name"))
        nameFS:SetTextColor(cnc.r, cnc.g, cnc.b, 1)
        if colNameSide == "none" then
            nameFS:Hide()
        else
            local pt, xb, jh = ns.GetCastTextAnchor(colNameSide, colShowTimer and colTimerSide == colNameSide, colTimerW, false)
            nameFS:SetWidth(colCombine and (BAR_W * 0.80) or colNameW)
            nameFS:SetJustifyH(jh)
            nameFS:SetPoint(pt, cast, pt, xb, 0)
        end

        -- Cast timer (side only "left"/"right"; visibility via showCastTimer)
        local timerFS = cast:CreateFontString(nil, "OVERLAY")
        SetPVFont(timerFS, fontPath, colCtmSz, GetNPOptOutline())
        timerFS:SetWordWrap(false)
        timerFS:SetMaxLines(1)
        timerFS:SetTextColor(colCtmC.r, colCtmC.g, colCtmC.b, 1)
        timerFS:SetText("2.3")
        if colShowTimer then
            local tpt, txb, tjh = ns.GetCastTextAnchor(colTimerSide, false, colTimerW, true)
            timerFS:SetWidth(colTimerW)
            timerFS:SetJustifyH(tjh)
            timerFS:SetPoint(tpt, cast, tpt, txb, 0)
        else
            timerFS:Hide()
        end

        -- Spell target
        local targetFS = cast:CreateFontString(nil, "OVERLAY")
        SetPVFont(targetFS, fontPath, cts, GetNPOptOutline())
        targetFS:SetWordWrap(colTgtWrap)
        targetFS:SetNonSpaceWrap(false)
        targetFS:SetMaxLines(colTgtWrap and 2 or 1)
        local colTargetText = isHalf and (UnitName("player") or EllesmereUI.L("Target")) or (UnitName("player") or EllesmereUI.L("Spell Target"))
        targetFS:SetText(colTargetText)
        local useClassColor = defaults.castTargetClassColor
        if dbRef and dbRef.castTargetClassColor ~= nil then useClassColor = dbRef.castTargetClassColor end
        local colTargetHex
        if useClassColor then
            local _, pClass = UnitClass("player")
            local c = pClass and RAID_CLASS_COLORS and RAID_CLASS_COLORS[pClass]
            if c then
                targetFS:SetTextColor(c.r, c.g, c.b, 1)
                colTargetHex = (c.GenerateHexColor and c:GenerateHexColor()) or c.colorStr or "ffffffff"
            else
                targetFS:SetTextColor(1, 1, 1, 1)
                colTargetHex = "ffffffff"
            end
        else
            local ctc = (dbRef and dbRef.castTargetColor) or defaults.castTargetColor
            targetFS:SetTextColor(ctc.r, ctc.g, ctc.b, 1)
            colTargetHex = string.format("ff%02x%02x%02x",
                math.floor(ctc.r * 255 + 0.5), math.floor(ctc.g * 255 + 0.5), math.floor(ctc.b * 255 + 0.5))
        end
        if colCombine then
            nameFS:SetFormattedText("%s - |c" .. colTargetHex .. "%s|r",
                EllesmereUI.L("Spell Name"), colTargetText)
        end
        if colCombine or colTargetSide == "none" then
            targetFS:Hide()
        else
            local pt, xb, jh = ns.GetCastTextAnchor(colTargetSide, colShowTimer and colTimerSide == colTargetSide, colTimerW, false)
            targetFS:SetWidth(colTgtW)
            targetFS:SetJustifyH(jh)
            targetFS:SetPoint(pt, cast, pt, xb, 0)
        end

        -- Shield for uninterruptible
        if colorType == "castLocked" then
            local shieldH = BAR_H * 0.75
            local shieldW = shieldH * (29 / 35)
            local shieldFrame = CreateFrame("Frame", nil, cast)
            shieldFrame:SetSize(shieldW, shieldH)
            shieldFrame:SetPoint("CENTER", cast, "LEFT", 0, 0)
            shieldFrame:SetFrameLevel(cast:GetFrameLevel() + 10)
            local shield = shieldFrame:CreateTexture(nil, "OVERLAY")
            shield:SetAllPoints()
            shield:SetTexture(MEDIA .. "shield.png")
        end

        -- Color the bar
        local c = (DB() and DB()[colorKey]) or defaults[colorKey]
        cast:SetStatusBarColor(c.r, c.g, c.b, 1)

        -- Shift container left to account for cast icon hanging outside
        container:ClearAllPoints()
        PP.Point(container, "RIGHT", anchor, "RIGHT", -(20 + SWATCH_SZ + SWATCH_GAP), 0)

        container.UpdateColor = function()
            local cc = (DB() and DB()[colorKey]) or defaults[colorKey]
            cast:SetStatusBarColor(cc.r, cc.g, cc.b, 1)
        end
        container.Randomize = function()
            cast:SetValue(NextCastFill())
            icon:SetTexture(NextCastIcon())
        end
        container.RefreshBorderStyle = function() end
        container.RefreshBorderColor = function() end
    end

    return container
end

local function BuildColorsPage(pageName, parent, yOffset)
    local env = ns._NPO_OptEnv
    local _colorPagePreviews, DB, DBColor, DBVal = env._colorPagePreviews, env.DB, env.DBColor, env.DBVal
    local defaults, optState, pairs, PP = env.defaults, env.optState, env.pairs, env.PP
    local RefreshAllPlates, SECTION_ENEMY, SECTION_THREAT, THREAT_PCT_POSITION_ORDER = env.RefreshAllPlates, env.SECTION_ENEMY, env.SECTION_THREAT, env.THREAT_PCT_POSITION_ORDER
    local THREAT_PCT_POSITIONS = env.THREAT_PCT_POSITIONS
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h

    -- No content header on Colors tab (presets are inline in scroll area)
    EllesmereUI:ClearContentHeader()

    -- Enable per-row center divider for the dual-column layout (same as Display tab)
    parent._showRowDivider = true

    -- Track all mini previews for border style refresh
    _G._EUI_ColorPreviews = {}

    -- LazyColorPreviewBar and _colorPagePreviews live at init scope (shared between Display and Colors pages).

    -----------------------------------------------------------------------
    --  ENEMY COLORS
    -----------------------------------------------------------------------
    _, h = W:SectionHeader(parent, SECTION_ENEMY, y);  y = y - h

    local enemyTypesRow
    enemyTypesRow, h = W:DualRow(parent, y,
        { type="multiSwatch", text="Enemy Types",
          swatches = {
            { tooltip = "Enemies",
              getValue = function() return DBColor("enemyInCombat") end,
              setValue = function(r, g, b)
                DB().enemyInCombat = { r = r, g = g, b = b }
                RefreshAllPlates()
              end },
            { tooltip = "Spell Casters",
              getValue = function() return DBColor("caster") end,
              setValue = function(r, g, b)
                DB().caster = { r = r, g = g, b = b }
                RefreshAllPlates()
              end },
            { tooltip = "Mini-Bosses",
              getValue = function() return DBColor("miniboss") end,
              setValue = function(r, g, b)
                DB().miniboss = { r = r, g = g, b = b }
                RefreshAllPlates()
              end },
            { tooltip = "Bosses",
              getValue = function() return DBColor("boss") end,
              setValue = function(r, g, b)
                DB().boss = { r = r, g = g, b = b }
                RefreshAllPlates()
              end },
          } },
        { type="toggle", text="Enable Quest Mob Color",
          getValue=function() return DBVal("questMobColorEnabled") == true end,
          setValue=function(v)
            DB().questMobColorEnabled = v
            for _, plate in pairs(ns.plates) do
                plate:UpdateHealthColor()
            end
            EllesmereUI:RefreshPage()
          end,
          tooltip="Colors enemy nameplates for quest mobs you still need to kill." });  y = y - h

    -- Inline Quest Mob Color swatch
    if not EllesmereUI._prebuilding then
        local rightRgn = enemyTypesRow._rightRegion
        local questColorGet = function()
            local c = DB().questMobColor or defaults.questMobColor
            return c.r, c.g, c.b
        end
        local questColorSet = function(r, g, b)
            DB().questMobColor = { r = r, g = g, b = b }
            RefreshAllPlates()
        end
        local isQuestOff = function() return DBVal("questMobColorEnabled") ~= true end
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5, questColorGet, questColorSet, nil, 20)
        PP.Point(swatch, "RIGHT", rightRgn._control, "LEFT", -12, 0)
        EllesmereUI.RegisterWidgetRefresh(function()
            local off = isQuestOff()
            swatch:SetAlpha(off and 0.15 or 1)
            swatch:EnableMouse(not off)
            updateSwatch()
        end)
        local off = isQuestOff()
        swatch:SetAlpha(off and 0.15 or 1)
        swatch:EnableMouse(not off)
    end

    -- Inline cog on "Enemy Types": Full Coloring M+ Only. On: outside 5-man dungeons, Mini/Caster/Miniboss/Boss all use the flat "All Enemies" color below (Neutral keeps its own); off (default) has no effect anywhere. Keys keep their owBasic* names from before the current UI label.
    if not EllesmereUI._prebuilding then
        local leftRgn = enemyTypesRow._leftRegion
        local isOWOff = function()
            local v = DBVal("owBasicColoring")
            if v == nil then return not defaults.owBasicColoring end
            return not v
        end
        EllesmereUI.BuildInlineCog(leftRgn, {
            title = "Enemy Colors",
            rows = {
                { type="toggle", label="Full Coloring M+ Only",
                  get=function()
                    local v = DBVal("owBasicColoring")
                    if v == nil then return defaults.owBasicColoring end
                    return v
                  end,
                  set=function(v)
                    DB().owBasicColoring = v
                    RefreshAllPlates()
                  end },
                { type="colorpicker", label="All Enemies",
                  get=function() return DBColor("owBasicColor") end,
                  set=function(r, g, b)
                    DB().owBasicColor = { r = r, g = g, b = b }
                    RefreshAllPlates()
                  end,
                  disabled=isOWOff,
                  disabledTooltip="Full Coloring M+ Only" },
            },
        })
    end

    -- Neutral & Mini Enemies | Darken Enemies Out of Combat
    local neutralMiniRow
    neutralMiniRow, h = W:DualRow(parent, y,
        { type="multiSwatch", text="Neutral & Mini Enemies",
          swatches = {
            { tooltip = "Neutral",
              getValue = function() return DBColor("neutral") end,
              setValue = function(r, g, b)
                DB().neutral = { r = r, g = g, b = b }
                RefreshAllPlates()
              end },
            { tooltip = "Mini Enemies",
              -- Until explicitly set, views the user's "Enemies" color so the swatch starts matching enemyInCombat (see GetReactionColor).
              getValue = function()
                local db = DB()
                local c = (db and db.miniEnemy) or (db and db.enemyInCombat) or defaults.enemyInCombat
                return c.r, c.g, c.b
              end,
              setValue = function(r, g, b)
                DB().miniEnemy = { r = r, g = g, b = b }
                RefreshAllPlates()
              end },
          } },
        { type="toggle", text="Darken Enemies Out of Combat",
          getValue=function()
            local db = DB()
            if db and db.darkenEnemiesOOC ~= nil then return db.darkenEnemiesOOC end
            return defaults.darkenEnemiesOOC
          end,
          setValue=function(v)
            DB().darkenEnemiesOOC = v
            for _, plate in pairs(ns.plates) do
                plate:UpdateHealthColor()
            end
          end,
          tooltip="Dims enemy nameplate colours while the enemy is out of combat. Turn off to keep enemies at full colour whether or not they are fighting." });  y = y - h

    -- Inline cog on "Neutral & Mini Enemies": "Mini Coloring M+ Only" toggle. On (default) restricts the Mini Enemies color to 5-man dungeons; off applies it everywhere.
    if not EllesmereUI._prebuilding then
        local leftRgn = neutralMiniRow._leftRegion
        EllesmereUI.BuildInlineCog(leftRgn, {
            title = "Mini Enemies",
            rows = {
                { type="toggle", label="Mini Coloring M+ Only",
                  get=function()
                    local v = DBVal("miniColoringMPlusOnly")
                    if v == nil then return defaults.miniColoringMPlusOnly end
                    return v
                  end,
                  set=function(v)
                    DB().miniColoringMPlusOnly = v
                    RefreshAllPlates()
                  end },
            },
        })

        -- Inline cog on "Darken Enemies Out of Combat": recolor OOC enemy
        -- plates with a flat color instead of dimming them (MaybeDarken).
        local rightRgn = neutralMiniRow._rightRegion
        local function DarkenRecolorOn()
            local db = DB()
            local v = db and db.darkenOOCRecolor
            if v == nil then v = defaults.darkenOOCRecolor end
            return v
        end
        EllesmereUI.BuildInlineCog(rightRgn, {
            title = "Out of Combat",
            rows = {
                { type="toggle", label="Change Color Instead",
                  tooltip="Give out-of-combat enemy nameplates a custom color instead of darkening them.",
                  get=DarkenRecolorOn,
                  set=function(v)
                    DB().darkenOOCRecolor = v
                    for _, plate in pairs(ns.plates) do
                        plate:UpdateHealthColor()
                    end
                  end },
                { type="colorpicker", label="Out of Combat Color",
                  disabled=function() return not DarkenRecolorOn() end,
                  disabledTooltip="Change Color Instead",
                  get=function()
                    local db = DB()
                    local c = (db and db.darkenOOCColor) or defaults.darkenOOCColor
                    return c.r, c.g, c.b
                  end,
                  set=function(r, g, b)
                    DB().darkenOOCColor = { r = r, g = g, b = b }
                    for _, plate in pairs(ns.plates) do
                        plate:UpdateHealthColor()
                    end
                  end },
            },
        })
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    -----------------------------------------------------------------------
    --  THREAT COLORS
    -----------------------------------------------------------------------
    _, h = W:SectionHeader(parent, SECTION_THREAT, y);  y = y - h

    -- Show Threat Colors (threatColorMode): Never / Instances (dungeons, raids and
    -- delves) / Always; an unknown saved value reads as the default. Never locks every
    -- threat-color control below. The WoW Forever Threat % rows are their own feature
    -- and stay live.
    local function threatModeGet()
        local v = DBVal("threatColorMode")
        if v ~= "never" and v ~= "instances" and v ~= "always" then v = defaults.threatColorMode end
        return v
    end
    local function threatNever() return threatModeGet() == "never" end

    -- Row 1: Show Threat Colors (left) ---- Tank Threat (right)
    _, h = W:DualRow(parent, y,
        { type="dropdown", text="Show Threat Colors",
          tooltip="Where nameplates use the threat colors below. Instances covers dungeons, raids and delves.",
          values={ never="Never", instances="Instances", always="Always" },
          order={ "never", "instances", "always" },
          getValue=threatModeGet,
          setValue=function(v)
            DB().threatColorMode = v
            ns.NP_ApplyThreatColorMode()
            EllesmereUI:RefreshPage()
          end },
        { type="multiSwatch", text="Tank Threat",
          disabled=threatNever, disabledTooltip="Show Threat Colors",
          swatches = {
            { tooltip = "Losing Aggro",
              getValue = function() return DBColor("tankLosingAggro") end,
              setValue = function(r, g, b)
                DB().tankLosingAggro = { r = r, g = g, b = b }
                RefreshAllPlates()
              end },
            { tooltip = "No Aggro",
              getValue = function() return DBColor("tankNoAggro") end,
              setValue = function(r, g, b)
                DB().tankNoAggro = { r = r, g = g, b = b }
                RefreshAllPlates()
              end },
          } });  y = y - h

    -- Disabled-state helpers (shared across the toggle rows' swatches and cogs)
    local function isTankHasAggroDisabled()
        local db = DB()
        if db and db.tankHasAggroEnabled ~= nil then return not db.tankHasAggroEnabled end
        return not defaults.tankHasAggroEnabled
    end
    local function isClassicTankAggroDisabled()
        local db = DB()
        if db and db.classicTankAggro ~= nil then return not db.classicTankAggro end
        return not defaults.classicTankAggro
    end
    local function isOffTankDisabled()
        local db = DB()
        if db and db.offTankAggroEnabled ~= nil then return not db.offTankAggroEnabled end
        return not defaults.offTankAggroEnabled
    end
    local function isDpsNoAggroDisabled()
        local db = DB()
        if db and db.dpsNoAggroEnabled ~= nil then return not db.dpsNoAggroEnabled end
        return not defaults.dpsNoAggroEnabled
    end
    -- The Override toggles only reorder the health bar's color priority, so the No Aggro
    -- and Has Aggro cogs (Override rows only) lock while Show Threat On leaves the Health Bar out.
    local function isThreatHealthOff() return not ns.GetThreatColorHealth() end

    -- Inline swatch lock for the toggle rows: dimmed and click-blocked while its own
    -- toggle is off or Show Threat Colors is Never; the block names the missing one.
    local function LockThreatSwatch(swatch, updateSwatch, ownOff, ownReq)
        local tipCfg = { disabledTooltip = function()
            if threatNever() then return "Show Threat Colors" end
            return ownReq
        end }
        local block = CreateFrame("Frame", nil, swatch)
        block:SetAllPoints()
        block:SetFrameLevel(swatch:GetFrameLevel() + 10)
        block:EnableMouse(true)
        block:SetScript("OnEnter", function()
            EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.ResolveDisabledTip(tipCfg))
        end)
        block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local function State()
            local off = threatNever() or ownOff()
            swatch:SetAlpha(off and 0.3 or 1)
            block:SetShown(off)
        end
        EllesmereUI.RegisterWidgetRefresh(function()
            State()
            updateSwatch()
        end)
        State()
    end

    -- Row 2: Non-Tank Threat (left) ---- DPS: Show Special "No Aggro" Color (right)
    local nonTankRow
    nonTankRow, h = W:DualRow(parent, y,
        { type="multiSwatch", text="Non-Tank Threat",
          disabled=threatNever, disabledTooltip="Show Threat Colors",
          swatches = {
            { tooltip = "Has Aggro",
              getValue = function() return DBColor("dpsHasAggro") end,
              setValue = function(r, g, b)
                DB().dpsHasAggro = { r = r, g = g, b = b }
                RefreshAllPlates()
              end },
            { tooltip = "Near Aggro",
              getValue = function() return DBColor("dpsNearAggro") end,
              setValue = function(r, g, b)
                DB().dpsNearAggro = { r = r, g = g, b = b }
                RefreshAllPlates()
              end },
          } },
        { type="toggle", text="DPS: Show Special \"No Aggro\" Color",
          tooltip="Shows a special color for non caster/mini-boss enemies when you do not have aggro on them.",
          disabled=threatNever, disabledTooltip="Show Threat Colors",
          getValue=function()
            local db = DB()
            if db and db.dpsNoAggroEnabled ~= nil then return db.dpsNoAggroEnabled end
            return defaults.dpsNoAggroEnabled
          end,
          setValue=function(v)
            DB().dpsNoAggroEnabled = v
            RefreshAllPlates()
            EllesmereUI:RefreshPage()
          end });  y = y - h

    -- Inline cog on "Non-Tank Threat": steady red execute-style glow
    -- while the Near Aggro color is active (see EnsureNearAggroGlow).
    if not EllesmereUI._prebuilding then
        EllesmereUI.BuildInlineCog(nonTankRow._leftRegion, {
            disabled = threatNever,
            disabledTooltip = "Show Threat Colors",
            title = "Near Aggro",
            rows = {
                { type="toggle", label="Glow Nameplate When Near Aggro",
                  tooltip="Adds a steady red glow around the nameplate while the Near Aggro color is active.",
                  get=function()
                    local db = DB()
                    local v = db and db.threatNearAggroGlow
                    if v == nil then v = defaults.threatNearAggroGlow end
                    return v
                  end,
                  set=function(v)
                    DB().threatNearAggroGlow = v and true or false
                    for _, plate in pairs(ns.plates) do
                        plate:UpdateHealthColor()
                    end
                  end },
            },
        })
    end

    -- Inline "No Aggro" color swatch next to the DPS toggle
    if not EllesmereUI._prebuilding then
        local rgn = nonTankRow._rightRegion
        local dpsNoAggroColorGet = function() return DBColor("dpsNoAggro") end
        local dpsNoAggroColorSet = function(r, g, b)
            DB().dpsNoAggro = { r = r, g = g, b = b }
            RefreshAllPlates()
        end
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, dpsNoAggroColorGet, dpsNoAggroColorSet, nil, 20)
        PP.Point(swatch, "RIGHT", rgn._control, "LEFT", -12, 0)
        LockThreatSwatch(swatch, updateSwatch, isDpsNoAggroDisabled, 'DPS: Show Special "No Aggro" Color')

        -- Inline cog: independent "Override Mini-Boss colors" / "Override Caster colors" / "Override Boss colors" toggles promote the DPS No Aggro color above that single mob-type color (kept separate for contrast); dimmed while off.
        EllesmereUI.BuildInlineCog(rgn, {
            chain = false, anchorTo = swatch,
            disabled = function() return threatNever() or isDpsNoAggroDisabled() or isThreatHealthOff() end,
            disabledTooltip = function()
                if threatNever() then return "Show Threat Colors" end
                if isDpsNoAggroDisabled() then return 'DPS: Show Special "No Aggro" Color' end
                return "Health Bar"
            end,
            title = "No Aggro",
            rows = {
                { type="toggle", label="Override Mini-Boss colors",
                  get=function()
                    local db = DB()
                    if db and db.dpsNoAggroOverrideMiniBoss ~= nil then return db.dpsNoAggroOverrideMiniBoss end
                    return defaults.dpsNoAggroOverrideMiniBoss
                  end,
                  set=function(v) DB().dpsNoAggroOverrideMiniBoss = v; RefreshAllPlates() end },
                { type="toggle", label="Override Caster colors",
                  get=function()
                    local db = DB()
                    if db and db.dpsNoAggroOverrideCaster ~= nil then return db.dpsNoAggroOverrideCaster end
                    return defaults.dpsNoAggroOverrideCaster
                  end,
                  set=function(v) DB().dpsNoAggroOverrideCaster = v; RefreshAllPlates() end },
                { type="toggle", label="Override Boss colors",
                  get=function()
                    local db = DB()
                    if db and db.dpsNoAggroOverrideBoss ~= nil then return db.dpsNoAggroOverrideBoss end
                    return defaults.dpsNoAggroOverrideBoss
                  end,
                  set=function(v) DB().dpsNoAggroOverrideBoss = v; RefreshAllPlates() end },
            },
        })
    end

    -- Row 3: Classic Tank Aggro (left) ---- Tank: Show Special "Has Aggro" Color (right)
    local tankAggroRow
    tankAggroRow, h = W:DualRow(parent, y,
        { type="toggle", text="Classic Tank Aggro",
          tooltip="Enables a three-tier tank aggro system: has aggro, losing aggro, and no aggro colors override all mob-type colors.",
          disabled=threatNever, disabledTooltip="Show Threat Colors",
          getValue=function()
            local db = DB()
            if db and db.classicTankAggro ~= nil then return db.classicTankAggro end
            return defaults.classicTankAggro
          end,
          setValue=function(v)
            DB().classicTankAggro = v
            RefreshAllPlates()
            EllesmereUI:RefreshPage()
          end },
        { type="toggle", text="Tank: Show Special \"Has Aggro\" Color",
          tooltip="Shows a special color for non caster/mini-boss enemies when you have aggro on them.",
          disabled=threatNever, disabledTooltip="Show Threat Colors",
          getValue=function()
            local db = DB()
            if db and db.tankHasAggroEnabled ~= nil then return db.tankHasAggroEnabled end
            return defaults.tankHasAggroEnabled
          end,
          setValue=function(v)
            DB().tankHasAggroEnabled = v
            RefreshAllPlates()
            EllesmereUI:RefreshPage()
          end });  y = y - h

    -- Inline "Has Aggro" color swatch next to Classic Tank Aggro toggle
    if not EllesmereUI._prebuilding then
        local rgn = tankAggroRow._leftRegion
        local aggroColorGet = function() return DBColor("tankHasAggro") end
        local aggroColorSet = function(r, g, b)
            DB().tankHasAggro = { r = r, g = g, b = b }
            RefreshAllPlates()
        end
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, aggroColorGet, aggroColorSet, nil, 20)
        PP.Point(swatch, "RIGHT", rgn._control, "LEFT", -12, 0)
        LockThreatSwatch(swatch, updateSwatch, isClassicTankAggroDisabled, "Classic Tank Aggro")
    end

    -- Inline "Has Aggro" color swatch next to the tank Has Aggro toggle
    if not EllesmereUI._prebuilding then
        local rgn = tankAggroRow._rightRegion
        local tankAggroColorGet = function() return DBColor("tankHasAggro") end
        local tankAggroColorSet = function(r, g, b)
            DB().tankHasAggro = { r = r, g = g, b = b }
            RefreshAllPlates()
        end
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, tankAggroColorGet, tankAggroColorSet, nil, 20)
        PP.Point(swatch, "RIGHT", rgn._control, "LEFT", -12, 0)
        LockThreatSwatch(swatch, updateSwatch, isTankHasAggroDisabled, 'Tank: Show Special "Has Aggro" Color')

        -- Inline cog "Override Mini-Boss and Caster colors" promotes the tank has-aggro color above the mini-boss/caster priority steps; dimmed while Has Aggro is off.
        EllesmereUI.BuildInlineCog(rgn, {
            chain = false, anchorTo = swatch,
            disabled = function() return threatNever() or isTankHasAggroDisabled() or isThreatHealthOff() end,
            disabledTooltip = function()
                if threatNever() then return "Show Threat Colors" end
                if isTankHasAggroDisabled() then return 'Tank: Show Special "Has Aggro" Color' end
                return "Health Bar"
            end,
            title = "Has Aggro",
            rows = {
                { type="toggle", label="Override Mini-Boss and Caster colors",
                  get=function()
                    local db = DB()
                    if db and db.tankHasAggroOverrideMobType ~= nil then return db.tankHasAggroOverrideMobType end
                    return defaults.tankHasAggroOverrideMobType
                  end,
                  set=function(v) DB().tankHasAggroOverrideMobType = v; RefreshAllPlates() end },
                { type="toggle", label="Override Boss colors",
                  get=function()
                    local db = DB()
                    if db and db.tankHasAggroOverrideBoss ~= nil then return db.tankHasAggroOverrideBoss end
                    return defaults.tankHasAggroOverrideBoss
                  end,
                  set=function(v) DB().tankHasAggroOverrideBoss = v; RefreshAllPlates() end },
            },
        })
    end

    -- Show Threat On: which parts of the plate carry the threat colors above. Border and
    -- Name are second signals beside the Health Bar, so the bar can keep its Enemy Types
    -- color (Caster / Mini-Boss / Boss) while the border and the name show aggro.
    -- Border locks while no EUI border is drawn (None, or a stock style). Built as a
    -- placeholder dropdown (its disabled config dims the label and blocks the slot) and
    -- replaced below in whichever half of chanRow holds it.
    local chanCfg = { type="dropdown", text="Show Threat On",
          disabled=threatNever, disabledTooltip="Show Threat Colors",
          values={ __placeholder = "..." }, order={ "__placeholder" },
          getValue=function() return "__placeholder" end,
          setValue=function() end }

    -- WoW Forever Threat % helpers and toggle (nil on retail, where Show Threat On
    -- takes the Off-Tank row's right slot instead).
    local threatPctOff, ThreatPctSet, offTankRightCfg
    if EllesmereUI.IS_FOREVER then
        threatPctOff = function() return not DBVal("threatPctEnabled") end
        ThreatPctSet = function(key, v)
            DB()[key] = v
            ns.RefreshThreatPct()
        end
        offTankRightCfg = { type="toggle", text="Show Threat % on Nameplates",
              tooltip="Shows your threat percentage on each enemy nameplate while you are in combat with it.",
              getValue=function() return DBVal("threatPctEnabled") end,
              setValue=function(v)
                ThreatPctSet("threatPctEnabled", v)
                EllesmereUI:RefreshPage()
              end }
    else
        offTankRightCfg = chanCfg
    end

    -- Row 4: Tank: Show Special "Off-Tank" Color (left) ---- Show Threat On (right);
    -- on WoW Forever the right slot is Show Threat % on Nameplates.
    local offTankRow
    offTankRow, h = W:DualRow(parent, y,
        { type="toggle", text="Tank: Show Special \"Off-Tank\" Color",
          tooltip="Shows a special color for nameplates that another tank in your raid has aggro on.",
          disabled=threatNever, disabledTooltip="Show Threat Colors",
          getValue=function()
            local db = DB()
            if db and db.offTankAggroEnabled ~= nil then return db.offTankAggroEnabled end
            return defaults.offTankAggroEnabled
          end,
          setValue=function(v)
            DB().offTankAggroEnabled = v
            RefreshAllPlates()
            EllesmereUI:RefreshPage()
          end },
        offTankRightCfg);  y = y - h

    -- Inline "Off-Tank" color swatch next to the Off-Tank toggle
    if not EllesmereUI._prebuilding then
        local rgn = offTankRow._leftRegion
        local otColorGet = function() return DBColor("offTankAggro") end
        local otColorSet = function(r, g, b)
            DB().offTankAggro = { r = r, g = g, b = b }
            RefreshAllPlates()
        end
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, otColorGet, otColorSet, nil, 20)
        PP.Point(swatch, "RIGHT", rgn._control, "LEFT", -12, 0)
        LockThreatSwatch(swatch, updateSwatch, isOffTankDisabled, 'Tank: Show Special "Off-Tank" Color')
    end

    -- Row 5 (WoW Forever only): Threat % Position (left) ---- Show Threat On (right).
    local chanRow = offTankRow
    if EllesmereUI.IS_FOREVER then
        local threatPctRow
        threatPctRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Threat % Position",
              values=THREAT_PCT_POSITIONS, order=THREAT_PCT_POSITION_ORDER,
              disabled=threatPctOff, disabledTooltip="Show Threat % on Nameplates",
              getValue=function() return DBVal("threatPctPosition") end,
              setValue=function(v) ThreatPctSet("threatPctPosition", v) end },
            chanCfg);  y = y - h
        chanRow = threatPctRow

        if not EllesmereUI._prebuilding then
            local function ThreatPctSlider(key, label, lo, hi)
                return { type="slider", label=label, min=lo, max=hi, step=1,
                  get=function() return DBVal(key) end,
                  set=function(v) ThreatPctSet(key, v) end }
            end
            EllesmereUI.BuildInlineCog(threatPctRow._leftRegion, {
                title = "Threat %",
                disabled = threatPctOff,
                disabledTooltip = "Show Threat % on Nameplates",
                rows = {
                    { type="toggle", label="Color by Threat",
                      tooltip="Colors the number by threat status. Off shows it in white.",
                      get=function() return DBVal("threatPctColorByThreat") end,
                      set=function(v) ThreatPctSet("threatPctColorByThreat", v) end },
                    ThreatPctSlider("threatPctSize", "Size", 6, 20),
                    ThreatPctSlider("threatPctXOffset", "X", -100, 100),
                    ThreatPctSlider("threatPctYOffset", "Y", -100, 100),
                },
            })
        end
    end

    -- Replace the Show Threat On placeholder with a multi-select checkbox dropdown,
    -- in whichever half of chanRow was built from chanCfg.
    if not EllesmereUI._prebuilding then
        local rgn = chanRow._rightRegion
        if chanRow._leftRegion._cfg == chanCfg then rgn = chanRow._leftRegion end
        if rgn._control then rgn._control:Hide() end
        -- A locked Border also drops out of the summary, which then reads what is drawn.
        local function isThreatBorderLocked()
            return not (ns.IsBorderEnabled() or ns.IsCustomBorderEnabled())
        end
        local chanItems = {
            { key = "health", label = "Health Bar" },
            { key = "border", label = "Border",
              lockedFn = isThreatBorderLocked,
              excludeFromSummaryFn = isThreatBorderLocked,
              lockedTooltip = function()
                if EllesmereUI.BlizzStyle.Get("nameplates") then
                    return EllesmereUI.DisabledTooltip(EllesmereUI.BlizzStyle.Label("nameplates"), "disabled")
                end
                return "This option requires a Border to be selected"
              end },
            { key = "name",   label = "Name" },
        }
        local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
            rgn, 170, rgn:GetFrameLevel() + 2,
            chanItems,
            function(k)
                if k == "health" then return ns.GetThreatColorHealth() end
                if k == "border" then return ns.GetThreatColorBorder() end
                if k == "name"   then return ns.GetThreatColorName() end
                return false
            end,
            function(k, v)
                if k == "health" then DB().threatColorHealth = v
                elseif k == "border" then DB().threatColorBorder = v
                elseif k == "name" then DB().threatColorName = v end
                RefreshAllPlates()
                -- Health Bar gates the No Aggro and Has Aggro cogs.
                EllesmereUI:RefreshPage()
            end)
        PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
        rgn._control = cbDD
        cbDD:HookScript("OnEnter", function()
            EllesmereUI.ShowWidgetTooltip(cbDD, "Chooses which parts of the nameplate show the threat colors; with Health Bar off, the bar keeps its Enemy Types color.")
        end)
        cbDD:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
        -- The checkbox dropdown has no disabled state of its own: grey it and block
        -- clicks while Show Threat Colors is Never; the placeholder's disabled overlay
        -- over the same slot shows the requirement.
        local function ApplyChanDisabled()
            local off = threatNever()
            cbDD:SetAlpha(off and 0.3 or 1)
            cbDD:EnableMouse(not off)
        end
        ApplyChanDisabled()
        EllesmereUI.RegisterWidgetRefresh(ApplyChanDisabled)
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    -- Build a refresh-all function for page cache restore
    optState._colorPreviewRefreshAll = function()
        for _, prev in ipairs(_G._EUI_ColorPreviews) do
            if prev.UpdateColor then prev.UpdateColor() end
            if prev.UpdateOverlay then prev.UpdateOverlay() end
            if prev.RefreshBorderColor then prev.RefreshBorderColor() end
            if prev.RefreshHealthText then prev.RefreshHealthText() end
        end
        for _, prev in ipairs(_colorPagePreviews) do
            if prev.UpdateColor then prev.UpdateColor() end
            if prev.UpdateOverlay then prev.UpdateOverlay() end
            if prev.RefreshBorderColor then prev.RefreshBorderColor() end
            if prev.RefreshHealthText then prev.RefreshHealthText() end
        end
    end
    for _, prev in ipairs(_colorPagePreviews) do
        if prev.UpdateColor then
            EllesmereUI.RegisterWidgetRefresh(prev.UpdateColor)
        end
        if prev.UpdateOverlay then
            EllesmereUI.RegisterWidgetRefresh(prev.UpdateOverlay)
        end
    end

    return math.abs(y)
end

-- Used by EUI_Nameplates_Options.lua
ns.NPO_MakeColorPreviewBar = MakeColorPreviewBar
ns.NPO_BuildColorsPage = BuildColorsPage
