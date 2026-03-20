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

local FRIENDLY_BAR_W = 150
local FRIENDLY_PLATE_Y_OFFSET = -18

local function IsFriendlyEnabled()
    local fp = FP()
    return fp and (fp.friendlyNameOnly == false)
end

local function IsNameOnlyMode()
    local fp = FP()
    return not fp or (fp.friendlyNameOnly ~= false)
end

local function IsFriendlyNPCEnabled()
    local fp = FP()
    return fp and (fp.showFriendlyNPCs == true)
end

-- Friendly NPC color: #00ff00
local NPC_COLOR_R, NPC_COLOR_G, NPC_COLOR_B = 0, 1, 0

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

local function ApplyFriendlyFontOverride()
    SaveOriginalFonts()
    local font = GetFont()
    if SystemFont_NamePlate and SystemFont_NamePlate.SetFont then
        local _, h, flags = SystemFont_NamePlate:GetFont()
        SystemFont_NamePlate:SetFont(font, h or 9, flags or GetNPOutline())
    end
    if SystemFont_NamePlate_Outlined and SystemFont_NamePlate_Outlined.SetFont then
        local _, h, flags = SystemFont_NamePlate_Outlined:GetFont()
        SystemFont_NamePlate_Outlined:SetFont(font, h or 9, flags or GetNPOutline())
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
    nameText:SetFont(font, h or 9, GetNPOutline())
    if GetNPUseShadow() then
        nameText:SetShadowOffset(1, -1)
        nameText:SetShadowColor(0, 0, 0, 1)
    end
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

local function AcquireOverlay()
    local overlay = table.remove(npcOverlayPool)
    if overlay then return overlay end
    overlay = CreateFrame("Frame", nil, UIParent)
    overlay:SetSize(1, 1)
    overlay.name = overlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(overlay.name, 9, "")
    overlay.name:SetPoint("CENTER", overlay, "CENTER", 0, 0)
    overlay.name:SetShadowOffset(1, -1)
    overlay.name:SetShadowColor(0, 0, 0, 1)
    if overlay.name.SetSnapToPixelGrid then
        overlay.name:SetSnapToPixelGrid(false)
    end
    if overlay.name.SetTexelSnappingBias then
        overlay.name:SetTexelSnappingBias(0)
    end
    return overlay
end

local NPC_OVERLAY_FONT_SIZE = 13
local NPC_OVERLAY_Y_OFFSET = 5  -- positive = lower on screen (closer to character)
local NPC_OVERLAY_WIDTH = 126   -- word-wrap width

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
    overlay.name:SetWidth(NPC_OVERLAY_WIDTH)
    overlay.name:SetWordWrap(true)
    overlay.name:SetNonSpaceWrap(false)
    overlay.name:SetMaxLines(0)
    -- Apply our font
    local font = GetFont()
    overlay.name:SetFont(font, NPC_OVERLAY_FONT_SIZE, GetNPOutline())
    if GetNPUseShadow() then
        overlay.name:SetShadowOffset(1, -1)
        overlay.name:SetShadowColor(0, 0, 0, 1)
    end
    if overlay.name.SetSnapToPixelGrid then
        overlay.name:SetSnapToPixelGrid(false)
    end
    if overlay.name.SetTexelSnappingBias then
        overlay.name:SetTexelSnappingBias(0)
    end
    -- Color based on reaction
    local r, g, b = GetNPCNameColor(unit)
    overlay.name:SetTextColor(r, g, b)
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
    overlay:SetParent(UIParent)
    overlay:ClearAllPoints()
    overlay.unit = nil
    npcOverlays[nameplate] = nil
    table.insert(npcOverlayPool, overlay)
end

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
    -- Fully suppress the Blizzard UF
    SuppressBlizzardUF(unit, nameplate)
    -- Show our custom name overlay
    ShowNPCOverlay(nameplate, unit)
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

    -- Health-bar mode: full UF suppression for players (and NPCs if enabled)
    if IsFriendlyEnabled() then
        if not UnitIsPlayer(unit) and not IsFriendlyNPCEnabled() then return end
        local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
        if nameplate then
            SuppressBlizzardUF(unit, nameplate)
        end
        return
    end

    -- Name-only mode: suppress Blizzard UF and show our own name overlay for NPCs
    if IsNameOnlyMode() and IsFriendlyNPCEnabled() and not UnitIsPlayer(unit) then
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

    local BORDER_TEX = "Interface\\AddOns\\EllesmereUINameplates\\Media\\border.png"
    local BORDER_CORNER = 6
    plate.borderFrame = CreateFrame("Frame", nil, plate.health)
    plate.borderFrame:SetFrameLevel(plate.health:GetFrameLevel() + 5)
    plate.borderFrame:SetAllPoints()

    local function CreateBorderTex()
        local PP = EllesmereUI and EllesmereUI.PP
        local t = plate.borderFrame:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetTexture(BORDER_TEX)
        return t
    end

    plate.borderTL = CreateBorderTex()
    plate.borderTL:SetSize(BORDER_CORNER, BORDER_CORNER)
    plate.borderTL:SetPoint("TOPLEFT", plate.borderFrame, "TOPLEFT", 0, 0)
    plate.borderTL:SetTexCoord(0, 0.5, 0, 0.5)
    plate.borderTR = CreateBorderTex()
    plate.borderTR:SetSize(BORDER_CORNER, BORDER_CORNER)
    plate.borderTR:SetPoint("TOPRIGHT", plate.borderFrame, "TOPRIGHT", 0, 0)
    plate.borderTR:SetTexCoord(0.5, 1, 0, 0.5)
    plate.borderBL = CreateBorderTex()
    plate.borderBL:SetSize(BORDER_CORNER, BORDER_CORNER)
    plate.borderBL:SetPoint("BOTTOMLEFT", plate.borderFrame, "BOTTOMLEFT", 0, 0)
    plate.borderBL:SetTexCoord(0, 0.5, 0.5, 1)
    plate.borderBR = CreateBorderTex()
    plate.borderBR:SetSize(BORDER_CORNER, BORDER_CORNER)
    plate.borderBR:SetPoint("BOTTOMRIGHT", plate.borderFrame, "BOTTOMRIGHT", 0, 0)
    plate.borderBR:SetTexCoord(0.5, 1, 0.5, 1)
    plate.borderTop = CreateBorderTex()
    plate.borderTop:SetHeight(BORDER_CORNER)
    plate.borderTop:SetPoint("TOPLEFT", plate.borderTL, "TOPRIGHT", 0, 0)
    plate.borderTop:SetPoint("TOPRIGHT", plate.borderTR, "TOPLEFT", 0, 0)
    plate.borderTop:SetTexCoord(0.5, 0.5, 0, 0.5)
    plate.borderBottom = CreateBorderTex()
    plate.borderBottom:SetHeight(BORDER_CORNER)
    plate.borderBottom:SetPoint("BOTTOMLEFT", plate.borderBL, "BOTTOMRIGHT", 0, 0)
    plate.borderBottom:SetPoint("BOTTOMRIGHT", plate.borderBR, "BOTTOMLEFT", 0, 0)
    plate.borderBottom:SetTexCoord(0.5, 0.5, 0.5, 1)
    plate.borderLeft = CreateBorderTex()
    plate.borderLeft:SetWidth(BORDER_CORNER)
    plate.borderLeft:SetPoint("TOPLEFT", plate.borderTL, "BOTTOMLEFT", 0, 0)
    plate.borderLeft:SetPoint("BOTTOMLEFT", plate.borderBL, "TOPLEFT", 0, 0)
    plate.borderLeft:SetTexCoord(0, 0.5, 0.5, 0.5)
    plate.borderRight = CreateBorderTex()
    plate.borderRight:SetWidth(BORDER_CORNER)
    plate.borderRight:SetPoint("TOPRIGHT", plate.borderTR, "BOTTOMRIGHT", 0, 0)
    plate.borderRight:SetPoint("BOTTOMRIGHT", plate.borderBR, "TOPRIGHT", 0, 0)
    plate.borderRight:SetTexCoord(0.5, 1, 0.5, 0.5)

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
    SetFSFont(plate.hpText, 10, "OUTLINE")
    plate.hpText:SetPoint("RIGHT", plate.health, -2, 0)

    plate.highlight = plate.health:CreateTexture(nil, "OVERLAY", nil, 6)
    plate.highlight:SetAllPoints()
    plate.highlight:SetColorTexture(1, 1, 1, 0.3)
    plate.highlight:Hide()

    plate.name = plate:CreateFontString(nil, "OVERLAY")
    SetFSFont(plate.name, 12, "OUTLINE")
    plate.name:SetPoint("BOTTOM", plate.health, "TOP", 0, 4)
    plate.name:SetWordWrap(false)
    plate.name:SetMaxLines(1)

    plate.leftArrow = plate:CreateTexture(nil, "OVERLAY")
    plate.leftArrow:SetTexture("Interface\\AddOns\\EllesmereUINameplates\\Media\\arrow_left.png")
    plate.leftArrow:SetSize(11, 16)
    plate.leftArrow:SetPoint("RIGHT", plate.name, "LEFT", -2, 0)
    plate.leftArrow:Hide()
    plate.rightArrow = plate:CreateTexture(nil, "OVERLAY")
    plate.rightArrow:SetTexture("Interface\\AddOns\\EllesmereUINameplates\\Media\\arrow_right.png")
    plate.rightArrow:SetSize(11, 16)
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

    local classColor
    if UnitIsPlayer(unit) then
        local _, classToken = UnitClass(unit)
        if classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken] then
            classColor = RAID_CLASS_COLORS[classToken]
        end
    end
    if classColor then
        self.health:SetStatusBarColor(classColor.r, classColor.g, classColor.b)
        self.name:SetTextColor(1, 1, 1)
    else
        -- Friendly NPC: #00ff00
        self.health:SetStatusBarColor(NPC_COLOR_R, NPC_COLOR_G, NPC_COLOR_B)
        self.name:SetTextColor(NPC_COLOR_R, NPC_COLOR_G, NPC_COLOR_B)
    end

    self:UpdateHealth()
    self:UpdateName()
    self:UpdateRaidIcon()
    self:ApplyTarget()
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
    self.highlight:Hide()
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
        self.raidFrame:SetPoint("BOTTOMLEFT", self.health, "TOPLEFT", -2, rmY)
    elseif pos == "topright" then
        self.raidFrame:SetPoint("BOTTOMRIGHT", self.health, "TOPRIGHT", 2, rmY)
    end
    self.raidFrame:Show()
end

function FriendlyFrame:ApplyTarget()
    if not self.unit then return end
    local isTarget = UnitIsUnit(self.unit, "target")
    self.glow:SetShown(isTarget)
    local showArrows = isTarget and FP() and FP().showTargetArrows
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
local friendlyMouseoverPlate = nil

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
    -- Skip non-player units unless friendly NPC plates are enabled
    if not UnitIsPlayer(unit) and not IsFriendlyNPCEnabled() then return end
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
    if friendlyMouseoverPlate == plate then
        friendlyMouseoverPlate = nil
    end
    plate:ClearUnit()
    friendlyFrameCache:Release(plate)
    friendlyPlates[unit] = nil
end

-- Same as RemoveFriendlyPlate but does NOT restore the Blizzard UF.
-- Used when promoting friendly → enemy so the Blizzard UF stays suppressed
-- until HideBlizzardFrame takes over in the enemy plate's SetUnit.
function ns.RemoveFriendlyPlateNoRestore(unit)
    local plate = friendlyPlates[unit]
    if not plate then return end
    if friendlyMouseoverPlate == plate then
        friendlyMouseoverPlate = nil
    end
    -- Clean up our plate without restoring Blizzard UF
    plate:UnregisterAllEvents()
    plate.name:SetText("")
    -- Clear modifiedUFs entry so the friendly SetAlpha hook stops interfering
    modifiedUFs[unit] = nil
    plate.unit = nil
    plate.nameplate = nil
    plate.glow:Hide()
    plate.highlight:Hide()
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
    friendlyManager:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
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
        for _, plate in pairs(friendlyPlates) do plate:ApplyTarget() end
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        if friendlyMouseoverPlate then
            friendlyMouseoverPlate.highlight:Hide()
            friendlyMouseoverPlate = nil
        end
        if UnitExists("mouseover") then
            for _, plate in pairs(friendlyPlates) do
                if plate.unit and UnitIsUnit(plate.unit, "mouseover") then
                    plate.highlight:Show()
                    friendlyMouseoverPlate = plate
                    break
                end
            end
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

-------------------------------------------------------------------------------
--  System enable / disable  (called from toggle setValue and on login)
-------------------------------------------------------------------------------
function ns.UpdateFriendlyNameplateSystem()
    local shouldEnable = IsFriendlyEnabled()       -- health-bar mode
    local nameOnly     = IsNameOnlyMode()           -- name-only mode

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
        if SetCVar then
            local cc = (_fp and _fp.classColorFriendly ~= false) and 1 or 0
            pcall(SetCVar, "nameplateUseClassColorForFriendlyPlayerUnitNames", cc)
        end
        -- Sweep NPC plates: suppress health bars and color names green
        local npcEnabled = IsFriendlyNPCEnabled()
        local function SweepNPCPlates()
            local allPlates = C_NamePlate.GetNamePlates()
            if allPlates then
                for _, nameplate in ipairs(allPlates) do
                    local u = nameplate.namePlateUnitToken
                    if u and not UnitCanAttack("player", u) and not UnitIsUnit(u, "player") and not UnitIsPlayer(u) then
                        if npcEnabled then
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
end

-------------------------------------------------------------------------------
--  Bootstrap — wait for DB then enable system
--  PLAYER_LOGIN enables the system; PLAYER_ENTERING_WORLD does a follow-up
--  sweep because some friendly nameplates may not be queryable yet at
--  PLAYER_LOGIN time (the world isn't fully loaded).
-------------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        ns.UpdateFriendlyNameplateSystem()
    elseif event == "PLAYER_ENTERING_WORLD" then
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
            -- Name-only NPC sweep: suppress health bars and color names
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
