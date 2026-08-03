local addon, ns = ...

if not ns or not ns.isLegacyNameplates then return end

-- WoTLK nameplates are anonymous WorldFrame children. They have no unit token,
-- so use Blizzard's native bars/text as the authoritative data source. This is
-- accurate for every visible plate, unlike target/mouseover Unit* fallbacks.
local select, type, pairs, ipairs = select, type, pairs, ipairs
local lower, find, abs = string.lower, string.find, math.abs
local WHITE = "Interface\\Buttons\\WHITE8X8"
local plates = setmetatable({}, { __mode = "k" })
local lastWorldChildCount = 0
local enabled = false

ns.legacyPlates = plates

local function DB()
    return (ns.db and ns.db.profile) or ns.defaults or {}
end

local function RegionCount(frame)
    return select("#", frame:GetRegions())
end

local function ChildCount(frame)
    return select("#", frame:GetChildren())
end

local function TexturePath(texture)
    if not texture or not texture.GetTexture then return nil end
    local path = texture:GetTexture()
    return type(path) == "string" and lower(path) or nil
end

-- Blizzard refreshes legacy nameplate regions directly and may restore the
-- native name/level FontStrings after we skin the plate.  Keep those regions
-- transparent permanently: their text is still readable through GetText(), so
-- they remain the authoritative source for our replacement FontStrings.
local function SuppressSourceFont(fs)
    if not fs then return end
    fs:Hide()
    fs:SetAlpha(0)
    if fs._euiAlphaSuppressed or not hooksecurefunc then return end
    fs._euiAlphaSuppressed = true
    hooksecurefunc(fs, "Show", function(self)
        if not self._euiForcingHidden then
            self._euiForcingHidden = true
            self:Hide()
            self._euiForcingHidden = nil
        end
    end)
    hooksecurefunc(fs, "SetAlpha", function(self, alpha)
        if alpha ~= 0 and not self._euiForcingAlpha then
            self._euiForcingAlpha = true
            self:SetAlpha(0)
            self._euiForcingAlpha = nil
        end
    end)
end

local function IsLegacyNameplate(frame)
    if not frame or frame == WorldFrame or frame:GetParent() ~= WorldFrame then return false end
    local bars, fonts, signature = 0, 0, false
    for i = 1, RegionCount(frame) do
        local region = select(i, frame:GetRegions())
        if region and region.GetObjectType then
            local kind = region:GetObjectType()
            if kind == "FontString" then
                fonts = fonts + 1
            elseif kind == "Texture" then
                local path = TexturePath(region)
                if path and (find(path, "nameplate", 1, true)
                    or find(path, "targetingframe", 1, true)) then
                    signature = true
                end
            end
        end
    end
    for i = 1, ChildCount(frame) do
        local child = select(i, frame:GetChildren())
        if child and child.GetObjectType and child:GetObjectType() == "StatusBar" then
            bars = bars + 1
        end
    end
    return signature and bars > 0 and fonts > 0
end

local function AddEdge(parent, first, second, vertical)
    local edge = parent:CreateTexture(nil, "OVERLAY")
    edge:SetTexture(WHITE)
    edge:SetVertexColor(0, 0, 0, 1)
    edge:SetPoint(unpack(first))
    edge:SetPoint(unpack(second))
    if vertical then edge:SetWidth(1) else edge:SetHeight(1) end
    return edge
end

local function CreateBorder(bar)
    return {
        AddEdge(bar, { "TOPLEFT", bar, "TOPLEFT", -1, 1 }, { "TOPRIGHT", bar, "TOPRIGHT", 1, 1 }),
        AddEdge(bar, { "BOTTOMLEFT", bar, "BOTTOMLEFT", -1, -1 }, { "BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1 }),
        AddEdge(bar, { "TOPLEFT", bar, "TOPLEFT", -1, 1 }, { "BOTTOMLEFT", bar, "BOTTOMLEFT", -1, -1 }, true),
        AddEdge(bar, { "TOPRIGHT", bar, "TOPRIGHT", 1, 1 }, { "BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1 }, true),
    }
end

local function SetBorder(border, shown, color)
    if not border then return end
    for _, edge in ipairs(border) do
        if color then edge:SetVertexColor(color.r or 0, color.g or 0, color.b or 0, 1) end
        if shown then edge:Show() else edge:Hide() end
    end
end

local function FindParts(frame)
    local health, cast
    for i = 1, ChildCount(frame) do
        local child = select(i, frame:GetChildren())
        if child and child.GetObjectType and child:GetObjectType() == "StatusBar" then
            if not health then health = child elseif not cast then cast = child end
        end
    end

    local nameSource, levelSource, raidIcon
    local fonts = {}
    local hiddenArt = {}
    for i = 1, RegionCount(frame) do
        local region = select(i, frame:GetRegions())
        if region and region.GetObjectType then
            local kind = region:GetObjectType()
            if kind == "FontString" then
                fonts[#fonts + 1] = region
            elseif kind == "Texture" then
                local path = TexturePath(region)
                if path and find(path, "raidtargetingicons", 1, true) then
                    raidIcon = region
                elseif path and (find(path, "nameplate%-border") or find(path, "nameplate%-glow")
                    or find(path, "nameplate%-highlight") or find(path, "nameplate%-castbar")) then
                    region:SetAlpha(0)
                    hiddenArt[#hiddenArt + 1] = region
                end
            end
        end
    end
    for _, fs in ipairs(fonts) do
        local value = fs:GetText()
        if value and tostring(value):match("^%??%d+[%+%-]?$" ) then
            levelSource = levelSource or fs
        elseif value and value ~= "" then
            nameSource = nameSource or fs
        end
    end
    nameSource = nameSource or fonts[1]
    if not levelSource then
        for _, fs in ipairs(fonts) do if fs ~= nameSource then levelSource = fs; break end end
    end
    return health, cast, nameSource, levelSource, raidIcon, fonts, hiddenArt
end

local function ResolveTexture(key)
    if EllesmereUI and EllesmereUI.ResolveTexturePath and ns.healthBarTextures then
        return EllesmereUI.ResolveTexturePath(ns.healthBarTextures, key or "none", WHITE)
    end
    return WHITE
end

local function ApplyReactionColor(state, r, g, b)
    if state.applyingColor then return end
    local db, color = DB()
    state.isFriendly = (r < .3 and g > .7 and b < .35)
        or (r < .35 and g < .55 and b > .7)
    if r > .85 and g < .25 and b < .25 then
        color = db.hostile or ns.defaults.hostile
    elseif r > .75 and g > .65 and b < .35 then
        color = db.neutral or ns.defaults.neutral
    elseif abs(r - g) < .08 and abs(g - b) < .08 then
        color = db.tapped or ns.defaults.tapped
    end
    if color then r, g, b = color.r, color.g, color.b end
    state.applyingColor = true
    state.health:SetStatusBarColor(r, g, b)
    state.applyingColor = false
    if state.name then state.name:SetTextColor(r, g, b) end
    -- `friendlyNameOnly` is a friendly-player option.  Legacy nameplates have
    -- no unit token, so reaction color alone cannot distinguish a friendly
    -- player from a friendly/attackable NPC (training dummies are a common
    -- example).  Hiding by color made valid NPC health bars appear to be
    -- missing.  Keep the bar visible unless this backend can positively
    -- identify the plate as a player in the future.
    local nameOnly = state.isFriendlyPlayer == true and db.friendlyNameOnly ~= false
    state.health:SetAlpha(nameOnly and 0 or 1)
    if state.cast then state.cast:SetAlpha(nameOnly and 0 or 1) end
    if state.healthText then
        if nameOnly then state.healthText:Hide() elseif state.healthElement then state.healthText:Show() end
    end
end

local function PositionHealthText(state)
    local db = DB()
    local slots = {
        { key = "textSlotRight", point = "RIGHT", relative = "RIGHT", x = -2, y = 0 },
        { key = "textSlotLeft", point = "LEFT", relative = "LEFT", x = 2, y = 0 },
        { key = "textSlotCenter", point = "CENTER", relative = "CENTER", x = 0, y = 0 },
        { key = "textSlotTop", point = "BOTTOM", relative = "TOP", x = 0, y = 3 },
    }
    state.healthText:ClearAllPoints()
    state.healthText:Hide()
    state.healthElement = nil
    state.value = nil
    for _, slot in ipairs(slots) do
        local element = db[slot.key]
        if element == "healthPercent" or element == "healthPercentNoSign" then
            local x = slot.x + (db[slot.key .. "XOffset"] or 0)
            local y = slot.y + (db[slot.key .. "YOffset"] or 0)
            state.healthText:SetPoint(slot.point, state.health, slot.relative, x, y)
            ns.SetFSFont(state.healthText, db[slot.key .. "Size"] or 9, ns.GetNPOutline())
            local color = db[slot.key .. "Color"]
            if color then state.healthText:SetTextColor(color.r, color.g, color.b, 1) end
            state.healthElement = element
            state.healthText:Show()
            break
        end
    end
end

local function RefreshAppearance(state)
    local db, health = DB(), state.health
    for _, fs in ipairs(state.sourceFonts) do SuppressSourceFont(fs) end
    for _, texture in ipairs(state.hiddenArt) do texture:SetAlpha(0) end
    local width = ns.GetHealthBarWidth and ns.GetHealthBarWidth() or 120
    local height = ns.GetHealthBarHeight and ns.GetHealthBarHeight() or 12
    health:SetWidth(width)
    health:SetHeight(height)
    health:SetStatusBarTexture(ResolveTexture(db.healthBarTexture))
    local bg = db.bgColor or ns.defaults.bgColor
    state.bg:SetVertexColor(bg.r, bg.g, bg.b, db.bgAlpha or ns.defaults.bgAlpha or 1)
    SetBorder(state.healthBorder, db.showBorder ~= false, db.borderColor or ns.defaults.borderColor)

    if state.cast then
        local castHeight = ns.GetCastBarHeight and ns.GetCastBarHeight() or 8
        state.cast:ClearAllPoints()
        state.cast:SetPoint("TOP", health, "BOTTOM", 0, -2)
        state.cast:SetWidth(width)
        state.cast:SetHeight(castHeight)
        state.cast:SetStatusBarTexture(ResolveTexture(db.castBarTexture))
        SetBorder(state.castBorder, (db.castBorderSize or 0) > 0,
            db.castBorderColor or ns.defaults.castBorderColor)
    end
    ns.SetFSFont(state.name, db.enemyNameTextSize or 11, ns.GetNPOutline())
    state.name:ClearAllPoints()
    state.name:SetPoint("BOTTOM", health, "TOP", 0, 3 + (db.nameYOffset or 0))
    ns.SetFSFont(state.level, 9, ns.GetNPOutline())
    state.level:ClearAllPoints()
    state.level:SetPoint("LEFT", health, "RIGHT", 4, 0)
    PositionHealthText(state)
    if state.castBg then
        local castBg = db.castBgColor or ns.defaults.castBgColor
        state.castBg:SetVertexColor(castBg.r, castBg.g, castBg.b,
            db.castBgAlpha or ns.defaults.castBgAlpha or .9)
    end
    if state.castFonts then
        for _, fs in ipairs(state.castFonts) do
            ns.SetFSFont(fs, db.castNameSize or 10, ns.GetNPOutline())
            local color = db.castNameColor or ns.defaults.castNameColor
            if color then fs:SetTextColor(color.r, color.g, color.b, 1) end
        end
    end
    if state.raidIcon then
        state.raidIcon:ClearAllPoints()
        state.raidIcon:SetPoint("BOTTOM", health, "TOP", 0, 15)
        state.raidIcon:SetWidth(18)
        state.raidIcon:SetHeight(18)
    end
    local r, g, b = state.nativeR, state.nativeG, state.nativeB
    if not r then r, g, b = health:GetStatusBarColor() end
    ApplyReactionColor(state, r or 1, g or 0, b or 0)
end

local function RefreshValues(state)
    if not state.frame:IsShown() then return end
    -- The 3.3.5 engine can mutate native nameplate regions from C without
    -- passing through Lua method hooks.  Reassert suppression on each driver
    -- update so Blizzard's own white name/level text cannot reappear.
    for _, fs in ipairs(state.sourceFonts) do SuppressSourceFont(fs) end
    local minimum, maximum = state.health:GetMinMaxValues()
    local value = state.health:GetValue()
    if state.value ~= value or state.maximum ~= maximum then
        state.value, state.maximum = value, maximum
        local pct = maximum and maximum > 0 and math.floor(value / maximum * 100 + .5) or 0
        local suffix = state.healthElement == "healthPercentNoSign" and "" or "%"
        state.healthText:SetText(pct .. suffix)
    end
    local name = state.nameSource and state.nameSource:GetText() or ""
    if name ~= state.nameValue then state.nameValue = name; state.name:SetText(name) end
    local level = state.levelSource and state.levelSource:GetText() or ""
    if level ~= state.levelValue then state.levelValue = level; state.level:SetText(level) end
end

local function Skin(frame)
    if plates[frame] then return end
    local health, cast, nameSource, levelSource, raidIcon, fonts, hiddenArt = FindParts(frame)
    if not health then return end
    local state = { frame = frame, health = health, cast = cast, nameSource = nameSource,
        levelSource = levelSource, raidIcon = raidIcon, sourceFonts = fonts, hiddenArt = hiddenArt }
    state.nativeR, state.nativeG, state.nativeB = health:GetStatusBarColor()
    plates[frame] = state
    for _, fs in ipairs(fonts) do SuppressSourceFont(fs) end

    state.bg = health:CreateTexture(nil, "BACKGROUND")
    state.bg:SetTexture(WHITE)
    state.bg:SetAllPoints(health)
    state.healthBorder = CreateBorder(health)
    -- Prime with a built-in FontObject as an additional legacy-client safety
    -- net; SetFSFont replaces it with the configured font when supported.
    state.name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    state.level = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    state.healthText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if cast then
        state.castBorder = CreateBorder(cast)
        state.castBg = cast:CreateTexture(nil, "BACKGROUND")
        state.castBg:SetTexture(WHITE)
        state.castBg:SetAllPoints(cast)
        state.castFonts = {}
        for i = 1, RegionCount(cast) do
            local region = select(i, cast:GetRegions())
            if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                state.castFonts[#state.castFonts + 1] = region
            end
        end
    end

    hooksecurefunc(health, "SetStatusBarColor", function(_, r, g, b)
        if not state.applyingColor then
            state.nativeR, state.nativeG, state.nativeB = r, g, b
            ApplyReactionColor(state, r, g, b)
        end
    end)
    frame:HookScript("OnShow", function()
        RefreshAppearance(state)
        RefreshValues(state)
    end)
    RefreshAppearance(state)
    RefreshValues(state)
end

local function Discover()
    local count = ChildCount(WorldFrame)
    if count < lastWorldChildCount then lastWorldChildCount = 0 end
    if count == lastWorldChildCount then return end
    local children = { WorldFrame:GetChildren() }
    -- GetChildren order is not contractual. Rescan the list when its size
    -- changes and let the weak plate map make already-known frames O(1).
    for i = 1, count do
        local frame = children[i]
        if not plates[frame] and IsLegacyNameplate(frame) then Skin(frame) end
    end
    lastWorldChildCount = count
end

local driver = CreateFrame("Frame")
local elapsed = 0
driver:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < .05 then return end
    elapsed = 0
    Discover()
    for _, state in pairs(plates) do RefreshValues(state) end
end)
driver:Hide()

function ns.LegacyRefreshAll()
    for _, state in pairs(plates) do
        RefreshAppearance(state)
        RefreshValues(state)
    end
end

function ns.LegacyEnable()
    if enabled then return end
    enabled = true
    -- These are real 3.3.5 CVars. Private-server variants differ, so isolate
    -- every optional write instead of allowing one absent CVar to abort setup.
    if SetCVar then
        pcall(SetCVar, "nameplateShowEnemies", 1)
        pcall(SetCVar, "nameplateShowAll", 1)
        pcall(SetCVar, "nameplateShowFriends", DB().showFriendlyPlayers == false and 0 or 1)
        pcall(SetCVar, "nameplateShowEnemyPets", DB().showEnemyPets == true and 1 or 0)
    end
    driver:Show()
    Discover()
end

function ns.ForceFriendlyPlayerCVarsOn()
    if SetCVar then pcall(SetCVar, "nameplateShowFriends", 1) end
end

function ns.UpdateFriendlyNameplateSystem()
    if SetCVar then
        pcall(SetCVar, "nameplateShowFriends", DB().showFriendlyPlayers == false and 0 or 1)
    end
    ns.LegacyRefreshAll()
end
