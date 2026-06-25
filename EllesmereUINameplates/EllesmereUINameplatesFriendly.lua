local addon, ns = ...

if not ns then return end

local GetFont = ns.GetFont
local GetNPOutline = ns.GetNPOutline
local GetNPUseShadow = ns.GetNPUseShadow
local SetFSFont = ns.SetFSFont
local GetHealthBarHeight = ns.GetHealthBarHeight
local GetFriendlyHealthBarHeight = ns.GetFriendlyHealthBarHeight
local GetFriendlyHealthBarWidth = ns.GetFriendlyHealthBarWidth

-- Profile alias: reads from the centralized store via ns.db
local function FP()
    return ns.db and ns.db.profile
end

local pairs, ipairs = pairs, ipairs
local UnitHealth, UnitHealthMax = UnitHealth, UnitHealthMax
local UnitName, UnitIsUnit = UnitName, UnitIsUnit
local UnitCanAttack, UnitIsPlayer = UnitCanAttack, UnitIsPlayer
local UnitClass, UnitIsDeadOrGhost = UnitClass, UnitIsDeadOrGhost
local UnitExists, UnitHealthPercent = UnitExists, UnitHealthPercent
local GetRaidTargetIndex, SetRaidTargetIconTexture = GetRaidTargetIndex, SetRaidTargetIconTexture
local C_NamePlate = C_NamePlate
local Enum = Enum

-------------------------------------------------------------------------------
--  State
-------------------------------------------------------------------------------
local friendlyEnabled = false
local friendlyPlates = {}
ns.friendlyPlates = friendlyPlates
local _cachedFriendlyTargetPlate = nil

local FRIENDLY_BAR_W = 150
local FRIENDLY_PLATE_Y_OFFSET = -18

local function IsInFollowerDungeon()
    if C_LFGInfo and C_LFGInfo.IsInLFGFollowerDungeon and C_LFGInfo.IsInLFGFollowerDungeon() then
        return true
    end
    -- Delves (difficultyID 208) also have follower NPCs
    local _, _, difficultyID = GetInstanceInfo()
    if difficultyID == 208 then
        return true
    end
    return false
end

local function IsFriendlyEnabled()
    if IsInFollowerDungeon() then return false end
    local fp = FP()
    if not fp or fp.showFriendlyPlayers == false then return false end
    return (fp.friendlyNameOnly == false)
end

local function IsNameOnlyMode()
    if IsInFollowerDungeon() then return false end
    local fp = FP()
    if not fp then return false end
    if fp.showFriendlyPlayers == false then return false end
    return (fp.friendlyNameOnly ~= false)
end

local function IsFriendlyNPCEnabled()
    local fp = FP()
    return fp and (fp.showFriendlyNPCs == true)
end

-- Per-unit gate for friendly NPC nameplates. On top of our own toggle, respect
-- Blizzard's "NPC Names" filter via UnitShouldDisplayName(unit): it returns true
-- for the "desired" NPCs the game names (vendors, guards, quest givers, plus the
-- current target/mouseover) and false for flavor NPCs the filter hides. Without
-- this gate our overlay / custom plate would draw a name on NPCs the game
-- intentionally leaves nameless. nil-guarded for safety.
local function IsFriendlyNPCShownForUnit(unit)
    if not IsFriendlyNPCEnabled() then return false end
    if unit and UnitShouldDisplayName and not UnitShouldDisplayName(unit) then
        return false
    end
    return true
end

local function ShowNPCTitles()
    local fp = FP()
    return fp and (fp.showNPCTitles ~= false)
end

-- Extract the NPC subtitle (e.g. "Innkeeper", "Flight Master") from tooltip
-- line 2 via the safe C_TooltipInfo API. Returns nil if none found.
local LEVEL_PATTERN
do
    local tpl = UNIT_LEVEL_TEMPLATE or "Level %d"
    LEVEL_PATTERN = tpl:lower():gsub("%%d", "(.+)")
end

local function GetNPCTitle(unit)
    if not C_TooltipInfo or not C_TooltipInfo.GetUnit then return nil end
    local data = C_TooltipInfo.GetUnit(unit)
    if not data or not data.lines then return nil end
    local cbMode = tonumber(GetCVar("colorblindMode")) or 0
    local line = data.lines[2 + cbMode]
    if not line then return nil end
    local text = line.leftText
    -- The secret guard MUST come before any comparison: line.leftText is a secret
    -- string under nameplate taint, and "text == ''" throws on a secret value.
    -- A truthiness check (not text) is secret-safe, so the nil-guard stays first.
    if not text then return nil end
    if issecretvalue and issecretvalue(text) then return nil end
    if text == "" then return nil end
    -- Filter out level strings (e.g. "Level 70 Humanoid")
    if text:lower():match(LEVEL_PATTERN) then return nil end
    return text
end

-- Friendly NPC color: #00ff00
local NPC_COLOR_R, NPC_COLOR_G, NPC_COLOR_B = 0, 1, 0

-- Bar & name color for full-plate friendly NPCs. User-customizable via the
-- inline swatch on "Show Friendly NPC Nameplates"; defaults to the green
-- NPC_COLOR. Only used in full-plate mode -- name-only NPCs use the overlay's
-- reaction color instead.
local function GetFriendlyNPCColor()
    local fp = FP()
    local c = fp and fp.friendlyNPCColor
    if c then return c.r, c.g, c.b end
    return NPC_COLOR_R, NPC_COLOR_G, NPC_COLOR_B
end

-- User-configurable size for the full-plate friendly name text (players AND
-- NPCs in health-bar mode -- not name-only). Defaults to 12.
local function GetFriendlyNameTextSize()
    local fp = FP()
    return (fp and fp.friendlyNameTextSize) or 12
end

-------------------------------------------------------------------------------
--  Friendly name-only font override
--  When name-only mode is active we replace the system nameplate fonts with
--  our own (Expressway) so Blizzard renders friendly names in our style.
--  Original font info is saved once and restored when switching to health-bar
--  mode.
-------------------------------------------------------------------------------
local origNamePlateFont, origNamePlateOutlined
local fontOverrideApplied = false

local function SaveOriginalFonts()
    if origNamePlateFont then return end
    if SystemFont_NamePlate and SystemFont_NamePlate.GetFont then
        local file, height, flags = SystemFont_NamePlate:GetFont()
        origNamePlateFont = { file = file, height = height, flags = flags }
    end
    if SystemFont_NamePlate_Outlined and SystemFont_NamePlate_Outlined.GetFont then
        local file, height, flags = SystemFont_NamePlate_Outlined:GetFont()
        origNamePlateOutlined = { file = file, height = height, flags = flags }
    end
end

-- User-configurable size for friendly name-only player names. The names render
-- through Blizzard's shared SystemFont_NamePlate object (per-instance SetFont is
-- blocked on name-only plates), so this size is applied to the font object.
local function GetFriendlyNameSize()
    local fp = FP()
    return (fp and fp.friendlyNameSize) or 15
end

local function ApplyFriendlyFontOverride()
    SaveOriginalFonts()
    -- Restore to known-good originals first so we read the correct height
    -- even if Blizzard reset the font objects after a CVar change.
    if fontOverrideApplied then
        if origNamePlateFont and SystemFont_NamePlate and SystemFont_NamePlate.SetFont then
            SystemFont_NamePlate:SetFont(origNamePlateFont.file, origNamePlateFont.height, origNamePlateFont.flags or "")
        end
        if origNamePlateOutlined and SystemFont_NamePlate_Outlined and SystemFont_NamePlate_Outlined.SetFont then
            SystemFont_NamePlate_Outlined:SetFont(origNamePlateOutlined.file, origNamePlateOutlined.height, origNamePlateOutlined.flags or "OUTLINE")
        end
        fontOverrideApplied = false
    end
    local font = GetFont()
    local size = GetFriendlyNameSize()
    if SystemFont_NamePlate and SystemFont_NamePlate.SetFont then
        local _, _, flags = SystemFont_NamePlate:GetFont()
        SystemFont_NamePlate:SetFont(font, size, flags or GetNPOutline())
    end
    if SystemFont_NamePlate_Outlined and SystemFont_NamePlate_Outlined.SetFont then
        local _, _, flags = SystemFont_NamePlate_Outlined:GetFont()
        SystemFont_NamePlate_Outlined:SetFont(font, size, flags or GetNPOutline())
    end
    fontOverrideApplied = true
end

local function RestoreFriendlyFontOverride()
    if not fontOverrideApplied then return end
    fontOverrideApplied = false
    if origNamePlateFont and SystemFont_NamePlate and SystemFont_NamePlate.SetFont then
        SystemFont_NamePlate:SetFont(origNamePlateFont.file, origNamePlateFont.height, origNamePlateFont.flags or "")
    end
    if origNamePlateOutlined and SystemFont_NamePlate_Outlined and SystemFont_NamePlate_Outlined.SetFont then
        SystemFont_NamePlate_Outlined:SetFont(origNamePlateOutlined.file, origNamePlateOutlined.height, origNamePlateOutlined.flags or "OUTLINE")
    end
end

-------------------------------------------------------------------------------
--  Per-FontString font override
--  Instead of modifying the global SystemFont_NamePlate objects (which causes
--  sub-pixel shimmer/warping), we hook each nameplate's name FontString and
--  apply our font + pixel snap settings directly on it.  This preserves
--  Blizzard's internal font object rendering properties.
-------------------------------------------------------------------------------
local styledNameTexts = {}  -- nameText → true (tracks which FontStrings we've styled)
local hookedNameFonts = {}  -- nameText → true (permanent hooks, applied once)

local function ApplyFontToNameText(nameText)
    if not nameText or not nameText.SetFont then return end
    local font = GetFont()
    local _, h = nameText:GetFont()
    if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(nameText, GetNPUseShadow()) end
    nameText:SetFont(font, h or 9, GetNPOutline())
    if nameText.SetSnapToPixelGrid then
        nameText:SetSnapToPixelGrid(false)
    end
    if nameText.SetTexelSnappingBias then
        nameText:SetTexelSnappingBias(0)
    end
    styledNameTexts[nameText] = true
end

local function ApplyFontToNameplate(nameplate)
    -- No-op: font is now applied globally via SystemFont_NamePlate override.
end
ns.ApplyFontToNameplate = ApplyFontToNameplate

local function RestoreFontOnNameplate(nameplate)
    if not nameplate then return end
    local uf = nameplate.UnitFrame
    if not uf then return end
    local nameText = uf.name
    if nameText then
        styledNameTexts[nameText] = nil
        -- Blizzard will re-apply its default font on the next SetFontObject call
    end
end

-- Exposed so the options panel can live-apply a new friendly name-only size.
-- Re-running the override re-reads GetFriendlyNameSize and resizes the shared
-- font object; the name FontStrings inherit it on the next render.
function ns.RefreshFriendlyNameSize()
    if IsNameOnlyMode() then
        ApplyFriendlyFontOverride()
    end
end

-- Re-assert the name-only font size after Blizzard touches nameplate fonts.
-- The size lives on the shared SystemFont_NamePlate object, which Blizzard resets
-- to its default during per-plate setup (new plates / camera revealing plates) and
-- on UpdateNamePlateOptions (CVar / display / options changes). Without re-applying,
-- newly shown or re-shown name-only plates revert to the default size. Deferred to
-- the next frame (after Blizzard's setup finishes) and debounced to batch bursts.
-- Touches font objects only -- no CVar writes -- so it can never feed back into
-- UpdateNamePlateOptions.
local _nameSizeReapplyPending = false
local function ScheduleNameSizeReapply()
    if _nameSizeReapplyPending or not IsNameOnlyMode() then return end
    _nameSizeReapplyPending = true
    C_Timer.After(0, function()
        _nameSizeReapplyPending = false
        if IsNameOnlyMode() then ApplyFriendlyFontOverride() end
    end)
end

-- Exposed so the options panel can trigger a refresh after font changes
function ns.RefreshFriendlyFontOverride()
    if IsNameOnlyMode() then
        -- Re-style all currently visible friendly nameplates
        for i, nameplate in ipairs(C_NamePlate.GetNamePlates(true)) do
            local unit = nameplate.namePlateUnitToken
            if unit and not UnitCanAttack("player", unit) and not UnitIsUnit(unit, "player") then
                ApplyFontToNameplate(nameplate)
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Name-only NPC overlay
--  In name-only mode, Blizzard's name FontString is restricted and can't be
--  resized.  Instead of trying to modify it, we fully suppress the Blizzard
--  UnitFrame (reparent to hidden frame) and render our own name FontString
--  on the nameplate.  This gives us full control over width, color, and font.
-------------------------------------------------------------------------------
local npcOverlays = {}        -- nameplate → overlay frame
local npcOverlayPool = {}     -- recycled overlay frames

local function GetNPCNameColor(unit)
    -- UnitReaction: 1-3 = hostile, 4 = neutral, 5+ = friendly
    local reaction = UnitReaction(unit, "player")
    if reaction and reaction == 4 then
        -- Neutral: yellow
        return 0.9, 0.7, 0.0
    end
    -- Friendly NPC: green
    return NPC_COLOR_R, NPC_COLOR_G, NPC_COLOR_B
end

local NPC_TITLE_FONT_SIZE = 10

local function AcquireOverlay()
    local overlay = table.remove(npcOverlayPool)
    if overlay then return overlay end
    overlay = CreateFrame("Frame", nil, UIParent)
    overlay:SetSize(1, 1)
    overlay.name = overlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(overlay.name, 9, "")
    overlay.name:SetPoint("CENTER", overlay, "CENTER", 0, 0)
    -- 12.0.7: shadow is primed by SetFSFont above (FontObject-based); instance shadow removed.
    if overlay.name.SetSnapToPixelGrid then
        overlay.name:SetSnapToPixelGrid(false)
    end
    if overlay.name.SetTexelSnappingBias then
        overlay.name:SetTexelSnappingBias(0)
    end
    -- Title FontString (below name)
    overlay.title = overlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(overlay.title, 9, "")
    overlay.title:SetPoint("TOP", overlay.name, "BOTTOM", 0, -1)
    -- 12.0.7: shadow is primed by SetFSFont above (FontObject-based); instance shadow removed.
    if overlay.title.SetSnapToPixelGrid then
        overlay.title:SetSnapToPixelGrid(false)
    end
    if overlay.title.SetTexelSnappingBias then
        overlay.title:SetTexelSnappingBias(0)
    end
    overlay.title:Hide()
    return overlay
end

local NPC_OVERLAY_FONT_SIZE = 13
local NPC_OVERLAY_Y_OFFSET = 5  -- positive = lower on screen (closer to character)
local NPC_OVERLAY_WIDTH = 126   -- word-wrap width

-- User-configurable size for the friendly NPC name-only overlay name text.
-- Defaults to NPC_OVERLAY_FONT_SIZE.
local function GetNPCOverlayNameSize()
    local fp = FP()
    return (fp and fp.friendlyNPCNameSize) or NPC_OVERLAY_FONT_SIZE
end

local function ShowNPCOverlay(nameplate, unit)
    if npcOverlays[nameplate] then return end
    local overlay = AcquireOverlay()
    overlay:SetParent(nameplate)
    overlay:ClearAllPoints()
    overlay:SetPoint("CENTER", nameplate, "CENTER", 0, -NPC_OVERLAY_Y_OFFSET)
    overlay:SetFrameLevel(nameplate:GetFrameLevel() + 5)
    overlay:Show()
    -- Set name text
    local unitName = UnitName(unit) or ""
    overlay.name:SetText(unitName)
    overlay.name:SetWidth(0)
    overlay.name:SetWordWrap(false)
    overlay.name:SetNonSpaceWrap(false)
    overlay.name:SetMaxLines(1)
    -- Apply our font
    local font = GetFont()
    if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(overlay.name, GetNPUseShadow()) end
    overlay.name:SetFont(font, GetNPCOverlayNameSize(), GetNPOutline())
    if overlay.name.SetSnapToPixelGrid then
        overlay.name:SetSnapToPixelGrid(false)
    end
    if overlay.name.SetTexelSnappingBias then
        overlay.name:SetTexelSnappingBias(0)
    end
    -- Color based on reaction
    local r, g, b = GetNPCNameColor(unit)
    overlay.name:SetTextColor(r, g, b)
    -- NPC title (e.g. "Innkeeper", "Flight Master")
    if ShowNPCTitles() then
        local titleText = GetNPCTitle(unit)
        if titleText then
            local font = GetFont()
            if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(overlay.title, GetNPUseShadow()) end
            overlay.title:SetFont(font, NPC_TITLE_FONT_SIZE, GetNPOutline())
            overlay.title:SetText("<" .. titleText .. ">")
            overlay.title:SetTextColor(r, g, b, 0.7)
            overlay.title:Show()
        else
            overlay.title:Hide()
        end
    else
        overlay.title:Hide()
    end
    overlay.unit = unit
    -- Listen for name updates (server may not have sent the name yet)
    overlay:RegisterUnitEvent("UNIT_NAME_UPDATE", unit)
    overlay:SetScript("OnEvent", function(self, event, ...)
        if event == "UNIT_NAME_UPDATE" then
            local updatedName = UnitName(self.unit) or ""
            self.name:SetText(updatedName)
        end
    end)
    npcOverlays[nameplate] = overlay
end

local function HideNPCOverlay(nameplate)
    local overlay = npcOverlays[nameplate]
    if not overlay then return end
    overlay:UnregisterAllEvents()
    overlay:Hide()
    overlay.title:Hide()
    overlay:SetParent(UIParent)
    overlay:ClearAllPoints()
    overlay.unit = nil
    npcOverlays[nameplate] = nil
    table.insert(npcOverlayPool, overlay)
end

-- Refresh all visible NPC overlays (called when Show NPC Titles is toggled)
local function RefreshAllNPCOverlays()
    -- Snapshot first since Hide/Show modifies npcOverlays
    local snap = {}
    for nameplate, overlay in pairs(npcOverlays) do
        if overlay.unit then
            snap[#snap + 1] = { np = nameplate, unit = overlay.unit }
        end
    end
    for _, entry in ipairs(snap) do
        HideNPCOverlay(entry.np)
        ShowNPCOverlay(entry.np, entry.unit)
    end
end
ns.RefreshAllNPCOverlays = RefreshAllNPCOverlays

-------------------------------------------------------------------------------
--  Hidden frame — Blizzard sub-frames reparented here become invisible
--  and stop receiving layout updates.  This suppresses the default frames.
-------------------------------------------------------------------------------
local hiddenFrame = CreateFrame("Frame")
hiddenFrame:Hide()

-------------------------------------------------------------------------------
--  Blizzard UnitFrame suppression via NamePlateDriverFrame hooks
--  Hook OnNamePlateAdded/Removed on the
--  NamePlateDriverFrame so suppression happens BEFORE any addon event fires.
--  This eliminates the flash of Blizzard nameplates.
-------------------------------------------------------------------------------
local hookedUFs = {}   -- UnitFrame → true  (hooks are permanent, only applied once)
local modifiedUFs = {} -- unit → { uf = UnitFrame, nameplate = nameplate }

local function SuppressBlizzardUF(unit, nameplate)
    if modifiedUFs[unit] then return end  -- already suppressed
    local uf = nameplate and nameplate.UnitFrame
    if not uf then return end

    uf:SetAlpha(0)

    -- Reparent the entire UnitFrame to the hidden frame.
    -- This makes everything invisible. We do NOT unregister events
    -- because we need Blizzard's UF to stay functional for when
    -- we restore it (e.g. toggling back to name-only mode).
    uf:SetParent(hiddenFrame)

    modifiedUFs[unit] = { uf = uf, nameplate = nameplate }

    -- Permanent SetAlpha hook (once per UF instance)
    if not hookedUFs[uf] then
        hookedUFs[uf] = true
        local locked = false
        hooksecurefunc(uf, "SetAlpha", function(self)
            if locked or self:IsForbidden() then return end
            locked = true
            local ufUnit = self.unit or (self.GetUnit and self:GetUnit())
            if ufUnit and modifiedUFs[ufUnit] then
                self:SetAlpha(0)
            end
            locked = false
        end)
    end
end

local function RestoreBlizzardUF(unit)
    local entry = modifiedUFs[unit]
    if not entry then return end
    -- Clear from modifiedUFs FIRST so the SetAlpha hook stops suppressing
    modifiedUFs[unit] = nil
    -- Restore UnitFrame back to its nameplate parent
    local uf = entry.uf
    uf:SetParent(entry.nameplate)
    uf:SetAlpha(1)
    uf:Show()
end

-------------------------------------------------------------------------------
--  Name-only NPC suppression
--  Fully suppress the Blizzard UnitFrame for NPC plates in name-only mode
--  by reparenting it to the hidden frame (same technique as health-bar mode).
--  Then show our own name overlay on top.
-------------------------------------------------------------------------------
local nameOnlyNPCSuppressed = {}  -- nameplate → true

local function SuppressNPCNameplate(nameplate, unit)
    if nameOnlyNPCSuppressed[nameplate] then return end
    nameOnlyNPCSuppressed[nameplate] = true
    -- Always hide Blizzard's default plate (its health bar) for friendly NPCs so
    -- nothing leaks through...
    SuppressBlizzardUF(unit, nameplate)
    -- ...but only draw our name overlay for NPCs Blizzard would actually name
    -- (respects the "NPC Names" filter via IsFriendlyNPCShownForUnit). Filtered
    -- flavor NPCs stay suppressed with no overlay = fully hidden, matching Blizz.
    if IsFriendlyNPCShownForUnit(unit) then
        ShowNPCOverlay(nameplate, unit)
    end
end

local function RestoreNPCNameplate(nameplate, unit)
    if not nameOnlyNPCSuppressed[nameplate] then return end
    nameOnlyNPCSuppressed[nameplate] = nil
    -- Hide our overlay
    HideNPCOverlay(nameplate)
    -- Restore Blizzard UF
    if unit then
        RestoreBlizzardUF(unit)
    end
end

-------------------------------------------------------------------------------
--  NamePlateDriverFrame hooks — suppress Blizzard UFs at the earliest moment
--  These fire synchronously inside Blizzard's nameplate creation, BEFORE
--  NAME_PLATE_UNIT_ADDED reaches any addon event handler.
-------------------------------------------------------------------------------
hooksecurefunc(NamePlateDriverFrame, "OnNamePlateAdded", function(_, unit)
    if not unit or unit == "preview" then return end
    if UnitCanAttack("player", unit) then return end
    if UnitIsUnit(unit, "player") then return end

    -- Re-assert the name-only font size for this newly added / camera-revealed
    -- plate -- Blizzard's per-plate setup resets the shared font object to default.
    -- No-op outside name-only mode.
    ScheduleNameSizeReapply()

    -- Health-bar mode: full UF suppression for players (and NPCs if enabled)
    if IsFriendlyEnabled() then
        -- Suppress Blizzard's default plate for players and ALL enabled friendly
        -- NPCs. The custom plate itself is gated per-NPC in TryAddFriendlyPlate, so
        -- filtered NPCs end up suppressed with no plate = hidden.
        if not UnitIsPlayer(unit) and not IsFriendlyNPCEnabled() then return end
        local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
        if nameplate then
            SuppressBlizzardUF(unit, nameplate)
        end
        return
    end

    -- Name-only mode: suppress Blizzard UF and show our own name overlay for NPCs
    if IsNameOnlyMode() and not UnitIsPlayer(unit) and IsFriendlyNPCEnabled() then
        local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
        if nameplate then
            SuppressNPCNameplate(nameplate, unit)
        end
    end

    -- Name-only mode (players): remove Blizzard's width constraint on the
    -- name FontString so long names are never truncated with "...".
    if IsNameOnlyMode() and UnitIsPlayer(unit) then
        local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
        if nameplate and nameplate.UnitFrame and nameplate.UnitFrame.name then
            local nameFS = nameplate.UnitFrame.name
            nameFS:SetWidth(0)
            -- Hook SetWidth so Blizzard can't re-apply a constraint later
            if not hookedNameFonts[nameFS] then
                hookedNameFonts[nameFS] = true
                local guard = false
                hooksecurefunc(nameFS, "SetWidth", function(self, w)
                    if guard then return end
                    if w and w > 0 and IsNameOnlyMode() then
                        guard = true
                        self:SetWidth(0)
                        guard = false
                    end
                end)
            end
        end
    end
end)

hooksecurefunc(NamePlateDriverFrame, "OnNamePlateRemoved", function(_, unit)
    -- Guard: Blizzard settings panel can fire this with "preview" which is not a valid unit
    if not unit or not unit:find("^nameplate") then return end
    -- Clean up NPC overlay if present
    local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
    if nameplate then
        HideNPCOverlay(nameplate)
        nameOnlyNPCSuppressed[nameplate] = nil
    end
    if modifiedUFs[unit] then
        RestoreBlizzardUF(unit)
    end
end)

-------------------------------------------------------------------------------
--  Frame pool for custom friendly plates
-------------------------------------------------------------------------------
local friendlyFrameCache = CreateFramePool("Frame", UIParent, nil, nil, false, function(plate)
    plate:SetFlattensRenderLayers(true)

    plate.health = CreateFrame("StatusBar", nil, plate)
    plate.health:SetFrameLevel(10)
    plate.health:SetPoint("CENTER", 0, FRIENDLY_PLATE_Y_OFFSET)
    plate.health:SetSize(GetFriendlyHealthBarWidth(), GetFriendlyHealthBarHeight())
    plate.health:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")

    plate.healthBG = plate.health:CreateTexture(nil, "BACKGROUND")
    plate.healthBG:SetAllPoints()
    plate.healthBG:SetColorTexture(0.12, 0.12, 0.12, 1.0)

    -- Border: pixel-perfect PP.CreateBorder mirroring the enemy nameplate
    -- border exactly. Reads the same enemy border settings (showBorder,
    -- borderSize, borderColor) so friendly plates always match whatever
    -- border the user has configured for enemy plates. Lives on a child
    -- container at health level + 1 so it renders above the mouseover
    -- highlight (OVERLAY sublevel 6) and the health fill.
    local PP = EllesmereUI and EllesmereUI.PP
    if PP and PP.CreateBorder then
        local cr, cg, cb = ns.GetBorderColor()
        local sz = (FP() and FP().borderSize) or ns.defaults.borderSize
        PP.CreateBorder(plate.health, cr, cg, cb, 1, sz, "OVERLAY", 7)
        if not ns.IsBorderEnabled() then PP.HideBorder(plate.health) end
    end

    function plate:ApplyBorder()
        if not PP then return end
        if ns.IsCustomBorderEnabled() then
            -- Custom border mirrors the enemy custom-border settings 1:1.
            PP.HideBorder(plate.health)
            ns.ApplyCustomBorderStyle(plate)
        else
            ns.HideCustomBorder(plate)
            if ns.IsBorderEnabled() then
                local sz = (FP() and FP().borderSize) or ns.defaults.borderSize
                PP.SetBorderSize(plate.health, sz)
                PP.ShowBorder(plate.health)
            else
                PP.HideBorder(plate.health)
            end
        end
    end
    function plate:ApplyBorderColor()
        if not PP then return end
        if ns.IsCustomBorderEnabled() then
            ns.ApplyCustomBorderColor(plate)
        else
            local cr, cg, cb = ns.GetBorderColor()
            PP.SetBorderColor(plate.health, cr, cg, cb, 1)
        end
    end

    local GLOW_TEX = "Interface\\AddOns\\EllesmereUINameplates\\Media\\background.png"
    local GLOW_MARGIN = 0.48
    local GLOW_CORNER = 12
    local GLOW_EXTEND = 6
    plate.glowFrame = CreateFrame("Frame", nil, plate)
    plate.glowFrame:SetFrameStrata("BACKGROUND")
    plate.glowFrame:SetFrameLevel(1)
    plate.glowFrame:SetPoint("TOPLEFT", plate.health, "TOPLEFT", -GLOW_EXTEND, GLOW_EXTEND)
    plate.glowFrame:SetPoint("BOTTOMRIGHT", plate.health, "BOTTOMRIGHT", GLOW_EXTEND, -GLOW_EXTEND)

    local function CreateGlowTex()
        local t = plate.glowFrame:CreateTexture(nil, "BACKGROUND")
        t:SetTexture(GLOW_TEX)
        t:SetVertexColor(0.4117, 0.6667, 1.0, 1.0)
        t:SetBlendMode("ADD")
        return t
    end

    plate.glowTL = CreateGlowTex()
    plate.glowTL:SetSize(GLOW_CORNER, GLOW_CORNER)
    plate.glowTL:SetPoint("TOPLEFT")
    plate.glowTL:SetTexCoord(0, GLOW_MARGIN, 0, GLOW_MARGIN)
    plate.glowTR = CreateGlowTex()
    plate.glowTR:SetSize(GLOW_CORNER, GLOW_CORNER)
    plate.glowTR:SetPoint("TOPRIGHT")
    plate.glowTR:SetTexCoord(1 - GLOW_MARGIN, 1, 0, GLOW_MARGIN)
    plate.glowBL = CreateGlowTex()
    plate.glowBL:SetSize(GLOW_CORNER, GLOW_CORNER)
    plate.glowBL:SetPoint("BOTTOMLEFT")
    plate.glowBL:SetTexCoord(0, GLOW_MARGIN, 1 - GLOW_MARGIN, 1)
    plate.glowBR = CreateGlowTex()
    plate.glowBR:SetSize(GLOW_CORNER, GLOW_CORNER)
    plate.glowBR:SetPoint("BOTTOMRIGHT")
    plate.glowBR:SetTexCoord(1 - GLOW_MARGIN, 1, 1 - GLOW_MARGIN, 1)
    plate.glowTop = CreateGlowTex()
    plate.glowTop:SetHeight(GLOW_CORNER)
    plate.glowTop:SetPoint("TOPLEFT", plate.glowTL, "TOPRIGHT")
    plate.glowTop:SetPoint("TOPRIGHT", plate.glowTR, "TOPLEFT")
    plate.glowTop:SetTexCoord(GLOW_MARGIN, 1 - GLOW_MARGIN, 0, GLOW_MARGIN)
    plate.glowBottom = CreateGlowTex()
    plate.glowBottom:SetHeight(GLOW_CORNER)
    plate.glowBottom:SetPoint("BOTTOMLEFT", plate.glowBL, "BOTTOMRIGHT")
    plate.glowBottom:SetPoint("BOTTOMRIGHT", plate.glowBR, "BOTTOMLEFT")
    plate.glowBottom:SetTexCoord(GLOW_MARGIN, 1 - GLOW_MARGIN, 1 - GLOW_MARGIN, 1)
    plate.glowLeft = CreateGlowTex()
    plate.glowLeft:SetWidth(GLOW_CORNER)
    plate.glowLeft:SetPoint("TOPLEFT", plate.glowTL, "BOTTOMLEFT")
    plate.glowLeft:SetPoint("BOTTOMLEFT", plate.glowBL, "TOPLEFT")
    plate.glowLeft:SetTexCoord(0, GLOW_MARGIN, GLOW_MARGIN, 1 - GLOW_MARGIN)
    plate.glowRight = CreateGlowTex()
    plate.glowRight:SetWidth(GLOW_CORNER)
    plate.glowRight:SetPoint("TOPRIGHT", plate.glowTR, "BOTTOMRIGHT")
    plate.glowRight:SetPoint("BOTTOMRIGHT", plate.glowBR, "TOPRIGHT")
    plate.glowRight:SetTexCoord(1 - GLOW_MARGIN, 1, GLOW_MARGIN, 1 - GLOW_MARGIN)
    plate.glow = plate.glowFrame
    plate.glowFrame:Hide()

    plate.hpText = plate.health:CreateFontString(nil, "OVERLAY")
    -- Forced crisp outline; SetFSFont applies the global "Never Show Slug" gate.
    SetFSFont(plate.hpText, 10, "OUTLINE, SLUG")
    plate.hpText:SetPoint("RIGHT", plate.health, -2, 0)

    plate.highlight = plate.health:CreateTexture(nil, "OVERLAY", nil, 6)
    plate.highlight:SetAllPoints()
    local _hc = (FP() and FP().hoverColor) or ns.defaults.hoverColor
    local _ha = (FP() and FP().hoverAlpha) or ns.defaults.hoverAlpha
    plate.highlight:SetColorTexture(_hc.r, _hc.g, _hc.b, _ha)
    plate.highlight:Hide()

    plate.name = plate:CreateFontString(nil, "OVERLAY")
    SetFSFont(plate.name, GetFriendlyNameTextSize(), "OUTLINE, SLUG")
    plate.name:SetPoint("BOTTOM", plate.health, "TOP", 0, 4)
    plate.name:SetWordWrap(false)
    plate.name:SetMaxLines(1)

    local _aSt = ns.ResolveTargetArrowStyle(FP())
    plate.leftArrow = plate:CreateTexture(nil, "OVERLAY")
    plate.leftArrow:SetTexture(ns.TARGET_ARROW_DIR .. _aSt.l .. ".png")
    plate.leftArrow:SetSize(_aSt.w, 16)
    plate.leftArrow:SetPoint("RIGHT", plate.name, "LEFT", -2, 0)
    plate.leftArrow:Hide()
    plate.rightArrow = plate:CreateTexture(nil, "OVERLAY")
    plate.rightArrow:SetTexture(ns.TARGET_ARROW_DIR .. _aSt.r .. ".png")
    plate.rightArrow:SetSize(_aSt.w, 16)
    plate.rightArrow:SetPoint("LEFT", plate.name, "RIGHT", 2, 0)
    plate.rightArrow:Hide()

    plate.raidFrame = CreateFrame("Frame", nil, plate)
    plate.raidFrame:SetSize(24, 24)
    plate.raidFrame:SetPoint("BOTTOMRIGHT", plate.health, "TOPRIGHT", 2, 2)
    plate.raidFrame:Hide()
    plate.raid = plate.raidFrame:CreateTexture(nil, "ARTWORK")
    plate.raid:SetPoint("TOPLEFT", 1, -1)
    plate.raid:SetPoint("BOTTOMRIGHT", -1, 1)
    plate.raid:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    plate.raid:SetTexCoord(0, 1, 0, 1)

    if CreateUnitHealPredictionCalculator then
        plate.hpCalculator = CreateUnitHealPredictionCalculator()
        if plate.hpCalculator.SetMaximumHealthMode then
            plate.hpCalculator:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.Default)
        end
    end

    plate:SetScript("OnEvent", function(self, event, ...)
        local handler = self[event]
        if handler then handler(self, ...) end
    end)
end)

-------------------------------------------------------------------------------
--  FriendlyFrame mixin
-------------------------------------------------------------------------------
local FriendlyFrame = {}

function FriendlyFrame:SetUnit(unit, nameplate)
    self.unit = unit
    self.nameplate = nameplate
    self:SetParent(nameplate)
    self:ClearAllPoints()
    -- Single center anchor to prevent pixel shimmer when nameplate bounces
    local yOff = (FP() and FP().friendlyPlateYOffset) or 0
    self:SetPoint("CENTER", nameplate, "CENTER", 0, yOff)
    self:SetSize(1, 1)
    self:SetFrameLevel(nameplate:GetFrameLevel() + 1)
    self:Show()

    self.health:SetSize(GetFriendlyHealthBarWidth(), GetFriendlyHealthBarHeight())

    -- Suppress Blizzard UF via reparenting (immediate, no OnUpdate needed)
    SuppressBlizzardUF(unit, nameplate)

    self:RegisterUnitEvent("UNIT_HEALTH", unit)
    self:RegisterUnitEvent("UNIT_NAME_UPDATE", unit)

    local _fp = FP()
    local useClassColor = not _fp or _fp.classColorFriendly ~= false
    local classColor
    if UnitIsPlayer(unit) then
        if useClassColor then
            local _, classToken = UnitClass(unit)
            if classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken] then
                classColor = RAID_CLASS_COLORS[classToken]
            end
        else
            local bc = (_fp and _fp.friendlyBarColor) or ns.defaults.friendlyBarColor
            classColor = bc
        end
    end
    if classColor then
        self.health:SetStatusBarColor(classColor.r, classColor.g, classColor.b)
        self.name:SetTextColor(1, 1, 1)
    else
        local nr, ng, nb = GetFriendlyNPCColor()
        self.health:SetStatusBarColor(nr, ng, nb)
        self.name:SetTextColor(nr, ng, nb)
    end

    self:UpdateHealth()
    self:UpdateName()
    self:UpdateRaidIcon()
    self:ApplyTarget()
    -- Re-apply the enemy border settings every spawn: a pooled plate may have
    -- been released while the user changed the border size/color/toggle.
    if self.ApplyBorder then self:ApplyBorder() end
    if self.ApplyBorderColor then self:ApplyBorderColor() end
    if ns.ApplyHealthBarTexture then ns.ApplyHealthBarTexture(self) end
end

function FriendlyFrame:ClearUnit()
    self:UnregisterAllEvents()
    self.name:SetText("")
    -- Restore Blizzard UF before clearing our reference
    if self.unit then RestoreBlizzardUF(self.unit) end
    self.unit = nil
    self.nameplate = nil
    self.glow:Hide()
    if ns.HideHoverEffect then ns.HideHoverEffect(self) else self.highlight:Hide() end
    self.raidFrame:Hide()
    self.leftArrow:Hide()
    self.rightArrow:Hide()
    self:Hide()
    self:SetParent(UIParent)
    self:ClearAllPoints()
end

function FriendlyFrame:UpdateHealth()
    local unit = self.unit
    if not unit then return end
    if self.hpCalculator and self.hpCalculator.GetMaximumHealth then
        UnitGetDetailedHealPrediction(unit, nil, self.hpCalculator)
        self.hpCalculator:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.Default)
        local maxHP = self.hpCalculator:GetMaximumHealth()
        self.health:SetMinMaxValues(0, maxHP)
        self.health:SetValue(self.hpCalculator:GetCurrentHealth())
    else
        self.health:SetMinMaxValues(0, UnitHealthMax(unit))
        self.health:SetValue(UnitHealth(unit))
    end
    if UnitIsDeadOrGhost(unit) then
        self.hpText:SetText("0%")
    elseif UnitHealthPercent then
        local fp = FP()
        if fp and fp.friendlyHideHealthText then
            self.hpText:SetText("")
        else
            self.hpText:SetFormattedText("%d%%", UnitHealthPercent(unit, true, CurveConstants.ScaleTo100))
        end
    else
        self.hpText:SetText("")
    end
end

function FriendlyFrame:UpdateName()
    local unit = self.unit
    if not unit then return end
    local unitName = UnitName(unit)
    self.name:SetText(unitName or "")
end

function FriendlyFrame:UpdateRaidIcon()
    if not self.unit then return end
    local pos = ns.GetRaidMarkerPos()
    if pos == "none" then self.raidFrame:Hide(); return end
    local idx = GetRaidTargetIndex and GetRaidTargetIndex(self.unit)
    if not idx then self.raidFrame:Hide(); return end
    SetRaidTargetIconTexture(self.raid, idx)
    local sz = ns.GetRaidMarkerSize()
    local rmY = ns.GetRaidMarkerYOffset()
    self.raidFrame:SetSize(sz, sz)
    self.raidFrame:ClearAllPoints()
    if pos == "top" then
        self.raidFrame:SetPoint("BOTTOM", self.health, "TOP", 0, ns.GetDebuffYOffset())
    elseif pos == "left" then
        self.raidFrame:SetPoint("RIGHT", self.health, "LEFT", -ns.GetSideAuraXOffset(), 0)
    elseif pos == "right" then
        self.raidFrame:SetPoint("LEFT", self.health, "RIGHT", ns.GetSideAuraXOffset(), 0)
    elseif pos == "topleft" then
        -- Flush with the nameplate's left edge (PP borders inset -> bar corner is
        -- the outer edge; offset 0 = flush). Matches the enemy plate convention.
        self.raidFrame:SetPoint("BOTTOMLEFT", self.health, "TOPLEFT", 0, rmY)
    elseif pos == "topright" then
        self.raidFrame:SetPoint("BOTTOMRIGHT", self.health, "TOPRIGHT", 0, rmY)
    end
    self.raidFrame:Show()
end

function FriendlyFrame:ApplyTarget()
    if not self.unit then return end
    local isTarget = UnitIsUnit(self.unit, "target")
    self.glow:SetShown(isTarget)
    local fp = FP()
    local showArrows = isTarget and fp and fp.showTargetArrows
    if showArrows then
        local st = ns.ResolveTargetArrowStyle(fp)
        self.leftArrow:SetTexture(ns.TARGET_ARROW_DIR .. st.l .. ".png")
        self.rightArrow:SetTexture(ns.TARGET_ARROW_DIR .. st.r .. ".png")
        local acr, acg, acb = ns.GetTargetArrowColor(fp)
        self.leftArrow:SetVertexColor(acr, acg, acb)
        self.rightArrow:SetVertexColor(acr, acg, acb)
        self.leftArrow:SetSize(st.w, 16)
        self.rightArrow:SetSize(st.w, 16)
    end
    self.leftArrow:SetShown(showArrows or false)
    self.rightArrow:SetShown(showArrows or false)
end

function FriendlyFrame:UNIT_HEALTH()  self:UpdateHealth() end
function FriendlyFrame:UNIT_NAME_UPDATE()  self:UpdateName() end

-------------------------------------------------------------------------------
--  Friendly event manager (target, mouseover, raid icons)
--  Only registered when friendly plates are active -- zero CPU when disabled.
-------------------------------------------------------------------------------
local friendlyManager = CreateFrame("Frame")
local friendlyManagerRegistered = false

local RegisterFriendlyManager   -- forward declaration
local UnregisterFriendlyManager -- forward declaration

-------------------------------------------------------------------------------
--  Add / Remove helpers
-------------------------------------------------------------------------------
local function ClearAllFriendlyPlates()
    for unit, plate in pairs(friendlyPlates) do
        plate:ClearUnit()
        friendlyFrameCache:Release(plate)
        friendlyPlates[unit] = nil
    end
end

local function TryAddFriendlyPlate(unit)
    -- Auto-enable on first call if DB says we should be active but the
    -- runtime flag hasn't been set yet (happens when NAME_PLATE_UNIT_ADDED
    -- fires before PLAYER_LOGIN).
    if not friendlyEnabled then
        if IsFriendlyEnabled() then
            friendlyEnabled = true
            RegisterFriendlyManager()
        else
            return
        end
    end
    if UnitCanAttack("player", unit) then return end
    if UnitIsUnit(unit, "player") then return end
    -- Skip non-player units unless friendly NPC plates are enabled (and the unit
    -- isn't filtered out by Blizzard's "NPC Names" setting).
    if not UnitIsPlayer(unit) and not IsFriendlyNPCShownForUnit(unit) then return end
    local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
    if not nameplate then return end
    if friendlyPlates[unit] then return end

    local plate = friendlyFrameCache:Acquire()
    if not plate._mixedIn then
        Mixin(plate, FriendlyFrame)
        plate._mixedIn = true
    end
    friendlyPlates[unit] = plate
    plate:SetUnit(unit, nameplate)
end
ns.TryAddFriendlyPlate = TryAddFriendlyPlate

function ns.RemoveFriendlyPlate(unit)
    local plate = friendlyPlates[unit]
    if not plate then return end
    if ns._ClearMouseoverPlate then ns._ClearMouseoverPlate(plate) end
    if _cachedFriendlyTargetPlate == plate then _cachedFriendlyTargetPlate = nil end
    plate:ClearUnit()
    friendlyFrameCache:Release(plate)
    friendlyPlates[unit] = nil
end

-- Same as RemoveFriendlyPlate but does NOT restore the Blizzard UF.
-- Used when promoting friendly -> enemy so the Blizzard UF stays suppressed
-- until HideBlizzardFrame takes over in the enemy plate's SetUnit.
function ns.RemoveFriendlyPlateNoRestore(unit)
    local plate = friendlyPlates[unit]
    if not plate then return end
    if ns._ClearMouseoverPlate then ns._ClearMouseoverPlate(plate) end
    if _cachedFriendlyTargetPlate == plate then _cachedFriendlyTargetPlate = nil end
    -- Clean up our plate without restoring Blizzard UF
    plate:UnregisterAllEvents()
    plate.name:SetText("")
    -- Clear modifiedUFs entry so the friendly SetAlpha hook stops interfering
    modifiedUFs[unit] = nil
    plate.unit = nil
    plate.nameplate = nil
    plate.glow:Hide()
    if ns.HideHoverEffect then ns.HideHoverEffect(plate) else plate.highlight:Hide() end
    plate.raidFrame:Hide()
    plate.leftArrow:Hide()
    plate.rightArrow:Hide()
    plate:Hide()
    plate:SetParent(UIParent)
    plate:ClearAllPoints()
    friendlyFrameCache:Release(plate)
    friendlyPlates[unit] = nil
end

-------------------------------------------------------------------------------
--  Friendly event manager function definitions
-------------------------------------------------------------------------------
function RegisterFriendlyManager()
    if friendlyManagerRegistered then return end
    friendlyManager:RegisterEvent("PLAYER_TARGET_CHANGED")
    friendlyManager:RegisterEvent("RAID_TARGET_UPDATE")
    friendlyManagerRegistered = true
end

function UnregisterFriendlyManager()
    if not friendlyManagerRegistered then return end
    friendlyManager:UnregisterAllEvents()
    friendlyManagerRegistered = false
end

friendlyManager:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_TARGET_CHANGED" then
        -- PERF: only update old + new target instead of iterating all
        local oldTarget = _cachedFriendlyTargetPlate
        _cachedFriendlyTargetPlate = nil
        for _, plate in pairs(friendlyPlates) do
            if plate.unit and UnitIsUnit(plate.unit, "target") then
                _cachedFriendlyTargetPlate = plate
                break
            end
        end
        if oldTarget and oldTarget.unit then oldTarget:ApplyTarget() end
        if _cachedFriendlyTargetPlate and _cachedFriendlyTargetPlate ~= oldTarget then
            _cachedFriendlyTargetPlate:ApplyTarget()
        end
    elseif event == "RAID_TARGET_UPDATE" then
        for _, plate in pairs(friendlyPlates) do plate:UpdateRaidIcon() end
    end
end)

-------------------------------------------------------------------------------
--  Live refresh of friendly plate Y offset
-------------------------------------------------------------------------------
function ns.RefreshFriendlyPlateYOffset()
    local yOff = (FP() and FP().friendlyPlateYOffset) or 0
    for _, plate in pairs(friendlyPlates) do
        if plate.nameplate then
            plate:ClearAllPoints()
            plate:SetPoint("CENTER", plate.nameplate, "CENTER", 0, yOff)
        end
    end
end

-------------------------------------------------------------------------------
--  Live refresh of friendly plate size (height / width)
-------------------------------------------------------------------------------
function ns.RefreshFriendlyPlateSize()
    local h = GetFriendlyHealthBarHeight()
    local w = GetFriendlyHealthBarWidth()
    for _, plate in pairs(friendlyPlates) do
        plate.health:SetSize(w, h)
    end
end

function ns.RefreshFriendlyHealthText()
    for _, plate in pairs(friendlyPlates) do
        plate:UpdateHealth()
    end
end

function ns.RefreshFriendlyColors()
    local _fp = FP()
    local useClassColor = not _fp or _fp.classColorFriendly ~= false
    local bc = (_fp and _fp.friendlyBarColor) or ns.defaults.friendlyBarColor
    local nr, ng, nb = GetFriendlyNPCColor()
    for unit, plate in pairs(friendlyPlates) do
        if UnitIsPlayer(unit) then
            if useClassColor then
                local _, classToken = UnitClass(unit)
                if classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken] then
                    local cc = RAID_CLASS_COLORS[classToken]
                    plate.health:SetStatusBarColor(cc.r, cc.g, cc.b)
                end
            else
                plate.health:SetStatusBarColor(bc.r, bc.g, bc.b)
            end
        else
            plate.health:SetStatusBarColor(nr, ng, nb)
            plate.name:SetTextColor(nr, ng, nb)
        end
    end
end

-- Re-apply the full-plate friendly name text size to all live plates so the
-- slider updates without a /reload. The name carries an explicit outline flag.
function ns.RefreshFriendlyNameTextSize()
    local size = GetFriendlyNameTextSize()
    for _, plate in pairs(friendlyPlates) do
        if plate.name then SetFSFont(plate.name, size, "OUTLINE, SLUG") end
    end
end

-------------------------------------------------------------------------------
--  Friendly nameplate click-through
--  Make friendly nameplates (players AND NPCs) non-clickable so their names
--  never intercept mouse input or cause accidental friendly targeting. We do
--  NOT resize the plate (which would distort visuals) -- instead we shrink the
--  click hit-test rectangle to nothing via a large positive inset on every
--  edge. An inset of 0 restores the natural (fully clickable) hit rect.
--  The hit-test API is protected in combat, so we gate on InCombatLockdown and
--  retry once on combat end. The retry listener is only registered while a
--  change is actually pending, so this costs nothing when idle.
-------------------------------------------------------------------------------
local CLICK_THROUGH_INSET = 10000
local clickThroughApplied = false
local clickThroughRetry = CreateFrame("Frame")

local function ApplyFriendlyClickThrough()
    if not (C_NamePlateManager and C_NamePlateManager.SetNamePlateHitTestInsets
            and Enum and Enum.NamePlateType) then
        return
    end
    local fp = FP()
    local on = fp and fp.friendlyClickThrough == true
    -- Never applied and feature is off: leave Blizzard's hit rect untouched.
    if not on and not clickThroughApplied then return end
    if InCombatLockdown() then
        clickThroughRetry:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    clickThroughRetry:UnregisterEvent("PLAYER_REGEN_ENABLED")
    local inset = on and CLICK_THROUGH_INSET or 0
    C_NamePlateManager.SetNamePlateHitTestInsets(Enum.NamePlateType.Friendly, inset, inset, inset, inset)
    clickThroughApplied = on
end
ns.UpdateFriendlyClickThrough = ApplyFriendlyClickThrough

clickThroughRetry:SetScript("OnEvent", function() ApplyFriendlyClickThrough() end)

-------------------------------------------------------------------------------
--  System enable / disable  (called from toggle setValue and on login)
-------------------------------------------------------------------------------
function ns.UpdateFriendlyNameplateSystem()
    local shouldEnable = IsFriendlyEnabled()       -- health-bar mode
    local nameOnly     = IsNameOnlyMode()           -- name-only mode

    -- In follower dungeons, force-hide friendly nameplates via CVars.
    -- In instances (dungeons/raids/scenarios/arenas/PvP), force-hide
    -- friendly NPC nameplates because GetNamePlateForUnit returns nil
    -- for protected frames and our suppression can't run.
    -- SetCVar for nameplate CVars is protected in combat; skip to avoid taint.
    -- Friendly player CVars are only touched when the user has EUI managing
    -- friendly player nameplates. When disabled we leave those CVars alone
    -- so Blizzard's own Nameplate settings own them. Friendly NPC CVars are
    -- always managed because they have their own EUI toggle.
    if not InCombatLockdown() and SetCVar then
        local fp = FP()
        local euiManagesPlayers = fp and (fp.showFriendlyPlayers ~= false)
        local _, iType = GetInstanceInfo()
        local inInstance = (iType == "party" or iType == "raid" or iType == "scenario" or iType == "arena" or iType == "pvp")
        if IsInFollowerDungeon() then
            if euiManagesPlayers then
                pcall(SetCVar, "nameplateShowFriendlyPlayers", 0)
                pcall(SetCVar, "nameplateShowFriends", 0)
            end
            pcall(SetCVar, "nameplateShowFriendlyNPCs", 0)
            pcall(SetCVar, "nameplateShowFriendlyNpcs", 0)
        elseif inInstance then
            -- NPC plates only: force off in instances since our frame
            -- suppression doesn't work on protected nameplate frames.
            -- Player CVars are unaffected.
            pcall(SetCVar, "nameplateShowFriendlyNPCs", 0)
            pcall(SetCVar, "nameplateShowFriendlyNpcs", 0)
        else
            -- Restore user's preferred friendly CVar state
            if fp then
                local showNPCs = (fp.showFriendlyNPCs == true)
                if euiManagesPlayers then
                    local nameOnlyVal = (fp.friendlyNameOnly ~= false) and 1 or 0
                    pcall(SetCVar, "nameplateShowFriendlyPlayers", 1)
                    pcall(SetCVar, "nameplateShowFriends", 1)
                    pcall(SetCVar, "nameplateShowOnlyNameForFriendlyPlayerUnits", nameOnlyVal)
                end
                pcall(SetCVar, "nameplateShowFriendlyNPCs", showNPCs and 1 or 0)
                pcall(SetCVar, "nameplateShowFriendlyNpcs", showNPCs and 1 or 0)
            end
        end
    end

    if shouldEnable and not friendlyEnabled then
        -- Switching TO health-bar mode
        RestoreFriendlyFontOverride()               -- undo any font override
        -- Clean up any name-only NPC overlays
        for np in pairs(nameOnlyNPCSuppressed) do
            local u = np.namePlateUnitToken
            RestoreNPCNameplate(np, u)
        end
        friendlyEnabled = true
        RegisterFriendlyManager()
        -- Pick up any nameplates already visible.
        local units = {}
        if ns.pendingUnits then
            for unit, _ in pairs(ns.pendingUnits) do
                units[unit] = true
            end
        end
        local allPlates = C_NamePlate.GetNamePlates()
        if allPlates then
            for _, nameplate in ipairs(allPlates) do
                local unit = nameplate.namePlateUnitToken
                if unit then units[unit] = true end
            end
        end
        for unit, _ in pairs(units) do
            TryAddFriendlyPlate(unit)
        end
    elseif shouldEnable and friendlyEnabled then
        -- Already in health-bar mode — re-sweep to pick up NPC plates that
        -- may have been skipped (e.g. user just toggled showFriendlyNPCs on)
        local allPlates = C_NamePlate.GetNamePlates()
        if allPlates then
            for _, nameplate in ipairs(allPlates) do
                local unit = nameplate.namePlateUnitToken
                if unit then TryAddFriendlyPlate(unit) end
            end
        end
    elseif not shouldEnable and friendlyEnabled then
        -- Switching FROM health-bar mode
        friendlyEnabled = false
        UnregisterFriendlyManager()
        ClearAllFriendlyPlates()
        -- Clean up any leftover NPC overlays from name-only mode
        for np in pairs(nameOnlyNPCSuppressed) do
            local u = np.namePlateUnitToken
            RestoreNPCNameplate(np, u)
        end
    end

    -- Name-only font override: apply when name-only AND friendly plates are shown
    local _fp = FP()
    local showFriendly = _fp and _fp.showFriendlyPlayers ~= false
    if nameOnly and showFriendly then
        ApplyFriendlyFontOverride()
        -- (nameplate sizing handled by Blizzard in name-only mode)
        -- Set class-color CVar for Blizzard's name-only rendering
        if SetCVar and not InCombatLockdown() then
            local cc = (_fp and _fp.classColorFriendly ~= false) and 1 or 0
            pcall(SetCVar, "nameplateUseClassColorForFriendlyPlayerUnitNames", cc)
        end
        -- Sweep NPC plates: suppress health bars and color names green. Gated
        -- per-unit so Blizzard's "NPC Names" filter is respected -- widgets-only
        -- NPCs are left to Blizzard instead of getting our overlay.
        local function SweepNPCPlates()
            local allPlates = C_NamePlate.GetNamePlates()
            if allPlates then
                for _, nameplate in ipairs(allPlates) do
                    local u = nameplate.namePlateUnitToken
                    if u and not UnitCanAttack("player", u) and not UnitIsUnit(u, "player") and not UnitIsPlayer(u) then
                        if IsFriendlyNPCEnabled() then
                            SuppressNPCNameplate(nameplate, u)
                        else
                            RestoreNPCNameplate(nameplate, u)
                        end
                    end
                end
            end
        end
        SweepNPCPlates()
        -- Delayed sweep: Blizzard creates NPC plates asynchronously after
        -- the CVar changes, so sweep again after a short delay.
        C_Timer.After(0.1, SweepNPCPlates)
        C_Timer.After(0.5, SweepNPCPlates)
    elseif not shouldEnable then
        -- Not in health-bar mode — restore fonts (covers disabled + name-only-off)
        RestoreFriendlyFontOverride()
    end

    -- Apply friendly click-through (independent of player/NPC plate mode).
    ApplyFriendlyClickThrough()
end

-------------------------------------------------------------------------------
--  Bootstrap — wait for DB then enable system
--  PLAYER_LOGIN enables the system; PLAYER_ENTERING_WORLD does a follow-up
--  sweep because some friendly nameplates may not be queryable yet at
--  PLAYER_LOGIN time (the world isn't fully loaded).
-- Re-sweep after NamePlateDriverFrame.UpdateNamePlateOptions fires.
-- TRP3 hooks this and calls UpdateAllNamePlates which can reset our
-- suppression on friendly plates. Debounced to batch multiple calls.
if C_AddOns.IsAddOnLoaded("totalRP3") or C_AddOns.DoesAddOnExist("totalRP3") then
    local _npOptsPending = false
    hooksecurefunc(NamePlateDriverFrame, "UpdateNamePlateOptions", function()
        if _npOptsPending then return end
        _npOptsPending = true
        C_Timer.After(0, function()
            _npOptsPending = false
            ns.UpdateFriendlyNameplateSystem()
        end)
    end)
end

-- Blizzard re-applies the default nameplate font whenever UpdateNamePlateOptions
-- fires (CVar / display / nameplate-options changes), wiping our name-only size.
-- Re-assert it for everyone (the TRP3 branch above only runs when TRP3 is loaded).
-- Font objects only -- safe, debounced, no CVar feedback.
if NamePlateDriverFrame and NamePlateDriverFrame.UpdateNamePlateOptions then
    hooksecurefunc(NamePlateDriverFrame, "UpdateNamePlateOptions", function()
        ScheduleNameSizeReapply()
    end)
end

-------------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
initFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        ns.UpdateFriendlyNameplateSystem()
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        -- Re-evaluate the friendly system on every zone transition so
        -- follower dungeons (and similar) correctly disable/enable it.
        ns.UpdateFriendlyNameplateSystem()
        -- Delayed re-check: instance/follower dungeon state may not be
        -- available yet when PLAYER_ENTERING_WORLD first fires on zone-in.
        C_Timer.After(1, function()
            ns.UpdateFriendlyNameplateSystem()
        end)
        -- Sweep every zone transition / reload to pick up any plates that
        -- were missed during the initial enable or that appeared between
        -- PLAYER_LOGIN and the world being fully rendered.
        C_Timer.After(0, function()
            if friendlyEnabled then
                local allPlates = C_NamePlate.GetNamePlates()
                if allPlates then
                    for _, nameplate in ipairs(allPlates) do
                        local u = nameplate.namePlateUnitToken
                        if u then TryAddFriendlyPlate(u) end
                    end
                end
            end
            -- Name-only NPC sweep: suppress health bars and color names. Per-unit
            -- gate respects Blizzard's "NPC Names" filter (skip widgets-only NPCs).
            if IsNameOnlyMode() and IsFriendlyNPCEnabled() then
                local allPlates = C_NamePlate.GetNamePlates()
                if allPlates then
                    for _, nameplate in ipairs(allPlates) do
                        local u = nameplate.namePlateUnitToken
                        if u and not UnitCanAttack("player", u) and not UnitIsUnit(u, "player") and not UnitIsPlayer(u) then
                            SuppressNPCNameplate(nameplate, u)
                        end
                    end
                end
            end
        end)
    end
end)

-------------------------------------------------------------------------------
--  Exported API — called from EllesmereNameplates.lua (NAME_PLATE_UNIT_ADDED/REMOVED)
--  These wrap the new overlay system so the main file doesn't need to change.
-------------------------------------------------------------------------------
function ns.TryColorFriendlyNPCName(unit, nameplate)
    -- In name-only mode, NPC overlay handles coloring automatically
    -- (SuppressNPCNameplate is called from OnNamePlateAdded hook)
end

function ns.TrySuppressNPCHealthBar(unit, nameplate)
    -- In name-only mode, NPC overlay fully suppresses the Blizzard UF
    -- (SuppressNPCNameplate is called from OnNamePlateAdded hook)
end

function ns.RestoreFriendlyNPCNameColor(nameplate)
    local unit = nameplate and nameplate.namePlateUnitToken
    if unit and not UnitIsPlayer(unit) then
        RestoreNPCNameplate(nameplate, unit)
    end
end

function ns.RestoreNPCHealthBar(nameplate)
    local unit = nameplate and nameplate.namePlateUnitToken
    if unit and not UnitIsPlayer(unit) then
        RestoreNPCNameplate(nameplate, unit)
    end
end
