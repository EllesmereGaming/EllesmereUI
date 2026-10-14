if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_MapReveal.lua  (WoW Forever only)
--  Reveal Unexplored Areas: draws the world map overlays the player has not
--  explored yet, tinted with the chosen color.
--
--  The overlays are module.MapRevealData, the generated file listed before
--  this one (.tools/map-reveal-data.sh). A data provider reports map changes;
--  the textures live on a frame of our own under the canvas, so nothing of
--  Blizzard's map is hooked. They are not passed to AddMaskableTexture: that
--  table is walked with pairs() in secure code. Nothing is built while off.
-------------------------------------------------------------------------------
local _, module = ...

-- Settings live in EllesmereUIDB.worldMapReveal; unset keys read these.
local F = module.Feature("worldMapReveal", {
    enabled = false,
    color = { r = 0.55, g = 0.55, b = 0.55, a = 1 },
})

local provider, layer, waiter
local added = false
local textures, used = {}, 0
local explored = {}

local function Clear()
    for i = 1, used do textures[i]:Hide() end
    used = 0
end

-- Size of the texture file holding a partial tile: a power of two, at least 16
local function FileSize(px)
    local s = 16
    while s < px do s = s * 2 end
    return s
end

local function Refresh()
    Clear()
    local data = module.MapRevealData
    local mapID = WorldMapFrame:GetMapID()
    local overlays = data and mapID and data[C_Map.GetMapArtID(mapID)]
    if not overlays then return end
    local layers = C_Map.GetMapArtLayers(mapID)
    local art = layers and layers[1]
    if not art then return end
    local tw, th = art.tileWidth, art.tileHeight

    wipe(explored)
    local known = C_MapExplorationInfo.GetExploredMapTextures(mapID)
    if known then
        for i = 1, #known do
            local id = known[i].fileDataIDs[1]
            if id then explored[id] = true end
        end
    end

    local col = F.Get("color")
    local cr, cg, cb, ca = col.r, col.g, col.b, col.a or 1
    for i = 1, #overlays do
        local o = overlays[i]
        if not explored[o[5]] then
            local w, h, x, y = o[1], o[2], o[3], o[4]
            local cols, rows = math.ceil(w / tw), math.ceil(h / th)
            for r = 1, rows do
                local ph = r < rows and th or h - th * (rows - 1)
                local fh = r < rows and th or FileSize(ph)
                for c = 1, cols do
                    local pw = c < cols and tw or w - tw * (cols - 1)
                    local fw = c < cols and tw or FileSize(pw)
                    used = used + 1
                    local t = textures[used]
                    if not t then
                        t = layer:CreateTexture(nil, "ARTWORK")
                        textures[used] = t
                    end
                    t:SetSize(pw, ph)
                    t:SetTexCoord(0, pw / fw, 0, ph / fh)
                    t:ClearAllPoints()
                    t:SetPoint("TOPLEFT", x + tw * (c - 1), -(y + th * (r - 1)))
                    t:SetTexture(o[4 + (r - 1) * cols + c], nil, nil, "TRILINEAR")
                    t:SetVertexColor(cr, cg, cb, ca)
                    t:Show()
                end
            end
        end
    end
end

local function Build()
    layer = CreateFrame("Frame", nil, WorldMapFrame.ScrollContainer.Child)
    layer:SetAllPoints()
    layer:SetFrameLevel(WorldMapFrame:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_MAP_EXPLORATION"))
    layer:SetScript("OnEvent", Refresh)  -- MAP_EXPLORATION_UPDATED

    provider = CreateFromMixins(MapCanvasDataProviderMixin)
    provider.OnMapChanged = Refresh
    provider.RefreshAllData = Refresh
    provider.RemoveAllData = Clear
    provider.OnShow = function() layer:RegisterEvent("MAP_EXPLORATION_UPDATED") end
    provider.OnHide = function() layer:UnregisterEvent("MAP_EXPLORATION_UPDATED") end
    provider.OnGlobalAlphaChanged = function(self) layer:SetAlpha(self:GetMap():GetGlobalAlpha()) end
end

-- The world map loads on demand, so building may wait for it.
local function Apply()
    if not F.Enabled() then
        if added then
            WorldMapFrame:RemoveDataProvider(provider)
            layer:UnregisterEvent("MAP_EXPLORATION_UPDATED")
            added = false
        end
        if waiter then waiter:UnregisterEvent("ADDON_LOADED") end
        return
    end
    if not provider then
        if not C_AddOns.IsAddOnLoaded("Blizzard_WorldMap") then
            if not waiter then
                waiter = CreateFrame("Frame")
                waiter:SetScript("OnEvent", function(self, _, name)
                    if name ~= "Blizzard_WorldMap" then return end
                    self:UnregisterEvent("ADDON_LOADED")
                    Apply()
                end)
            end
            waiter:RegisterEvent("ADDON_LOADED")
            return
        end
        Build()
    end
    if not added then
        WorldMapFrame:AddDataProvider(provider)
        added = true
        provider:OnGlobalAlphaChanged()
        if WorldMapFrame:IsShown() then provider:OnShow() end
    end
    if WorldMapFrame:IsShown() then Refresh() end
end

-- Options-page entry points.
EllesmereUI._MapReveal = {
    Get = F.Get,
    Cfg = F.Cfg,
    Apply = Apply,
}

F.Start(Apply)
