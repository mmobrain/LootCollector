local L = LootCollector
local Core = L:NewModule("Core")
local ZoneList = L:GetModule("ZoneList", true)

local floor    = math.floor
local time     = time
local tonumber = tonumber
local tostring = tostring
local pairs    = pairs
local select   = select
local type     = type
local max      = math.max

Core.pendingBroadcasts = {}  
local BROADCAST_DELAY = 6  

local Constants = L:GetModule("Constants", true)
local XXH_Lua_Lib = _G.XXH_Lua_Lib

local itemCacheTooltip
local cacheTicker
local cacheActive = false
local CACHE_MIN_DELAY, CACHE_MAX_DELAY = 3, 6

Core._pumpJitterLeft = 3  
Core._isSBCached = nil

Core.ZoneIndex = {}
Core.ZoneIndexBuilt = false
Core.IndexQueue = {}

local SCAN_BUDGET_MS   = 4       
local SCAN_MAX_PER_TICK = 300    
local PAUSE_IN_COMBAT   = true
local PAUSE_WHEN_MOVING = false

local MID_GEN_CHUNK_SIZE = 2
local INDEXER_TICK_RATE = 1

Core._indexerNextKey = nil
Core._indexerInProgress = false
Core._purgeInProgress = false
Core._purgeKey = nil
Core._purgeData = nil
Core._purgeRemovedCount = 0
Core._finderBlacklistCache = {}

local function ScheduleAfter(seconds, func)
    if C_Timer and C_Timer.After then
        return C_Timer.After(seconds, func)
    end
    local f = CreateFrame("Frame")
    local cancelled = false
    local target = GetTime() + (tonumber(seconds) or 0)
    f:SetScript("OnUpdate", function(self)
        if cancelled then
            self:SetScript("OnUpdate", nil)
            self:Hide()
            return
        end
        if GetTime() >= target then
            self:SetScript("OnUpdate", nil)
            self:Hide()
            func()
        end
    end)
    f:Show()
    return {
        Cancel = function() cancelled = true end,
        IsCancelled = function() return cancelled end,
    }
end

local c_z_toPurge = {
    [1] = { [322]=true, [382]=true, [363]=true },
    [2] = { [302]=true, [342]=true, [383]=true },
    [3] = { [482]=true, [505]=true }
}

function Core:RunUnifiedDatabasePass(blacklistName)
    local pTime = L.ProfileStart and L:ProfileStart() 

    local discoveries = L:GetDiscoveriesDB()
    local vendors = L:GetVendorsDB()
    if not discoveries then 
        if pTime then L:ProfileStop("Core:RunUnifiedDatabasePass", pTime) end
        return {} 
    end

    local Constants = L:GetModule("Constants", true)
    local isCoA = self.IsConfirmedCoARealm and self:IsConfirmedCoARealm()
    local MS_TYPE = Constants and Constants.DISCOVERY_TYPE.MYSTIC_SCROLL or 2
    local SPECIAL_SRC = Constants and Constants.AcceptedLootSrcMS and Constants.AcceptedLootSrcMS.direct or 3
    local TRUSTED_OWNERS = { ["deidre"] = true, ["skulltrail"] = true }
    
    local fullIgnoreList = {}
    if L.ignoreList then for k in pairs(L.ignoreList) do fullIgnoreList[k] = true end end
    if L.sourceSpecificIgnoreList then for k in pairs(L.sourceSpecificIgnoreList) do fullIgnoreList[k] = true end end
    
    local itemIgnoreCache = {}
    
    local stats = {
        blacklist = 0, zeroCoord = 0, ignored = 0, prefix = 0, 
        forbidden = 0, coa = 0, vendorDeadzones = 0, 
        msMigrated = 0, msInvalidSrc = 0, vendorsFixed = 0,
        
        invalidZoneCombo = 0
    }
    
    local vendorsByZone = {}
    if vendors then
        for g, v in pairs(vendors) do
            if not v.vendorType then
                if g:find("MS%-", 1, true) then v.vendorType = "MS"
                elseif g:find("BM%-", 1, true) then v.vendorType = "BM"
                elseif g:find("EX%-", 1, true) then v.vendorType = "EX"
                elseif g:find("RING%-", 1, true) then v.vendorType = "RING"
                elseif v.i then
                    local id = tonumber(v.i) or 0
                    if id >= -399999 and id <= -300000 then v.vendorType = "BM"
                    elseif id >= -499999 and id <= -400000 then v.vendorType = "MS"
                    else v.vendorType = "UNK" end
                else
                    v.vendorType = "UNK"
                end
                stats.vendorsFixed = stats.vendorsFixed + 1
                L.DataHasChanged = true
            end

            if Constants and Constants.IsForbiddenZone and Constants:IsForbiddenZone(v.c, v.z, v.fp) then
                vendors[g] = nil
                L:SendMessage("LootCollector_DiscoveriesUpdated", "remove", g, nil)
            elseif isCoA and v.vendorType == "MS" then
                vendors[g] = nil
                L:SendMessage("LootCollector_DiscoveriesUpdated", "remove", g, nil)
            else
                local zKey = tostring(v.c)..":"..tostring(v.z)..":"..tostring(v.iz or 0)
                if not vendorsByZone[zKey] then vendorsByZone[zKey] = {} end
                table.insert(vendorsByZone[zKey], v)
            end
        end
    end

    local guidsToRemove = {}

    local function normalizeName(name)
        local n = L.normalizeSenderName and L:normalizeSenderName(name) or name
        return n and string.lower(n) or nil
    end

    for guid, d in pairs(discoveries) do
        local removeReason = nil
        
        if not removeReason and d.xy and d.xy.x == 0 and d.xy.y == 0 then
            removeReason = "zeroCoord"
        end
        
        if not removeReason and Constants and Constants.IsForbiddenZone and Constants:IsForbiddenZone(d.c, d.z, d.fp) then
            removeReason = "forbidden"
        end
        
        if not removeReason and d.c and d.z and c_z_toPurge[d.c] and c_z_toPurge[d.c][d.z] then
            removeReason = "prefix"
        end
        
        if not removeReason and d.fp and self:_isFinderOnBlacklist(d.fp, blacklistName) then
            removeReason = "blacklist"
        end
        
        if not removeReason and isCoA and (d.dt == MS_TYPE or d.ist == 6 or d.ist == 7) then
            removeReason = "coa"
        end
        
        
        if not removeReason and d.c and d.z then
            local mapData = ZoneList and ZoneList.MapDataByID and ZoneList.MapDataByID[tonumber(d.z)]
            if mapData and mapData.continentID ~= tonumber(d.c) and tonumber(d.z) <= 2000 then
                removeReason = "invalidZoneCombo"
            end
        end
        
        if not removeReason and d.i then
            if itemIgnoreCache[d.i] == nil then
                local name = (d.il and d.il:match("%[(.+)%]")) or GetItemInfo(d.i)
                itemIgnoreCache[d.i] = (name and fullIgnoreList[name]) and true or false
            end
            if itemIgnoreCache[d.i] then removeReason = "ignored" end
        end
        
        if not removeReason and d.dt == MS_TYPE then
            local zKey = tostring(d.c)..":"..tostring(d.z)..":"..tostring(d.iz or 0)
            local vList = vendorsByZone[zKey]
            if vList then
                for _, v in ipairs(vList) do
                    if v.vendorType == "MS" then
                        local dist = L:ComputeDistance(d.c, d.z, d.xy.x, d.xy.y, v.c, v.z, v.xy and v.xy.x or 0, v.xy and v.xy.y or 0)
                        if dist and dist <= 70 then
                            removeReason = "vendorDeadzones"
                            break
                        end
                    end
                end
            end
            
            if not removeReason then
                local owner = normalizeName(d.o) or normalizeName(d.fp)
                local isTrusted = owner and TRUSTED_OWNERS[owner]
                
                local srcNum = tonumber(d.src)
                if srcNum == nil and type(d.src) == "string" then
                    srcNum = Constants.AcceptedLootSrcMS and Constants.AcceptedLootSrcMS[d.src]
                end
                
                local isValidSrc = false
                if srcNum ~= nil and Constants.AcceptedLootSrcMS then
                    for _, v in pairs(Constants.AcceptedLootSrcMS) do
                        if srcNum == v then isValidSrc = true; break end
                    end
                end
                
                if isTrusted and (srcNum == nil or srcNum == 3) then
                    if d.src ~= SPECIAL_SRC then
                        d.src = SPECIAL_SRC
                        stats.msMigrated = stats.msMigrated + 1
                        L.DataHasChanged = true
                    end
                elseif not isValidSrc then
                    removeReason = "msInvalidSrc"
                end
            end
        end
        
        if removeReason then
            stats[removeReason] = stats[removeReason] + 1
            table.insert(guidsToRemove, guid)
        end
    end
    
    for _, guid in ipairs(guidsToRemove) do
        local d = discoveries[guid]
        if d and d.z then self:RemoveFromZoneIndex(guid, d.z) end
        discoveries[guid] = nil
        L:SendMessage("LootCollector_DiscoveriesUpdated", "remove", guid, nil)
    end
    
    if pTime then L:ProfileStop("Core:RunUnifiedDatabasePass", pTime) end
    return stats
end

local function GetItemClassAbbr(itemLinkOrID)
    local Scanner = L:GetModule("Scanner", true)
    if not Scanner then return "cl" end
    
    local itemID = L:ExtractItemID(itemLinkOrID)
    if not itemID then return "cl" end

    local itemData = Scanner:GetItemData(itemID, type(itemLinkOrID) == "string" and itemLinkOrID or nil)
    local tok = itemData and itemData.classToken
    
    if tok and Constants.CLASS_ABBREVIATIONS[tok] then
        return Constants.CLASS_ABBREVIATIONS[tok]
    end
    return "cl"
end

local function debugPrint(message) return end

local function _lcGetConst(fnName, defaultValue)
    local fn = rawget(_G, fnName)
    if type(fn) == "function" then
        local ok, value = pcall(fn)
        if ok and value ~= nil then
            return value
        end
    end
    return defaultValue
end

local function _lcRoundN(v, n)
    v = tonumber(v) or 0
    local mul = 10 ^ (tonumber(n) or 0)
    return math.floor(v * mul + 0.5) / mul
end

local function _lcFNV1a32(s)
    local pTime = L.ProfileStart and L:ProfileStart() 

    local hash = 2166136261
    for i = 1, #s do
        hash = bit.bxor(hash, string.byte(s, i))
        hash = (hash * 16777619) % 4294967296
    end
    
    if pTime then L:ProfileStop("Core:_lcFNV1a32", pTime) end 
    return hash
end

local function _lcHex32(u)
    local n = tonumber(u) or 0
    local hi = math.floor(n / 65536)
    local lo = n % 65536
    return string.format("%04x%04x", hi, lo)
end

local function _lcIdentityString(tbl)
    return table.concat({
        tostring(tbl.v or 5),
        tostring(tbl.op or "DISC"),
        tostring(tbl.c or 0),
        tostring(tbl.z or 0),
        tostring(tbl.iz or 0),
        tostring(tbl.i or 0),
        string.format("%.4f", tonumber(tbl.x) or 0),
        string.format("%.4f", tonumber(tbl.y) or 0),
        "0",
    }, "|")
end

function L:ExtractItemID(linkOrId)
    if type(linkOrId) == "number" then
        return tonumber(linkOrId)
    end

    if type(linkOrId) == "string" then
        local id = linkOrId:match("item:(%d+)")
        if id then
            return tonumber(id)
        end
    end

    return nil
end

function Core:RunGridBasedAOEClusterBomb()
    local pTime = L.ProfileStart and L:ProfileStart() 
    
    local Constants = L:GetModule("Constants", true)
    if not (Constants and Constants.DISCOVERY_TYPE and Constants.AOETS_PROCESSED_TYPES) then 
        if pTime then L:ProfileStop("Core:RunGridBasedAOEClusterBomb", pTime) end
        return 0 
    end
    
    local discoveries = L:GetDiscoveriesDB()
    if not discoveries then 
        if pTime then L:ProfileStop("Core:RunGridBasedAOEClusterBomb", pTime) end
        return 0 
    end
    
    local CLUSTER_YARDS = 50
    local totalAOERemoved = 0
    local gridLists = {}
    
    
    for guid, d in pairs(discoveries) do
        local dt = d.dt
        if dt and Constants.AOETS_PROCESSED_TYPES[dt] then
            if not (d.c == 1 and d.z == 14) then
                local zKey = tostring(d.c) .. ":" .. tostring(d.z) .. ":" .. tostring(d.iz or 0) .. ":" .. tostring(dt)
                if not gridLists[zKey] then gridLists[zKey] = {} end
                
                
                local gx = math.floor((d.xy.x or 0) * 20) 
                local gy = math.floor((d.xy.y or 0) * 20)
                local gKey = gx .. "_" .. gy
                
                if not gridLists[zKey][gKey] then gridLists[zKey][gKey] = {} end
                table.insert(gridLists[zKey][gKey], d)
            end
        end
    end
    
    
    for zKey, grid in pairs(gridLists) do
        for gKey, cell in pairs(grid) do
            if #cell >= 4 then
                local flagKey = "_processedBomb"
                for i = 1, #cell do
                    local anchor = cell[i]
                    if not anchor[flagKey] then
                        local cluster = { anchor }
                        for j = i + 1, #cell do
                            local neighbor = cell[j]
                            if not neighbor[flagKey] then
                                local dist = L:ComputeDistance(anchor.c, anchor.z, anchor.xy.x, anchor.xy.y, neighbor.c, neighbor.z, neighbor.xy.x, neighbor.xy.y)
                                if dist and dist <= CLUSTER_YARDS then
                                    table.insert(cluster, neighbor)
                                end
                            end
                        end
                        
                        if #cluster >= 4 then
                            for _, pin in ipairs(cluster) do pin[flagKey] = true end
                            local typeStr = (anchor.dt == Constants.DISCOVERY_TYPE.WORLDFORGED) and "WF" or "UNK"
                            local bombName = string.format("LocalClusterBomb_%s_%d_%d", typeStr, anchor.z, math.random(1000, 9999))
                            
                            self:DropAOETombstone(bombName, anchor.c, anchor.z, tonumber(anchor.iz) or 0, anchor.dt, anchor.xy.x, anchor.xy.y, CLUSTER_YARDS, 10)
                            totalAOERemoved = totalAOERemoved + #cluster
                        end
                    end
                end
            end
        end
    end
    
    if pTime then L:ProfileStop("Core:RunGridBasedAOEClusterBomb", pTime) end 
    return totalAOERemoved
end

local function GetClusterRadius(dt)
    local Constants = L:GetModule("Constants", true)
    if not Constants then return 100 end
    if dt == Constants.DISCOVERY_TYPE.MYSTIC_SCROLL then return Constants.CLUSTER_YARDS_MS or 200 end
    if dt == Constants.DISCOVERY_TYPE.BLACKMARKET then return Constants.CLUSTER_YARDS_VEND or 20 end
    return Constants.CLUSTER_YARDS_WF or 100
end

function L:GetDiscoveryMidCoordPrecision()
    local pTime = self.ProfileStart and self:ProfileStart() 

    local prec = tonumber(_lcGetConst("ConstantsGetCoordPrecision", 4)) or 4
    
    if pTime then self:ProfileStop("LootCollector:GetDiscoveryMidCoordPrecision", pTime) end 
    return prec
end

function L:BuildDiscoveryMidPayload(discoveryLike, op)
    local pTime = self.ProfileStart and self:ProfileStart() 

    local coordPrec = self:GetDiscoveryMidCoordPrecision()

    local rawX = discoveryLike and (
        (discoveryLike.xy and discoveryLike.xy.x)
        or discoveryLike.x
    ) or 0

    local rawY = discoveryLike and (
        (discoveryLike.xy and discoveryLike.xy.y)
        or discoveryLike.y
    ) or 0

    local rawItem = discoveryLike and (
        discoveryLike.i
        or discoveryLike.il
    ) or 0

    local payload = {
        v  = 5,
        op = op or "DISC",
        c  = tonumber(discoveryLike and discoveryLike.c) or 0,
        z  = tonumber(discoveryLike and discoveryLike.z) or 0,
        iz = tonumber(discoveryLike and discoveryLike.iz) or 0,
        i  = tonumber(self:ExtractItemID(rawItem)) or 0,
        x  = _lcRoundN(rawX, coordPrec),
        y  = _lcRoundN(rawY, coordPrec),
        t  = tonumber(discoveryLike and (discoveryLike.t0 or discoveryLike.t)) or 0,
    }
    
    if pTime then self:ProfileStop("LootCollector:BuildDiscoveryMidPayload", pTime) end 
    return payload
end

function L:ComputeDiscoveryMid(discoveryLike, op)
    local pTime = self.ProfileStart and self:ProfileStart() 

    local payload = self:BuildDiscoveryMidPayload(discoveryLike, op or "DISC")
    local mid = _lcHex32(_lcFNV1a32(_lcIdentityString(payload)))
    
    if pTime then self:ProfileStop("LootCollector:ComputeDiscoveryMid", pTime) end 
    return mid
end

function L:ComputeCanonicalDiscoveryMid(discoveryLike)
    return self:ComputeDiscoveryMid(discoveryLike, "DISC")
end

local function hasHighPrecisionCoords(x, y)
    local sx, sy = tostring(x or 0), tostring(y or 0)
    local decX = sx:match("%.(%d+)") or ""
    local decY = sy:match("%.(%d+)") or ""
    return #decX >= 4 and #decY >= 4
end

local function FindWorldforgedInZone(continent, zoneID, itemID, db)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if not db then 
        if pTime then L:ProfileStop("Core:FindWorldforgedInZone", pTime) end
        return nil 
    end
    
    if Core.ZoneIndex and Core.ZoneIndex[zoneID] then
        local zoneGUIDs = Core.ZoneIndex[zoneID]
        for _, guid in ipairs(zoneGUIDs) do
            local d = db[guid]
            if d and d.i == itemID and d.c == continent then
                local Constants = L:GetModule("Constants", true)
                if Constants and d.dt == Constants.DISCOVERY_TYPE.WORLDFORGED then
                    if pTime then L:ProfileStop("Core:FindWorldforgedInZone", pTime) end
                    return d
                end
            end
        end
        if pTime then L:ProfileStop("Core:FindWorldforgedInZone", pTime) end
        return nil
    end
    
    for _, d in pairs(db) do
        if d and d.c == continent and d.z == zoneID and d.i == itemID then
            local Constants = L:GetModule("Constants", true)
            if Constants and d.dt == Constants.DISCOVERY_TYPE.WORLDFORGED then
                if pTime then L:ProfileStop("Core:FindWorldforgedInZone", pTime) end
                return d
            end
        end
    end
    
    if pTime then L:ProfileStop("Core:FindWorldforgedInZone", pTime) end 
    return nil
end

local function FindNearbyDiscovery(continent, zoneID, itemID, x, y, db)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if not db then 
        if pTime then L:ProfileStop("Core:FindNearbyDiscovery", pTime) end
        return nil 
    end
    local Constants = L:GetModule("Constants", true)    
    
    if Core.ZoneIndex and Core.ZoneIndex[zoneID] then
        local zoneGUIDs = Core.ZoneIndex[zoneID]
        for _, guid in ipairs(zoneGUIDs) do
            local d = db[guid]
            if d and d.i == itemID and d.c == continent then
                if d.xy then
                    local dist = L:ComputeDistance(continent, zoneID, x, y, d.c, d.z, d.xy.x, d.xy.y)
                    local radius = GetClusterRadius(d.dt)
                    if dist and dist <= radius then
                        if pTime then L:ProfileStop("Core:FindNearbyDiscovery", pTime) end
                        return d
                    end
                end
            end
        end
        if pTime then L:ProfileStop("Core:FindNearbyDiscovery", pTime) end
        return nil
    end

    for _, d in pairs(db) do
        if d and d.c == continent and d.z == zoneID and d.i == itemID then
            if d.xy then
                local dist = L:ComputeDistance(continent, zoneID, x, y, d.c, d.z, d.xy.x, d.xy.y)
                local radius = GetClusterRadius(d.dt)
			    if dist and dist <= radius then
                    if pTime then L:ProfileStop("Core:FindNearbyDiscovery", pTime) end
                    return d
                end
            end
        end
    end
    
    if pTime then L:ProfileStop("Core:FindNearbyDiscovery", pTime) end 
    return nil
end

function Core:IsInsideAOETombstone(c, z, iz, dt, x, y)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if not (L.db and L.db.global and L.db.global.aoeTombstones) then 
        if pTime then L:ProfileStop("Core:IsInsideAOETombstone", pTime) end
        return false 
    end
    
    local tnow = time()
    local tombstones = L.db.global.aoeTombstones
    
    for i = #tombstones, 1, -1 do
        local ts = tombstones[i]
        
        if tnow > (ts.expires or 0) then
            table.remove(tombstones, i)
        else
            if ts.c == c and ts.z == z and ts.iz == iz then
                if ts.dt == 0 or ts.dt == dt then
                    local dist = L:ComputeDistance(c, z, x, y, ts.c, ts.z, ts.x, ts.y)
                    if dist and dist <= (ts.radius or 50) then
                        L._debug("Core-AOE", string.format("Blocked %d inside AOE Tombstone '%s'", dt, tostring(ts.name)))
                        if pTime then L:ProfileStop("Core:IsInsideAOETombstone", pTime) end
                        return true
                    end
                end
            end
        end
    end
    
    if pTime then L:ProfileStop("Core:IsInsideAOETombstone", pTime) end 
    return false
end

function Core:DropAOETombstone(name, c, z, iz, dt, x, y, radiusYards, daysToLive)
    if not (L.db and L.db.global) then return end
    L.db.global.aoeTombstones = L.db.global.aoeTombstones or {}
    
    local expires = time() + ((tonumber(daysToLive) or 10) * 86400)
    
    
    
    local found = false
    for _, ts in ipairs(L.db.global.aoeTombstones) do
        local nameMatch = (ts.name and ts.name == name)
        
        
        local geomMatch = false
        if ts.c == c and ts.z == z and ts.iz == iz and ts.dt == dt then
            
            local dist = L:ComputeDistance(c, z, x, y, ts.c, ts.z, ts.x, ts.y)
            if dist and dist < 0.5 and ts.radius == radiusYards then
                geomMatch = true
            end
        end

        if nameMatch or geomMatch then
            
            ts.name = name 
            ts.c, ts.z, ts.iz, ts.dt = c, z, iz, dt
            ts.x, ts.y = x, y
            ts.radius = radiusYards
            ts.expires = expires
            found = true
            break
        end
    end
    
    if not found then
        table.insert(L.db.global.aoeTombstones, {
            name = name,
            c = c, z = z, iz = iz, dt = dt,
            x = x, y = y,
            radius = radiusYards,
            expires = expires
        })
    end
    
    L._debug("Core-AOE", string.format("AOE Tombstone '%s' dropped at %d:%d (%.4f, %.4f) r=%d", name, z, iz, x, y, radiusYards))
    
    
    local discoveries = L:GetDiscoveriesDB()
    if discoveries then
        local guidsToRemove = {}
        for guid, d in pairs(discoveries) do
            if d.c == c and d.z == z and (tonumber(d.iz) or 0) == iz then
                if dt == 0 or d.dt == dt then
                    local dist = L:ComputeDistance(c, z, x, y, d.c, d.z, d.xy.x, d.xy.y)
                    if dist and dist <= radiusYards then
                        table.insert(guidsToRemove, guid)
                    end
                end
            end
        end
        for _, guid in ipairs(guidsToRemove) do
		  local d = discoveries[guid]
		  if d and d.z then self:RemoveFromZoneIndex(guid, d.z) end
		  discoveries[guid] = nil
		  L:SendMessage("LootCollector_DiscoveriesUpdated", "remove", guid, nil)
	    end
        if #guidsToRemove > 0 then
            L._debug("Core-AOE", string.format("Blast radius annihilated %d existing pins.", #guidsToRemove))
        end
    end
end

function Core:RemoveAOETombstone(name)
    if not (L.db and L.db.global and L.db.global.aoeTombstones) then return end
    
    local tombstones = L.db.global.aoeTombstones
    for i = #tombstones, 1, -1 do
        if tombstones[i].name == name then
            table.remove(tombstones, i)
            L._debug("Core-AOE", "AOE Tombstone removed: " .. name)
            return true
        end
    end
    return false
end

function Core:IsInsideVendorDeadzone(c, z, iz, dt, x, y)
    local pTime = L.ProfileStart and L:ProfileStart() 

    local Constants = L:GetModule("Constants", true)
    if not Constants or dt ~= Constants.DISCOVERY_TYPE.MYSTIC_SCROLL then 
        if pTime then L:ProfileStop("Core:IsInsideVendorDeadzone", pTime) end
        return false 
    end
    
    local vendors = L:GetVendorsDB()
    if not vendors then 
        if pTime then L:ProfileStop("Core:IsInsideVendorDeadzone", pTime) end
        return false 
    end
    
    for guid, v in pairs(vendors) do
        local isMSVendor = (v.vendorType == "MS" or (v.g and v.g:find("MS%-", 1, true)))
        if isMSVendor then
            if v.c == c and v.z == z and (tonumber(v.iz) or 0) == iz then
                local dist = L:ComputeDistance(c, z, x, y, v.c, v.z, v.xy and v.xy.x or 0, v.xy and v.xy.y or 0)
                if dist and dist <= 70 then 
                    L._debug("Core-Deadzone", string.format("Blocked MS inside 70yd Vendor Deadzone '%s'", tostring(v.vendorName)))
                    if pTime then L:ProfileStop("Core:IsInsideVendorDeadzone", pTime) end
                    return true
                end
            end
        end
    end
    
    if pTime then L:ProfileStop("Core:IsInsideVendorDeadzone", pTime) end 
    return false
end

function Core:EnforceDatabaseCap()
    local db = L:GetDiscoveriesDB()
    if not db then return false end
    
    local oldestGuid = nil
    local oldestLs = time() + 99999999
    
    for k, v in pairs(db) do
        
        if v.s ~= "CONFIRMED" then
            local ls = tonumber(v.ls) or 0
            if ls < oldestLs then
                oldestLs = ls
                oldestGuid = k
            end
        end
    end
    
    if oldestGuid then
        local rec = db[oldestGuid]
        if rec and rec.z then
            self:RemoveFromZoneIndex(oldestGuid, rec.z)
        end
        if self._lookupIndicesBuilt and rec and rec.mid then
            self._midIndex[rec.mid] = nil
        end
        
        db[oldestGuid] = nil
        self._dbDiscoveriesCount = math.max(0, (self._dbDiscoveriesCount or 1) - 1)
        
        
        L:SendMessage("LootCollector_DiscoveriesUpdated", "remove", oldestGuid, nil)
        L._debug("Core-Capacity", "Enforced database hard cap (10,000). Removed oldest non-healthy record: " .. oldestGuid)
        return true
    end
    
    L._debug("Core-Capacity", "Database cap reached, but no disposable (non-CONFIRMED) pins found. Allowing temporary overflow.")
    return false
end

function Core:EnforceDatabaseCapBulk()
    local db = L:GetDiscoveriesDB()
    if not db then return 0 end
    
    
    local count = 0
    local disposable = {}
    for k, v in pairs(db) do
        count = count + 1
        
        if v.s ~= "CONFIRMED" then
            table.insert(disposable, { guid = k, ls = tonumber(v.ls) or 0 })
        end
    end
    
    if count <= 10000 then 
        self._dbDiscoveriesCount = count
        return 0 
    end
    
    local excess = count - 10000
    if #disposable == 0 then return 0 end 
    
    
    table.sort(disposable, function(a, b) return a.ls < b.ls end)
    
    local removedCount = 0
    local targetRemovals = math.min(excess, #disposable)
    
    for i = 1, targetRemovals do
        local guid = disposable[i].guid
        local rec = db[guid]
        
        if rec and rec.z then
            self:RemoveFromZoneIndex(guid, rec.z)
        end
        if self._lookupIndicesBuilt and rec and rec.mid then
            self._midIndex[rec.mid] = nil
        end
        
        db[guid] = nil
        removedCount = removedCount + 1
        L:SendMessage("LootCollector_DiscoveriesUpdated", "remove", guid, nil)
    end
    
    self._dbDiscoveriesCount = count - removedCount
    L._debug("Core-Capacity", string.format("Bulk enforcement removed %d old non-healthy pins to respect the 10,000 cap.", removedCount))
    return removedCount
end

local function mergeRecords(a, b)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if not a.il and b.il then a.il = b.il end
    a.ls  = max(tonumber(a.ls) or 0, tonumber(b.ls) or 0)
    local aTs = tonumber(a.st) or 0
    local bTs = tonumber(b.st) or 0
    if bTs > aTs and b.s then
        a.s = b.s
        a.st = bTs
    end
    
    if pTime then L:ProfileStop("Core:mergeRecords", pTime) end 
    return a
end

local QUALITY_HEX = {
    [0] = "605c53", 
    [1] = "ffffff", 
    [2] = "1eff00", 
    [3] = "0070dd", 
    [4] = "a335ee", 
    [5] = "ff8000", 
    [6] = "cbae77", 
    [7] = "e6cc80", 
}

local function EnsureColoredLink(rawLink, quality)
    if not rawLink or type(rawLink) ~= "string" then return rawLink end
    if rawLink:sub(1, 2) == "|c" then return rawLink end
    if rawLink:sub(1, 2) == "|H" then
        local useWCAG = L.db and L.db.profile and L.db.profile.viewer and L.db.profile.viewer.useWCAGColoring
        if useWCAG == nil then useWCAG = true end 

        local hex
        if useWCAG then
            local WCAG_HEX = {
                [0] = "a09c93", 
                [1] = "ffffff", 
                [2] = "1eff00", 
                [3] = "54b2ff", 
                [4] = "c884ff", 
                [5] = "ff8000", 
                [6] = "cbae77", 
                [7] = "e6cc80", 
            }
            hex = WCAG_HEX[tonumber(quality) or -1] or "ffffff"
        else
            local LEGACY_HEX = {
                [0] = "605c53", 
                [1] = "ffffff", 
                [2] = "1eff00", 
                [3] = "0070dd", 
                [4] = "a335ee", 
                [5] = "ff8000", 
                [6] = "cbae77", 
                [7] = "e6cc80", 
            }
            hex = LEGACY_HEX[tonumber(quality) or -1] or "ffffff"
        end
        return "|cff" .. hex .. rawLink .. "|r"
    end
    return rawLink
end

function Core:IsItemFullyCached(itemID)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if not itemID then 
        if pTime then L:ProfileStop("Core:IsItemFullyCached", pTime) end
        return true 
    end
    
    local name, link, quality, _, _, _, _, _, _, texture = GetItemInfo(itemID)
    if not (name and link and texture) then 
        if pTime then L:ProfileStop("Core:IsItemFullyCached", pTime) end
        return false 
    end
    
    if not link:find("^|c") then 
        if pTime then L:ProfileStop("Core:IsItemFullyCached", pTime) end
        return false 
    end
    
    local isFull = quality ~= nil
    if pTime then L:ProfileStop("Core:IsItemFullyCached", pTime) end 
    return isFull
end

local function AnyRecordNeedsNormalization(itemID)
    local pTime = L.ProfileStart and L:ProfileStart() 

    local db = L:GetDiscoveriesDB()
    if not db then 
        if pTime then L:ProfileStop("Core:AnyRecordNeedsNormalization", pTime) end
        return false 
    end
    
    for _, d in pairs(db) do
        if d and d.i == itemID then
            local il = d.il
            if not (type(il) == "string" and il:find("^|c")) then
                if pTime then L:ProfileStop("Core:AnyRecordNeedsNormalization", pTime) end
                return true
            end
        end
    end
    
    if pTime then L:ProfileStop("Core:AnyRecordNeedsNormalization", pTime) end 
    return false
end

function Core:ShouldCacheItem(itemID)
    if not self:IsItemFullyCached(itemID) then return true end
    return AnyRecordNeedsNormalization(itemID)
end

function Core:EnsureDatabaseStructure()
    local pTime = L.ProfileStart and L:ProfileStart() 

    if not (L.db and L.db.profile and L.db.global and L.db.char) then
        if pTime then L:ProfileStop("Core:EnsureDatabaseStructure", pTime) end
        return
    end

    L.db.global.cacheQueue = L.db.global.cacheQueue or {}
    L.db.global.manualCleanupRunCount = L.db.global.manualCleanupRunCount or 0
    L.db.global.autoCleanupPhase = L.db.global.autoCleanupPhase or 0

    if L.db.global.purgeEmbossedState == nil then
        L.db.global.purgeEmbossedState = 0
    end

    if L.db.global.legacyMysticScrollSrcFixV1 == nil then
        L.db.global.legacyMysticScrollSrcFixV1 = false
    end

    L.db.char.looted = L.db.char.looted or {}
    L.db.char.hidden = L.db.char.hidden or {}

    if L.db.profile.autoCache == nil then
        L.db.profile.autoCache = true
    end
    
    if pTime then L:ProfileStop("Core:EnsureDatabaseStructure", pTime) end 
end

function Core:isSB()    
    local pTime = L.ProfileStart and L:ProfileStart() 

    if Core._isSBCached ~= nil then
        if pTime then L:ProfileStop("Core:isSB", pTime) end 
        return Core._isSBCached
    end

    if not XXH_Lua_Lib then
        Core._isSBCached = false
        if pTime then L:ProfileStop("Core:isSB", pTime) end 
        return false
    end

    local Constants = L:GetModule("Constants", true)
    if not Constants then
        Core._isSBCached = false
        if pTime then L:ProfileStop("Core:isSB", pTime) end 
        return false
    end

    local playerName = UnitName("player")
    if not playerName then
        Core._isSBCached = false
        if pTime then L:ProfileStop("Core:isSB", pTime) end 
        return false
    end
    
    local normalizedName = L:normalizeSenderName(playerName)
    if not normalizedName then
        Core._isSBCached = false
        if pTime then L:ProfileStop("Core:isSB", pTime) end 
        return false
    end

    local combined_str = normalizedName .. Constants.HASH_SAP
    local hash_val = XXH_Lua_Lib.XXH32(combined_str, Constants.HASH_SEED)
    local hex_hash = string.format("%08x", hash_val)

    if Constants.rHASH_BLACKLIST and Constants.rHASH_BLACKLIST[hex_hash] then
        Core._isSBCached = true
        if pTime then L:ProfileStop("Core:isSB", pTime) end 
        return true
    end
    
    Core._isSBCached = false
    
    if pTime then L:ProfileStop("Core:isSB", pTime) end 
    return false
end

function Core:FixIncorrectInstanceContinentIDs()
    local pTime = L.ProfileStart and L:ProfileStart() 

    if L.db.global.instanceContinentFixV1 then 
        if pTime then L:ProfileStop("Core:FixIncorrectInstanceContinentIDs", pTime) end
        return 
    end
	if not (L.db and L.db.profile and L.db.profile.hideNonEssential) then
    print("|cff00ff00LootCollector:|r Scanning for instance records with incorrect continent data...")
	end

    local discoveries = L:GetDiscoveriesDB()
    if not (discoveries and next(discoveries)) then
        L.db.global.instanceContinentFixV1 = true
        if pTime then L:ProfileStop("Core:FixIncorrectInstanceContinentIDs", pTime) end
        return
    end

    local guidsToFix = {}
    
    for guid, d in pairs(discoveries) do
        if d and d.iz and tonumber(d.iz) > 0 and d.c and tonumber(d.c) ~= 0 then
            table.insert(guidsToFix, guid)
        end
    end

    if #guidsToFix == 0 and not (L.db and L.db.profile and L.db.profile.hideNonEssential) then
        print("|cff00ff00LootCollector:|r No incorrect instance records found.")
        L.db.global.instanceContinentFixV1 = true
        if pTime then L:ProfileStop("Core:FixIncorrectInstanceContinentIDs", pTime) end
        return
    end

    local guidRemap = {} 
    local fixedCount = 0

    for _, oldGuid in ipairs(guidsToFix) do
        local d = discoveries[oldGuid]
        if d then
            discoveries[oldGuid] = nil
            d.c = 0
            local newGuid = L:GenerateGUID(d.c, d.z, d.iz, d.i, d.xy.x, d.xy.y)
            d.g = newGuid
            discoveries[newGuid] = d
            guidRemap[oldGuid] = newGuid
            fixedCount = fixedCount + 1
            L._debug("Core-Fix", "Corrected instance GUID: " .. oldGuid .. " -> " .. newGuid)
        end
    end
	if fixedCount >0 and not (L.db and L.db.profile and L.db.profile.hideNonEssential) then
    print(string.format("|cff00ff00LootCollector:|r Corrected %d instance records with legacy continent data.", fixedCount))
	end

    local lootedFixedCount = 0
    if L.db and L.db.char and L.db.char.looted then
        local newLooted = {}
        local charFixed = false
        for guid, timestamp in pairs(L.db.char.looted) do
            if guidRemap[guid] then
                newLooted[guidRemap[guid]] = timestamp
                lootedFixedCount = lootedFixedCount + 1
                charFixed = true
            else
                newLooted[guid] = timestamp
            end
        end
        if charFixed then
            L.db.char.looted = newLooted
        end
    end
    
    if lootedFixedCount > 0 then
        print(string.format("|cff00ff00LootCollector:|r Updated %d looted history records to match corrected instance data.", lootedFixedCount))
    end
    
    L.db.global.instanceContinentFixV1 = true
    
    if pTime then L:ProfileStop("Core:FixIncorrectInstanceContinentIDs", pTime) end 
end

function Core:PurgeDiscoveriesFromBlockedPlayers()
    if not (L.db and L.db.profile and L.db.profile.sharing and L.db.profile.sharing.blockList) then
        print("|cffff7f00LootCollector:|r Block list is empty or database is not ready.")
        return 0
    end

    local blockList = L.db.profile.sharing.blockList
    if not next(blockList) then
        print("|cffff7f00LootCollector:|r Block list is empty. Nothing to purge.")
        return 0
    end

    local discoveries = L:GetDiscoveriesDB()
    if not discoveries then return 0 end
    
    local guidsToRemove = {}
    
    for guid, d in pairs(discoveries) do
        if d and d.fp then
            local fpName = L:normalizeSenderName(d.fp)
            if fpName and blockList[fpName] then
                table.insert(guidsToRemove, guid)
            end
        end
    end
    
    local removedCount = #guidsToRemove
    if removedCount > 0 then
        for _, guid in ipairs(guidsToRemove) do
            local d = discoveries[guid]
            if d and d.z then self:RemoveFromZoneIndex(guid, d.z) end
            discoveries[guid] = nil
            L:SendMessage("LootCollector_DiscoveriesUpdated", "remove", guid, nil)
        end
        print(string.format("|cff00ff00LootCollector:|r Purged %d discoveries from blocked players.", removedCount))
        local Map = L:GetModule("Map", true)
        if Map and Map.Update and WorldMapFrame and WorldMapFrame:IsShown() then
            Map:Update()
        end
    else
        print("|cff00ff00LootCollector:|r No discoveries found from players on your block list.")
    end

    return removedCount
end

function Core:InvalidateLookupIndices()
    self._lookupIndicesBuilt = false
    if self._midIndex then wipe(self._midIndex) end
end

local PURGE_VERSION = "EmbossedScroll_v1"
function Core:PurgeEmbossedScrolls()
    if L.db.global.purgeEmbossedState == 2 then
        return
    end

    local purgeState = L.db.global.purgeEmbossedState or 0
    local discoveries = L:GetDiscoveriesDB()
    if not discoveries then return end

    local guidsToProcess = {}
    local processedCount = 0

    for guid, d in pairs(discoveries) do
        if d then
            local name
            local itemID = d.i or L:ExtractItemID(d.il)
            if d.il then
                name = d.il:match("%[(.+)%]")[1]
            end
            if not name and itemID then
                name = GetItemInfo(itemID)
            end
            if name and string.find(name, "Embossed Mystic Scroll", 1, true) then
                table.insert(guidsToProcess, guid)
            end
        end
    end

    processedCount = #guidsToProcess

    if purgeState == 0 then
        for _, guid in ipairs(guidsToProcess) do discoveries[guid] = nil end
        if processedCount > 0 then
            print(string.format("|cff00ff00LootCollector:|r Removed %d 'Embossed Mystic Scroll' entries from the database.", processedCount))
        end
        L.db.global.purgeEmbossedState = 1
    elseif purgeState == 1 then
        if processedCount == 0 then
            L.db.global.purgeEmbossedState = 2
        else
            print("|cffff7f00LootCollector:|r Verification failed! Found " .. processedCount .. " 'Embossed Mystic Scroll' entries that should have been deleted. The cleanup will run again on next login.")
        end
    end
end

function Core:RemapLootedHistoryV6()
    if not (L.db and L.db.char and not L.db.char.looted_remapped_v6) then
        return
    end
    
    local discoveries = L:GetDiscoveriesDB()
    if not (discoveries and next(discoveries) and next(L.db.char.looted)) then
        L.db.char.looted_remapped_v6 = true
        return
    end

    local wfLookup = {}
    local Constants = L:GetModule("Constants", true)
    if Constants and Constants.DISCOVERY_TYPE then
        for guid, d in pairs(discoveries) do
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

    local newLooted = {}
    local remappedCount = 0
    for oldGuid, timestamp in pairs(L.db.char.looted) do
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
    
    L.db.char.looted = newLooted
    
    if remappedCount > 0 then
        print(string.format("|cff00ff00LootCollector:|r Automatically updated %d looted records to match the new database format.", remappedCount))
    end

    L.db.char.looted_remapped_v6 = true
end

function Core:DeduplicateItems(mysticScrollsKeepOldest)
    local pTime = L.ProfileStart and L:ProfileStart() 

    local startTime = debugprofilestop()
    L._debug("Deduplicator", "Starting dynamic deduplication pass...")

    local discoveries = L:GetDiscoveriesDB()
    if not discoveries then 
        if pTime then L:ProfileStop("Core:DeduplicateItems", pTime) end
        return 0, 0, 0 
    end

    local groups = {}
    for guid, d in pairs(discoveries) do
        if d and d.i and d.z and d.c ~= nil then
            local key = d.c .. ":" .. d.z .. ":" .. d.i
            groups[key] = groups[key] or {}
            table.insert(groups[key], d)
        end
    end

    local guidsToRemove = {}
    local wfRemoved, msRemoved, refinedCount = 0, 0, 0
    local Constants = L:GetModule("Constants", true)

    for key, group in pairs(groups) do
        if #group > 1 then
            local isMS = Constants and group[1].dt == Constants.DISCOVERY_TYPE.MYSTIC_SCROLL
            local isWF = Constants and group[1].dt == Constants.DISCOVERY_TYPE.WORLDFORGED

            if isWF then
                table.sort(group, function(a, b)
                    local amc, bmc = tonumber(a.mc) or 1, tonumber(b.mc) or 1
                    if amc ~= bmc then return amc > bmc end
                    return (tonumber(a.ls) or 0) > (tonumber(b.ls) or 0)
                end)

                local anchor = group[1]
                for i = 2, #group do
                    local d = group[i]
                    
                    if L.db and L.db.char and L.db.char.looted and L.db.char.looted[d.g] then
                        L.db.char.looted[anchor.g] = L.db.char.looted[d.g]
                    end
                    
                    anchor.mc = (anchor.mc or 1) + (d.mc or 1)
                    if d.fp_votes then
                        anchor.fp_votes = anchor.fp_votes or {}
                        for voter, vData in pairs(d.fp_votes) do
                            if not anchor.fp_votes[voter] then
                                anchor.fp_votes[voter] = vData
                            else
                                anchor.fp_votes[voter].score = anchor.fp_votes[voter].score + vData.score
                            end
                        end
                    end
                    
                    if anchor.xy and d.xy then
                        local oldX, oldY = anchor.xy.x, anchor.xy.y
                        anchor.xy.x = L:Round4((oldX * 0.8) + (d.xy.x * 0.2))
                        anchor.xy.y = L:Round4((oldY * 0.8) + (d.xy.y * 0.2))
                        
                        if oldX ~= anchor.xy.x or oldY ~= anchor.xy.y then
                            refinedCount = refinedCount + 1
                        end
                    end
                    
                    table.insert(guidsToRemove, d.g)
                    wfRemoved = wfRemoved + 1
                end

            else
                table.sort(group, function(a, b)
                    local aTs = tonumber(isMS and a.t0 or a.ls) or 0
                    local bTs = tonumber(isMS and b.t0 or b.ls) or 0
                    if isMS and mysticScrollsKeepOldest then return aTs < bTs else return aTs > bTs end
                end)

                local anchors = {}
                local radius = isMS and (Constants.CLUSTER_YARDS_MS or 85) or 40

                for _, d in ipairs(group) do
                    local x, y = d.xy and d.xy.x or 0, d.xy and d.xy.y or 0
                    local isDuplicate = false

                    for _, anchor in ipairs(anchors) do
                        local ax, ay = anchor.xy and anchor.xy.x or 0, anchor.xy and anchor.xy.y or 0
                        local dist = L:ComputeDistance(d.c, d.z, x, y, anchor.c, anchor.z, ax, ay)
                        
                        if dist and dist <= radius then
                            isDuplicate = true
                            
                            if L.db and L.db.char and L.db.char.looted and L.db.char.looted[d.g] then
                                L.db.char.looted[anchor.g] = L.db.char.looted[d.g]
                            end
                            anchor.mc = (anchor.mc or 1) + (d.mc or 1)
                            
                            local a_ls = tonumber(anchor.ls) or 0
                            local d_ls = tonumber(d.ls) or 0
                            if d_ls > a_ls then anchor.ls = d_ls end
                            
                            if d.fp_votes then
                                anchor.fp_votes = anchor.fp_votes or {}
                                for voter, vData in pairs(d.fp_votes) do
                                    if not anchor.fp_votes[voter] then anchor.fp_votes[voter] = vData
                                    else anchor.fp_votes[voter].score = anchor.fp_votes[voter].score + vData.score end
                                end
                            end
                            
                            if anchor.xy and d.xy then
                                local oldX, oldY = anchor.xy.x, anchor.xy.y
                                anchor.xy.x = L:Round4((oldX * 0.8) + (d.xy.x * 0.2))
                                anchor.xy.y = L:Round4((oldY * 0.8) + (d.xy.y * 0.2))
                                
                                if oldX ~= anchor.xy.x or oldY ~= anchor.xy.y then
                                    refinedCount = refinedCount + 1
                                end
                            end
                            
                            break
                        end
                    end

                    if isDuplicate then
                        table.insert(guidsToRemove, d.g)
                        if isMS then msRemoved = msRemoved + 1 end
                    else
                        table.insert(anchors, d)
                    end
                end
            end
        end
    end

    if #guidsToRemove > 0 then
        for _, guid in ipairs(guidsToRemove) do 
            local d = discoveries[guid]
            if d and d.z then
                self:RemoveFromZoneIndex(guid, d.z)
            end
            discoveries[guid] = nil 
        end
    end
    
    L._debug("Deduplicator", string.format("Completed in %.2f ms. Removed %d WF, %d MS. Refined %d coords.", debugprofilestop() - startTime, wfRemoved, msRemoved, refinedCount))
    
    if pTime then L:ProfileStop("Core:DeduplicateItems", pTime) end 
    return wfRemoved, msRemoved, refinedCount
end

function Core:DeduplicateVendorsPerZone()
    local pTime = L.ProfileStart and L:ProfileStart() 

    local vendors = L:GetVendorsDB()
    if not vendors then 
        if pTime then L:ProfileStop("Core:DeduplicateVendorsPerZone", pTime) end
        return 0 
    end
    
    local Constants = L:GetModule("Constants", true)
    local CLUSTER_YARDS = Constants and Constants.CLUSTER_YARDS_VEND or 20
    local vendorGroups = {}
    
    for guid, d in pairs(vendors) do
        if d and d.vendorName and d.vendorType then
            local key = string.format("%d:%d:%s:%s", d.c or 0, d.z or 0, d.vendorName, d.vendorType)
            vendorGroups[key] = vendorGroups[key] or {}
            table.insert(vendorGroups[key], guid)
        end
    end
    
    local guidsToRemove = {}
    local mergedCount = 0
    
    for _, guids in pairs(vendorGroups) do
        if #guids > 1 then
            table.sort(guids, function(a, b)
                local aTime = tonumber(vendors[a].ls) or 0
                local bTime = tonumber(vendors[b].ls) or 0
                return aTime > bTime
            end)
            
            local i = 1
            while i <= #guids do
                local keepGuid = guids[i]
                local keepVendor = vendors[keepGuid]
                local keepX = keepVendor.xy and L:Round4(keepVendor.xy.x) or 0
                local keepY = keepVendor.xy and L:Round4(keepVendor.xy.y) or 0
                
                local j = i + 1
                while j <= #guids do
                    local checkGuid = guids[j]
                    local checkVendor = vendors[checkGuid]
                    local checkX = checkVendor.xy and L:Round4(checkVendor.xy.x) or 0
                    local checkY = checkVendor.xy and L:Round4(checkVendor.xy.y) or 0
                    
                    local dist = L:ComputeDistance(keepVendor.c, keepVendor.z, keepX, keepY, checkVendor.c, checkVendor.z, checkX, checkY)
                    
                    if dist and dist <= CLUSTER_YARDS then
                        if checkVendor.vendorItems and #checkVendor.vendorItems > 0 then
                            keepVendor.vendorItems = keepVendor.vendorItems or {}
                            local itemLookup = {}
                            for _, item in ipairs(keepVendor.vendorItems) do
                                if item.itemID then itemLookup[item.itemID] = true end
                            end
                            
                            for _, item in ipairs(checkVendor.vendorItems) do
                                if item.itemID and not itemLookup[item.itemID] then
                                    table.insert(keepVendor.vendorItems, item)
                                    itemLookup[item.itemID] = true
                                end
                            end
                        end
                        
                        keepVendor.mc = (tonumber(keepVendor.mc) or 1) + 1
                        
                        table.insert(guidsToRemove, checkGuid)
                        table.remove(guids, j)
                        mergedCount = mergedCount + 1
                    else
                        j = j + 1
                    end
                end
                i = i + 1
            end
        end
    end
    
    if #guidsToRemove > 0 then
        for _, guid in ipairs(guidsToRemove) do
            local v = vendors[guid]
            if v and v.z then
                self:RemoveFromZoneIndex(guid, v.z)
            end
            vendors[guid] = nil
            L:SendMessage("LootCollector_DiscoveriesUpdated", "remove", guid, nil)
        end
    end
    
    if pTime then L:ProfileStop("Core:DeduplicateVendorsPerZone", pTime) end 
    return mergedCount
end

function Core:_isFinderOnBlacklist(name, listName)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if not name or name == "" or not XXH_Lua_Lib or not listName then 
        if pTime then L:ProfileStop("Core:_isFinderOnBlacklist", pTime) end
        return false 
    end
    
    self._finderBlacklistCache[listName] = self._finderBlacklistCache[listName] or {}
    local cache = self._finderBlacklistCache[listName]
    
    
    if cache[name] ~= nil then
        if pTime then L:ProfileStop("Core:_isFinderOnBlacklist", pTime) end
        return cache[name]
    end

    local Constants = L:GetModule("Constants", true)
    if not Constants or not Constants[listName] then 
        if pTime then L:ProfileStop("Core:_isFinderOnBlacklist", pTime) end
        return false 
    end

    local blacklist = Constants[listName]
    local normalizedName = L:normalizeSenderName(name)
    if not normalizedName then 
        cache[name] = false
        if pTime then L:ProfileStop("Core:_isFinderOnBlacklist", pTime) end
        return false 
    end
    
    local combined_str = normalizedName .. Constants.HASH_SAP
    local hash_val = XXH_Lua_Lib.XXH32(combined_str, Constants.HASH_SEED)
    local hex_hash = string.format("%08x", hash_val)

    local isBlocked = blacklist[hex_hash] == true
    cache[name] = isBlocked  
    
    if pTime then L:ProfileStop("Core:_isFinderOnBlacklist", pTime) end 
    return isBlocked
end

function Core:FixLegacyVendorQuality()
    if L.db.global.legacyVendorQualityFixV1 then return end
    
    local vendors = L:GetVendorsDB()
    if not vendors then
        L.db.global.legacyVendorQualityFixV1 = true
        return
    end
    
    local count = 0
    for guid, v in pairs(vendors) do
        if v and (v.q ~= 7) then
            v.q = 7
            count = count + 1
        end
    end
    
    if count > 0 and not (L.db and L.db.profile and L.db.profile.hideNonEssential) then
        print(string.format("|cff00ff00LootCollector:|r Repaired %d existing Specialty Vendor records in database to Heirloom quality.", count))
        L.DataHasChanged = true
    end
    
    L.db.global.legacyVendorQualityFixV1 = true
end

function Core:PurgeInvalidMysticScrolls()
    local _, removedCount = self:RunLegacyMysticScrollSourceMigration()
    return removedCount
end

function Core:IsConfirmedCoARealm()
    local Constants = L:GetModule("Constants", true)
    if not Constants then return false end

    local activeType = Constants:GetActiveRealmType()
    if activeType ~= "COA" then return false end

    
    local p = L.db and L.db.profile
    if p and p.featureOverrides and p.featureOverrides.realmType == "COA" then
        return true
    end

    local realmName = GetRealmName() or ""
    if string.find(realmName, "Vol'jin") or string.find(realmName, "CoA") then
        return true
    end

    return false
end

function Core:RunManualDatabaseCleanup()
    print("|cff00ff00LootCollector:|r Starting manual database cleanup...")

    local stats = self:RunUnifiedDatabasePass("rHASH_BLACKLIST")

    if stats.blacklist > 0 then print(string.format("|cff00ff00LootCollector:|r Purged %d entries from restricted finders.", stats.blacklist)) end
    if stats.zeroCoord > 0 then print(string.format("|cff00ff00LootCollector:|r Purged %d entries with 0,0 coordinates.", stats.zeroCoord)) end
    if stats.ignored > 0 then print(string.format("|cff00ff00LootCollector:|r Purged %d entries matching internal ignore lists.", stats.ignored)) end
    if stats.prefix > 0 then print(string.format("|cff00ff00LootCollector:|r Purged %d entries from specific zone GUIDs.", stats.prefix)) end
    if stats.forbidden > 0 then print(string.format("|cff00ff00LootCollector:|r Purged %d entries found in forbidden/city zones.", stats.forbidden)) end
    if stats.coa > 0 then print(string.format("|cff00ff00LootCollector:|r Purged %d incompatible entries (Mystic Scrolls/Librams/Idols) for CoA realm.", stats.coa)) end
    if stats.vendorDeadzones > 0 then print(string.format("|cff00ff00LootCollector:|r Purged %d Mystic Scrolls found near MS Vendors.", stats.vendorDeadzones)) end
    if stats.msMigrated > 0 then print(string.format("|cff00ff00LootCollector:|r Converted %d trusted legacy Mystic Scroll entries to specialobject source.", stats.msMigrated)) end
    if stats.msInvalidSrc > 0 then print(string.format("|cff00ff00LootCollector:|r Purged %d Mystic Scroll entries with invalid legacy sources.", stats.msInvalidSrc)) end
    if stats.vendorsFixed > 0 then print(string.format("|cff00ff00LootCollector:|r Repaired %d vendor entries missing 'vendorType' tags.", stats.vendorsFixed)) end
    
    if stats.invalidZoneCombo > 0 then print(string.format("|cff00ff00LootCollector:|r Purged %d discoveries with invalid Continent-Zone combinations.", stats.invalidZoneCombo)) end

    local vendorsMerged = self:DeduplicateVendorsPerZone()
    if vendorsMerged > 0 then print(string.format("|cff00ff00LootCollector:|r Merged %d duplicate vendor entries.", vendorsMerged)) end
    
    local totalAOERemoved = self:RunGridBasedAOEClusterBomb()
    if totalAOERemoved > 0 then print(string.format("|cff00ff00LootCollector:|r Obliterated %d corrupted items via Cluster Bomb deadzones.", totalAOERemoved)) end

    local wfRemoved, msRemoved, refinedCount = self:DeduplicateItems(true)
    if wfRemoved > 0 then print(string.format("|cff00ff00LootCollector:|r Removed %d duplicate Worldforged entries, keeping the most recent.", wfRemoved)) end
    if msRemoved > 0 then print(string.format("|cff00ff00LootCollector:|r Removed %d duplicate Mystic Scroll entries, keeping the oldest.", msRemoved)) end
    if refinedCount > 0 then print(string.format("|cff00ff00LootCollector:|r Refined map coordinates for %d discoveries via EMA cluster-merging.", refinedCount)) end

    local capRemoved = self:EnforceDatabaseCapBulk()
    if capRemoved > 0 then print(string.format("|cff00ff00LootCollector:|r Database hard cap enforced. Removed %d old/unconfirmed records.", capRemoved)) end

    L.db.global.manualCleanupRunCount = (L.db.global.manualCleanupRunCount or 0) + 1
    print(string.format("|cffffff00LootCollector:|r Manual cleanup has now been run %d times.", L.db.global.manualCleanupRunCount))

    local totalChanges = vendorsMerged + totalAOERemoved + wfRemoved + msRemoved + capRemoved + 
        stats.blacklist + stats.zeroCoord + stats.ignored + stats.prefix + stats.forbidden + 
        stats.coa + stats.vendorDeadzones + stats.msMigrated + stats.msInvalidSrc + stats.vendorsFixed + stats.invalidZoneCombo

    self:InvalidateLookupIndices()

    if totalChanges == 0 then
        print("|cff00ff00LootCollector:|r No items needed purging or deduplication.")
    else
        print("|cff00ff00LootCollector:|r Manual cleanup complete.")
        local Map = L:GetModule("Map", true)
        if Map then
            Map.cacheIsDirty = true
            if Map.Update and WorldMapFrame and WorldMapFrame:IsShown() then Map:Update() end
            if Map.UpdateMinimap then Map:UpdateMinimap() end
        end
    end
end

function Core:RunAutomaticOnLoginCleanup()
    local pTime = L.ProfileStart and L:ProfileStart() 

    local stats = self:RunUnifiedDatabasePass("rHASH_BLACKLIST")
    local vendorsMerged = self:DeduplicateVendorsPerZone()
    local totalAOERemoved = self:RunGridBasedAOEClusterBomb()
    local wfRemoved, msRemoved, refinedCount = self:DeduplicateItems(true)
    local capRemoved = self:EnforceDatabaseCapBulk()

    local totalRemoved = capRemoved + totalAOERemoved + stats.blacklist + stats.zeroCoord + stats.ignored + stats.prefix + stats.forbidden + stats.coa + stats.vendorDeadzones + stats.msInvalidSrc + stats.invalidZoneCombo
    
    self:InvalidateLookupIndices()

    if totalRemoved + wfRemoved + msRemoved + vendorsMerged + stats.msMigrated + refinedCount + stats.vendorsFixed > 0 then
        if not (L.db and L.db.profile and L.db.profile.hideNonEssential) then
            print(string.format(
                "|cff00ff00LootCollector:|r Routine maintenance complete. Purged %d entries. Converted %d legacy. Merged %d vendors. Removed %d WF and %d MS dupes. Refined %d coords. Fixed %d vendor tags.",
                totalRemoved, stats.msMigrated, vendorsMerged, wfRemoved, msRemoved, refinedCount, stats.vendorsFixed
            ))
        end

        local Map = L:GetModule("Map", true)
        if Map and Map.Update and WorldMapFrame and WorldMapFrame:IsShown() then
            Map:Update()
        end
    end
    
    if pTime then L:ProfileStop("Core:RunAutomaticOnLoginCleanup", pTime) end 
end

function Core:RunInitialCleanup()
    local stats = self:RunUnifiedDatabasePass("iHASH_BLACKLIST")
    local wfRemoved, msRemoved = self:DeduplicateItems(true)

    self:InvalidateLookupIndices()

    local totalRemoved = stats.blacklist + stats.msInvalidSrc + stats.zeroCoord + stats.forbidden + stats.prefix + stats.ignored + stats.invalidZoneCombo

    if totalRemoved + stats.msMigrated + wfRemoved + msRemoved + stats.vendorsFixed > 0 then
        if not (L.db and L.db.profile and L.db.profile.hideNonEssential) then
            print(string.format("|cff00ff00LootCollector:|r Initial cleanup complete. Removed %d blacklist, %d invalid scrolls, converted %d trusted legacy scrolls, %d 0,0, %d city/forbidden, %d prefix, %d ignored, %d WF dupes, %d MS dupes. Fixed %d vendor tags.",
                totalRemoved, stats.msMigrated, stats.msMigrated, stats.zeroCoord, stats.forbidden, stats.prefix, stats.ignored, wfRemoved, msRemoved, stats.vendorsFixed))
        end

        local Map = L:GetModule("Map", true)
        if Map and Map.Update and WorldMapFrame and WorldMapFrame:IsShown() then
            Map:Update()
        end
    end
end

function Core:ConvertLegacyInstanceData()
    local discoveries = L:GetDiscoveriesDB()
    if not (discoveries and next(discoveries)) then return end

    if L.db.global.legacyInstanceConversionV5 then
        return
    end

	if not (L.db and L.db.profile and L.db.profile.hideNonEssential) then
    print("|cff00ff00LootCollector:|r Scanning for and converting ALL legacy instance data (v5). This is a one-time process.")
	end
    
    local ZoneList = L:GetModule("ZoneList", true)
    if not ZoneList then 
        print("|cffff0000LootCollector:|r ZoneList module not available. Cannot perform legacy data conversion.")
        return 
    end

    local guidsToConvert = {}

    local nameToModernMapID = {}
    for mapID, data in pairs(ZoneList.MapDataByID) do
        if data and data.name then nameToModernMapID[data.name] = mapID end
        if data and data.altName then nameToModernMapID[data.altName] = mapID end
        if data and data.altName2 then nameToModernMapID[data.altName2] = mapID end
    end
    
    L._debug("Core-LegacyConvert", "--- SCANNING PHASE (v5) ---")
    for guid, d in pairs(discoveries) do
        if type(d) == "table" and d.iz and ZoneList.InstanceZones[d.iz] then
            local legacyInstanceName = ZoneList.InstanceZones[d.iz]
            local modernMapID = nameToModernMapID[legacyInstanceName]

            if modernMapID then
                if d.z ~= modernMapID then
                    L._debug("Core-LegacyConvert", string.format("Found legacy record for '%s' (GUID: %s). Marked for conversion.", legacyInstanceName, guid))
                    table.insert(guidsToConvert, guid)
                end
            end
        end
    end
    L._debug("Core-LegacyConvert", "--- SCANNING PHASE COMPLETE ---")
    L._debug("Core-LegacyConvert", "Total candidates for conversion: " .. #guidsToConvert)

    if #guidsToConvert == 0 and not (L.db and L.db.profile and L.db.profile.hideNonEssential) then
        print("|cff00ff00LootCollector:|r No legacy instance data found to convert.")
        L.db.global.legacyInstanceConversionV5 = true
        return
    end

    local convertedCount = 0
    local failedCount = 0

    for _, oldGuid in ipairs(guidsToConvert) do
        local d = discoveries[oldGuid]
        if d then
            local legacyInstanceName = ZoneList.InstanceZones[d.iz]
            if legacyInstanceName then
                local modernMapID = nameToModernMapID[legacyInstanceName]
                
                if modernMapID then
                    discoveries[oldGuid] = nil
                    
                    d.c = 0 
                    d.z = modernMapID
                    d.iz = modernMapID
                    
                    local newGuid = L:GenerateGUID(d.c, d.z, d.i, d.xy.x, d.xy.y)
                    d.g = newGuid
                    
                    discoveries[newGuid] = d
                    convertedCount = convertedCount + 1
                    L._debug("Core-LegacyConvert", string.format("Converted '%s' (Old GUID: %s) to modern mapID %d. New GUID: %s", legacyInstanceName, oldGuid, modernMapID, newGuid))
                else
                    failedCount = failedCount + 1
                end
            else
                failedCount = failedCount + 1
            end
        end
    end

    self:InvalidateLookupIndices()

    print(string.format("|cff00ff00LootCollector:|r Legacy instance data conversion complete. Converted: %d, Failed: %d.", convertedCount, failedCount))
    L.db.global.legacyInstanceConversionV5 = true
end

function Core:FixEmptyFinderNames()
    local discoveries = L:GetDiscoveriesDB()
    if not discoveries then return 0 end
    
    local fixedCount = 0
    
    for guid, d in pairs(discoveries) do
        if d and (d.fp == nil or d.fp == "") then
            d.fp = "An Unnamed Collector"
            fixedCount = fixedCount + 1
        end
    end
    
    return fixedCount
end

function Core:FixMissingFpVotes()
    local discoveries = L:GetDiscoveriesDB()
    if not discoveries then return 0 end
    
    local fixedCount = 0
    
    for guid, d in pairs(discoveries) do
        if d and not d.fp_votes then
            d.fp_votes = {}
            if d.fp and d.fp ~= "" and d.t0 then
                d.fp_votes[d.fp] = { score = 1, t0 = d.t0 }
            end
            fixedCount = fixedCount + 1
        end
    end
    
    return fixedCount
end

function Core:FixInvalidContinentIDs()
    if L.db.global.invalidContinentFix_v1 then return end

	if not (L.db and L.db.profile and L.db.profile.hideNonEssential) then
    print("|cff00ff00LootCollector:|r Scanning database for records with invalid continent IDs (c=-1)...")
	end

    local discoveries = L:GetDiscoveriesDB()
    if not (discoveries and next(discoveries)) then
        L.db.global.invalidContinentFix_v1 = true
        return
    end

    local ZoneList = L:GetModule("ZoneList", true)
    if not (ZoneList and ZoneList.MapDataByID) then
        print("|cffff0000LootCollector:|r ZoneList module not ready. Skipping continent fix.")
        return
    end

    local fixedCount = 0
    local guidsToFix = {}
    
    for guid, d in pairs(discoveries) do
        if d and (tonumber(d.c) or 0) == -1 and d.z then
            table.insert(guidsToFix, guid)
        end
    end

    for _, oldGuid in ipairs(guidsToFix) do
        local d = discoveries[oldGuid]
        if d then
            local zInfo = ZoneList.MapDataByID[tonumber(d.z)]
            if zInfo and zInfo.continentID then
                
                discoveries[oldGuid] = nil
                
                d.c = zInfo.continentID
                
                local newGuid = L:GenerateGUID(d.c, d.z, d.i, d.xy.x, d.xy.y)
                d.g = newGuid
                
                discoveries[newGuid] = d
                fixedCount = fixedCount + 1
                
                L._debug("Core-Fix", string.format("Fixed c=-1 -> c=%d for zone %d. Old GUID: %s -> New GUID: %s", d.c, d.z, oldGuid, newGuid))
            end
        end
    end

    if fixedCount > 0 then
        self:InvalidateLookupIndices()
        print(string.format("|cff00ff00LootCollector:|r Repaired %d records with invalid continent IDs.", fixedCount))
        L:SendMessage("LOOTCOLLECTOR_DISCOVERY_LIST_UPDATED")
    end
    
    L.db.global.invalidContinentFix_v1 = true
end

function Core:PerformOnLoginMaintenance()
    local pTime = L.ProfileStart and L:ProfileStart() 

    if self.onLoginCleanupPerformed then 
        if pTime then L:ProfileStop("Core:PerformOnLoginMaintenance", pTime) end
        return 
    end
    self.onLoginCleanupPerformed = true

    local hideMsgs = L.db and L.db.profile and L.db.profile.hideNonEssential

    local fixedFPCount = self:FixEmptyFinderNames()
    if fixedFPCount > 0 and not hideMsgs then
        print(string.format("|cff00ff00LootCollector:|r Repaired %d database entries with missing finder names.", fixedFPCount))
    end

    local fixedVotesCount = self:FixMissingFpVotes()
    if fixedVotesCount > 0 and not hideMsgs then
        print(string.format("|cff00ff00LootCollector:|r Updated %d older records with the new finder consensus system.", fixedVotesCount))
    end
        
    self:FixCorruptedTimestamps()    
    self:FixInvalidContinentIDs()
    self:FixLegacyVendorQuality()

    local phase = L.db.global.autoCleanupPhase or 0
    if phase < 3 then
        if not hideMsgs then
            print(string.format("|cff00ff00LootCollector:|r Performing initial database cleanup (stage %d of 3)...", phase + 1))
        end
        self:RunInitialCleanup()
        L.db.global.autoCleanupPhase = phase + 1
    else
        if not hideMsgs then
            print("|cff00ff00LootCollector:|r Performing routine database maintenance...")
        end
        self:RunAutomaticOnLoginCleanup()
    end

    local currentVersion = L.Version or "0.0.0"
    if L.db.global.lastPurgedInvalidSendersVersion ~= currentVersion then
        if L.db.profile then
            if L.db.profile.invalidSenders then wipe(L.db.profile.invalidSenders) end
            if L.db.profile.sharing and L.db.profile.sharing.blockList then wipe(L.db.profile.sharing.blockList) end
            
            if not hideMsgs then
                print("|cff00ff00LootCollector:|r One-time cleanup: Invalid Senders tracking and Block List have been purged for version " .. currentVersion .. ".")
            end
        end
        L.db.global.lastPurgedInvalidSendersVersion = currentVersion
    end

    self:RemapLootedHistoryV6()
    
    if pTime then L:ProfileStop("Core:PerformOnLoginMaintenance", pTime) end 
end

function Core:IsItemCached(itemID)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if not itemID then 
        if pTime then L:ProfileStop("Core:IsItemCached", pTime) end
        return true 
    end
    local name = GetItemInfo(itemID)
    
    if pTime then L:ProfileStop("Core:IsItemCached", pTime) end 
    return name ~= nil
end

function Core:UpdateItemRecordFromCache(itemID)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if not itemID or type(itemID) ~= "number" or itemID == 0 then 
        if pTime then L:ProfileStop("Core:UpdateItemRecordFromCache", pTime) end
        return false 
    end
    
    if not (L.db and L.db.global) then 
        if pTime then L:ProfileStop("Core:UpdateItemRecordFromCache", pTime) end
        return false 
    end
    
    local Constants = L:GetModule("Constants", true)
    if not Constants then 
        if pTime then L:ProfileStop("Core:UpdateItemRecordFromCache", pTime) end
        return false 
    end
    
    local name, link, quality, _, _, itemType, itemSubType = GetItemInfo(itemID)
    if not (name and link) then 
        if pTime then L:ProfileStop("Core:UpdateItemRecordFromCache", pTime) end
        return false 
    end

    local colored = EnsureColoredLink(link, quality)
    local updated = false
    
    local discoveries = L:GetDiscoveriesDB() or {}
    
    local it = (itemType and Constants.ITEM_TYPE_TO_ID[itemType]) or 0
    local ist = (itemSubType and Constants.ITEM_SUBTYPE_TO_ID[itemSubType]) or 0

    for _, d in pairs(discoveries) do
        if type(d) == "table" and d.i == itemID then
            if d.il ~= colored then d.il = colored; updated = true end
            if not d.q and quality then d.q = quality; updated = true end
            
            if (not d.it or d.it == 0) and it ~= 0 then d.it = it; updated = true end
            if (not d.ist or d.ist == 0) and ist ~= 0 then d.ist = ist; updated = true end

            local abbr = GetItemClassAbbr(colored)
            if abbr and abbr ~= "cl" then
                if d.cl ~= abbr then d.cl = abbr; updated = true end
            elseif not d.cl then
                d.cl = "cl"
            end
        end
    end

    if updated then        
	   local Map = L:GetModule("Map", true)
		if Map then Map.cacheIsDirty = true end
        L.DataHasChanged = true
    end
    
    if name and link then 
        if pTime then L:ProfileStop("Core:UpdateItemRecordFromCache", pTime) end
        return true 
    end
    
    if pTime then L:ProfileStop("Core:UpdateItemRecordFromCache", pTime) end 
    return updated
end

local function SafeCacheItemRequest(itemID)
local pTime = L.ProfileStart and L:ProfileStart() 
    local cacheInitiated = false

    
    if C_AssetQueryService and C_AssetQueryService.TryCacheItem then
        local ok = pcall(C_AssetQueryService.TryCacheItem, itemID)
        if ok then cacheInitiated = true end
    elseif _G.TryCacheItem then
        local ok = pcall(_G.TryCacheItem, itemID)
        if ok then cacheInitiated = true end
    end
    
    
    local wasUpdated = Core:UpdateItemRecordFromCache(itemID)
    
    
    if wasUpdated then
        local name, link = GetItemInfo(itemID)
        if link then
            local Scanner = L:GetModule("Scanner", true)
            if Scanner and Scanner.PreWarmCache then
                Scanner:PreWarmCache(itemID, link)
            end
        end
    elseif not cacheInitiated then
        
        local Scanner = L:GetModule("Scanner", true)
        if Scanner and Scanner.tooltip then
            local ok = pcall(function()
                Scanner.tooltip:SetHyperlink("item:"..itemID)
                Scanner.tooltip:Hide()
            end)
        end
    end
    if pTime then L:ProfileStop("Core:SafeCacheItemRequest", pTime) end 
end

function Core:QueueItemForCaching(itemID)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if not itemID or itemID <= 0 then 
        if pTime then L:ProfileStop("Core:QueueItemForCaching", pTime) end
        return 
    end
    if not itemID or not (L.db and L.db.profile and L.db.profile.autoCache) then 
        if pTime then L:ProfileStop("Core:QueueItemForCaching", pTime) end
        return 
    end
    
    L.db.global.cacheQueue = L.db.global.cacheQueue or {}
    Core._queueSet = Core._queueSet or {}
    
    if not Core._queueSetBuilt or (#L.db.global.cacheQueue == 0 and next(Core._queueSet)) then
        wipe(Core._queueSet)
        for _, id in ipairs(L.db.global.cacheQueue) do
            Core._queueSet[id] = true
        end
        Core._queueSetBuilt = true
    end
    
    if not Core._queueSet[itemID] then
        table.insert(L.db.global.cacheQueue, itemID)
        Core._queueSet[itemID] = true
    end
    
    if pTime then L:ProfileStop("Core:QueueItemForCaching", pTime) end 
end

function Core:_ScanShouldPause()
if L:IsPaused() then return true end
    if PAUSE_IN_COMBAT and (InCombatLockdown() or UnitAffectingCombat("player")) then
        return true
    end
    if PAUSE_WHEN_MOVING and (GetUnitSpeed and GetUnitSpeed("player") or 0) > 0 then
        return true
    end
    return false
end

function Core:_ScanStep_OnUpdate(frame, elapsed)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if not self._scanDb then
        frame:SetScript("OnUpdate", nil)
        frame:Hide()
        if pTime then L:ProfileStop("Core:_ScanStep_OnUpdate", pTime) end
        return
    end

    if self:_ScanShouldPause() then 
        if pTime then L:ProfileStop("Core:_ScanStep_OnUpdate", pTime) end
        return 
    end
    if InCombatLockdown() then 
        if pTime then L:ProfileStop("Core:_ScanStep_OnUpdate", pTime) end
        return 
    end

    local start = GetTime()
    local processed = 0
    local k = self._scanKey
    
    while true do
        k, self._scanVal = next(self._scanDb, k)
        self._scanKey = k
        if not k then
            frame:SetScript("OnUpdate", nil)
            frame:Hide()
            
            if not (L.db and L.db.profile and L.db.profile.hideNonEssential) then
                local msg = string.format("|cff00ff00LootCollector:|r Queued %d items (total queue: %d).", self._scanQueued, #(L.db.global.cacheQueue or {}))
                print(msg)
            end
            
            ScheduleAfter(0.3 + math.random() * 0.4, function()
                Core:EnsureCachePump()
            end)
            
            self._scanDb, self._scanKey, self._scanVal = nil, nil, nil
            self._scanQueued = 0
            
            if pTime then L:ProfileStop("Core:_ScanStep_OnUpdate", pTime) end
            return
        end

        local d = self._scanVal
        local itemID = d and d.i
        
        if itemID and itemID > 0 then
            local fullyCached = self:IsItemFullyCached(itemID)
            local needsNorm = false
            if d.il and type(d.il) == "string" and not d.il:find("^|c") then
                needsNorm = true
            end
            
            if not fullyCached or needsNorm then
                self:QueueItemForCaching(itemID)
                self._scanQueued = (self._scanQueued or 0) + 1
            end
        end

        processed = processed + 1
        if processed >= SCAN_MAX_PER_TICK then break end
    end
    
    if pTime then L:ProfileStop("Core:_ScanStep_OnUpdate", pTime) end 
end

function Core:ScanDatabaseForUncachedItems()
    local pTime = L.ProfileStart and L:ProfileStart() 

    if not (L.db and L.db.profile and L.db.profile.autoCache) then 
        if pTime then L:ProfileStop("Core:ScanDatabaseForUncachedItems", pTime) end
        return 
    end
    
    local db = L:GetDiscoveriesDB() or {}
    self._scanDb, self._scanKey, self._scanVal = db, nil, nil
    self._scanQueued = 0
    
    if not self._scanFrame then
        self._scanFrame = CreateFrame("Frame", "LootCollectorChunkedScanFrame")
    end
    
    self._scanFrame:SetScript("OnUpdate", function(frame, elapsed)
        Core:_ScanStep_OnUpdate(frame, elapsed)
    end)
    self._scanFrame:Show()
    
    if pTime then L:ProfileStop("Core:ScanDatabaseForUncachedItems", pTime) end 
end

function Core:StopCaching()
    if cacheTicker and cacheTicker.Cancel then cacheTicker:Cancel() end
    cacheTicker, cacheActive = nil, false
end

function Core:EnsureCachePump()
    local pTime = L.ProfileStart and L:ProfileStart() 

    if not L.db.profile.autoCache then 
        if pTime then L:ProfileStop("Core:EnsureCachePump", pTime) end
        return 
    end
    
    local queue = L.db.global.cacheQueue
    if not queue or #queue == 0 then 
        if pTime then L:ProfileStop("Core:EnsureCachePump", pTime) end
        return 
    end
    
    if cacheActive and cacheTicker and (not cacheTicker.IsCancelled or not cacheTicker:IsCancelled()) then 
        if pTime then L:ProfileStop("Core:EnsureCachePump", pTime) end
        return 
    end
    
    cacheActive = true
    local Comm = L:GetModule("Comm", true)
    if Comm and not (L.db and L.db.profile and L.db.profile.hideNonEssential) then
        print(string.format("|cffffff00|r Starting cache queue processor (%d items).", #queue))
    end
    
    self:ProcessCacheQueue()
    
    if pTime then L:ProfileStop("Core:EnsureCachePump", pTime) end 
end

function Core:ProcessCacheQueue()
local pTime = L.ProfileStart and L:ProfileStart() 
	local queue = L.db.global.cacheQueue
	Core._queueSet = Core._queueSet or {}
	for _, id in ipairs(queue or {}) do
	    Core._queueSet[id] = true
	end
	
    if L:IsPaused() or not (L.db and L.db.profile and L.db.profile.autoCache) then
        if cacheTicker and cacheTicker.Cancel then cacheTicker:Cancel() end
        cacheTicker, cacheActive = nil, false
        return
    end
    
    if not (L.db and L.db.profile and L.db.profile.autoCache) then
        if cacheTicker and cacheTicker.Cancel then cacheTicker:Cancel() end
        cacheTicker, cacheActive = nil, false
        return
    end
    local queue = L.db.global.cacheQueue
	for _, id in ipairs(L.db.global.cacheQueue or {}) do
		Core._queueSet[id] = true
	end
    if not queue or #queue == 0 then
        if cacheTicker and cacheTicker.Cancel then cacheTicker:Cancel() end
        cacheTicker, cacheActive = nil, false
        local Comm = L:GetModule("Comm", true)
        if Comm and not (L.db and L.db.profile and L.db.profile.hideNonEssential) then
            print("|cffffff00|r Item cache queue is now empty.")
        end
        return
    end

    local itemID = table.remove(queue, 1)
    if itemID then
        if self:ShouldCacheItem(itemID) then
            SafeCacheItemRequest(itemID)
            
            if self:ShouldCacheItem(itemID) then
                cacheTicker = ScheduleAfter(2, function()
                    Core:UpdateItemRecordFromCache(itemID)
                    if Core:ShouldCacheItem(itemID) and L and L.db and L.db.global then
                        table.insert(L.db.global.cacheQueue, itemID)
                    end
                    Core:ProcessCacheQueue()
                end)
                return
            end
        end
    end

    if cacheTicker and cacheTicker.Cancel then cacheTicker:Cancel() end
    if #queue > 0 then
        local delay
        
        if (C_AssetQueryService and C_AssetQueryService.TryCacheItem) or _G.TryCacheItem then
            delay = math.random(50, 70) / 100 
        else
            delay = math.random(CACHE_MIN_DELAY, CACHE_MAX_DELAY) 
        end

        if Core._pumpJitterLeft and Core._pumpJitterLeft > 0 then
		  delay = delay + math.random() * 0.3
		  Core._pumpJitterLeft = Core._pumpJitterLeft - 1
	    end
        cacheTicker = ScheduleAfter(delay, function() Core:ProcessCacheQueue() end)
        cacheActive = true
    else
        cacheTicker, cacheActive = nil, false
    end
    if pTime then L:ProfileStop("Core:ProcessCacheQueue", pTime) end 
end

function Core:OnGetItemInfoReceived(_, itemID)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if itemID then
        self:UpdateItemRecordFromCache(itemID)

        local Map = L:GetModule("Map", true)
        if Map and Map.RefreshPinIconsForItem then
            Map:RefreshPinIconsForItem(itemID)
        end

        local mapTooltip = GameTooltip
        if mapTooltip and mapTooltip:IsShown() and mapTooltip:GetOwner() and mapTooltip:GetOwner():GetParent() == WorldMapButton then
            local _, link = mapTooltip:GetItem()
            local owner = mapTooltip:GetOwner()
            local discovery = owner and owner.discovery
            
            if discovery and tonumber(discovery.i) == tonumber(itemID) then
                L._debug("Core-Cache", "Forcing map tooltip refresh for newly cached item: " .. itemID)
                if IsAltKeyDown() or (discovery.dt and discovery.dt == L:GetModule("Constants", true).DISCOVERY_TYPE.BLACKMARKET) then
                    Map:ShowDiscoveryTooltip(owner)
                else
                    mapTooltip:SetHyperlink(discovery.il or discovery.i)
                end
            end
        end
    end
    
    if pTime then L:ProfileStop("Core:OnGetItemInfoReceived", pTime) end 
end

function Core:ProcessIndexerBatch()
    local pTime = L.ProfileStart and L:ProfileStart() 

    
    if L:IsPaused() then
        ScheduleAfter(2.0, function()
            if self._indexerInProgress then self:ProcessIndexerBatch() end
        end)
        if pTime then L:ProfileStop("Core:ProcessIndexerBatch", pTime) end
        return
    end

    if not (L.db and L.db.global) then 
        if pTime then L:ProfileStop("Core:ProcessIndexerBatch", pTime) end
        return 
    end
    local db = L:GetDiscoveriesDB()
    if not db or not next(db) then 
        self._indexerInProgress = false
        if pTime then L:ProfileStop("Core:ProcessIndexerBatch", pTime) end
        return 
    end

    local processed = 0
    local k = self._indexerNextKey
    local changedCount = 0

    if k ~= nil and db[k] == nil then
        k = nil
    end

    while processed < MID_GEN_CHUNK_SIZE do
        k, v = next(db, k)
        
        if not k then
            self._indexerNextKey = nil
            self._indexerInProgress = false
            if changedCount > 0 then
                L._debug("Core-Indexer", string.format("Index maintenance cycle complete. Generated %d missing identifiers.", changedCount))
            end
            if pTime then L:ProfileStop("Core:ProcessIndexerBatch", pTime) end
            return
        end

        if type(v) == "table" then
            if not v.mid or v.mid == "" then
                v.mid = L:ComputeCanonicalDiscoveryMid(v)
                changedCount = changedCount + 1
                if self._lookupIndicesBuilt then
                    self._midIndex[v.mid] = k
                end
            end
        end

        processed = processed + 1
    end

    self._indexerNextKey = k
    
    ScheduleAfter(INDEXER_TICK_RATE, function()
        if self._indexerInProgress then
            self:ProcessIndexerBatch()
        end
    end)
    
    if pTime then L:ProfileStop("Core:ProcessIndexerBatch", pTime) end 
end

function Core:StartIndexMaintenance()
    local pTime = L.ProfileStart and L:ProfileStart() 

    if self._indexerInProgress then 
        print("|cffff7f00LootCollector:|r Index maintenance is already running.")
        if pTime then L:ProfileStop("Core:StartIndexMaintenance", pTime) end
        return 
    end
    L._debug("Core-Indexer", "Starting background index maintenance...")
    self._indexerInProgress = true
    self._indexerNextKey = nil
    self:ProcessIndexerBatch()
    
    if pTime then L:ProfileStop("Core:StartIndexMaintenance", pTime) end 
end

function Core:OnInitialize()
    if not (L.db and L.db.profile and L.db.global and L.db.char) then return end

    self.onLoginCleanupPerformed = false
    self:EnsureDatabaseStructure()   

    L:RegisterEvent("GET_ITEM_INFO_RECEIVED", function(_, ...)
        Core:OnGetItemInfoReceived(...)
    end)
    
    local INDEX_BATCH_SIZE = 50
    local indexTicker = CreateFrame("Frame")
    indexTicker:SetScript("OnUpdate", function()
        if #Core.IndexQueue > 0 then
            local processed = 0
            while processed < INDEX_BATCH_SIZE and #Core.IndexQueue > 0 do
                local entry = table.remove(Core.IndexQueue, 1)
                local guid, zoneID = entry.g, tonumber(entry.z) or 0
                
                if Core.ZoneIndexBuilt then
                     if not Core.ZoneIndex[zoneID] then Core.ZoneIndex[zoneID] = {} end
                     table.insert(Core.ZoneIndex[zoneID], guid)
                end
                processed = processed + 1
            end
        end
    end)
    
    SLASH_LOOTCOLLECTORCCQ1 = "/lcccq"
    SlashCmdList["LOOTCOLLECTORCCQ"] = function()
        if L.db and L.db.global then
            local queueSize = (L.db.global.cacheQueue and #L.db.global.cacheQueue) or 0
            L.db.global.cacheQueue = {}
            if Core._queueSet then wipe(Core._queueSet) end
            print(string.format("|cff00ff00LootCollector:|r Cleared %d items from the background cache queue.", queueSize))
        else
            print("|cffff7f00LootCollector:|r Database not ready.")
        end
    end
	
	SLASH_LOOTCOLLECTORCZFIX1 = "/lcczfix"
    SlashCmdList["LOOTCOLLECTORCZFIX"] = function()
        if Core.FixLegacyZoneIDs then
            L.db.global.legacyZoneFixV2 = false
            Core:FixLegacyZoneIDs()
        else
             print("|cffff7f00LootCollector:|r Core module not available.")
        end
    end

    ScheduleAfter(8, function()
        local Constants = L:GetModule("Constants", true)
        if Constants then
            print(string.format("|cff00ff00LootCollector %s started.|r Realm capabilities mapped: |cffffff00%s|r mode.", L.Version or "", Constants:GetActiveRealmType()))
        end
	  	 
	  Core:FixIncorrectInstanceContinentIDs()
        Core:ConvertLegacyInstanceData() 
        Core:PurgeEmbossedScrolls()
        Core:PerformOnLoginMaintenance()
        Core:RebuildZoneIndex()       
    end)
    ScheduleAfter(10, function()	        
	  Core:ScanDatabaseForUncachedItems()
        Core:EnsureCachePump() 
    end)
    ScheduleAfter(11, function()	        
        Core:StartIndexMaintenance()
    end)
end

function Core:Qualifies(linkOrQuality)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if type(linkOrQuality) == "number" then 
        if pTime then L:ProfileStop("Core:Qualifies", pTime) end
        return false 
    end
    local link = linkOrQuality
    if not link then 
        if pTime then L:ProfileStop("Core:Qualifies", pTime) end
        return false 
    end

    local name = (select(1, GetItemInfo(link))) or (link:match("%[(.-)%]")) or ""
    if name == "" then 
        if pTime then L:ProfileStop("Core:Qualifies", pTime) end
        return false 
    end
    if L.ignoreList and L.ignoreList[name] then 
        if pTime then L:ProfileStop("Core:Qualifies", pTime) end
        return false 
    end

    local isScroll = string.find(name, "Mystic Scroll", 1, true) ~= nil
    
    local itemID = L:ExtractItemID(link)
    local isWorldforged = false
    
    if itemID then
        local Scanner = L:GetModule("Scanner", true)
        local itemData = Scanner and Scanner:GetItemData(itemID, link)
        if itemData and itemData.isWF then
            isWorldforged = true
        end
    end

    if pTime then L:ProfileStop("Core:Qualifies", pTime) end 
    return isWorldforged or isScroll
end

function Core:HandleLocalLoot(discovery)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if not discovery or type(discovery) ~= "table" then
        if pTime then L:ProfileStop("Core:HandleLocalLoot", pTime) end
        return
    end

    local Constants = L:GetModule("Constants", true)
    
    
    local infoTarget = discovery.il or discovery.i
    if not infoTarget then 
        if pTime then L:ProfileStop("Core:HandleLocalLoot", pTime) end
        return 
    end

    local name, link, quality, _, _, itemType, itemSubType = GetItemInfo(infoTarget)
    local itemID = discovery.i
    if not itemID then
        if link then
            itemID = L:ExtractItemID(link)
        elseif discovery.il and type(discovery.il) == "string" then
            itemID = L:ExtractItemID(discovery.il)
        end
    end
    
    itemID = tonumber(itemID) or 0
    if itemID == 0 then 
        if pTime then L:ProfileStop("Core:HandleLocalLoot", pTime) end
        return 
    end
    discovery.i = itemID
    
    local dt = discovery.dt
    if not dt then 
        local cachedName = name
        if not cachedName and discovery.il and type(discovery.il) == "string" then
            cachedName = discovery.il:match("%[(.-)%]")
        end
        if cachedName then
            if string.find(cachedName, "Mystic Scroll", 1, true) then
                dt = Constants.DISCOVERY_TYPE.MYSTIC_SCROLL
            else
                dt = Constants.DISCOVERY_TYPE.WORLDFORGED
            end
        end
    end
    discovery.dt = dt
    

    if Constants and Constants.IsForbiddenZone then
        if Constants:IsForbiddenZone(discovery.c, discovery.z, discovery.fp) then
            L._debug("Core-Block", "Blocked local discovery from a forbidden zone: " .. tostring(discovery.il))
            if pTime then L:ProfileStop("Core:HandleLocalLoot", pTime) end
            return
        end
    end
    
    if Core:IsInsideAOETombstone(discovery.c, discovery.z, discovery.iz, discovery.dt, discovery.xy and discovery.xy.x or 0, discovery.xy and discovery.xy.y or 0) then
	    L._debug("Core-Block", "Blocked local discovery from tombstone area: " .. tostring(discovery.il))
        if pTime then L:ProfileStop("Core:HandleLocalLoot", pTime) end
        return
    end
    
    if Core:IsInsideVendorDeadzone(discovery.c, discovery.z, discovery.iz, discovery.dt, discovery.xy and discovery.xy.x or 0, discovery.xy and discovery.xy.y or 0) then
        L._debug("Core-Block", "Blocked local discovery near Mystic Scroll vendor: " .. tostring(discovery.il))
        if pTime then L:ProfileStop("Core:HandleLocalLoot", pTime) end
        return
    end
    
    if not (L and L.db and L.db.global) or not Constants then
        if pTime then L:ProfileStop("Core:HandleLocalLoot", pTime) end
        return
    end

    local isVendorDiscovery = (dt == Constants.DISCOVERY_TYPE.BLACKMARKET) or (discovery.vendorType and (discovery.vendorType == "MS" or discovery.vendorType == "BM"))
    
    if dt and Constants.ALLOWED_DISCOVERY_TYPES then
        if Constants.ALLOWED_DISCOVERY_TYPES[dt] == false then
            if pTime then L:ProfileStop("Core:HandleLocalLoot", pTime) end
            return
        end
    end

	if isVendorDiscovery then
        if not dt then
            dt = Constants.DISCOVERY_TYPE.BLACKMARKET
            discovery.dt = dt
        end

        local vType = discovery.vendorType
        if not vType then
            local id = tonumber(discovery.i) or 0
            if id >= -499999 and id <= -400000 then vType = "MS" end
        end

        if vType == "MS" and not Constants:HasMysticScrolls() then
            if pTime then L:ProfileStop("Core:HandleLocalLoot", pTime) end
            return
        end
        
        local c = tonumber(discovery.c) or 0
        local z = tonumber(discovery.z) or 0
        local iz = tonumber(discovery.iz) or 0
        local mapID = tonumber(discovery.mapID) or z
        local x = L:Round4(discovery.xy and discovery.xy.x or 0)
        local y = L:Round4(discovery.xy and discovery.xy.y or 0)

        local guid = L:GenerateVendorGUID(vType, c, z, iz, x, y)
        local itemLink

        if vType == "MS" then
            itemID = - (400000 + mapID) 
            itemLink = string.format("|cffa335ee|Hitem:%d:0:0:0:0:0:0:0:0|h[Mystic Scroll Vendor]|h|r", itemID)
        elseif vType == "BM" then
            itemID = - (300000 + mapID)
            itemLink = string.format("|cff663300|Hitem:%d:0:0:0:0:0:0:0:0|h[Blackmarket Supplies]|h|r", itemID)
        else
            itemID = - (500000 + mapID)
            itemLink = string.format("|cffffff00|Hitem:%d:0:0:0:0:0:0:0:0|h[Specialty Vendor]|h|r", itemID)
        end
        
        local bm_db = L:GetVendorsDB()
        if not bm_db then 
            if pTime then L:ProfileStop("Core:HandleLocalLoot", pTime) end
            return 
        end

        local existing = bm_db[guid]
        local recordToBroadcast = nil

        if not existing then
            local newRecord = {
                g = guid, c = c, z = z, iz = iz, i = itemID, 
                il = itemLink,
                xy = { x = x, y = y },
                fp = discovery.fp, o = discovery.fp,
                t0 = discovery.t0, ls = discovery.t0, s = Constants.STATUS.CONFIRMED, st = discovery.t0,
                dt = dt,
		        q = 7,
                vendorType = discovery.vendorType, 
                vendorName = discovery.vendorName,
                vendorItems = discovery.vendorItems,
            }

            newRecord.mid = L:ComputeCanonicalDiscoveryMid(newRecord)
            bm_db[guid] = newRecord
            recordToBroadcast = newRecord
            
            self:AddToZoneIndex(guid, z)
            
            if vType == "MS" then self:PurgeMysticScrollsNearVendors() end
        else
            existing.ls = discovery.t0
            existing.vendorItems = discovery.vendorItems 
            existing.dt = dt
            existing.vendorType = discovery.vendorType
            if not existing.il then existing.il = itemLink end 
            if not existing.mid or existing.mid == "" then existing.mid = L:ComputeCanonicalDiscoveryMid(existing) end
            recordToBroadcast = existing
        end
	  
	    if discovery.vendorItems and self.QueueItemForCaching then
            for _, itemData in ipairs(discovery.vendorItems) do
                if itemData.itemID then
                    self:QueueItemForCaching(itemData.itemID)
                end
            end
        end
        
        L.DataHasChanged = true
        
        if recordToBroadcast then
            local shouldBeShared = (not recordToBroadcast.vendorItems) or (#recordToBroadcast.vendorItems <= 5)
            if shouldBeShared then
                L._debug("Core-Share", "Vendor discovery is eligible for sharing.")
            else
                L._debug("Core-Share", "Vendor discovery has too many items (" .. #recordToBroadcast.vendorItems .. ") and will NOT be shared in real-time.")
            end
        end

        if pTime then L:ProfileStop("Core:HandleLocalLoot", pTime) end
        return 
    end

    local src_numeric = discovery.src
	if type(src_numeric) == "string" then
        local mapped = nil
        if dt == Constants.DISCOVERY_TYPE.MYSTIC_SCROLL then
            mapped = Constants.AcceptedLootSrcMS[src_numeric]
        elseif dt == Constants.DISCOVERY_TYPE.WORLDFORGED then
            mapped = Constants.AcceptedLootSrcWF[src_numeric]
        end
        if mapped ~= nil then
            src_numeric = mapped
        end
    end
    
    local it = (itemType and Constants.ITEM_TYPE_TO_ID[itemType]) or 0
    local ist = (itemSubType and Constants.ITEM_SUBTYPE_TO_ID[itemSubType]) or 0
    local colored = EnsureColoredLink(link, quality)
    local cl = GetItemClassAbbr(colored)
    
    local finderName = discovery.fp or UnitName("player")
    local s_flag = (finderName == "An Unnamed Collector") and 1 or 0
    local payload_fp = (s_flag == 1 and "" or finderName)
    
    local c = tonumber(discovery.c) or 0
    local z = tonumber(discovery.z) or 0
    local iz = tonumber(discovery.iz) or 0
    local x = L:Round4(discovery.xy and tonumber(discovery.xy.x) or 0)
    local y = L:Round4(discovery.xy and tonumber(discovery.xy.y) or 0)
    local t0 = tonumber(discovery.t0) or time()
    
    local db = L:GetDiscoveriesDB()
    if not db then 
        if pTime then L:ProfileStop("Core:HandleLocalLoot", pTime) end
        return 
    end

    local canonicalMid = nil
    local existing, existingGuid = self:FindExistingDiscovery(guid, incomingMid)
    
    if not existing and FindNearbyDiscovery then
        local nearby = FindNearbyDiscovery(d.c, d.z, d.i, d.xy.x, d.xy.y, db)
        if nearby then
            existing = nearby
            existingGuid = nearby.g
            guid = nearby.g
        end
    end
    
    if not rec then
        rec = {
            g = guid, c = c, z = z, iz = iz, i = itemID, il = colored or discovery.il,
            xy = { x = x, y = y },
            fp = finderName, o = finderName,
            t0 = t0, ls = t0, s = Constants.STATUS.UNCONFIRMED, st = t0, cl = cl,
            q = quality or 0, dt = dt, it = it, ist = ist,
            src = src_numeric,
            fp_votes = { [finderName] = { score = 1, t0 = t0 } },
            s_flag = s_flag,		
        }

        rec.mid = L:ComputeCanonicalDiscoveryMid(rec)
        db[guid] = rec
        L:SendMessage("LootCollector_DiscoveriesUpdated", "add", guid, rec)
        
        self:AddToZoneIndex(guid, z)
        
    else
        if not rec or type(rec) ~= "table" then 
            if pTime then L:ProfileStop("Core:HandleLocalLoot", pTime) end
            return 
        end

        discovery.g = rec.g 
        rec.ls = max(tonumber(rec.ls) or 0, t0)        
        
        local oldX = (rec.xy and type(rec.xy) == "table" and rec.xy.x) or 0
        local oldY = (rec.xy and type(rec.xy) == "table" and rec.xy.y) or 0
        local dist = L:ComputeDistance(c, z, x, y, rec.c, rec.z, oldX, oldY)
        
        local radius = GetClusterRadius(rec.dt)
        if dist and dist <= radius and dist > 0.5 then
            L._debug("Core-Refine", "Local loot coordinate refinement via EMA.")
            rec.xy.x = L:Round4((oldX * 0.8) + (x * 0.2))
            rec.xy.y = L:Round4((oldY * 0.8) + (y * 0.2))
        end
        
        if finderName and finderName ~= "" then
            rec.fp_votes = rec.fp_votes or {}
            if not rec.fp_votes[finderName] then
                rec.fp_votes[finderName] = { score = 1, t0 = t0 }
            else
                rec.fp_votes[finderName].score = rec.fp_votes[finderName].score + 1
            end
            self:UpdateConsensusWinner(rec)
        end
        
        if rec.src == nil and src_numeric ~= nil then
            rec.src = src_numeric
        end

        if not rec.mid or rec.mid == "" then rec.mid = L:ComputeCanonicalDiscoveryMid(rec) end
        
        L:SendMessage("LootCollector_DiscoveriesUpdated", "update", rec.g, rec)
    end
    
    if L.db and L.db.char then
        L.db.char.looted = L.db.char.looted or {}
        L.db.char.looted[rec.g] = time()
    end
    
    local Map = L:GetModule("Map", true)
    if Map then Map.cacheIsDirty = true end

    if not self:IsItemCached(itemID) then
        if self.QueueItemForCaching then
            self:QueueItemForCaching(itemID)
        end
    end
    
    L.DataHasChanged = true
    
    local norm = {
        i = itemID, il = colored or discovery.il, q = quality or 1,
        c = c, z = z, iz = iz, xy = { x = x, y = y }, t0 = t0,
        dt = dt, it = it, ist = ist, cl = cl,
        src = src_numeric,
        s = s_flag, fp = payload_fp,
    }
    
    local bufferKey = string.format("%d-%d-%d", c, z, itemID)
    
    if Core.pendingBroadcasts[bufferKey] then
        if Core.pendingBroadcasts[bufferKey].timerHandle then
            Core.pendingBroadcasts[bufferKey].timerHandle.Cancel()
        end
    end
    
    local timerHandle
    timerHandle = ScheduleAfter(1, function()
        local cached = Core:IsItemFullyCached(itemID)
        local remainingDelay = BROADCAST_DELAY - 1
        
        if not cached then
            SafeCacheItemRequest(itemID)
            remainingDelay = remainingDelay - 1
            ScheduleAfter(1, function()
                ScheduleAfter(remainingDelay, function()
                    Core:ExecutePendingBroadcast(bufferKey)
                end)
            end)
        else
            ScheduleAfter(remainingDelay, function()
                Core:ExecutePendingBroadcast(bufferKey)
            end)
        end
    end)
    
    Core.pendingBroadcasts[bufferKey] = {
        discovery = norm,
        timerHandle = timerHandle,
        fireAt = time() + BROADCAST_DELAY,
        cacheChecked = false
    }

    if pTime then L:ProfileStop("Core:HandleLocalLoot", pTime) end 
end

function Core:ExecutePendingBroadcast(bufferKey)
    local pTime = L.ProfileStart and L:ProfileStart() 

    local pending = Core.pendingBroadcasts[bufferKey]
    if not pending then
        if pTime then L:ProfileStop("Core:ExecutePendingBroadcast", pTime) end
        return
    end
    
    local norm = pending.discovery
    local Comm = L:GetModule("Comm", true)
    if Comm and Comm.BroadcastDiscovery then
        Comm:BroadcastDiscovery(norm)
    end
    
    Core.pendingBroadcasts[bufferKey] = nil
    
    if pTime then L:ProfileStop("Core:ExecutePendingBroadcast", pTime) end 
end

function Core:UpdateConsensusWinner(d)
    if not d or not d.fp_votes then return end

    local winner_fp = d.fp
    local max_score = 0
    local min_t0 = 9999999999

    for name, data in pairs(d.fp_votes) do
        if data.score > max_score then
            max_score = data.score
            min_t0 = data.t0
            winner_fp = name
        elseif data.score == max_score then
            if data.t0 < min_t0 then
                min_t0 = data.t0
                winner_fp = name
            end
        end
    end

    if d.fp ~= winner_fp then
        d.fp = winner_fp
    end
end

function Core:HandleCorrection(corr_data)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if not corr_data then 
        if pTime then L:ProfileStop("Core:HandleCorrection", pTime) end
        return 
    end
    
    local db = L:GetDiscoveriesDB()
    local record = FindNearbyDiscovery(corr_data.c, corr_data.z, corr_data.i, 0, 0, db)

    if not record then 
        if pTime then L:ProfileStop("Core:HandleCorrection", pTime) end
        return 
    end
    
    local Comm = L:GetModule("Comm", true)
    local isAU = Comm and Comm.isAU and Comm:isAU(corr_data.sender)
    local voteWeight = isAU and 1000 or 1

    record.fp_votes = record.fp_votes or {}
    local vote = record.fp_votes[corr_data.fp]

    if not vote then
        record.fp_votes[corr_data.fp] = { score = voteWeight, t0 = corr_data.t0 }
    else
        vote.score = vote.score + voteWeight
    end

    self:UpdateConsensusWinner(record)
    
    if pTime then L:ProfileStop("Core:HandleCorrection", pTime) end 
end

function Core:_ResolveZoneDisplay(cx, zx, izx)
    local pTime = L.ProfileStart and L:ProfileStart() 

    local c = tonumber(cx) or 0
    local z = tonumber(zx) or 0
    local iz = tonumber(izx) or 0
    
    local result
    if z == 0 then
        result = (ZoneList and ZoneList.ResolveIz and ZoneList:ResolveIz(iz)) or (GetRealZoneText and GetRealZoneText()) or "Unknown Instance"
    else    
        result = (ZoneList and ZoneList.GetZoneName and ZoneList:GetZoneName(c, z)) or "Unknown Zone"
    end
    
    if pTime then L:ProfileStop("Core:_ResolveZoneDisplay", pTime) end 
    return result
end

function Core:RebuildZoneIndex()
    local pTime = L.ProfileStart and L:ProfileStart() 

    L._debug("Core-Index", "Rebuilding Zone Index...")
    wipe(Core.ZoneIndex)
    wipe(Core.IndexQueue) 
    
    local discoveries = L:GetDiscoveriesDB()
    local dbCount = 0
    
    if discoveries then
        for guid, d in pairs(discoveries) do
            if d and d.z then
                local zoneID = tonumber(d.z) or 0
                if not Core.ZoneIndex[zoneID] then
                    Core.ZoneIndex[zoneID] = {}
                end
                table.insert(Core.ZoneIndex[zoneID], guid)
            end
            dbCount = dbCount + 1
        end
    end
    
    self._dbDiscoveriesCount = dbCount
    
    local vendors = L:GetVendorsDB()
    if vendors then
        for guid, d in pairs(vendors) do
            if d and d.z then
                local zoneID = tonumber(d.z) or 0
                if not Core.ZoneIndex[zoneID] then
                    Core.ZoneIndex[zoneID] = {}
                end
                table.insert(Core.ZoneIndex[zoneID], guid)
            end
        end
    end
    
    Core.ZoneIndexBuilt = true
    L._debug("Core-Index", "Zone Index Rebuilt. Total discoveries: " .. tostring(dbCount))
    
    if pTime then L:ProfileStop("Core:RebuildZoneIndex", pTime) end 
end

function Core:AddToZoneIndex(guid, zoneID)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if not Core.ZoneIndexBuilt then 
        if pTime then L:ProfileStop("Core:AddToZoneIndex", pTime) end
        return 
    end 
    if not guid or not zoneID then 
        if pTime then L:ProfileStop("Core:AddToZoneIndex", pTime) end
        return 
    end
    
    zoneID = tonumber(zoneID) or 0
    if not Core.ZoneIndex[zoneID] then
        Core.ZoneIndex[zoneID] = {}
    end
    
    
    for _, existingGuid in ipairs(Core.ZoneIndex[zoneID]) do
        if existingGuid == guid then
            if pTime then L:ProfileStop("Core:AddToZoneIndex", pTime) end
            return
        end
    end
    
    table.insert(Core.ZoneIndex[zoneID], guid)
    
    if pTime then L:ProfileStop("Core:AddToZoneIndex", pTime) end 
end

function Core:RemoveFromZoneIndex(guid, zoneID)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if not Core.ZoneIndexBuilt then 
        if pTime then L:ProfileStop("Core:RemoveFromZoneIndex", pTime) end
        return 
    end
    if not guid or not zoneID then 
        if pTime then L:ProfileStop("Core:RemoveFromZoneIndex", pTime) end
        return 
    end
    
    zoneID = tonumber(zoneID) or 0
    local list = Core.ZoneIndex[zoneID]
    if not list then 
        if pTime then L:ProfileStop("Core:RemoveFromZoneIndex", pTime) end
        return 
    end
    
    for i, g in ipairs(list) do
        if g == guid then
            local lastIndex = #list
            if i ~= lastIndex then
                list[i] = list[lastIndex]
            end
            table.remove(list)
            if pTime then L:ProfileStop("Core:RemoveFromZoneIndex", pTime) end
            return
        end
    end
    
    if pTime then L:ProfileStop("Core:RemoveFromZoneIndex", pTime) end 
end

local function TriggerReactiveAck(tKey, t)
    local pTime = L.ProfileStart and L:ProfileStart() 

    local tnow = time()
    if (tnow - (t.lastReactive or 0)) > 300 then
        t.lastReactive = tnow
        local Comm = L:GetModule("Comm", true)
        if Comm and Comm.BroadcastAckFor and t.payload then
            local ackMid = tKey
            if tKey:sub(1, 2) == "k:" then ackMid = t.payload.mid or ackMid end
            Comm:BroadcastAckFor(t.payload, ackMid, "DET")
        end
    end
    
    if pTime then L:ProfileStop("Core:TriggerReactiveAck", pTime) end 
end

local function isTombstoneValidAndActive(tKey, incomingT0, op, incomingAV)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if not L.db or not L.db.global or not L.db.global.deletedCache then 
        if pTime then L:ProfileStop("Core:isTombstoneValidAndActive", pTime) end
        return false 
    end
    local deletedCache = L.db.global.deletedCache
    local t = deletedCache[tKey]
    if not t then 
        if pTime then L:ProfileStop("Core:isTombstoneValidAndActive", pTime) end
        return false 
    end

    local isExpired = false
    local tnow = time()

    if t.expiresAt then
        if tnow > t.expiresAt then isExpired = true end
    elseif t.deletedAt then
        if (tnow - t.deletedAt) > (90 * 86400) then isExpired = true end
    end

    local function CheckAndTriggerReactiveAck()
        if incomingAV then
            local major, minor, patch = incomingAV:match("(%d+)%.(%d+)%.(%d+)")
            major = tonumber(major) or 0
            minor = tonumber(minor) or 0
            patch = tonumber(patch) or 0
            
            if major > 0 or (major == 0 and minor > 7) or (major == 0 and minor == 7 and patch >= 47) then
                TriggerReactiveAck(tKey, t)
            end
        end
    end

    if not isExpired then
        if op == "CONF" or op == "SHOW" then
            if op == "CONF" then CheckAndTriggerReactiveAck() end
            if pTime then L:ProfileStop("Core:isTombstoneValidAndActive", pTime) end
            return true
        end
        if op == "DISC" then
            if t.expiresAt then 
                CheckAndTriggerReactiveAck()
                if pTime then L:ProfileStop("Core:isTombstoneValidAndActive", pTime) end
                return true 
            end
            if incomingT0 > (tonumber(t.t0) or 0) then
                deletedCache[tKey] = nil
                if pTime then L:ProfileStop("Core:isTombstoneValidAndActive", pTime) end
                return false
            else
                CheckAndTriggerReactiveAck()
                if pTime then L:ProfileStop("Core:isTombstoneValidAndActive", pTime) end
                return true
            end
        end
    else
        deletedCache[tKey] = nil
        if pTime then L:ProfileStop("Core:isTombstoneValidAndActive", pTime) end
        return false
    end
    
    if pTime then L:ProfileStop("Core:isTombstoneValidAndActive", pTime) end
    return true
end

function Core:_ProcessVendorDiscovery(d, options, op, t0)
    local Constants = L:GetModule("Constants", true)
    if not Constants then return nil end

    local vendorType = d.vendorType
    if not vendorType then
        if d.i >= -399999 and d.i <= -300000 then 
            vendorType = "BM"
        elseif d.i >= -499999 and d.i <= -400000 then 
            vendorType = "MS" 
        end
    end

    local guid = L:GenerateVendorGUID(vendorType, d.c, d.z, d.iz, d.xy.x, d.xy.y)
    d.g = guid

    local vendorItems = {}
    if d.vendorItemIDs and type(d.vendorItemIDs) == "table" then
        for _, receivedItemID in ipairs(d.vendorItemIDs) do
            local vName, vLink = GetItemInfo(receivedItemID)
            if vName and vLink then
                table.insert(vendorItems, { itemID = receivedItemID, name = vName, link = vLink })
            end
        end
    end

    local bm_db = L:GetVendorsDB()
    if not bm_db then return nil end

    local existing = bm_db[guid]
    local recordToBroadcast

    if not existing then
        local newRecord = {
            g = guid, 
            c = d.c, 
            z = d.z, 
            iz = d.iz, 
            i = d.i,
            il = d.il, 
            xy = { x = d.xy.x, y = d.xy.y },
            fp = d.fp, 
            o = d.sender or d.o,
            t0 = t0, 
            ls = t0, 
            s = Constants.STATUS.CONFIRMED, 
            st = t0,
            dt = d.dt, 
            vendorType = vendorType,
            vendorName = d.vendorName or d.fp,
            vendorItems = vendorItems,
        }

        bm_db[guid] = newRecord
        recordToBroadcast = newRecord

        L:SendMessage("LootCollector_DiscoveriesUpdated", "add", guid, newRecord)
        self:AddToZoneIndex(guid, d.z)

        if options.isNetwork and not options.suppressToast then
            local Toast = L:GetModule("Toast", true)
            if Toast and Toast.Show then
                Toast:Show(newRecord, false, { op = op, isNew = true })
            end
        end
    else
        existing.ls = math.max(tonumber(existing.ls) or 0, t0)
        existing.vendorName = d.vendorName or existing.vendorName
        
        if #vendorItems > 0 then
            existing.vendorItems = vendorItems
        end
        
        recordToBroadcast = existing

        L:SendMessage("LootCollector_DiscoveriesUpdated", "update", guid, existing)
        
        if options.isNetwork and not options.suppressToast then
            local Toast = L:GetModule("Toast", true)
            if Toast and Toast.Show then
                Toast:Show(existing, false, { op = op, isNew = false })
            end
        end
    end

    L.DataHasChanged = true

    if recordToBroadcast then
        local shouldBeShared = (not recordToBroadcast.vendorItems) or (#recordToBroadcast.vendorItems <= 5)
        if shouldBeShared then
            L._debug("Core-Share", "Vendor discovery is eligible for sharing.")
        else
            L._debug("Core-Share", "Vendor discovery has too many items (" .. #recordToBroadcast.vendorItems .. ") and will NOT be shared in real-time.")
        end
    end
    
    return guid
end

function Core:_ProcessItemDiscovery(d, options, op, t0)
    local pTime = L.ProfileStart and L:ProfileStart() 

    local Constants = L:GetModule("Constants", true)
    if not Constants then 
        if pTime then L:ProfileStop("Core:_ProcessItemDiscovery", pTime) end
        return nil 
    end

    local db = L:GetDiscoveriesDB()
    if not db then 
        if pTime then L:ProfileStop("Core:_ProcessItemDiscovery", pTime) end
        return nil 
    end

    local guid = d.g or L:GenerateGUID(d.c, d.z, d.iz, d.i, d.xy.x, d.xy.y)
    d.g = guid

    local incomingMid = nil
    if type(d.mid) == "string" and d.mid ~= "" then
        incomingMid = d.mid
    end

    L.db.global.deletedCache = L.db.global.deletedCache or {}

    if incomingMid and isTombstoneValidAndActive(incomingMid, t0, op, d.av) then 
        if pTime then L:ProfileStop("Core:_ProcessItemDiscovery", pTime) end
        return nil 
    end

    local canonicalMid = nil
    local existing, existingGuid = self:FindExistingDiscovery(guid, incomingMid)
    
    if not existing then
        local nearby = nil
        if Constants and d.dt == Constants.DISCOVERY_TYPE.WORLDFORGED then
            nearby = FindWorldforgedInZone(d.c, d.z, d.i, db)
        elseif FindNearbyDiscovery then
            nearby = FindNearbyDiscovery(d.c, d.z, d.i, d.xy.x, d.xy.y, db)
        end
        
        if nearby then
            existing = nearby
            existingGuid = nearby.g
            guid = nearby.g
        end
    end
    
    local function ensureCanonicalMid()
        if canonicalMid == nil then
            canonicalMid = L:ComputeCanonicalDiscoveryMid({
                c = d.c, z = d.z, iz = d.iz, i = d.i, xy = { x = d.xy.x, y = d.xy.y }, t0 = t0,
            })
        end
        return canonicalMid
    end

    if not existing and not incomingMid then
        local probeCanonicalMid = ensureCanonicalMid()
        if isTombstoneValidAndActive(probeCanonicalMid, t0, op, d.av) then 
            if pTime then L:ProfileStop("Core:_ProcessItemDiscovery", pTime) end
            return nil 
        end
        existing, existingGuid = self:FindByMid(probeCanonicalMid)
    end

    local name, link, quality, _, _, itemType, itemSubType = GetItemInfo(d.il or d.i)
    
    local finalLink = d.il or link
    if link and quality and EnsureColoredLink then
        finalLink = EnsureColoredLink(link, quality)
    end

    local src_numeric = d.src
    if type(src_numeric) == "string" then
        local mapped = nil
        if d.dt == Constants.DISCOVERY_TYPE.MYSTIC_SCROLL and Constants.AcceptedLootSrcMS then 
            mapped = Constants.AcceptedLootSrcMS[src_numeric]
        elseif d.dt == Constants.DISCOVERY_TYPE.WORLDFORGED and Constants.AcceptedLootSrcWF then 
            mapped = Constants.AcceptedLootSrcWF[src_numeric] 
        end
        
        if mapped ~= nil then 
            src_numeric = mapped 
        end
    end

    local itemTypeID = d.it
    if not itemTypeID and Constants.ITEM_TYPE_TO_ID then 
        itemTypeID = Constants.ITEM_TYPE_TO_ID[itemType] or 0 
    end

    local itemSubTypeID = d.ist
    if not itemSubTypeID and Constants.ITEM_SUBTYPE_TO_ID then 
        itemSubTypeID = Constants.ITEM_SUBTYPE_TO_ID[itemSubType] or 0 
    end

    local classAbbr = d.cl
    if (not classAbbr or classAbbr == "") and GetItemClassAbbr then 
        classAbbr = GetItemClassAbbr(finalLink or d.i) or "cl" 
    end
    
    if not classAbbr or classAbbr == "" then 
        classAbbr = "cl" 
    end

    local normalizedStatus = d.s
    if normalizedStatus ~= Constants.STATUS.CONFIRMED and normalizedStatus ~= Constants.STATUS.UNCONFIRMED and normalizedStatus ~= Constants.STATUS.FADING and normalizedStatus ~= Constants.STATUS.STALE then
        if options.isNetwork then
            normalizedStatus = (op == "CONF") and Constants.STATUS.CONFIRMED or Constants.STATUS.UNCONFIRMED
        else
            normalizedStatus = Constants.STATUS.CONFIRMED
        end
    end

    local finderName = d.fp or UnitName("player") or "Unknown"
    local s_flag = (finderName == "An Unnamed Collector") and 1 or 0

    local changed = false
    local rec
        
    local Comm = L:GetModule("Comm", true)
    local isAU = Comm and Comm.isAU and Comm:isAU(d.sender)

    if not existing then
        local storedMid = incomingMid
        if not storedMid or storedMid == "" then 
            storedMid = ensureCanonicalMid() 
        end
    
        rec = {
            g = guid, 
            c = d.c, 
            z = d.z, 
            iz = d.iz, 
            i = d.i, 
            il = finalLink,
            q = tonumber(d.q) or tonumber(quality) or 0,
            xy = { x = d.xy.x, y = d.xy.y },
            fp = finderName, 
            o = d.sender or d.o or finderName,
            t0 = t0, 
            ls = t0, 
            st = tonumber(d.st) or t0,
            s = normalizedStatus, 
            mc = tonumber(d.mc) or 1,
            dt = d.dt, 
            src = src_numeric, 
            cl = classAbbr,
            it = tonumber(itemTypeID) or 0, 
            ist = tonumber(itemSubTypeID) or 0,
            mid = storedMid, 
            adc = tonumber(d.adc) or 0,
            fp_votes = { [finderName] = { score = (isAU and 1000 or 1), t0 = t0 } },
            s_flag = s_flag,		
        }

        db[guid] = rec
        
        self._dbDiscoveriesCount = (self._dbDiscoveriesCount or 0) + 1
        if self._dbDiscoveriesCount > 10000 then
            self:EnforceDatabaseCap()
        end
        
        self:AddToZoneIndex(guid, d.z)
        
        if self._lookupIndicesBuilt and rec.mid then 
            self._midIndex[rec.mid] = guid 
        end

        changed = true
        L:SendMessage("LootCollector_DiscoveriesUpdated", "add", guid, rec)
        
        if options.isNetwork and not options.suppressToast then
            local Toast = L:GetModule("Toast", true)
            if Toast and Toast.Show then
                Toast:Show(rec, false, { op = op, isNew = true })
            end
        end

    else
        rec = existing
        guid = existingGuid

        if not rec or type(rec) ~= "table" then 
            if pTime then L:ProfileStop("Core:_ProcessItemDiscovery", pTime) end
            return 
        end

        d.g = rec.g 

        rec.ls = max(tonumber(rec.ls) or 0, t0)        
        
        local oldX = (rec.xy and type(rec.xy) == "table" and rec.xy.x) or 0
        local oldY = (rec.xy and type(rec.xy) == "table" and rec.xy.y) or 0
        local dist = L:ComputeDistance(d.c, d.z, d.xy.x, d.xy.y, rec.c, rec.z, oldX, oldY)
        
        local radius = GetClusterRadius(rec.dt)
        if dist and dist <= radius and dist > 0.5 then
            if op == "DISC" then
                L._debug("Core-Refine", "Network loot coordinate refinement via EMA.")
                rec.xy.x = L:Round4((oldX * 0.8) + (d.xy.x * 0.2))
                rec.xy.y = L:Round4((oldY * 0.8) + (d.xy.y * 0.2))
                changed = true
            end
        end

        if op == "DISC" then
            if finderName and finderName ~= "" and finderName ~= "An Unnamed Collector" then
                local voteWeight = isAU and 1000 or 1
                rec.fp_votes = rec.fp_votes or {}
                if not rec.fp_votes[finderName] then
                    rec.fp_votes[finderName] = { score = voteWeight, t0 = t0 }
                    changed = true
                else
                    rec.fp_votes[finderName].score = rec.fp_votes[finderName].score + voteWeight
                    changed = true
                end
                
                local oldFp = rec.fp
                self:UpdateConsensusWinner(rec)
                if rec.fp ~= oldFp then changed = true end
            end
        end

        if not rec.st or t0 > (rec.st or 0) then
            if op == "CONF" and normalizedStatus == Constants.STATUS.CONFIRMED and rec.s ~= Constants.STATUS.CONFIRMED then
                rec.s = Constants.STATUS.CONFIRMED
                rec.st = t0
                changed = true
            elseif normalizedStatus == Constants.STATUS.FADING or normalizedStatus == Constants.STATUS.STALE then
                rec.s = normalizedStatus
                rec.st = t0
                changed = true
            end
        end

        local newLs = tonumber(d.ls) or t0
        if newLs > (rec.ls or 0) then
            rec.ls = newLs
            changed = true
        end
        
        local incMc = tonumber(d.mc) or 1
        if not isAU then
            incMc = math.min(math.max(incMc, 1), 3)
        end

        if incMc >= 1 then
            rec.mc = (tonumber(rec.mc) or 1) + incMc
            if rec.mc > 1000 then rec.mc = 1000 end 
            changed = true
        end
        
        if d.adc and d.adc > (rec.adc or 0) then 
            rec.adc = d.adc
            changed = true 
        end
        
        if not rec.il and finalLink then 
            rec.il = finalLink
            changed = true 
        end
        
        if not rec.dt and d.dt then 
            rec.dt = d.dt
            changed = true 
        end
        
        if rec.src == nil and src_numeric ~= nil then 
            rec.src = src_numeric
            changed = true 
        end

        if changed then
            L:SendMessage("LootCollector_DiscoveriesUpdated", "update", guid, rec)
        end
        
        if options.isNetwork and not options.suppressToast then
            local Toast = L:GetModule("Toast", true)
            if Toast and Toast.Show then
                Toast:Show(rec, false, { op = op, isNew = false })
            end
        end
    end

    if changed then
        L.DataHasChanged = true
        local Map = L:GetModule("Map", true)
        if Map then 
            Map.cacheIsDirty = true 
        end
        
        if options.isNetwork then
            if Core.IsBatchProcessing then
                if not Core.pendingBroadcasts then Core.pendingBroadcasts = {} end
                Core.pendingBroadcasts[guid] = true
            else
                L:ScheduleAfter(BROADCAST_DELAY, function() 
                    L:SendMessage("LOOTCOLLECTOR_DISCOVERY_LIST_UPDATED") 
                end)
            end
        else
            L:SendMessage("LOOTCOLLECTOR_DISCOVERY_LIST_UPDATED")
        end
    end
    
    if pTime then L:ProfileStop("Core:_ProcessItemDiscovery", pTime) end 
    return guid
end

function Core:AddDiscovery(d, options)
    local pTime = L.ProfileStart and L:ProfileStart() 

    options = options or {}
    local op = tostring(options.op or (options.isNetwork and "DISC" or "LOCAL"))

    if type(d) ~= "table" then 
        if pTime then L:ProfileStop("Core:AddDiscovery", pTime) end
        return nil 
    end

    local c = tonumber(d.c) or 0
    local z = tonumber(d.z) or 0
    local Constants = L:GetModule("Constants", true)
    
    
    local infoTarget = d.il or d.i
    if not infoTarget then 
        if pTime then L:ProfileStop("Core:AddDiscovery", pTime) end
        return nil 
    end

    local itemID = d.i
    if not itemID then
        local _, link = GetItemInfo(infoTarget)
        if link then 
            itemID = L:ExtractItemID(link)
        elseif type(d.il) == "string" then 
            itemID = L:ExtractItemID(d.il) 
        end
    end

    itemID = tonumber(itemID) or 0
    if itemID == 0 then 
        if pTime then L:ProfileStop("Core:AddDiscovery", pTime) end
        return nil 
    end
    d.i = itemID

    local dt = d.dt
    if not dt and itemID > 0 and Constants and Constants.DISCOVERY_TYPE then
        local cachedName = select(1, GetItemInfo(itemID))
        if not cachedName and d.il and type(d.il) == "string" then
            cachedName = d.il:match("%[(.-)%]")
        end
        if cachedName then
            if string.find(cachedName, "Mystic Scroll", 1, true) then 
                dt = Constants.DISCOVERY_TYPE.MYSTIC_SCROLL
            else 
                dt = Constants.DISCOVERY_TYPE.WORLDFORGED 
            end
        end
    end
    d.dt = dt
    
    
    if Constants and Constants.FORBIDDEN_ZONES and Constants.FORBIDDEN_ZONES[c] and Constants.FORBIDDEN_ZONES[c][z] then
        L._debug("Core-Block", "Blocked incoming discovery from a forbidden zone: " .. tostring(d.il))
        if pTime then L:ProfileStop("Core:AddDiscovery", pTime) end
        return nil
    end
    
    if self:IsInsideAOETombstone(c, z, tonumber(d.iz) or 0, d.dt, d.xy and d.xy.x or 0, d.xy and d.xy.y or 0) then
        if pTime then L:ProfileStop("Core:AddDiscovery", pTime) end
        return nil
    end

    if self:IsInsideVendorDeadzone(c, z, tonumber(d.iz) or 0, d.dt, d.xy and d.xy.x or 0, d.xy and d.xy.y or 0) then
        if pTime then L:ProfileStop("Core:AddDiscovery", pTime) end
        return nil
    end

    if options.isNetwork then
        if not (d.xy and d.c and d.z and (d.il or d.i)) then 
            if pTime then L:ProfileStop("Core:AddDiscovery", pTime) end
            return nil 
        end
        local ZoneList = L:GetModule("ZoneList", true)
        if not (ZoneList and ZoneList.MapDataByID and ZoneList.MapDataByID[z]) then 
            if pTime then L:ProfileStop("Core:AddDiscovery", pTime) end
            return nil 
        end
        if L:IsZoneIgnored() then 
            if pTime then L:ProfileStop("Core:AddDiscovery", pTime) end
            return nil 
        end
    end

    if not (L.db and L.db.global) then 
        if pTime then L:ProfileStop("Core:AddDiscovery", pTime) end
        return nil 
    end

    local isBlackmarket = Constants and Constants.DISCOVERY_TYPE and d.dt == Constants.DISCOVERY_TYPE.BLACKMARKET

    if options.isNetwork then
        if not isBlackmarket and not self:IsItemFullyCached(itemID) then
            local firstDelay = math.random(5, 25)
            self:QueueItemForCaching(itemID)

            L:ScheduleAfter(firstDelay, function()
                if self:IsItemFullyCached(itemID) then
                    self:AddDiscovery(d, options)
                else
                    SafeCacheItemRequest(itemID)
                    L:ScheduleAfter(5, function()
                        if self:IsItemFullyCached(itemID) then self:AddDiscovery(d, options) end
                    end)
                end
            end)
            if pTime then L:ProfileStop("Core:AddDiscovery", pTime) end
            return nil
        end
    end

    if self:ShouldCacheItem(itemID) and not isBlackmarket then
        self:QueueItemForCaching(itemID)
        self:EnsureCachePump()
    end

    d.xy = d.xy or {}
    d.xy.x = L:Round4((d.xy.x) or d.x or 0)
    d.xy.y = L:Round4((d.xy.y) or d.y or 0)
    d.c = c
    d.z = z
    d.iz = tonumber(d.iz) or 0
    
    local t0 = tonumber(d.t0) or tonumber(d.t) or time()
    d.t0 = t0

    if isBlackmarket then
        local res = self:_ProcessVendorDiscovery(d, options, op, t0)
        if pTime then L:ProfileStop("Core:AddDiscovery", pTime) end
        return res
    else
        local res = self:_ProcessItemDiscovery(d, options, op, t0)
        if pTime then L:ProfileStop("Core:AddDiscovery", pTime) end
        return res
    end
end

function Core:FixCorruptedTimestamps()
    local pTime = L.ProfileStart and L:ProfileStart() 

    local discoveries = L:GetDiscoveriesDB()
    if not discoveries then 
        if pTime then L:ProfileStop("Core:FixCorruptedTimestamps", pTime) end
        return 0 
    end
    
    local fixedCount = 0
    local tnow = time()
    local penaltyAge = tnow - (113 * 86400) 
    
    for guid, d in pairs(discoveries) do
        if type(d) == "table" then
            local hasValidT0 = d.t0 and tonumber(d.t0) and tonumber(d.t0) > 0
            
            if not hasValidT0 then
                d.t0 = penaltyAge
                d.ls = penaltyAge
                d.s = "STALE"
                d.st = tnow
                fixedCount = fixedCount + 1
            end
        end
    end
    
    if fixedCount > 0 then
        print(string.format("|cffff7f00LootCollector:|r Repaired %d corrupted timestamps with the 113-day V8 Amnesty penalty.", fixedCount))
    end
    
    if pTime then L:ProfileStop("Core:FixCorruptedTimestamps", pTime) end 
    return fixedCount
end

local function StoreDiscoveryTombstone(deletedCache, discoveryLike, expiryTime)
    if not deletedCache or not discoveryLike then return end
    local t0 = tonumber(discoveryLike.t0 or discoveryLike.t or 0)
    if t0 <= 0 then return end

    local incomingMid = type(discoveryLike.mid) == "string" and discoveryLike.mid or nil
    local canonicalMid = L:ComputeCanonicalDiscoveryMid({
        c = discoveryLike.c,
        z = discoveryLike.z,
        iz = discoveryLike.iz or 0,
        i = discoveryLike.i or discoveryLike.il,
        xy = discoveryLike.xy or { x = discoveryLike.x or 0, y = discoveryLike.y or 0 },
        t0 = t0,
    })

    local payload = {
        i = discoveryLike.i or discoveryLike.il,
        il = discoveryLike.il,
        c = discoveryLike.c,
        z = discoveryLike.z,
        iz = discoveryLike.iz or 0,
        xy = discoveryLike.xy or { x = discoveryLike.x or 0, y = discoveryLike.y or 0 },
        t0 = t0,
        mid = canonicalMid
    }

    local Constants = L:GetModule("Constants", true)
    local offsets = Constants and Constants.ACK_REINFORCE_OFFSETS
    local nd = time() + (offsets and offsets[1] or 3600)

    if incomingMid and incomingMid ~= "" then
        deletedCache[incomingMid] = {
            t0 = t0, deletedAt = time(), expiresAt = expiryTime,
            payload = payload, ac = 1, nd = nd
        }
    end

    if canonicalMid and canonicalMid ~= "" then
        deletedCache[canonicalMid] = {
            t0 = t0, deletedAt = time(), expiresAt = expiryTime,
            payload = payload, ac = 1, nd = nd, isPrimary = true
        }
    end
end

function Core:ReportDiscoveryAsGone(guid, reason, bypassAFK)
    if not guid then return end
    local db = L:GetDiscoveriesDB()
    if not db then return end

    local rec = db[guid]
    if not rec then return end

    if not rec.mid or rec.mid == "" then
        rec.mid = L:ComputeCanonicalDiscoveryMid(rec)
        L._debug("Core-Report", "Generated missing mid for local discovery: " .. tostring(rec.mid))
    end

    local Comm = L:GetModule("Comm", true)
    if Comm and Comm.BroadcastAckFor and rec.mid and rec.mid ~= "" then
        local discoveryPayload = {
            i = rec.i,
            il = rec.il,
            c = rec.c,
            z = rec.z,
            iz = rec.iz or 0,
            xy = rec.xy,
            t0 = rec.t0,
            mid = rec.mid
        }
        Comm:BroadcastAckFor(discoveryPayload, rec.mid, "DET", bypassAFK)
    else
        L._debug("Core-Report", "Failed to broadcast ACK. Missing Comm, BroadcastAckFor, or mid.")
    end

    L.db.global.deletedCache = L.db.global.deletedCache or {}
    StoreDiscoveryTombstone(L.db.global.deletedCache, rec, nil)

    self:RemoveDiscoveryByGuid(guid, string.format("Discovery %s reported as gone and removed.", rec.il or guid))
end

function Core:RemoveDiscoveryByGuid(guid, reason)
    local discoveries = L:GetDiscoveriesDB()
    if not guid or not discoveries then return end

    if discoveries[guid] then
        local rec = discoveries[guid]
        
        if rec and rec.z then
            self:RemoveFromZoneIndex(guid, rec.z)
        end
        
        if self._lookupIndicesBuilt then
            if rec.mid then self._midIndex[rec.mid] = nil end
        end
        
        discoveries[guid] = nil
        self._dbDiscoveriesCount = math.max(0, (self._dbDiscoveriesCount or 1) - 1)
        
        print(string.format("|cff00ff00LootCollector:|r %s", reason or ("Discovery " .. guid .. " removed.")))
        
        L:SendMessage("LootCollector_DiscoveriesUpdated", "remove", guid, nil)
        
        local Map = L:GetModule("Map", true)
        if Map then
            Map.cacheIsDirty = true
            if Map.Update and WorldMapFrame and WorldMapFrame:IsShown() then Map:Update() end
            if Map.UpdateMinimap then Map:UpdateMinimap() end
        end
        
        L:SendMessage("LOOTCOLLECTOR_DISCOVERY_LIST_UPDATED")
        return true
    end
    return false
end

function Core:RemoveBlackmarketVendorByGuid(guid)
    local vendors = L:GetVendorsDB()
    if not guid or not vendors then return end

    if vendors[guid] then
        local rec = vendors[guid]
        
        if rec and rec.z then
            self:RemoveFromZoneIndex(guid, rec.z)
        end
        
        vendors[guid] = nil
        print("|cff00ff00LootCollector:|r Specialty Vendor pin removed from local database.")
        
        local Map = L:GetModule("Map", true)
        if Map and Map.Update then Map:Update() end
        return true
    end
    return false
end

function Core:ClearDiscoveries()
    if not (L.db and L.db.global) then return end
    
    local realms = L.db.global.realms
    if realms and L.activeRealmKey and realms[L.activeRealmKey] then
         realms[L.activeRealmKey].discoveries = {}
         realms[L.activeRealmKey].blackmarketVendors = {}
    end
    
    self._dbDiscoveriesCount = 0

    print(string.format("[%s] Cleared all discovery and vendor data.", L.name))
    
    self:InvalidateLookupIndices()
    self:RebuildZoneIndex()
    
    L:SendMessage("LootCollector_DiscoveriesUpdated", "clear", nil, nil)
    
    local Map = L:GetModule("Map", true)
    if Map then
        Map.cacheIsDirty = true
        if Map.Update and WorldMapFrame and WorldMapFrame:IsShown() then Map:Update() end
        if Map.UpdateMinimap then Map:UpdateMinimap() end
    end
end

function Core:RemoveDiscovery(guid)
    local discoveries = L:GetDiscoveriesDB()
    if not guid or not discoveries then return end

    if discoveries[guid] then
        local rec = discoveries[guid]
        
        if self._lookupIndicesBuilt then
            if rec.mid then self._midIndex[rec.mid] = nil end
        end
        
        discoveries[guid] = nil
        self._dbDiscoveriesCount = math.max(0, (self._dbDiscoveriesCount or 1) - 1)
        
        print(string.format("|cff00ff00LootCollector:|r Discovery %s removed.", guid))
        
        L:SendMessage("LootCollector_DiscoveriesUpdated", "remove", guid, nil)
        
        local Map = L:GetModule("Map", true)
        if Map and Map.Update then
            Map:Update()
        end
        return true
    end
    return false
end

function Core:RescanAllClasses()
    local discoveries = L:GetDiscoveriesDB()
    if not discoveries then return 0 end

    local changed = 0
    for _, d in pairs(discoveries) do
        if type(d) == "table" and (d.il or d.i) then
            local abbr = GetItemClassAbbr(d.il or d.i)
            if abbr and abbr ~= "cl" and d.cl ~= abbr then
                d.cl = abbr
                changed = changed + 1
            elseif not d.cl then
                d.cl = "cl"
            end
        end
    end
    local Map = L:GetModule("Map", true)
    if Map and Map.Update and WorldMapFrame and WorldMapFrame:IsShown() then
        Map:Update()
    end
    return changed
end

function Core:BuildLookupIndices()
    if self._lookupIndicesBuilt then return end
    self._midIndex = {}
    
    local db = L:GetDiscoveriesDB()
    if not db then return end
    
    for g, r in pairs(db) do
        if type(r) == "table" then
            if r.mid then 
                self._midIndex[r.mid] = g 
            end
        end
    end
    self._lookupIndicesBuilt = true
end

function Core:FindByMid(mid)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if not mid or mid == "" then 
        if pTime then L:ProfileStop("Core:FindByMid", pTime) end
        return nil, nil 
    end
    local db = L:GetDiscoveriesDB()
    if not db then 
        if pTime then L:ProfileStop("Core:FindByMid", pTime) end
        return nil, nil 
    end

    self:BuildLookupIndices()
    
    local idx = self._midIndex[mid]
    if idx and db[idx] then
        if pTime then L:ProfileStop("Core:FindByMid", pTime) end
        return db[idx], idx
    end

    if pTime then L:ProfileStop("Core:FindByMid", pTime) end 
    return nil, nil
end

function Core:FindExistingDiscovery(guid, incomingMid)
    local pTime = L.ProfileStart and L:ProfileStart() 

    local db = L:GetDiscoveriesDB()
    if not db then 
        if pTime then L:ProfileStop("Core:FindExistingDiscovery", pTime) end
        return nil, nil 
    end

    if guid and db[guid] then
        if pTime then L:ProfileStop("Core:FindExistingDiscovery", pTime) end
        return db[guid], guid
    end

    self:BuildLookupIndices()

    if incomingMid and incomingMid ~= "" then
        local midGuid = self._midIndex[incomingMid]
        if midGuid and db[midGuid] then
            if pTime then L:ProfileStop("Core:FindExistingDiscovery", pTime) end
            return db[midGuid], midGuid
        end
    end

    if pTime then L:ProfileStop("Core:FindExistingDiscovery", pTime) end 
    return nil, nil
end

function Core:ProcessAckVote(mid, sender)
    local pTime = L.ProfileStart and L:ProfileStart() 

    L._debug("Core-Ack", "ProcessAckVote invoked for mid: " .. tostring(mid) .. " from " .. tostring(sender))
    if not mid or mid == "" or not sender or sender == "" then 
        if pTime then L:ProfileStop("Core:ProcessAckVote", pTime) end
        return 
    end
    local rec, guid = self:FindByMid(mid)
    
    if not rec then
        L._debug("Core-Ack", "Index miss for mid. Re-checking DB...")
        local db = L:GetDiscoveriesDB()
        for k, v in pairs(db) do
            if v.mid == mid then
                rec = v
                guid = k
                break
            end
        end
    end
    
    if not rec then
        L._debug("Core-Ack", "FAILED: Could not find any record in local DB matching mid: " .. tostring(mid))
        if pTime then L:ProfileStop("Core:ProcessAckVote", pTime) end
        return
    end

    guid = guid or rec.g
    L._debug("Core-Ack", "Match found! GUID: " .. tostring(guid) .. " | Current ADC: " .. tostring(rec.adc or 0))
    
    rec.ack_votes = rec.ack_votes or {}
    if rec.ack_votes[sender] then 
        L._debug("Core-Ack", "Sender has already voted on this record. Aborting.")
        if pTime then L:ProfileStop("Core:ProcessAckVote", pTime) end
        return 
    end
        
    local Comm = L:GetModule("Comm", true)
    local isAU = Comm and Comm.isAU and Comm:isAU(sender)
    local voteWeight = isAU and 10 or 1
    
    rec.ack_votes[sender] = voteWeight
    local voteCount = 0
    for _, w in pairs(rec.ack_votes) do 
        voteCount = voteCount + (type(w) == "number" and w or 1) 
    end
    rec.adc = voteCount
    
    local Constants = L:GetModule("Constants", true)
    local DELETION_THRESHOLD_REMOVE = Constants and Constants.DELETION_THRESHOLD_REMOVE or 7
    local DELETION_THRESHOLD_STALE = Constants and Constants.DELETION_THRESHOLD_STALE or 6
    local DELETION_THRESHOLD_FADING = Constants and Constants.DELETION_THRESHOLD_FADING or 5

    L._debug("Core-Ack", string.format("New VoteCount: %d. Thresholds: Fade=%d, Stale=%d, Rem=%d", voteCount, DELETION_THRESHOLD_FADING, DELETION_THRESHOLD_STALE, DELETION_THRESHOLD_REMOVE))
    
    if voteCount >= DELETION_THRESHOLD_REMOVE then
        L._debug("Core-Ack", "THRESHOLD REACHED: REMOVE")
        self:RemoveDiscoveryByGuid(rec.g, string.format("Discovery %s removed by consensus (%d votes).", rec.il or "item", voteCount))
    elseif rec.s == "CONFIRMED" and voteCount >= DELETION_THRESHOLD_STALE then
        L._debug("Core-Ack", "THRESHOLD REACHED: STALE")
        rec.s = "STALE"
        rec.st = time()
    elseif rec.s == "CONFIRMED" and voteCount >= DELETION_THRESHOLD_FADING then
        L._debug("Core-Ack", "THRESHOLD REACHED: FADING")
        rec.s = "FADING"
        rec.st = time()
    else
        L._debug("Core-Ack", "No threshold reached. Status remains: " .. tostring(rec.s))
    end    
    
    L:SendMessage("LOOTCOLLECTOR_DISCOVERY_LIST_UPDATED")
    local Map = L:GetModule("Map", true)
    if Map and Map.Update and WorldMapFrame and WorldMapFrame:IsShown() then
        Map:Update()
    end
    
    if pTime then L:ProfileStop("Core:ProcessAckVote", pTime) end 
end

function Core:HandleGuidedFix(fixData)
    local discoveries = L:GetDiscoveriesDB()
    if not fixData or not discoveries then return end

    local updatedCount = 0
    local deletedCount = 0
    local remoteKilledCount = 0
    local recordsToUpdate = {} 
    local recordsToDelete = {} 
    local recordsToRemoteKill = {}
    local recordsToMove = {} 
    
    local days = tonumber(fixData.dur) or 90 
    local expiryTime = time() + (days * 86400)
    
    local tolerance = tonumber(fixData.tol) or 15 
    
    if fixData.type == 1 then 
        for guid, d in pairs(discoveries) do
            if d.i == fixData.i and d.c == fixData.c and d.z == fixData.z then
                local dist = L:ComputeDistance(d.c, d.z, d.xy.x, d.xy.y, fixData.c, fixData.z, fixData.nx, fixData.ny)
                if dist and dist <= fixData.prox then
                    table.insert(recordsToUpdate, guid)
                end
            end
        end
    elseif fixData.type == 2 then 
        for guid, d in pairs(discoveries) do
            if d.i == fixData.i and d.c == fixData.c and d.z == fixData.z then
                local dist = L:ComputeDistance(d.c, d.z, d.xy.x, d.xy.y, fixData.c, fixData.z, fixData.ox, fixData.oy)
                if dist and dist <= tolerance then 
                    table.insert(recordsToUpdate, guid)
                end
            end
        end
    elseif fixData.type == 3 then
        for guid, d in pairs(discoveries) do
            if d.i == fixData.i and d.c == fixData.c and d.z == fixData.z then
                local dist = L:ComputeDistance(d.c, d.z, d.xy.x, d.xy.y, fixData.c, fixData.z, fixData.ox, fixData.oy)
                if dist and dist <= tolerance then
                    table.insert(recordsToDelete, guid)
                end
            end
        end
    elseif fixData.type == 4 then
        for guid, d in pairs(discoveries) do
            if d.i == fixData.i and d.c == fixData.c and d.z == fixData.z then
                local dist = L:ComputeDistance(d.c, d.z, d.xy.x, d.xy.y, fixData.c, fixData.z, fixData.ox, fixData.oy)
                if dist and dist <= tolerance then
                    table.insert(recordsToRemoteKill, guid)
                end
            end
        end
    elseif fixData.type == 6 then
        local oiz = tonumber(fixData.oiz) or 0
        for guid, d in pairs(discoveries) do
            if d.i == fixData.i and d.c == fixData.oc and d.z == fixData.oz and (tonumber(d.iz) or 0) == oiz then
                local dist = L:ComputeDistance(d.c, d.z, d.xy.x, d.xy.y, fixData.oc, fixData.oz, fixData.ox, fixData.oy)
                if dist and dist <= tolerance then
                    table.insert(recordsToMove, guid)
                end
            end
        end
    elseif fixData.type == 7 then
        
        
        self:StartTimeSeriesPurge(fixData)
        return
    elseif fixData.type == 8 then
        
        self:DropAOETombstone(fixData.name, fixData.c, fixData.z, tonumber(fixData.iz) or 0, fixData.dt, fixData.x, fixData.y, fixData.radius, fixData.dur)
        self:InvalidateLookupIndices()
        self:RebuildZoneIndex()
        local Map = L:GetModule("Map", true)
        if Map then Map.cacheIsDirty = true; if Map.Update then Map:Update() end end
        return
        
    elseif fixData.type == 9 then
        
        if self:RemoveAOETombstone(fixData.name) then
            
            
        end
        return
    elseif fixData.type == 10 then
        
        if not (L.db and L.db.global and L.db.global.aoeTombstones) then return end
        local tombstones = L.db.global.aoeTombstones
        local targetC, targetZ, targetIz = tonumber(fixData.c), tonumber(fixData.z), tonumber(fixData.iz)
        local targetDt = tonumber(fixData.dt)
        local removed = false

        for i = #tombstones, 1, -1 do
            local ts = tombstones[i]
            if ts.c == targetC and ts.z == targetZ and ts.iz == targetIz and ts.dt == targetDt then
                local dist = L:ComputeDistance(targetC, targetZ, fixData.x, fixData.y, ts.c, ts.z, ts.x, ts.y)
                if dist and dist <= tolerance then
                    table.remove(tombstones, i)
                    removed = true
                end
            end
        end
        if removed then L._debug("Core-AOE", "AOE Tombstone(s) removed via coordinate match.") end
        return
    end
    
    
	if recordsToUpdate and #recordsToUpdate > 0 then
	    for _, oldGuid in ipairs(recordsToUpdate) do
		  local oldRecord = discoveries[oldGuid]
		  if oldRecord then
			L.db.global.deletedCache = L.db.global.deletedCache or {}
			StoreDiscoveryTombstone(L.db.global.deletedCache, oldRecord, expiryTime)
			discoveries[oldGuid] = nil
			local newRecord = {}
			for k, v in pairs(oldRecord) do newRecord[k] = v end
			newRecord.xy = newRecord.xy or {}
			newRecord.xy.x = fixData.nx
			newRecord.xy.y = fixData.ny
			newRecord.s = "CONFIRMED"
			newRecord.st = time()
			local newGuid = L:GenerateGUID(newRecord.c, newRecord.z, newRecord.iz or 0, newRecord.i, newRecord.xy.x, newRecord.xy.y)
			newRecord.g = newGuid
			newRecord.mid = L:ComputeCanonicalDiscoveryMid(newRecord)
			discoveries[newGuid] = newRecord
			updatedCount = updatedCount + 1
		  end
	    end
	end

    
    if recordsToMove and #recordsToMove > 0 then
        for _, oldGuid in ipairs(recordsToMove) do
            local oldRecord = discoveries[oldGuid]
            if oldRecord then
                
                local newRecord = {}
                for k, v in pairs(oldRecord) do newRecord[k] = v end
                newRecord.c = fixData.nc
                newRecord.z = fixData.nz
                newRecord.iz = fixData.niz or 0
                newRecord.xy = { x = fixData.nx, y = fixData.ny }
                newRecord.s = "CONFIRMED"
                newRecord.st = time()
                
                local newGuid = L:GenerateGUID(newRecord.c, newRecord.z, newRecord.iz, newRecord.i, newRecord.xy.x, newRecord.xy.y)
                
                
                if L.db and L.db.char and L.db.char.looted and L.db.char.looted[oldGuid] then
                    L.db.char.looted[newGuid] = L.db.char.looted[oldGuid]
                    L.db.char.looted[oldGuid] = nil
                end

                
                L.db.global.deletedCache = L.db.global.deletedCache or {}
                StoreDiscoveryTombstone(L.db.global.deletedCache, oldRecord, expiryTime)
                discoveries[oldGuid] = nil
                
                newRecord.g = newGuid
                newRecord.mid = L:ComputeCanonicalDiscoveryMid(newRecord)
                discoveries[newGuid] = newRecord
                updatedCount = updatedCount + 1
            end
        end
    end

    
    if recordsToDelete and #recordsToDelete > 0 then
        for _, delGuid in ipairs(recordsToDelete) do            
            discoveries[delGuid] = nil
            deletedCount = deletedCount + 1
            L:SendMessage("LootCollector_DiscoveriesUpdated", "remove", delGuid, nil)
        end
    end

    
    if recordsToRemoteKill and #recordsToRemoteKill > 0 then
        for _, killGuid in ipairs(recordsToRemoteKill) do            
            local staggeredDelay = math.random(30, 200)
            L._debug("Core-GFIX", string.format("GFIX staggered: Remote Kill for %s scheduled in %d seconds.", killGuid, staggeredDelay))
            
            ScheduleAfter(staggeredDelay, function()                
                if discoveries[killGuid] then
                    
                    self:ReportDiscoveryAsGone(killGuid, "Removed via Remote Kill", true)
                end
            end)
            remoteKilledCount = remoteKilledCount + 1
        end
    end

    if updatedCount > 0 or deletedCount > 0 or remoteKilledCount > 0 then
        self:InvalidateLookupIndices()
        
        
        self:RebuildZoneIndex()
        
        local Map = L:GetModule("Map", true)
        if Map then
            
            Map.cacheIsDirty = true
            if Map.Update then Map:Update() end
        end
        L:SendMessage("LOOTCOLLECTOR_DISCOVERY_LIST_UPDATED")
    end
end

Core._purgeInProgress = false
Core._purgeKey = nil
Core._purgeData = nil
Core._purgeRemovedCount = 0

function Core:StartTimeSeriesPurge(fixData)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if self._purgeInProgress then 
        L._debug("Core-GFIX", "A Time-Series Purge is already running. Ignoring overlapping request.")
        if pTime then L:ProfileStop("Core:StartTimeSeriesPurge", pTime) end
        return 
    end
    
    local function parseDate(dateStr)
        if type(dateStr) ~= "string" or dateStr == "" then return nil end
        local Y, M, D, h, m = string.match(dateStr, "(%d+)-(%d+)-(%d+) (%d+):(%d+)")
        if Y and M and D and h and m then
            return time({year=tonumber(Y), month=tonumber(M), day=tonumber(D), hour=tonumber(h), min=tonumber(m), sec=0})
        end
        return nil
    end

    local epochStart = parseDate(fixData.dateStart) or 0
    local epochEnd = parseDate(fixData.dateEnd) or 2000000000 

    self._purgeData = {
        i = fixData.i,
        tStart = epochStart,
        tEnd = epochEnd
    }
    
    self._purgeInProgress = true
    self._purgeKey = nil
    self._purgeGuidsToRemove = {}
    
    L._debug("Core-GFIX", string.format("Starting background Time-Series Purge for item %d between %d and %d...", fixData.i, epochStart, epochEnd))
    self:ProcessTimeSeriesChunk()
    
    if pTime then L:ProfileStop("Core:StartTimeSeriesPurge", pTime) end 
end

function Core:ProcessTimeSeriesChunk()
    if not self._purgeInProgress then return end
    if InCombatLockdown() then 
        ScheduleAfter(2.0, function() self:ProcessTimeSeriesChunk() end)
        return 
    end

    local db = L:GetDiscoveriesDB()
    if not db or not next(db) then
        self._purgeInProgress = false
        return
    end

    local processed = 0
    local k = self._purgeKey
    local pData = self._purgeData

    
    if k ~= nil and db[k] == nil then k = nil end

    while processed < 300 do 
        k, d = next(db, k)
        
        if not k then
            
            local removedCount = #self._purgeGuidsToRemove
            
            if removedCount > 0 then
                for _, guid in ipairs(self._purgeGuidsToRemove) do
                    db[guid] = nil
                end
                
                L._debug("Core-GFIX", string.format("Time-Series Purge complete. Silently removed %d corrupted records.", removedCount))
                self:InvalidateLookupIndices()
                
                
                self:RebuildZoneIndex()
                local Map = L:GetModule("Map", true)
                if Map then 
                    Map.cacheIsDirty = true
                    if Map.Update then Map:Update() end 
                end
                L:SendMessage("LOOTCOLLECTOR_DISCOVERY_LIST_UPDATED")
            else
                L._debug("Core-GFIX", "Time-Series Purge complete. No matching records found to remove.")
            end
            
            
            self._purgeInProgress = false
            self._purgeKey = nil
            self._purgeGuidsToRemove = nil
            return
        end

        if type(d) == "table" and d.i == pData.i then
            local recT0 = tonumber(d.t0) or 0
            if recT0 >= pData.tStart and recT0 <= pData.tEnd then
                
                table.insert(self._purgeGuidsToRemove, k)
            end
        end

        processed = processed + 1
    end

    self._purgeKey = k
    ScheduleAfter(0.05, function() self:ProcessTimeSeriesChunk() end)
end

function Core:FixLegacyZoneIDs()
    print("|cff00ff00LootCollector:|r Checking database for invalid Continent-Zone combinations...")
    
    local discoveries = L:GetDiscoveriesDB()
    if not discoveries then 
        L.db.global.legacyZoneFixV2 = true
        return 
    end

    local ZoneList = L:GetModule("ZoneList", true)
    if not (ZoneList and ZoneList.MapDataByID) then 
        print("|cffff0000LootCollector:|r ZoneList module not ready.")
        return 
    end
    
    local LegacyZoneData = {[1]={[1]="Ammen Vale",[2]="Ashenvale",[3]="Azshara",[4]="Azuremyst Isle",[5]="Ban'ethil Barrow Den",[6]="Bloodmyst Isle",[7]="Burning Blade Coven",[8]="Caverns of Time",[9]="Darkshore",[10]="Darnassus",[11]="Desolace",[12]="Durotar",[13]="Dustwallow Marsh",[14]="Dustwind Cave",[15]="Fel Rock",[16]="Felwood",[17]="Feralas",[18]="Maraudon",[19]="Moonglade",[20]="Moonlit Ossuary",[21]="Mulgore",[22]="Orgrimmar",[23]="Palemane Rock",[24]="Camp Narache",[25]="Shadowglen",[26]="Shadowthread Cave",[27]="Silithus",[28]="Sinister Lair",[29]="Skull Rock",[30]="Stillpine Hold",[31]="Stonetalon Mountains",[32]="Tanaris",[33]="Teldrassil",[34]="The Barrens",[35]="The Exodar",[36]="The Gaping Chasm",[37]="The Noxious Lair",[38]="The Slithering Scar",[39]="The Venture Co. Mine",[40]="Thousand Needles",[41]="Thunder Bluff",[42]="Tides' Hollow",[43]="Twilight's Run",[44]="Un'Goro Crater",[45]="Valley of Trials",[46]="Wailing Caverns",[47]="Winterspring"},[2]={[1]="Alterac Mountains",[2]="Amani Catacombs",[3]="Arathi Highlands",[4]="Badlands",[5]="Blackrock Mountain",[6]="Blasted Lands",[7]="Burning Steppes",[8]="Coldridge Pass",[9]="Coldridge Valley",[10]="Deadwind Pass",[11]="Deathknell",[12]="Dun Morogh",[13]="Duskwood",[14]="Eastern Plaguelands",[15]="Echo Ridge Mine",[16]="Elwynn Forest",[17]="Eversong Woods",[18]="Fargodeep Mine",[19]="Ghostlands",[20]="Gol'Bolar Quarry",[21]="Gold Coast Quarry",[22]="Hillsbrad Foothills",[23]="Ironforge",[24]="Isle of Quel'Danas",[25]="Jangolode Mine",[26]="Jasperlode Mine",[27]="Loch Modan",[28]="Night Web's Hollow",[29]="Northshire Valley",[30]="Redridge Mountains",[31]="Scarlet Monastery",[32]="Searing Gorge",[33]="Secret Inquisitorial Dungeon",[34]="Shadewell Spring",[35]="Silvermoon City",[36]="Silverpine Forest",[37]="Stormwind City",[38]="Stranglethorn Vale",[39]="Sunstrider Isle",[40]="Swamp of Sorrows",[41]="The Deadmines",[42]="The Grizzled Den",[43]="The Hinterlands",[44]="Tirisfal Glades",[45]="Uldaman",[46]="Undercity",[47]="Western Plaguelands",[48]="Westfall",[49]="Wetlands"},[3]={[1]="Blade's Edge Mountains", [2]="Hellfire Peninsula", [3]="Nagrand", [4]="Netherstorm", [5]="Shadowmoon Valley", [6]="Shattrath City", [7]="Terokkar Forest", [8]="Zangarmarsh"},[4]={[1]="Borean Tundra", [2]="Crystalsong Forest", [3]="Dalaran", [4]="Dragonblight", [5]="Grizzly Hills", [6]="Howling Fjord", [7]="Hrothgar's Landing", [8]="Icecrown", [9]="Sholazar Basin", [10]="The Storm Peaks", [11]="Wintergrasp", [12]="Zul'Drak"}}

    local nameToNewMapID = {}
    for mapID, data in pairs(ZoneList.MapDataByID) do
        if data and data.name then nameToNewMapID[data.name] = mapID end
        if data and data.altName then nameToNewMapID[data.altName] = mapID end
        if data and data.altName2 then nameToNewMapID[data.altName2] = mapID end
    end

    local fixedCount = 0
    local guidRemap = {}
    
    local toRemove = {}
    local toAdd = {}
    
    for oldGuid, d in pairs(discoveries) do
        if d and d.c and d.z then
            local c = tonumber(d.c)
            local z = tonumber(d.z)
            
            local isValid = false
            local mapData = ZoneList.MapDataByID[z]
            
            if mapData then
                if mapData.continentID == c then
                    isValid = true
                elseif z > 2000 then 
                     isValid = true 
                end
            end

            if not isValid then
                local legacyName = LegacyZoneData[c] and LegacyZoneData[c][z]
                
                if legacyName then
                    local newMapID = nameToNewMapID[legacyName]
                    if newMapID then
                        local newMapData = ZoneList.MapDataByID[newMapID]
                        if newMapData then
                            d.c = newMapData.continentID
                            d.z = newMapData.zoneID 
                            
                            if d.iz == 0 then 
                                d.iz = 0 
                            end

                            local newGuid = L:GenerateGUID(d.c, d.z, d.i, d.xy.x, d.xy.y)
                            d.g = newGuid
                            
                            table.insert(toRemove, oldGuid)
                            toAdd[newGuid] = d
                            guidRemap[oldGuid] = newGuid
                            fixedCount = fixedCount + 1
                            
                            print(string.format("LootCollector: Fixed Invalid Zone [%d:%d] -> [%d:%d] (%s) - %s", c, z, d.c, d.z, legacyName, tostring(d.il)))
                        end
                    end
                end
            end
        end
    end
    
    for _, guid in ipairs(toRemove) do
        discoveries[guid] = nil
    end
    for guid, record in pairs(toAdd) do
        discoveries[guid] = record
    end
    
    if fixedCount > 0 then
         if L.db and L.db.char and L.db.char.looted then
            local newLooted = {}
            local charFixed = false
            for guid, timestamp in pairs(L.db.char.looted) do
                if guidRemap[guid] then
                    newLooted[guidRemap[guid]] = timestamp
                    charFixed = true
                else
                    newLooted[guid] = timestamp
                end
            end
            if charFixed then
                L.db.char.looted = newLooted
            end
        end
        print(string.format("|cff00ff00LootCollector:|r Fixed %d records with invalid zone combinations.", fixedCount))
        
        
        if self.RebuildZoneIndex then
            self:RebuildZoneIndex()
        end
        
        local Map = L:GetModule("Map", true)
        if Map then
            Map.cacheIsDirty = true
            if Map.Update then Map:Update() end
        end
        L:SendMessage("LOOTCOLLECTOR_DISCOVERY_LIST_UPDATED")
    else
        print("|cff00ff00LootCollector:|r No invalid zone combinations found.")
    end
end
