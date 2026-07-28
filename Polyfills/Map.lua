-- C_Map
if not C_Map then
    C_Map = {}

    C_Map.GetBestMapForUnit = function(unit)
        if GetCurrentMapAreaID then
            return GetCurrentMapAreaID()
        end
        return 0
    end

    C_Map.GetPlayerMapPosition = function(mapID, unit)
        if GetPlayerMapPosition then
            local x, y = GetPlayerMapPosition(unit or "player")
            if x and y then
                return {
                    GetXY = function()
                        return x, y
                    end
                }
            end
        end
        return nil
    end

    C_Map.GetMapInfo = function(mapID)
        local continentIdx = GetCurrentMapContinent and GetCurrentMapContinent() or 0
        local continents = { GetMapContinents() }
        local continentName = continents[continentIdx] or "Northrend"

        if mapID == 9999 then
            return {
                name = continentName,
                mapType = 2, -- Continent
                parentMapID = 0
            }
        else
            return {
                name = GetRealZoneText() or GetZoneText() or "Unknown Zone",
                mapType = 3, -- Zone
                parentMapID = 9999
            }
        end
    end
end
