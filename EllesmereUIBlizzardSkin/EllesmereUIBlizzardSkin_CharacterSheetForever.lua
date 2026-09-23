if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  Character Sheet on WoW Forever
--
--  The retail character sheet gets the full makeover
--  (EllesmereUIBlizzardSkin_CharacterSheet.lua); that file stands down on the
--  Forever client and this one gives the sheet the ordinary window-skin
--  treatment instead, on Blizzard's own Forever frame:
--    - the standard window shell (dark backdrop, border, top bar) and the
--      house close button, through the same engine calls every skinned
--      Blizzard window uses;
--    - every piece of frame art stripped: the pane backdrops and stone
--      header, the item slot frames, the class icon and its ring, the level
--      text plate, the right-pane collapse arrow;
--    - the retail sheet's model backdrop behind the character, cover-cropped
--      to the model area, and the retail sidebar's darker panel behind the
--      stats (its left edge is the divider between the two panes);
--    - the item slots as on retail: icons cropped by the Icon Zoom setting,
--      a grey square behind each and a 2px border in the item's quality
--      colour (dark grey when empty), recoloured through Blizzard's own
--      per-slot update;
--    - the character name and the "Level N Class" line in the house font,
--      as on retail (Blizzard keeps writing the text, so the class colour
--      and the pvp title still come from the client);
--    - the stats list stays Blizzard's list on Blizzard's scrollbar, whose
--      track and thumb take the house thin style in place (arrows kept);
--      its category headers and values take the retail sidebar's colour
--      system (per-category colours, the user's overrides from the options
--      page, the thin header bars) through the scroll box's own frame
--      callbacks, never by touching its data.
--
--  Cost: a one-time pass at login on frames that already exist, then a
--  recolour per element initialisation (what Blizzard does anyway on each
--  stats refresh) and one colour compare per slot update (Blizzard's own,
--  only while the slots are shown). No events of our own.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EllesmereUI = _G.EllesmereUI
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end

local FFD = setmetatable({}, { __mode = "k" })
local function GetFFD(frame)
    local d = FFD[frame]
    if not d then d = {}; FFD[frame] = d end
    return d
end

local function Enabled()
    if not EllesmereUIDB then return true end
    if EllesmereUIDB.themedCharacterSheet == false then return false end
    if EllesmereUI.BlizzWindowSkinsKilled and EllesmereUI.BlizzWindowSkinsKilled() then return false end
    return true
end

local function FontPath()
    return (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("blizzardSkin")) or STANDARD_TEXT_FONT
end

local MEDIA = "Interface\\AddOns\\EllesmereUIBlizzardSkin\\Media\\"

-- The retail sheet's Icon Zoom setting (same key, same default).
local function Zoom()
    return (EllesmereUIDB and EllesmereUIDB.charSheetIconZoom) or 0.07
end

-- Blizzard pieces that must go for good are parked under a hidden frame:
-- Hide() gets undone by the client's own refreshes, a hidden parent does not.
local Bin
local function Discard(region)
    if not region or not region.SetParent then return end
    if not Bin then
        Bin = CreateFrame("Frame")
        Bin:Hide()
    end
    region:SetParent(Bin)
end

--------------------------------------------------------------------------------
--  Colours: the retail sidebar's category palette, keyed the way the options
--  page stores overrides (EllesmereUIDB.statCategoryColors[key]). Forever's
--  categories map onto it; General gets its own cyan.
--------------------------------------------------------------------------------
local DEFAULT_COLORS = {
    General            = { r = 0.30,  g = 0.80,  b = 0.95 },
    Attributes         = { r = 0.047, g = 0.824, b = 0.616 },
    Attack             = { r = 1,     g = 0.353, b = 0.122 },
    ["Secondary Stats"] = { r = 0.471, g = 0.255, b = 0.784 },
    Defense            = { r = 0.247, g = 0.655, b = 1 },
}
local CATEGORY_KEY = {}
if STAT_CATEGORY_GENERAL then CATEGORY_KEY[STAT_CATEGORY_GENERAL] = "General" end
if STAT_CATEGORY_PRIMARY_ATTRIBUTES then CATEGORY_KEY[STAT_CATEGORY_PRIMARY_ATTRIBUTES] = "Attributes" end
if STAT_CATEGORY_WEAPONS then CATEGORY_KEY[STAT_CATEGORY_WEAPONS] = "Attack" end
if STAT_CATEGORY_MODIFIERS then CATEGORY_KEY[STAT_CATEGORY_MODIFIERS] = "Secondary Stats" end
if STAT_CATEGORY_DEFENSE then CATEGORY_KEY[STAT_CATEGORY_DEFENSE] = "Defense" end

local function CategoryColor(categoryName)
    local key = categoryName and CATEGORY_KEY[categoryName]
    local db = EllesmereUIDB
    -- A custom colour applies only while its "use" flag is on, as on retail.
    local custom = key and db and db.statCategoryUseColor and db.statCategoryUseColor[key]
        and db.statCategoryColors and db.statCategoryColors[key]
    local c = custom or (key and DEFAULT_COLORS[key])
    if c and c.r then return c.r, c.g, c.b end
    local EG = EllesmereUI.ELLESMERE_GREEN
    if EG then return EG.r, EG.g, EG.b end
    return 1, 1, 1
end

-- The category a stat element belongs to: the data provider lists a header
-- then its rows, so it is the last header ahead of the element.
local function CategoryOf(box, elementData)
    local list = box and box.elementData
    if type(list) ~= "table" then return nil end
    local current
    for i = 1, #list do
        local d = list[i]
        if d.isHeader then current = d.name end
        if d == elementData then return current end
    end
    return current
end

--------------------------------------------------------------------------------
--  Stats list elements
--------------------------------------------------------------------------------
local function OnePixel(frame)
    local PP = EllesmereUI.PP
    local perfect = (PP and PP.perfect) or 1
    local es = frame:GetEffectiveScale()
    if not es or es <= 0 then es = 1 end
    return perfect / es
end

local function SkinHeader(frame, r, g, b)
    local d = GetFFD(frame)
    if not d.done then
        d.done = true
        if frame.Background then frame.Background:SetAlpha(0) end
        if frame.Title then
            frame.Title:SetFont(FontPath(), 11, "")
        end
        local leftBar = frame:CreateTexture(nil, "ARTWORK")
        leftBar:SetPoint("LEFT", frame, "LEFT", 8, 0)
        leftBar:SetPoint("RIGHT", frame.Title, "LEFT", -6, 0)
        d.leftBar = leftBar
        local rightBar = frame:CreateTexture(nil, "ARTWORK")
        rightBar:SetPoint("LEFT", frame.Title, "RIGHT", 6, 0)
        rightBar:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
        d.rightBar = rightBar
    end
    if frame.Title then frame.Title:SetTextColor(r, g, b, 1) end
    local px = OnePixel(frame)
    d.leftBar:SetColorTexture(r, g, b, 0.8)
    d.rightBar:SetColorTexture(r, g, b, 0.8)
    d.leftBar:SetHeight(px)
    d.rightBar:SetHeight(px)
end

local function SkinRow(frame, r, g, b)
    local d = GetFFD(frame)
    if not d.done then
        d.done = true
        if frame.Background then frame.Background:SetAlpha(0) end
        if frame.Label then frame.Label:SetFont(FontPath(), 10, "") end
        if frame.Value then frame.Value:SetFont(FontPath(), 10, "") end
        -- The retail rows carry a faint divider under each line.
        local divider = frame:CreateTexture(nil, "ARTWORK")
        divider:SetColorTexture(1, 1, 1, 0.06)
        divider:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 0)
        divider:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 0)
        divider:SetHeight(OnePixel(frame))
        d.divider = divider
    end
    if frame.Label then frame.Label:SetTextColor(0.7, 0.7, 0.7, 0.8) end
    if frame.Value then frame.Value:SetTextColor(r, g, b, 1) end
end

local function SkinElement(box, frame, elementData)
    if not frame or not elementData then return end
    if elementData.isHeader then
        SkinHeader(frame, CategoryColor(elementData.name))
    else
        SkinRow(frame, CategoryColor(CategoryOf(box, elementData)))
    end
end

local function HookStatsList(box)
    if not box or not box.ScrollBox or GetFFD(box).hooked then return end
    GetFFD(box).hooked = true
    if ScrollUtil and ScrollUtil.AddInitializedFrameCallback then
        -- The event hands (owner, frame, elementData); the helper's own
        -- iterateExisting pass hands (frame, elementData) instead, so the
        -- frames already alive are walked separately below.
        ScrollUtil.AddInitializedFrameCallback(box.ScrollBox, function(_, frame, elementData)
            SkinElement(box, frame, elementData)
        end, nil, false)
        if box.ScrollBox.ForEachFrame then
            box.ScrollBox:ForEachFrame(function(frame, elementData) SkinElement(box, frame, elementData) end)
        end
    end
end

-- Options-page refresh: colour overrides and their use flags land here, on
-- the frames alive in both lists. The retail sheet's refresher of the same
-- name is replaced (it walks retail-only state), so the swatches reach this.
local STAT_BOXES = { "CharacterStatsPaneScrollBox", "CharacterStatsPanePetScrollBox" }
function EllesmereUI._refreshCharacterSheetColors()
    if not Enabled() then return end
    for i = 1, #STAT_BOXES do
        local box = _G[STAT_BOXES[i]]
        if box and box.ScrollBox and box.ScrollBox.ForEachFrame then
            box.ScrollBox:ForEachFrame(function(frame, elementData) SkinElement(box, frame, elementData) end)
        end
    end
end

--------------------------------------------------------------------------------
--  The frame
--------------------------------------------------------------------------------
local SLOTS = {
    "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot", "CharacterBackSlot",
    "CharacterChestSlot", "CharacterShirtSlot", "CharacterTabardSlot", "CharacterWristSlot",
    "CharacterHandsSlot", "CharacterWaistSlot", "CharacterLegsSlot", "CharacterFeetSlot",
    "CharacterFinger0Slot", "CharacterFinger1Slot", "CharacterTrinket0Slot", "CharacterTrinket1Slot",
    "CharacterMainHandSlot", "CharacterSecondaryHandSlot", "CharacterRangedSlot", "CharacterAmmoSlot",
}

local function FadeChildren(frame, Fade)
    if not frame then return end
    for i = 1, select("#", frame:GetChildren()) do
        local child = select(i, frame:GetChildren())
        if child and child.GetRegions and not (child.IsForbidden and child:IsForbidden()) then
            Fade(child)
        end
    end
end

-- The slot border colour: the equipped item's quality, dark grey when empty
-- (the retail sheet's values).
local function SlotBorderColor(slot)
    local quality = GetInventoryItemQuality("player", slot:GetID())
    if quality and not (issecretvalue and issecretvalue(quality)) then
        local r, g, b
        if C_Item and C_Item.GetItemQualityColor then
            r, g, b = C_Item.GetItemQualityColor(quality)
        elseif GetItemQualityColor then
            r, g, b = GetItemQualityColor(quality)
        end
        if r then return r, g, b end
    end
    return 0.4, 0.4, 0.4
end

local function ColorSlotBorder(slot)
    local PanelPP = EllesmereUI.PanelPP
    if not (PanelPP and PanelPP.SetBorderColor) then return end
    local r, g, b = SlotBorderColor(slot)
    PanelPP.SetBorderColor(slot, r, g, b, 1)
end

-- Blizzard refreshes every shown slot through this on equipment changes and
-- on show; the border follows. Foreign item buttons (bags) have no entry.
local function OnSlotUpdate(slot)
    local d = FFD[slot]
    if d and d.border then ColorSlotBorder(slot) end
end

local function SkinSlot(slotName, Fade)
    local slot = _G[slotName]
    if not slot or GetFFD(slot).done then return end
    GetFFD(slot).done = true
    -- The bronze slot frame lives on a child frame; the button art is the
    -- named NormalTexture (hidden, not faded: the client rewrites its vertex
    -- colour, and with it the alpha, on every item update).
    if slot.BorderFrame then
        Fade(slot.BorderFrame)
    else
        -- The ammo slot is built without that child: its ring is an atlas
        -- texture on the button itself. The arrow pointing at the ranged slot
        -- (an unnamed child frame of its own) stays.
        for i = 1, select("#", slot:GetRegions()) do
            local r = select(i, slot:GetRegions())
            if r.GetAtlas and r:GetAtlas() == "UI-Character-Info-GearSlotSmall" then r:SetAlpha(0) end
        end
    end
    local normal = _G[slotName .. "NormalTexture"]
    if normal then normal:Hide() end
    -- Blizzard's quality ring gets re-shown and recoloured on every item
    -- update, so it is collapsed onto one blank texel instead of hidden.
    if slot.IconBorder then slot.IconBorder:SetTexCoord(0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8) end
    -- The item icon is the button's own; the ammo slot also declares a
    -- legacy texture under the same global name, which is not it.
    local icon = slot.icon or _G[slotName .. "IconTexture"]
    if icon then
        local z = Zoom()
        icon:SetTexCoord(z, 1 - z, z, 1 - z)
    end
    local bg = slot:CreateTexture(nil, "BACKGROUND", nil, -5)
    bg:SetAllPoints(slot)
    bg:SetColorTexture(0.5, 0.5, 0.5, 0.7)
    GetFFD(slot).bg = bg
    local PanelPP = EllesmereUI.PanelPP
    if PanelPP and PanelPP.CreateBorder then
        PanelPP.CreateBorder(slot, 0.4, 0.4, 0.4, 1, 2, "OVERLAY", 1)
        local borders = PanelPP.GetBorders and PanelPP.GetBorders(slot)
        if borders then borders:SetFrameLevel(slot:GetFrameLevel()) end
        GetFFD(slot).border = true
        ColorSlotBorder(slot)
    end
end

-- Options-page refresh: the Icon Zoom slider lands here (the retail sheet's
-- own refresher is replaced, it walks the retail slot list).
function EllesmereUI._refreshCharSheetIconZoom()
    if not Enabled() then return end
    local z = Zoom()
    for i = 1, #SLOTS do
        local slot = _G[SLOTS[i]]
        if slot and FFD[slot] and FFD[slot].done then
            local icon = slot.icon or _G[SLOTS[i] .. "IconTexture"]
            if icon then icon:SetTexCoord(z, 1 - z, z, 1 - z) end
        end
    end
end

--------------------------------------------------------------------------------
--  The model backdrop and the sidebar panel, as on retail
--------------------------------------------------------------------------------
local IMG_ASPECT = 787 / 1030   -- character-bg.png

-- Cover crop: the image keeps its aspect and the box shows its centre.
local function CoverCrop(tex, w, h)
    if issecretvalue and (issecretvalue(w) or issecretvalue(h)) then return end
    if not w or not h or w <= 0 or h <= 0 then return end
    local box = w / h
    if box > IMG_ASPECT then
        local trim = (1 - IMG_ASPECT / box) / 2
        tex:SetTexCoord(0, 1, trim, 1 - trim)
    else
        local trim = (1 - box / IMG_ASPECT) / 2
        tex:SetTexCoord(trim, 1 - trim, 0, 1)
    end
end

-- Both panels draw above the shell's top bar (children of the frame render
-- over its own textures), so their top edge is pinned to the bar's bottom:
-- flush under it, never over it, no gap of bare backdrop between.
local function PinTop(region, topBar, fallback)
    if topBar then
        region:SetPoint("TOP", topBar, "BOTTOM", 0, 0)
    else
        region:SetPoint("TOP", fallback, "TOP", 0, 0)
    end
end

local function ModelBackdrop(frame, topBar)
    local scene = _G.CharacterModelScene
    local doll = _G.PaperDollFrame
    if not (scene and doll) or GetFFD(frame).modelBg then return end
    -- Under the paper doll so it comes and goes with that tab; one level
    -- under the scene so the character renders over it.
    local host = CreateFrame("Frame", nil, doll)
    PinTop(host, topBar, scene)
    host:SetPoint("LEFT", scene, "LEFT", 0, 0)
    host:SetPoint("RIGHT", scene, "RIGHT", 0, 0)
    host:SetPoint("BOTTOM", scene, "BOTTOM", 0, 0)
    host:SetFrameLevel(math.max(0, scene:GetFrameLevel() - 1))
    local tex = host:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints(host)
    tex:SetTexture(MEDIA .. "character-bg.png")
    host:SetScript("OnSizeChanged", function(_, w, h) CoverCrop(tex, w, h) end)
    CoverCrop(tex, host:GetSize())
    GetFFD(frame).modelBg = host
end

local function SidebarPanel(frame, topBar)
    local host = frame.RightPaneHost
    if not host or GetFFD(frame).sidebar then return end
    -- A child of the pane host so it collapses with it, at the host's own
    -- level so every list and scrollbar draws over it.
    local panel = CreateFrame("Frame", nil, host)
    panel:SetFrameLevel(host:GetFrameLevel())
    PinTop(panel, topBar, host)
    panel:SetPoint("LEFT", host, "LEFT", 0, 0)
    panel:SetPoint("RIGHT", host, "RIGHT", -6, 0)
    panel:SetPoint("BOTTOM", host, "BOTTOM", 0, 8)
    local tex = panel:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints(panel)
    tex:SetColorTexture(0, 0, 0, 0.2)
    GetFFD(frame).sidebar = panel
end

local function SkinFrame()
    local frame = _G.CharacterFrame
    local WSkin = ns.WSkin
    if not (frame and WSkin and WSkin.Shell) then return false end
    local Fade = WSkin.FadeRegions
    if not Fade then return false end
    local d = GetFFD(frame)
    if d.done then return true end
    d.done = true

    -- The ordinary window treatment: shell, border, top bar, house close
    -- button, title centred on the bar. explicitControls keeps the engine
    -- away from the stats scrollbar, which stays Blizzard's.
    WSkin.Shell("charsheet", frame)
    if WSkin.CommonChrome then WSkin.CommonChrome(frame, "CharacterFrame", true) end
    if WSkin.RemovePortrait then WSkin.RemovePortrait(frame) end

    -- The right-pane collapse arrow goes. The pane it toggles is kept open:
    -- with the arrow gone a sheet collapsed from an earlier session (the
    -- state is a cvar, read once at load) could never be opened again.
    Discard(frame.RightPaneToggleButton)
    if frame.IsRightPaneCollapsed and frame.SetRightPaneCollapsed then
        frame:HookScript("OnShow", function(self)
            if self:IsRightPaneCollapsed() then self:SetRightPaneCollapsed(false) end
        end)
    end

    -- Name in the top bar and the level line: the house font on Blizzard's
    -- own font strings, so the text (pvp title, class colour) stays theirs.
    local title = _G.CharacterFrameTitleText or (frame.TitleContainer and frame.TitleContainer.TitleText)
    if title and WSkin.Font then WSkin.Font(title, 1, 1, 1) end
    local level = _G.CharacterLevelText
    if level and WSkin.Font then WSkin.Font(level) end
    if _G.CharacterLevelTextBackground then _G.CharacterLevelTextBackground:SetAlpha(0) end

    -- Pane backdrops, the stone header, the divider strip, the stats box
    -- chrome (inside frame, scroll line, class crest) and the model backdrop.
    Fade(frame.LeftPaneHost)
    Fade(frame.RightPaneHost)
    FadeChildren(frame.RightPaneHost, function(child)
        -- The stats and pet lists are children too; their chrome goes, their
        -- rows and scrollbars are handled by the element callback and kept.
        if child ~= _G.CharacterStatsPaneScrollBox and child ~= _G.CharacterStatsPanePetScrollBox then
            Fade(child)
        end
    end)
    if frame.RightPaneHost and frame.RightPaneHost.StoneBg then frame.RightPaneHost.StoneBg:SetAlpha(0) end
    Fade(_G.CharacterStatsPaneScrollBox)
    Fade(_G.CharacterStatsPanePetScrollBox)
    Fade(_G.PaperDollFrame)
    Fade(_G.CharacterModelScene)
    local shell = WSkin.GetFFD and WSkin.GetFFD(frame)
    local topBar = shell and shell.topBar
    ModelBackdrop(frame, topBar)
    SidebarPanel(frame, topBar)

    -- Item slots: frames off, icons cropped, a grey square and a quality
    -- border on each; the border follows Blizzard's own slot refresh.
    for i = 1, #SLOTS do SkinSlot(SLOTS[i], Fade) end
    if not d.slotHook and type(_G.PaperDollItemSlotButton_Update) == "function" then
        d.slotHook = true
        hooksecurefunc("PaperDollItemSlotButton_Update", OnSlotUpdate)
    end

    -- Stats list colours.
    HookStatsList(_G.CharacterStatsPaneScrollBox)
    HookStatsList(_G.CharacterStatsPanePetScrollBox)

    -- The stats scrollbars: the house thin thumb in Blizzard's own track
    -- position, the up/down arrows left as they are. Texture work only, the
    -- bar keeps its scripts and its mouse handling.
    if WSkin.ScrollBar then
        local stats = _G.CharacterStatsPaneScrollBox
        if stats and stats.ScrollBar then WSkin.ScrollBar(stats.ScrollBar, true) end
        local pet = _G.CharacterStatsPanePetScrollBox
        if pet and pet.ScrollBar then WSkin.ScrollBar(pet.ScrollBar, true) end
    end
    return true
end

local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not _G.CharacterFrame or not Enabled() then return end
    if not SkinFrame() then
        -- The engine loads after this addon's own files; one retry on the
        -- first open covers a late shell.
        _G.CharacterFrame:HookScript("OnShow", function() SkinFrame() end)
    end
end)
