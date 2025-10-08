-- ZoneResolver.lua
-- Continent ID and zone ID resolution from zone name using LibBabble-Zone-3.0

local L = LootCollector
local ZoneResolver = L:NewModule("ZoneResolver")

-- Zone resolution libraries
local BZ = LibStub("LibBabble-Zone-3.0", true)
local BZR = BZ and BZ:GetReverseLookupTable() or {}

-- Zone resolution cache
local ZoneCache = {}

-- Zone resolution function
function ZoneResolver:GetMapZoneNumbers(zonename)
    if not zonename or zonename == "" then
        return 0, 0
    end

    local cached = ZoneCache[zonename]
    if cached then
        return unpack(cached)
    end

    -- Try to translate the zone name to English using LibBabble-Zone-3.0 if it's not already English
    local canonicalZonename = BZR[zonename] or zonename
    for cont in pairs { GetMapContinents() } do
        for zone, name in pairs { GetMapZones(cont) } do
            local cleanedName = string.lower((name or ""):gsub("^%s+", ""):gsub("%s+$", ""))
            local cleanedCanonicalZonename = string.lower((canonicalZonename or ""):gsub("^%s+", ""):gsub("%s+$", ""))
            if cleanedName == cleanedCanonicalZonename then
                ZoneCache[zonename] = { cont, zone }
                return cont, zone
            end
        end
    end

    -- Cache negative results to avoid repeated lookups
    ZoneCache[zonename] = { 0, 0 }
    return 0, 0
end

-- Clear the zone cache
function ZoneResolver:ClearCache()
    ZoneCache = {}
end

-- Get cache statistics
function ZoneResolver:GetCacheStats()
    local count = 0
    for _ in pairs(ZoneCache) do
        count = count + 1
    end
    return count
end

-- Update missing continent IDs for all discoveries in the database
function ZoneResolver:UpdateMissingContinentIDs()
    if not (L.db and L.db.global and L.db.global.discoveries) then
        return 0
    end

    local updated = 0

    for guid, discovery in pairs(L.db.global.discoveries) do
        if discovery and (not discovery.continentID or discovery.continentID == 0) and discovery.zone and discovery.zone ~= "" then
            local resolvedContID, resolvedZoneID = self:GetMapZoneNumbers(discovery.zone)
            if resolvedContID and resolvedContID > 0 then
                discovery.continentID = resolvedContID
                if (not discovery.zoneID or discovery.zoneID == 0) and resolvedZoneID > 0 then
                    discovery.zoneID = resolvedZoneID
                end
                updated = updated + 1
                if L:GetModule("Comm", true) and L:GetModule("Comm", true).verbose then
                    print(string.format(
                        "|cffffff00[ZoneResolver DEBUG]|r Updated discovery %s continentID from 0 to %d for zone '%s'",
                        guid,
                        resolvedContID, discovery.zone))
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
