-- ZoneResolver.lua
-- Continent ID and zone ID resolution from zone name using LibBabble-Zone-3.0

local L = LootCollector
local ZoneResolver = L:NewModule("ZoneResolver")

-- Zone resolution libraries
local BZ = LibStub("LibBabble-Zone-3.0", true)
local BZR = BZ and BZ:GetReverseLookupTable() or {}

-- Zone resolution cache - stores continentID,zoneID pairs directly
local ZoneCache = {}
local CacheCount = 0


-- Zone resolution function
function ZoneResolver:GetMapZoneNumbers(zonename)
    if not zonename or zonename == "" then
        return 0, 0
    end
    
    local cached = ZoneCache[zonename]
    if cached then
        return cached[1], cached[2]
    end
    
    return 0, 0
end

-- Returns zone name for given continent and zone ID
function ZoneResolver:GetZoneName(continentID, zoneID)
    local zones = GetMapZones(continentID)
    return zones and zones[zoneID]
end

-- Clear the zone cache
function ZoneResolver:ClearCache()
    ZoneCache = {}
    CacheCount = 0
end

-- Get cache statistics
function ZoneResolver:GetCacheStats()
    return CacheCount
end

-- Update missing continent IDs for all discoveries in the database
function ZoneResolver:UpdateMissingContinentIDs()
    local discoveries = L.db and L.db.global and L.db.global.discoveries
    if not discoveries then
        return 0
    end

    local updated = 0
    local Comm = L:GetModule("Comm", true)
    local verbose = Comm and Comm.verbose

    for guid, discovery in pairs(discoveries) do
        if discovery and (not discovery.continentID or discovery.continentID == 0) and discovery.zone and discovery.zone ~= "" then
            local resolvedContID, resolvedZoneID = self:GetMapZoneNumbers(discovery.zone)
            if resolvedContID and resolvedContID > 0 then
                discovery.continentID = resolvedContID
                if (not discovery.zoneID or discovery.zoneID == 0) and resolvedZoneID > 0 then
                    discovery.zoneID = resolvedZoneID
                end
                updated = updated + 1
                if verbose then
                    print(string.format(
                        "|cffffff00[ZoneResolver DEBUG]|r Updated discovery %s continentID from 0 to %d for zone '%s'",
                        guid, resolvedContID, discovery.zone))
                end
            end
        end
    end

    if updated > 0 then
        print(string.format("|cff00ff00LootCollector:|r Updated %d discoveries with missing continentID values.", updated))
        local Map = L:GetModule("Map", true)
        if Map and Map.Update then
            Map:Update()
        end
    end

    return updated
end

function ZoneResolver:OnInitialize()
    ZoneCache = {}
    CacheCount = 0
    
    for continentID in pairs({GetMapContinents()}) do
        for zoneID, zoneName in pairs({GetMapZones(continentID)}) do
            if zoneName and zoneName ~= "" then
                local canonicalZonename = BZR[zoneName] or zoneName
                local cacheEntry = {continentID, zoneID}
                
                ZoneCache[zoneName] = cacheEntry
                CacheCount = CacheCount + 1
                
                if canonicalZonename ~= zoneName then
                    ZoneCache[canonicalZonename] = cacheEntry
                    CacheCount = CacheCount + 1
                end
            end
        end
    end
end

return ZoneResolver