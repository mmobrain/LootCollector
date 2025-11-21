

local L = LootCollector
local Migration = L:NewModule("Migration_v5")

local TARGET_PROTO = 6

local function buildGuid3(continent, zoneID, itemID, x, y)
    local x2 = L:Round2(x or 0)
    local y2 = L:Round2(y or 0)
    return tostring(continent or 0) .. "-" .. tostring(zoneID or 0) .. "-" .. tostring(itemID or 0) .. "-" .. string.format("%.2f", x2) .. "-" .. string.format("%.2f", y2)
end

local function GenerateGUID(c, z, i, x, y)
    if L and L.GenerateGUID then
        return L:GenerateGUID(c, z, i, x, y)
    end
    return buildGuid3(c, z, i, x, y)
end

local function IsNewLootedKey(g)
    return type(g) == "string" and g:match("^%d+%-%d+%-%d+%-%-?[%d%.]+%-%-?[%d%.]+$") ~= nil
end

local function IsOldLootedKey(g)
    if type(g) ~= "string" then return false end
    if IsNewLootedKey(g) then return false end
    return g:match("^%d+%-%d+%-%-?[%d%.]+%-%-?[%d%.]+$") ~= nil
end

local function ParseOldLootedKey(g)
    if not IsOldLootedKey(g) then return nil end
    local z, i, x, y = g:match("^(%d+)%-(%d+)%-([%-%d%.]+)%-([%-%d%.]+)$")
    if z then return tonumber(z), tonumber(i), tonumber(x), tonumber(y) end
    return nil
end

local function BuildContinentLookupsFromDiscoveries(rootDB)
    local lookupByZIXY2 = {}; local zoneToContinent = {}
    local disc = rootDB and rootDB.global and rootDB.global.discoveries
    if type(disc) ~= "table" then return lookupByZIXY2, zoneToContinent end

    local function add(c, z, i, x, y)
        if not (c and z and i and x and y) then return end
        zoneToContinent[z] = zoneToContinent[z] or c
        local x2, y2 = L:Round2(x), L:Round2(y)
        lookupByZIXY2[z] = lookupByZIXY2[z] or {}; lookupByZIXY2[z][i] = lookupByZIXY2[z][i] or {}
        local k = string.format("%.2f:%.2f", x2, y2)
        if lookupByZIXY2[z][i][k] == nil then lookupByZIXY2[z][i][k] = c end
    end

    for k, d in pairs(disc) do
        if type(d) == "table" then
            local c = tonumber(d.c or d.continent or d.continentID)
            local z = tonumber(d.z or d.zoneID)
            local i = tonumber(d.i or d.itemID)
            local x, y
            if d.xy and type(d.xy) == "table" then x = tonumber(d.xy.x); y = tonumber(d.xy.y)
            elseif d.coords and type(d.coords) == "table" then x = tonumber(d.coords.x); y = tonumber(d.coords.y) end
            if not (c and z and i and x and y) and type(k) == "string" then
                local pc, pz, pi, px, py = k:match("^(%d+)%-(%d+)%-(%d+)%-([%-%d%.]+)%-([%-%d%.]+)$")
                if pc then c = c or tonumber(pc); z = z or tonumber(pz); i = i or tonumber(pi); x = x or tonumber(px); y = y or tonumber(py)
                else
                    local pz2, pi2, px2, py2 = k:match("^(%d+)%-(%d+)%-([%-%d%.]+)%-([%-%d%.]+)$")
                    if pz2 then z = z or tonumber(pz2); i = i or tonumber(pi2); x = x or tonumber(px2); y = y or tonumber(py2) end
                end
            end
            add(c, z, i, x, y)
            if z and c then zoneToContinent[z] = zoneToContinent[z] or c end
        end
    end
    return lookupByZIXY2, zoneToContinent
end

local function ConvertLootedTableForChar(lootedTbl, lookupByZIXY2, zoneToContinent)
    if type(lootedTbl) ~= "table" then return 0, 0, 0, {} end
    local converted = {}; local migrated, unmapped, keptNew = 0, 0, 0
    local function put(guid, ts)
        local prev = converted[guid]
        if prev == nil or (tonumber(ts) or 0) > (tonumber(prev) or 0) then converted[guid] = ts end
    end
    for g, ts in pairs(lootedTbl) do
        if IsNewLootedKey(g) then put(g, ts); keptNew = keptNew + 1
        elseif IsOldLootedKey(g) then
            local z, i, x, y = ParseOldLootedKey(g)
            if z and i and x and y then
                local x2, y2 = L:Round2(x), L:Round2(y)
                local c
                local zi = lookupByZIXY2[z]; if zi then local ix = zi[i]; if ix then c = ix[string.format("%.2f:%.2f", x2, y2)] end end
                if not c then c = zoneToContinent[z] end
                if c then local newGuid = GenerateGUID(c, z, i, x, y); put(newGuid, ts); migrated = migrated + 1
                else put(g, ts); unmapped = unmapped + 1 end
            else put(g, ts); unmapped = unmapped + 1 end
        else put(g, ts); unmapped = unmapped + 1 end
    end
    return migrated, unmapped, keptNew, converted
end

function Migration:PreserveAndReset()
    
    local rawDB = _G.LootCollectorDB_Asc
    if not (rawDB and type(rawDB) == "table") then
     
        rawDB = {}
        _G.LootCollectorDB_Asc = rawDB
    end

    if not rawDB.char then rawDB.char = {} end
    if not rawDB.global then rawDB.global = {} end
    if not rawDB.profile then rawDB.profile = {} end

    local lookupByZIXY2, zoneToContinent = BuildContinentLookupsFromDiscoveries(rawDB)
 
    if not rawDB.profiles then rawDB.profiles = {} end
    if not rawDB.profiles.Default then rawDB.profiles.Default = {} end
    rawDB.profiles.Default.preservedLootedData_v6 = {}
    
    print("|cff00ff00LootCollector:|r [1/4] Created temporary storage for looted data.")
    local totalChars, totalMigrated, totalUnmapped, totalKeptNew = 0, 0, 0, 0
    for charName, charData in pairs(rawDB.char) do
        if type(charData) == "table" and type(charData.looted) == "table" and next(charData.looted) ~= nil then
            totalChars = totalChars + 1
            local migrated, unmapped, keptNew, converted = ConvertLootedTableForChar(charData.looted, lookupByZIXY2, zoneToContinent)
            totalMigrated = totalMigrated + migrated; totalUnmapped = totalUnmapped + unmapped; totalKeptNew = totalKeptNew
            rawDB.profiles.Default.preservedLootedData_v6[charName] = { looted = converted }
        end
    end
    local totalRecords = totalMigrated + totalUnmapped + totalKeptNew
    if totalChars > 0 then
        print(string.format("|cff00ff00LootCollector:|r [1/4] Successfully preserved %d looted records across %d characters.", totalRecords, totalChars))
    else
        print("|cffff7f00LootCollector:|r [1/4] No character 'looted' data found to preserve.")
    end

    if rawDB.global and rawDB.global.discoveries then
        wipe(rawDB.global.discoveries)
        print("|cff00ff00LootCollector:|r [2/4] Old discovery database has been cleared.")
    end
    if rawDB.global and rawDB.global.blackmarketVendors then
        wipe(rawDB.global.blackmarketVendors) 
    end

    local ImportExport = L:GetModule("ImportExport", true)
    if ImportExport and type(_G.LootCollector_OptionalDB_Data) == "table" and _G.LootCollector_OptionalDB_Data.data ~= "" then
        print("|cff00ff00LootCollector:|r [3/4] Automatically merging starter database...")

        local parsed, err = deserialize(_G.LootCollector_OptionalDB_Data.data)
        if parsed then

            local disc = parsed.discoveries or {}
            if not rawDB.global.discoveries then rawDB.global.discoveries = {} end
            for guid, d in pairs(disc) do

                rawDB.global.discoveries[guid] = {
                    g = d.guid, c = d.continent, z = d.zoneID, iz = d.instanceID or 0, i = d.itemID,
                    xy = d.coords, il = d.itemLink, q = d.itemQuality or 0, t0 = d.timestamp,
                    ls = d.lastSeen, st = d.statusTs, s = d.status, mc = d.mergeCount,
                    fp = d.foundBy_player, o = d.originator, src = d.source, cl = d.class,
                    it = d.itemType or 0, ist = d.itemSubType or 0, dt = d.discoveryType or 0,
                }
            end
            print("|cff00ff00LootCollector:|r [3/4] Starter database merged successfully.")
        else
            print("|cffff7f00LootCollector:|r [3/4] Failed to parse starter database. It will be skipped.")
        end
    else
        print("|cffff7f00LootCollector:|r [3/4] Skipped starter database merge (not found or empty).")
    end
    

    print("|cffffff00LootCollector:|r [3.5/4] Remapping looted history to match new database GUIDs...")
    local Constants = L:GetModule("Constants", true)
    local wfLookup = {}
    local remappedCount = 0
    if Constants and Constants.DISCOVERY_TYPE and rawDB.global and rawDB.global.discoveries then
        for guid, d in pairs(rawDB.global.discoveries) do
            if d and d.dt == Constants.DISCOVERY_TYPE.WORLDFORGED then
                local c, z, i = d.c, d.z, d.i
                if c and z and i then
                    wfLookup[c] = wfLookup[c] or {}
                    wfLookup[c][z] = wfLookup[c][z] or {}
                    wfLookup[c][z][i] = guid 
                end
            end
        end
    end
    if next(wfLookup) ~= nil and rawDB.profiles.Default.preservedLootedData_v6 then
        for charName, charData in pairs(rawDB.profiles.Default.preservedLootedData_v6) do
            if charData and charData.looted then
                local newLooted = {}
                for oldGuid, timestamp in pairs(charData.looted) do
                    local c, z, i = oldGuid:match("^(%d+)%-(%d+)%-(%d+)%-")
                    c, z, i = tonumber(c), tonumber(z), tonumber(i)
                    local newGuid = c and z and i and wfLookup[c] and wfLookup[c][z] and wfLookup[c][z][i]
                    if newGuid and newGuid ~= oldGuid then
                        newLooted[newGuid] = timestamp
                        remappedCount = remappedCount + 1
                    else
                        newLooted[oldGuid] = timestamp
                    end
                end
                charData.looted = newLooted
            end
        end
    end
    if remappedCount > 0 then
        print(string.format("|cff00ff00LootCollector:|r ... Successfully remapped %d looted Worldforged records.", remappedCount))
    end
    
   
    rawDB._schemaVersion = TARGET_PROTO
    rawDB.global._schemaVersion = nil 
    if rawDB.profiles and rawDB.profiles.Default then
        rawDB.profiles.Default._schemaVersion = nil
    end
    print("|cff00ff00LootCollector:|r [4/4] Database version updated. Addon will now reload.")
    
    
    L.LEGACY_MODE_ACTIVE = false
    ReloadUI()
end

function Migration:Deserialize(s)
	local AceSerializer = LibStub and LibStub("AceSerializer-3.0", true)
	local LibDeflate = LibStub and LibStub("LibDeflate", true)
	if not AceSerializer or not LibDeflate then return nil, "Libs missing" end
	if type(s) ~= "string" then return nil, "Invalid input type" end
	
	local body = s:match("^!LC1!(.+)$")
	if not body then return nil, "Bad header" end
	
	local bytes = LibDeflate:DecodeForPrint(body)
	if not bytes then return nil, "Decode failed" end
	
	local unz = LibDeflate:DecompressDeflate(bytes)
	if not unz then return nil, "Decompress failed" end
	
	local ok, _, tbl = pcall(AceSerializer.Deserialize, AceSerializer, unz)
	if ok and type(tbl) == "table" then return tbl end
	
	return nil, "Deserialize final step failed"
end

function Migration:OnInitialize()
   
    if not deserialize then
        deserialize = self.Deserialize
    end

    SLASH_LootCollectorPRESERVE1 = "/lcpreserve"
    SlashCmdList["LootCollectorPRESERVE"] = function()
        if L.db and L.db.profile and L.db.profile.preservedLootedData_v6 then
            print("|cffff7f00LootCollector:|r Preserved data already exists. Please manually clean your SavedVariables if you need to run this again.")
            return
        end
        Migration:PreserveAndReset()
    end
end

return Migration
