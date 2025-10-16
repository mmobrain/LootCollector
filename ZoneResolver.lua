---@diagnostic disable: undefined-global
-- ZoneResolver.lua
-- WorldMapID resolution with fallback to Continent ID and zone ID resolution from zone name
-- Prioritizes WorldMapID for consistency, but retains continentID/zoneID for compatibility.

local L = LootCollector
local ZoneResolver = L:NewModule("ZoneResolver")

-- Load translation data
local nonEnglishToEnglish = {}
local Comm = L:GetModule("Comm", true)

local function debugLog(message, ...)
    if Comm then
        Comm:DebugPrint("ZoneResolver", string.format(message, ...))
    end
end

if LootCollector_Translation and LootCollector_Translation.nonEnglishToEnglish then
    nonEnglishToEnglish = LootCollector_Translation.nonEnglishToEnglish
    debugLog("Loaded %d zone translations",
        #nonEnglishToEnglish > 0 and next(nonEnglishToEnglish) and
        (function() local count = 0; for _ in pairs(nonEnglishToEnglish) do count = count + 1 end; return count end)() or 0)
else
    debugLog("Warning: Translation data not found")
end

-- Zone resolution cache - stores {worldMapID, continentID, zoneID} triples
local ZoneCache = {}
local CacheCount = 0

-- WorldMapID lookup table, populated on addon load
ZoneResolver.AreaID_Lookup = {}
local AreaIDLookupBuilt = false -- Flag to ensure lookup table is built only once
ZoneResolver.isReady = false -- New flag to indicate lookup tables are ready

-- Function to build the WorldMapID lookup table
local function BuildAreaLookup()
    if AreaIDLookupBuilt then return end
    AreaIDLookupBuilt = true

    -- Save current map state to restore later
    local prevWorldMapID = GetCurrentMapAreaID() or 0
    local prevContinentID = GetCurrentMapContinent() or 0
    local prevZoneID = GetCurrentMapZone() or 0

    -- iterate continents
    local continents = { GetMapContinents() }  -- returns names; count = #continents
    for cont = 1, #continents do
        local zones = { GetMapZones(cont) }
        for zi = 1, #zones do
            -- temporarily set map to cont/zi and read WorldMapID
            local ok, worldMapID = pcall(function()
                SetMapZoom(cont, zi)
                return GetCurrentMapAreaID()
            end)
            if ok and worldMapID and worldMapID > 0 then
                -- Convert localized zone name to English for consistency with MapData.lua
                local localizedZoneName = zones[zi]
                local englishZoneName = nonEnglishToEnglish[localizedZoneName] or localizedZoneName

                if localizedZoneName ~= englishZoneName then
                    debugLog("Converting zone name '%s' -> '%s' (WorldMapID: %d)", localizedZoneName, englishZoneName, worldMapID)
                end

                ZoneResolver.AreaID_Lookup[worldMapID] = { continent = cont, zoneIndex = zi, name = englishZoneName }
            end
        end
    end

    -- Restore previous map state
    if prevWorldMapID > 0 then
        if SetMapByID then
            SetMapByID(prevWorldMapID)
        else
            -- Fallback if SetMapByID is not available (older WoW versions)
            if SetMapZoom then SetMapZoom(prevContinentID, prevZoneID) end
        end
    else
        -- If no previous WorldMapID, restore to world view
        if SetMapZoom then SetMapZoom(0,0) end
    end

    -- Defer debug print to ensure Comm module is initialized
    C_Timer.After(0.1, function()
        debugLog("Built AreaID lookup table with %d entries.", #ZoneResolver.AreaID_Lookup)
        ZoneResolver.isReady = true -- Set the flag after tables are built and debug message is sent
    end)
end

-- Zone resolution function: Prefers WorldMapID, falls back to zone name.
function ZoneResolver:GetMapZoneNumbers(zonename, worldMapID)
    -- 1. Try resolving by WorldMapID first
    if worldMapID and worldMapID > 0 then
        local cached = ZoneCache[worldMapID]
        if cached then
            debugLog("Resolved (cached by WorldMapID) %d (Cont: %d, Zone: %d)", worldMapID, cached.continentID, cached.zoneID)
            return cached.continentID, cached.zoneID, cached.worldMapID
        end

        local continentID, zoneID = self:GetContinentAndZoneFromWorldMapID(worldMapID)
        if continentID and continentID > 0 and zoneID and zoneID > 0 then
            -- Cache this result for future lookups
            ZoneCache[worldMapID] = {worldMapID = worldMapID, continentID = continentID, zoneID = zoneID}
            CacheCount = CacheCount + 1

            -- Also cache by English zone name if available
            local englishZoneName = self:GetZoneNameByWorldMapID(worldMapID) -- This will return English name from AreaID_Lookup
            if englishZoneName and englishZoneName ~= "" and not ZoneCache[englishZoneName] then
                ZoneCache[englishZoneName] = ZoneCache[worldMapID]
                CacheCount = CacheCount + 1
            end

            debugLog("Resolved (from WoW API by WorldMapID) %d (Cont: %d, Zone: %d)", worldMapID, continentID, zoneID)
            return continentID, zoneID, worldMapID
        end
    end

    -- 2. Fallback to resolving by zone name
    if not zonename or zonename == "" then
        debugLog("No zone name provided. Returning 0,0,0.")
        return 0, 0, 0
    end

    local translatedZonename = nonEnglishToEnglish[zonename] or zonename
    local effectiveZoneName = translatedZonename -- Use translated name for initial lookup

    -- Check cache for both original and translated zone names
    local cached = ZoneCache[zonename] or ZoneCache[translatedZonename]
    if cached then
        debugLog("Found cached entry for zone name '%s' (translated: '%s', Cont: %d, Zone: %d, WorldMap: %d)", zonename, translatedZonename, cached.continentID, cached.zoneID, cached.worldMapID or 0)
        return cached.continentID, cached.zoneID, cached.worldMapID
    end

    -- Use MapData as ground truth for zone IDs if not found in cache
    local MapData = L:GetModule("MapData", true)
    if MapData then
        local width, height, continentID, zoneID = MapData:GetZoneDimensionsByName(effectiveZoneName)
        if continentID and continentID > 0 and zoneID and zoneID > 0 then
            local resolvedWorldMapID = nil

            -- Find the WorldMapID by looking up the effective zone name in the AreaID_Lookup table
            if ZoneResolver.AreaID_Lookup and next(ZoneResolver.AreaID_Lookup) then
                for wmID, data in pairs(ZoneResolver.AreaID_Lookup) do
                    if data.name and data.name == effectiveZoneName then
                        resolvedWorldMapID = wmID
                        break
                    end
                end
            end

            debugLog("MapData lookup for '%s' (translated: '%s'): Cont: %d, Zone: %d, WorldMapID: %s", zonename, effectiveZoneName, continentID, zoneID, tostring(resolvedWorldMapID))

            -- Cache this result for future lookups
            local newCacheEntry = {worldMapID = resolvedWorldMapID, continentID = continentID, zoneID = zoneID}
            ZoneCache[effectiveZoneName] = newCacheEntry
            CacheCount = CacheCount + 1
            if effectiveZoneName ~= zonename then
                ZoneCache[zonename] = newCacheEntry
                CacheCount = CacheCount + 1
            end
            if resolvedWorldMapID and resolvedWorldMapID > 0 and not ZoneCache[resolvedWorldMapID] then
                ZoneCache[resolvedWorldMapID] = newCacheEntry
                CacheCount = CacheCount + 1
            end

            return continentID, zoneID, resolvedWorldMapID
        end
    end

    debugLog("Failed to resolve zone '%s' (translated: '%s') to valid continent/zone IDs. Returning 0,0,0.", zonename, translatedZonename)
    return 0, 0, 0
end

-- Returns continent and zone ID for a given WorldMapID
function ZoneResolver:GetContinentAndZoneFromWorldMapID(worldMapID)
    if not worldMapID or worldMapID == 0 then
        return 0, 0
    end
    local lookup = ZoneResolver.AreaID_Lookup[worldMapID]
    if lookup then
        return lookup.continent, lookup.zoneIndex
    end
    return 0, 0
end

-- Returns zone name for given WorldMapID
function ZoneResolver:GetZoneNameByWorldMapID(worldMapID)
    if not worldMapID or worldMapID == 0 then
        return nil
    end

    -- 1. Prioritize GetMapNameByID (if available) for localized name
    if GetMapNameByID then
        local nameFromAPI = GetMapNameByID(worldMapID)
        if nameFromAPI and nameFromAPI ~= "" then
            debugLog("Resolved zone name '%s' from GetMapNameByID for WorldMapID %d (priority)", nameFromAPI, worldMapID)
            return nameFromAPI
        end
    end

    -- 2. Fallback to AreaID_Lookup table (which stores ENGLISH names from addon load)
    local lookupEntry = ZoneResolver.AreaID_Lookup[worldMapID]
    if lookupEntry and lookupEntry.name and lookupEntry.name ~= "" then
        debugLog("Resolved zone name '%s' from AreaID_Lookup for WorldMapID %d (fallback)", lookupEntry.name, worldMapID)
        return lookupEntry.name
    end

    -- 3. Last resort: construct a generic name
    debugLog("Could not resolve localized zone name for WorldMapID %d. Falling back to generic name.", worldMapID)
    return "Area#"..tostring(worldMapID)
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

-- Update ALL discoveries to use correct continent and zone IDs from MapData
-- Now also updates WorldMapID, preferring it over continentID/zoneID.
-- Removes discoveries without zone names as they cannot be resolved.
-- Enhanced data maintenance for:
-- - Missing zone names: DELETE entry
-- - Incorrect continentID/zoneID from non-English clients: UPDATE to match MapData.lua
-- - Missing/zero WorldMapID: UPDATE with resolved WorldMapID
function ZoneResolver:UpdateAllContinentAndZoneIDs()
    local discoveries = L.db and L.db.global and L.db.global.discoveries
    if not discoveries then
        debugLog("No discoveries found in database")
        return 0
    end

    local continentsUpdated = 0
    local zonesUpdated = 0
    local worldMapsUpdated = 0
    local failed = 0
    local removed = 0
    
    for guid, discovery in pairs(discoveries) do
        if not discovery then
            failed = failed + 1
        elseif not discovery.zone or discovery.zone == "" then
            -- Remove discoveries without zone names - they cannot be resolved
            discoveries[guid] = nil
            removed = removed + 1
        else
            local oldContinentID = discovery.continentID or 0
            local oldZoneID = discovery.zoneID or 0
            local oldWorldMapID = discovery.worldMapID or 0
            
            local resolvedContID, resolvedZoneID, resolvedWorldMapID = self:GetMapZoneNumbers(discovery.zone, discovery.worldMapID)
            
            if resolvedWorldMapID and resolvedWorldMapID > 0 then
                -- Update WorldMapID if it's missing or 0
                if oldWorldMapID == 0 or oldWorldMapID ~= resolvedWorldMapID then
                    discovery.worldMapID = resolvedWorldMapID
                    worldMapsUpdated = worldMapsUpdated + 1
                end
                
                -- Update continentID and zoneID to match MapData.lua
                if oldContinentID ~= resolvedContID then
                    discovery.continentID = resolvedContID
                    continentsUpdated = continentsUpdated + 1
                end
                if oldZoneID ~= resolvedZoneID then
                    discovery.zoneID = resolvedZoneID
                    zonesUpdated = zonesUpdated + 1
                end
            elseif resolvedContID and resolvedContID > 0 and resolvedZoneID and resolvedZoneID > 0 then
                -- Fallback: Update continentID and zoneID even if no WorldMapID was resolved
                if oldWorldMapID ~= 0 then
                    discovery.worldMapID = 0
                    worldMapsUpdated = worldMapsUpdated + 1 -- Count as an update (clearing it)
                end
                if oldContinentID ~= resolvedContID then
                    discovery.continentID = resolvedContID
                    continentsUpdated = continentsUpdated + 1
                end
                if oldZoneID ~= resolvedZoneID then
                    discovery.zoneID = resolvedZoneID
                    zonesUpdated = zonesUpdated + 1
                end
            else
                debugLog("Failed to update discovery '%s' with zone '%s'. Resolved to 0,0,0.", guid, discovery.zone)
                -- Mark as failed for now, but not removed.
                failed = failed + 1
            end
        end
    end

    print(string.format("|cff00ff00LootCollector:|r Maintenance completed: %d WorldMapIDs updated, %d continentIDs updated, %d zoneIDs updated", worldMapsUpdated, continentsUpdated, zonesUpdated))
    if removed > 0 then
        print(string.format("|cffff6600LootCollector:|r Removed %d discoveries without zone names (unresolvable data)", removed))
    end
    if failed > 0 then
        debugLog(string.format("|cffff6600LootCollector:|r Warning: %d discoveries failed to process (dungeons for example)", failed))
    end
    
    if (continentsUpdated + zonesUpdated + worldMapsUpdated) > 0 then
        local Map = L:GetModule("Map", true)
        if Map then
            Map:Update()
        end
    end

    return continentsUpdated + zonesUpdated + worldMapsUpdated + removed
end

function ZoneResolver:OnInitialize()
    -- Ensure the lookup tables are built when the module initializes
    BuildAreaLookup()
    ZoneCache = {}
    CacheCount = 0
    
    -- Populate ZoneCache with WorldMapID -> {worldMapID, continentID, zoneID}
    -- and English zone name -> {worldMapID, continentID, zoneID}
    for worldMapID, data in pairs(ZoneResolver.AreaID_Lookup) do
        if worldMapID and worldMapID > 0 and data.continent and data.zoneIndex then
            local newCacheEntry = {worldMapID = worldMapID, continentID = data.continent, zoneID = data.zoneIndex}
            ZoneCache[worldMapID] = newCacheEntry
            CacheCount = CacheCount + 1
            if data.name and data.name ~= "" then
                ZoneCache[data.name] = newCacheEntry
                CacheCount = CacheCount + 1
            end
        end
    end
    -- Defer this debug print to ensure Comm module is initialized
    C_Timer.After(0.1, function()
        debugLog("Populated zone cache with %d entries from WorldMapID lookup", CacheCount)
    end)
end

return ZoneResolver