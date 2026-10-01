if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- EUI_ResourceBars_CallTotemBar.lua
-- WoW FOREVER ONLY: Call Totem Bar. Blizzard's call totem bar
-- (MultiCastActionBarFrame: the Call of the Elements button, the four element
-- slots with their totem buttons, Totemic Recall) in the Totem Bar look, placed
-- by Unlock Mode instead of Edit Mode.
--
-- The bar stays Blizzard's: its own code fills, shows and hides it, and its
-- totem and spell buttons are secure. While the feature is on it is OURS in
-- four ways, all applied out of combat (a combat request waits for regen):
--   position  pinned to our holder (the unlock element) with the Edit Mode
--             system's saved base SetPoint / ClearAllPoints / SetScale, which
--             never flag Edit Mode's anchor pass; a layout apply's re-anchor
--             (ApplySystemAnchor) is answered by re-pinning
--   overlay   its Edit Mode selection at alpha 0 with no mouse, so Edit Mode
--             cannot select or drag it
--   layout    scale from Icon Size, and the shown buttons laid out in a row
--             or column with the chosen spacing (each totem button sits on
--             its element slot); re-run after every Blizzard bar update, which
--             re-anchors the first slot and Totemic Recall
--   look      Blizzard's frame, ring and slot art faded, icons unmasked and
--             cropped square, our border frame on each button, the cooldown
--             numbers shown or hidden and sized by Show Timer / Timer Size
-- On a secure button it changes texture alpha, masks and texcoords, the
-- cooldown's countdown numbers and font, and (out of combat) its anchor;
-- nothing is written onto a Blizzard frame (every saved value lives in the
-- weak tables here). Off hands every piece back.
-- Off by default: nothing is hooked or changed until it is first turned on.
-- Shamans only: no other class has call totem spells.
-- Limits: a combat /reload or an in-combat bar update (a flyout page switch)
-- can leave the first slot, Totemic Recall and the bar where Blizzard puts
-- them until combat ends (most visible in a column). If the bar is snapped to
-- another system in Edit Mode, resetting, reverting or hiding that system
-- re-pins the bar here, but Edit Mode records the bar's current spot as its
-- own, so saving the layout then keeps it for when this is turned off.

local _, ns = ...
local EllesmereUI = _G.EllesmereUI
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
local bar = _G.MultiCastActionBarFrame
if not bar then return end
local _, playerClass = UnitClass("player")
if playerClass ~= "SHAMAN" then return end

local UNLOCK_KEY = "ERB_CallTotemBar"
local BTN = 30          -- the bar's button size, in its own units
local MAX_BUTTONS = 6   -- Call of the Elements, four slots, Totemic Recall
local ZOOM = 0.08
local FONT_NAME = "ERB_CallTotemCountdownFont"

local SUMMON = _G.MultiCastSummonSpellButton
local RECALL = _G.MultiCastRecallSpellButton
local SLOT, ACT = {}, {}
for i = 1, 4 do SLOT[i] = _G["MultiCastSlotButton" .. i] end
for i = 1, 12 do ACT[i] = _G["MultiCastActionButton" .. i] end

local holder              -- our frame: the unlock element the bar is pinned to
local owned = false       -- the bar is anchored, laid out and skinned by us
local hooked = false
local home                -- the bar's own scale, size and strata before we took it
local order = {}          -- scratch: the shown buttons in layout order
local savedAlpha = setmetatable({}, { __mode = "k" })   -- faded texture -> its alpha
local unmasked = setmetatable({}, { __mode = "k" })     -- icon -> the mask we removed
local borders = setmetatable({}, { __mode = "k" })      -- button -> our border frame
local homeFont = setmetatable({}, { __mode = "k" })     -- cooldown -> its countdown font object's name (false: none)

-- Countdown numbers: a named font object the cooldowns render with.
local cdFont = CreateFont(FONT_NAME)
cdFont:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")

-------------------------------------------------------------------------------
--  Settings access
-------------------------------------------------------------------------------

local function P()
    local ERB = ns.ERB
    local db = ERB and ERB.db
    local p = db and db.profile
    return p and p.callTotemBar or nil
end

local function Blocked()
    return InCombatLockdown()
end

local function Queue(key, fn)
    ns.CombatQueue.Defer(key, fn)
end

-------------------------------------------------------------------------------
--  Look
-------------------------------------------------------------------------------

local function Fade(tex)
    if not tex then return end
    if savedAlpha[tex] == nil then
        local a = tex:GetAlpha()
        if issecretvalue(a) then a = 1 end
        savedAlpha[tex] = a
    end
    tex:SetAlpha(0)
end

local function Unfade(tex)
    local a = tex and savedAlpha[tex]
    if a == nil then return end
    tex:SetAlpha(a)
    savedAlpha[tex] = nil
end

-- The art a button carries in Blizzard's look: the icon frame, its slot art,
-- the element ring (overlayTex) and, on the two spell buttons, their ring
-- highlight. Region names follow the templates.
local function ArtOf(btn, fn)
    fn(btn:GetNormalTexture())
    fn(btn.SlotArt)
    fn(btn.SlotBackground)
    fn(btn.overlayTex)
    local name = btn:GetName()
    if name and (btn == SUMMON or btn == RECALL) then fn(_G[name .. "Highlight"]) end
end

local function SkinButton(btn, c)
    ArtOf(btn, Fade)
    local icon = btn.icon
    if icon then
        -- A masked texture rejects SetTexCoord: the mask goes first.
        local mask = btn.IconMask
        if mask and not unmasked[icon] then
            if pcall(icon.RemoveMaskTexture, icon, mask) then unmasked[icon] = mask end
        end
        pcall(icon.SetTexCoord, icon, ZOOM, 1 - ZOOM, ZOOM, 1 - ZOOM)
    end
    local cd = btn.cooldown
    if cd then
        cd:SetHideCountdownNumbers(not c.showTimer)
        if c.showTimer and cd.SetCountdownFont then
            if homeFont[cd] == nil then
                local fs = cd.GetCountdownFontString and cd:GetCountdownFontString()
                local obj = fs and fs:GetFontObject()
                homeFont[cd] = (obj and obj:GetName()) or false
            end
            cd:SetCountdownFont(FONT_NAME)
        end
    end
    -- Our border frame, in the button's own scale like the active bar's.
    local o = borders[btn]
    if not o then
        o = CreateFrame("Frame", nil, btn)
        o:SetAllPoints(btn)
        borders[btn] = o
    end
    o:SetFrameLevel(c.borderBehind and math.max(0, btn:GetFrameLevel() - 1) or (btn:GetFrameLevel() + 3))
    o:Show()
    local bs = c.borderSize or 0
    local texKey = c.borderTexture or "solid"
    EllesmereUI.ApplyBorderStyle(o, bs,
        c.borderR or 0, c.borderG or 0, c.borderB or 0, c.borderA or 1,
        texKey, c.borderTextureOffset, c.borderTextureOffsetY,
        c.borderTextureShiftX, c.borderTextureShiftY, "resourcebars", bs,
        nil, EllesmereUI.BorderPx(c.borderSizePx, bs, texKey))
end

-- hideNumbers: the stock countdown state (the totem buttons follow Blizzard's
-- Show Numbers for Cooldowns setting; the two spell buttons always show them).
local function UnskinButton(btn, hideNumbers)
    ArtOf(btn, Unfade)
    local icon = btn.icon
    if icon then
        local mask = unmasked[icon]
        if mask then
            pcall(icon.AddMaskTexture, icon, mask)
            unmasked[icon] = nil
        end
        pcall(icon.SetTexCoord, icon, 0, 1, 0, 1)
    end
    local cd = btn.cooldown
    if cd then
        cd:SetHideCountdownNumbers(hideNumbers)
        local fontName = homeFont[cd]
        if fontName and cd.SetCountdownFont then cd:SetCountdownFont(fontName) end
    end
    local o = borders[btn]
    if o then o:Hide() end
end

local function SkinAll(c)
    local scale = (c.iconSize or 30) / BTN
    local size = math.max(6, math.floor((c.timerSize or 11) / scale + 0.5))
    cdFont:SetFont(ns.GetRBFont(), size, EllesmereUI.GetFontOutlineFlag("resourceBars"))
    if SUMMON then SkinButton(SUMMON, c) end
    if RECALL then SkinButton(RECALL, c) end
    for i = 1, #ACT do SkinButton(ACT[i], c) end
    for i = 1, 4 do Fade(SLOT[i].overlayTex) end
end

local function UnskinAll()
    if SUMMON then UnskinButton(SUMMON, false) end
    if RECALL then UnskinButton(RECALL, false) end
    local hideNumbers = not GetCVarBool("countdownForCooldowns")
    for i = 1, #ACT do UnskinButton(ACT[i], hideNumbers) end
    for i = 1, 4 do Unfade(SLOT[i].overlayTex) end
end

-------------------------------------------------------------------------------
--  Position and layout (out of combat only)
-------------------------------------------------------------------------------

local function HolderSize(c)
    local iconSize = (c and c.iconSize) or 30
    local spacing = (c and c.spacing) or 2
    local len = iconSize * MAX_BUTTONS + spacing * (MAX_BUTTONS - 1)
    if c and c.orientation == "VERTICAL" then return iconSize, len end
    return len, iconSize
end

-- Pin the bar's top-left corner to the holder's, through the system's base
-- methods (Blizzard's SetPoint / ClearAllPoints overrides flag Edit Mode).
local function PinBar()
    local clear = bar.ClearAllPointsBase or bar.ClearAllPoints
    local setPt = bar.SetPointBase or bar.SetPoint
    clear(bar)
    setPt(bar, "TOPLEFT", holder, "TOPLEFT", 0, 0)
end

-- The shown buttons in a row (left to right) or a column (top to bottom), each
-- totem button on its element slot. Blizzard's updates re-anchor the first
-- slot by its BOTTOMLEFT and Totemic Recall by its LEFT, so those two points
-- are the ones used here: an update that lands before our pass moves them, it
-- never pulls them between two anchors.
local function Layout(c)
    local iconSize = c.iconSize or 30
    local scale = iconSize / BTN
    local spacing = c.spacing or 2
    local PP = EllesmereUI.PP
    if PP and PP.Snap then spacing = PP.Snap(spacing) end
    local gap = spacing / scale
    local vertical = c.orientation == "VERTICAL"

    wipe(order)
    if SUMMON and SUMMON:IsShown() then order[#order + 1] = SUMMON end
    local n = bar.numActiveSlots or 0
    if issecretvalue(n) then n = 0 end
    for i = 1, n do order[#order + 1] = SLOT[i] end
    if RECALL and RECALL:IsShown() then order[#order + 1] = RECALL end
    local count = #order
    local len = count > 0 and (count * BTN + (count - 1) * gap) or BTN

    for i = 1, count do
        local b = order[i]
        local off = (i - 1) * (BTN + gap)
        local x = vertical and 0 or off
        local y = vertical and (len - BTN - off) or 0
        b:ClearAllPoints()
        if b == RECALL then
            b:SetPoint("LEFT", bar, "BOTTOMLEFT", x, y + BTN / 2)
        else
            b:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x, y)
        end
    end
    for i = 1, #ACT do
        local b = ACT[i]
        b:ClearAllPoints()
        b:SetPoint("CENTER", SLOT[((i - 1) % 4) + 1], "CENTER", 0, 0)
    end

    if vertical then bar:SetSize(BTN, len) else bar:SetSize(len, BTN) end
    local setScale = bar.SetScaleBase or bar.SetScale
    setScale(bar, scale)
    bar:SetFrameStrata(c.frameStrata or "MEDIUM")
    PinBar()
end

-- Blizzard's own anchors (the template's, and its update rules for the first
-- slot and Totemic Recall), for the hand-back.
local function RestoreLayout()
    if SUMMON then
        SUMMON:ClearAllPoints()
        SUMMON:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 3, 3)
    end
    local x = (SUMMON and SUMMON:IsShown()) and (SUMMON:GetWidth() + 8 + 3) or 3
    SLOT[1]:ClearAllPoints()
    SLOT[1]:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x, 3)
    for i = 2, 4 do
        SLOT[i]:ClearAllPoints()
        SLOT[i]:SetPoint("LEFT", SLOT[i - 1], "RIGHT", 8, 0)
    end
    for i = 1, #ACT do
        local b = ACT[i]
        b:ClearAllPoints()
        if (i - 1) % 4 == 0 then
            b:SetPoint("LEFT", _G["MultiCastActionPage" .. (math.floor((i - 1) / 4) + 1)], "LEFT", 0, 0)
        else
            b:SetPoint("LEFT", ACT[i - 1], "RIGHT", 8, 0)
        end
    end
    if RECALL then
        local n = bar.numActiveSlots or 0
        if issecretvalue(n) then n = 0 end
        RECALL:ClearAllPoints()
        RECALL:SetPoint("LEFT", n > 0 and SLOT[n] or ACT[4], "RIGHT", 8, 0)
    end
end

-- The holder's spot: another element's anchor, the saved Unlock Mode spot, or
-- the default (where Blizzard's own default puts the bar's right edge).
local function PlaceHolder(c)
    -- Unlock Mode owns a placed holder while it is open.
    if EllesmereUI._unlockActive and holder:GetNumPoints() > 0 then return end
    local pos = c.unlockPos
    if pos and pos.point then
        if EllesmereUI.IsUnlockAnchored(UNLOCK_KEY) and holder:GetLeft() then return end
        local sx, sy = ns.SnapXY(pos.x or 0, pos.y or 0, holder, pos)
        holder:ClearAllPoints()
        holder:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, sx, sy)
    elseif not EllesmereUI.IsUnlockAnchored(UNLOCK_KEY) then
        holder:ClearAllPoints()
        holder:SetPoint("RIGHT", UIParent, "BOTTOM", -28, 128)
    end
end

-------------------------------------------------------------------------------
--  Ownership
-------------------------------------------------------------------------------

local Refresh

-- Blizzard's layout apply re-anchors the system; a bar update re-anchors the
-- first slot and Totemic Recall and re-sets the art. Both are answered while
-- the bar is ours (in combat, at regen).
local function OnSystemAnchor()
    if not owned then return end
    if Blocked() then Queue("CTRefresh", Refresh); return end
    PinBar()
end

local function OnBarUpdate()
    if not owned then return end
    if Blocked() then Queue("CTRefresh", Refresh); return end
    Refresh()
end

-- Blizzard hangs its flyout arrow above the hovered slot or Call of the
-- Elements button; in a column that covers the button above (a click there
-- opens the flyout), so a vertical bar gets it beside the button instead. The
-- arrow is not secure, so this holds in combat too. Blizzard adds its point on
-- every show without clearing, so each show is cleared and re-set here, and
-- put back above the button once the bar is no longer a column.
local arrowMoved = false
local function OnFlyoutArrow(arrow, _, parent)
    if not (arrow and parent) or arrow:GetParent() ~= parent then return end
    local c = owned and P()
    local side = (c and c.orientation == "VERTICAL") or false
    if not (side or arrowMoved) then return end
    arrowMoved = side
    arrow:ClearAllPoints()
    if side then
        arrow:SetPoint("LEFT", parent, "RIGHT", 0, 0)
    else
        arrow:SetPoint("BOTTOM", parent, "TOP", 0, 0)
    end
end

local function Hook()
    if hooked then return end
    hooked = true
    hooksecurefunc(bar, "ApplySystemAnchor", OnSystemAnchor)
    -- A snap break (Edit Mode resetting, reverting or hiding the system the bar
    -- was snapped to) re-anchors the bar to UIParent: re-pin it the same way.
    if bar.BreakFrameSnap then hooksecurefunc(bar, "BreakFrameSnap", OnSystemAnchor) end
    hooksecurefunc("MultiCastActionBarFrame_Update", OnBarUpdate)
    if _G.MultiCastFlyoutFrameOpenButton_Show then
        hooksecurefunc("MultiCastFlyoutFrameOpenButton_Show", OnFlyoutArrow)
    end
end

-- Edit Mode never resets the selection's alpha or mouse, so one write holds.
local selMouse
local function SuppressSelection()
    local sel = bar.Selection
    if not sel then return end
    Fade(sel)
    if selMouse == nil then selMouse = sel:IsMouseEnabled() end
    sel:EnableMouse(false)
end

local function ReleaseSelection()
    local sel = bar.Selection
    if not sel then return end
    Unfade(sel)
    if selMouse ~= nil then sel:EnableMouse(selMouse) end
end

Refresh = function()
    local c = P()
    if not (owned and c) then return end
    Layout(c)
    SkinAll(c)
end

local function Release()
    if not owned then return end
    if Blocked() then Queue("CTApply", ns.CT_Apply); return end
    owned = false
    UnskinAll()
    RestoreLayout()
    ReleaseSelection()
    local setScale = bar.SetScaleBase or bar.SetScale
    setScale(bar, home.scale)
    bar:SetSize(home.w, home.h)
    bar:SetFrameStrata(home.strata)
    -- Back to the Edit Mode layout's spot (read from the system's own record).
    local info = bar.systemInfo
    local ai = info and info.anchorInfo
    local clear = bar.ClearAllPointsBase or bar.ClearAllPoints
    local setPt = bar.SetPointBase or bar.SetPoint
    if ai then
        local s = bar:GetScale()
        clear(bar)
        setPt(bar, ai.point, ai.relativeTo, ai.relativePoint, ai.offsetX / s, ai.offsetY / s)
        local ai2 = info.anchorInfo2
        if ai2 then setPt(bar, ai2.point, ai2.relativeTo, ai2.relativePoint, ai2.offsetX / s, ai2.offsetY / s) end
    else
        clear(bar)
        setPt(bar, "RIGHT", UIParent, "BOTTOM", -28, 128)
    end
end

function ns.CT_Apply()
    local c = P()
    if not (c and c.enabled) then
        Release()
        -- In combat Release waits for regen with the bar still pinned to the
        -- holder (which that makes protected); its queued pass hides it then.
        if holder and not owned then holder:Hide() end
        return
    end
    if Blocked() then Queue("CTApply", ns.CT_Apply); return end
    if not holder then
        holder = CreateFrame("Frame", "ERB_CallTotemBarFrame", UIParent)
        holder:SetFrameLevel(15)
        -- Re-register so unlock mode picks up the new frame
        if _G._ERB_RegisterUnlock then _G._ERB_RegisterUnlock() end
    end
    holder:SetSize(HolderSize(c))
    holder:Show()
    PlaceHolder(c)
    Hook()
    if not owned then
        if not home then
            local w, h = bar:GetSize()
            home = { scale = bar:GetScale(), w = w, h = h, strata = bar:GetFrameStrata() }
        end
        owned = true
        SuppressSelection()
    end
    Refresh()
end

-------------------------------------------------------------------------------
--  Unlock element
-------------------------------------------------------------------------------

function ns.CT_MakeUnlockElement(MK)
    if not MK then return nil end
    local function save(key, point, relPoint, x, y)
        if not point then return end
        local c = P(); if not c then return end
        c.unlockPos = { point = point, relPoint = relPoint or point, x = x, y = y }
        if not EllesmereUI._unlockActive and holder then
            holder:ClearAllPoints()
            holder:SetPoint(point, UIParent, relPoint or point, x, y)
        end
    end
    local function load()
        local c = P()
        local pos = c and c.unlockPos
        if not pos then return nil end
        return { point = pos.point, relPoint = pos.relPoint or pos.point, x = pos.x, y = pos.y }
    end
    local function clear()
        local c = P(); if not c then return end
        c.unlockPos = nil
    end
    local function apply()
        local c = P()
        local pos = c and c.unlockPos
        if not (pos and holder) then return end
        local sx, sy = ns.SnapXY(pos.x, pos.y, holder, pos)
        holder:ClearAllPoints()
        holder:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, sx, sy)
    end
    return MK({
        key = UNLOCK_KEY, label = "Call Totem Bar", group = "Resource Bars", order = 509,
        noResize = true,
        noAnchorTarget = true,
        isHidden = function() local c = P(); return not (c and c.enabled) end,
        getFrame = function() return holder end,
        getSize  = function() return HolderSize(P()) end,
        savePos = save, loadPos = load, clearPos = clear, applyPos = apply,
    })
end
