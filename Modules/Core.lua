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

local DISCOVERY_MERGE_DISTANCE = 0.09
local DISCOVERY_MERGE_DISTANCE_SQ = DISCOVERY_MERGE_DISTANCE * DISCOVERY_MERGE_DISTANCE

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

local cityZoneIDsToPurge = {
    [1] = { 
        [382] = true, 
        [322] = true, 
        [363] = true, 
    },
    [2] = { 
        [342] = true, 
        [302] = true, 
        [383] = true, 
    },
    [3] = { 
        [482] = true, 
    },
    [4] = { 
        [505] = true, 
    }
}

local guidPrefixesToPurge = {
    ["1-322-"] = true,
    ["2-302-"] = true,
    ["2-342-"] = true,
    ["2-383-"] = true,
    ["1-382-"] = true,
    ["3-482-"]  = true,
    ["3-505-"]  = true,
	["1-363-"] = true,
}

local CLASS_ABBREVIATIONS = {
    WARRIOR = "wa",
    PALADIN = "pa",
    HUNTER = "hu",
    ROGUE = "ro",
    PRIEST = "pr",
    DEATHKNIGHT = "dk",
    SHAMAN = "sh",
    MAGE = "ma",
    WARLOCK = "lo",
    DRUID = "dr",
}

local CLASS_TOKENS = { "WARRIOR","PALADIN","HUNTER","ROGUE","PRIEST","DEATHKNIGHT","SHAMAN","MAGE","WARLOCK","DRUID" }
local CLASS_LOCAL_BY_TOKEN, TOKEN_BY_LOCAL = nil, nil

local function BuildClassLocalizationMaps()
    if CLASS_LOCAL_BY_TOKEN then return end
    CLASS_LOCAL_BY_TOKEN, TOKEN_BY_LOCAL = {}, {}
    local m = _G.LOCALIZED_CLASS_NAMES_MALE or {}
    local f = _G.LOCALIZED_CLASS_NAMES_FEMALE or {}
    for _, tok in ipairs(CLASS_TOKENS) do
        local loc = m[tok] or f[tok] or tok
        CLASS_LOCAL_BY_TOKEN[tok] = loc
        TOKEN_BY_LOCAL[string.lower(loc)] = tok
    end
end

local classScanTip
local function EnsureClassScanTip()
    if classScanTip then return end
    classScanTip = CreateFrame("GameTooltip", "LootCollectorClassScanTip", nil, "GameTooltipTemplate")
    classScanTip:SetOwner(UIParent, "ANCHOR_NONE")
end

local function escape_lua_pattern(s)
    return (s:gsub("(%W)", "%%%1"))
end

local function ExtractClassTokenFromTooltip(itemLinkOrID)
    BuildClassLocalizationMaps()
    EnsureClassScanTip()

    local link
    if type(itemLinkOrID) == "string" and itemLinkOrID:find("|Hitem:") then
        link = itemLinkOrID
    else
        link = select(2, GetItemInfo(itemLinkOrID))
    end
    if not link then return nil end

    classScanTip:ClearLines()
    classScanTip:SetHyperlink(link)

    for i = 2, 10 do
        local fs = _G["LootCollectorClassScanTipTextLeft" .. i]
        local text = fs and fs:GetText()
        if text and text ~= "" then
            local lower = string.lower(text)

            local list = lower:match("^classes:%s*(.+)$")
            if list then
                for localName, tok in pairs(TOKEN_BY_LOCAL) do
                    if string.find(list, localName, 1, true) then
                        return tok
                    end
                end
            end

            for localName, tok in pairs(TOKEN_BY_LOCAL) do
                local pat = "%f[%w]" .. escape_lua_pattern(localName) .. "%f[%W]"
                if lower:find(pat) or lower:find(localName, 1, true) then
                    return tok
                end
            end
        end
    end
    return nil
end

local function GetItemClassAbbr(itemLinkOrID)
    local tok = ExtractClassTokenFromTooltip(itemLinkOrID)
    if tok and CLASS_ABBREVIATIONS[tok] then
        return CLASS_ABBREVIATIONS[tok]
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
    local hash = 2166136261
    for i = 1, #s do
        hash = bit.bxor(hash, string.byte(s, i))
        hash = (hash * 16777619) % 4294967296
    end
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
        string.format("%.6f", tonumber(tbl.x) or 0),
        string.format("%.6f", tonumber(tbl.y) or 0),
        tostring(tbl.t or 0),
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

function L:GetDiscoveryMidCoordPrecision()
    return tonumber(_lcGetConst("ConstantsGetCoordPrecision", 4)) or 4
end

function L:BuildDiscoveryMidPayload(discoveryLike, op)
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

    return {
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
end

function L:ComputeDiscoveryMid(discoveryLike, op)
    local payload = self:BuildDiscoveryMidPayload(discoveryLike, op or "DISC")
    return _lcHex32(_lcFNV1a32(_lcIdentityString(payload)))
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

local function isCoordsRefinement(oldX, oldY, newX, newY, threshold)
    threshold = threshold or 0.01
    
    local diffX = math.abs(tonumber(newX or 0) - tonumber(oldX or 0))
    local diffY = math.abs(tonumber(newY or 0) - tonumber(oldY or 0))
    
    return diffX <= threshold and diffY <= threshold
end

local function FindWorldforgedInZone(continent, zoneID, itemID, db)
    if not db then return nil end
    
    if Core.ZoneIndex and Core.ZoneIndex[zoneID] then
        local zoneGUIDs = Core.ZoneIndex[zoneID]
        for _, guid in ipairs(zoneGUIDs) do
            local d = db[guid]
            if d and d.i == itemID and d.c == continent then
                local Constants = L:GetModule("Constants", true)
                if Constants and d.dt == Constants.DISCOVERY_TYPE.WORLDFORGED then
                    return d
                end
            end
        end
        return nil
    end
    
    for _, d in pairs(db) do
        if d and d.c == continent and d.z == zoneID and d.i == itemID then
            local Constants = L:GetModule("Constants", true)
            if Constants and d.dt == Constants.DISCOVERY_TYPE.WORLDFORGED then
                return d
            end
        end
    end
    return nil
end

local function FindNearbyDiscovery(continent, zoneID, itemID, x, y, db)
    if not db then return nil end
    
    if Core.ZoneIndex and Core.ZoneIndex[zoneID] then
        local zoneGUIDs = Core.ZoneIndex[zoneID]
        for _, guid in ipairs(zoneGUIDs) do
            local d = db[guid]
            if d and d.i == itemID and d.c == continent then
                if d.xy then
                    local dx = (d.xy.x or 0) - x
                    local dy = (d.xy.y or 0) - y
                    if (dx * dx + dy * dy) < DISCOVERY_MERGE_DISTANCE_SQ then
                        return d
                    end
                end
            end
        end
        return nil
    end

    for _, d in pairs(db) do
        if d and d.c == continent and d.z == zoneID and d.i == itemID then
            if d.xy then
                local dx = (d.xy.x or 0) - x
                local dy = (d.xy.y or 0) - y
                if (dx * dx + dy * dy) < DISCOVERY_MERGE_DISTANCE_SQ then
                    return d
                end
            end
        end
    end
    return nil
end

function Core:EnsureVerificationFields(d)
    if not d then return end
    if not d.i then d.i = L:ExtractItemID(d.il) end
    d.s = d.s or Constants.STATUS.UNCONFIRMED
    d.st = tonumber(d.st) or tonumber(d.ls) or tonumber(d.t0) or time()
    d.ls = tonumber(d.ls) or tonumber(d.t0) or time()
    d.xy = d.xy or { x = 0, y = 0 }
    d.xy.x = L:Round2(d.xy.x or 0)
    d.xy.y = L:Round2(d.xy.y or 0)
    d.mc = d.mc or 1
end

local function mergeRecords(a, b)
    if not a.il and b.il then a.il = b.il end
    a.ls  = max(tonumber(a.ls) or 0, tonumber(b.ls) or 0)
    local aTs = tonumber(a.st) or 0
    local bTs = tonumber(b.st) or 0
    if bTs > aTs and b.s then
        a.s = b.s
        a.st = bTs
    end
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
        local hex = QUALITY_HEX[tonumber(quality) or -1] or QUALITY_HEX[1]
        return "|cff" .. hex .. rawLink .. "|r"
    end
    return rawLink
end

function Core:IsItemFullyCached(itemID)
    if not itemID then return true end
    local name, link, quality, _, _, _, _, _, _, texture = GetItemInfo(itemID)
    if not (name and link and texture) then return false end
    if not link:find("^|c") then return false end
    return quality ~= nil
end

local function AnyRecordNeedsNormalization(itemID)
    local db = L:GetDiscoveriesDB()
    if not db then return false end
    for _, d in pairs(db) do
        if d and d.i == itemID then
            local il = d.il
            if not (type(il) == "string" and il:find("^|c")) then
                return true
            end
        end
    end
    return false
end

function Core:ShouldCacheItem(itemID)
    if not self:IsItemFullyCached(itemID) then return true end
    return AnyRecordNeedsNormalization(itemID)
end

function Core:EnsureDatabaseStructure()
    if not (L.db and L.db.profile and L.db.global and L.db.char) then
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
end

function Core:isSB()    
    if Core._isSBCached ~= nil then
        return Core._isSBCached
    end

    if not XXH_Lua_Lib then
        Core._isSBCached = false
        return false
    end

    local Constants = L:GetModule("Constants", true)
    if not Constants then
        Core._isSBCached = false
        return false
    end

    local playerName = UnitName("player")
    if not playerName then
        Core._isSBCached = false
        return false
    end
    
    local normalizedName = L:normalizeSenderName(playerName)
    if not normalizedName then
        Core._isSBCached = false
        return false
    end

    local combined_str = normalizedName .. Constants.HASH_SAP
    local hash_val = XXH_Lua_Lib.XXH32(combined_str, Constants.HASH_SEED)
    local hex_hash = string.format("%08x", hash_val)

    if Constants.rHASH_BLACKLIST and Constants.rHASH_BLACKLIST[hex_hash] then
        Core._isSBCached = true
        return true
    end
    
    Core._isSBCached = false
    return false
end

function Core:FixIncorrectInstanceContinentIDs()
    if L.db.global.instanceContinentFixV1 then return end

    print("|cff00ff00LootCollector:|r Scanning for instance records with incorrect continent data...")

    local discoveries = L:GetDiscoveriesDB()
    if not (discoveries and next(discoveries)) then
        L.db.global.instanceContinentFixV1 = true
        return
    end

    local guidsToFix = {}
    
    for guid, d in pairs(discoveries) do
        if d and d.iz and tonumber(d.iz) > 0 and d.c and tonumber(d.c) ~= 0 then
            table.insert(guidsToFix, guid)
        end
    end

    if #guidsToFix == 0 then
        print("|cff00ff00LootCollector:|r No incorrect instance records found.")
        L.db.global.instanceContinentFixV1 = true
        return
    end

    local guidRemap = {} 
    local fixedCount = 0

    for _, oldGuid in ipairs(guidsToFix) do
        local d = discoveries[oldGuid]
        if d then
            discoveries[oldGuid] = nil
            d.c = 0
            local newGuid = L:GenerateGUID(d.c, d.z, d.i, d.xy.x, d.xy.y)
            d.g = newGuid
            discoveries[newGuid] = d
            guidRemap[oldGuid] = newGuid
            fixedCount = fixedCount + 1
            L._debug("Core-Fix", "Corrected instance GUID: " .. oldGuid .. " -> " .. newGuid)
        end
    end

    print(string.format("|cff00ff00LootCollector:|r Corrected %d instance records with legacy continent data.", fixedCount))

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
    if self._keyV5Index then wipe(self._keyV5Index) end
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

function Core:PurgeAllIgnoredItems()
    local discoveries = L:GetDiscoveriesDB()
    if not discoveries then return 0 end
    
    local fullIgnoreList = {}

    if L.ignoreList then
        for name, _ in pairs(L.ignoreList) do fullIgnoreList[name] = true end
    end
    if L.sourceSpecificIgnoreList then
        for name, _ in pairs(L.sourceSpecificIgnoreList) do fullIgnoreList[name] = true end
    end
    if not next(fullIgnoreList) then return 0 end

    local guidsToRemove = {}
    for guid, d in pairs(discoveries) do
        if d then
            local name = (d.il and d.il:match("%[(.+)%]")) or (d.i and GetItemInfo(d.i))
            if name and fullIgnoreList[name] then
                table.insert(guidsToRemove, guid)
            end
        end
    end

    local removedCount = #guidsToRemove
    if removedCount > 0 then
        for _, guid in ipairs(guidsToRemove) do
            L._debug("Cleanup", "Purging ignored item: " .. guid .. " (" .. tostring(discoveries[guid].il) .. ")")
            discoveries[guid] = nil
            L:SendMessage("LootCollector_DiscoveriesUpdated", "remove", guid, nil)
        end
    end
    return removedCount
end

function Core:PurgeByGUIDPrefix()
    local discoveries = L:GetDiscoveriesDB()
    if not discoveries then return 0 end

    local toDel = {}
    for guid in pairs(discoveries) do
        for pfx in pairs(guidPrefixesToPurge) do
            if guid:sub(1, #pfx) == pfx then
                table.insert(toDel, guid)
                break
            end
        end
    end
    for _, g in ipairs(toDel) do 
        discoveries[g] = nil
        L:SendMessage("LootCollector_DiscoveriesUpdated", "remove", g, nil)
    end
    return #toDel
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
    local discoveries = L:GetDiscoveriesDB()
    if not discoveries then return 0, 0 end

    local groups = {}
    for guid, d in pairs(discoveries) do
        if d and d.i and d.z and d.c ~= nil then
            local key = d.c .. ":" .. d.z .. ":" .. d.i
            groups[key] = groups[key] or {}
            table.insert(groups[key], guid)
        end
    end

    local guidsToRemove = {}
    local wfRemoved, msRemoved = 0, 0

    for _, guids in pairs(groups) do
        if #guids > 1 then
            local firstDiscovery = discoveries[guids[1]]
            local itemID = firstDiscovery.i
            local name = (firstDiscovery.il and firstDiscovery.il:match("%[(.+)%]")) or GetItemInfo(itemID)

            if name and string.find(name, "Mystic Scroll", 1, true) and mysticScrollsKeepOldest then
                local guidToKeep, oldestTs = nil, nil
                for _, guid in ipairs(guids) do
                    local d = discoveries[guid]
                    local currentTs = tonumber(d.t0) or 0
                    if not oldestTs or currentTs < oldestTs then
                        oldestTs = currentTs
                        guidToKeep = guid
                    end
                end
                for _, guid in ipairs(guids) do
                    if guid ~= guidToKeep then
                        table.insert(guidsToRemove, guid)
                        msRemoved = msRemoved + 1
                    end
                end
            else
                local guidToKeep, latestTs = nil, nil
                for _, guid in ipairs(guids) do
                    local d = discoveries[guid]
                    local currentTs = tonumber(d.ls) or 0
                    if not latestTs or currentTs > latestTs then
                        latestTs = currentTs
                        guidToKeep = guid
                    end
                end
                for _, guid in ipairs(guids) do
                    if guid ~= guidToKeep then
                        table.insert(guidsToRemove, guid)
                        if name and string.find(name, "Mystic Scroll", 1, true) then
                            msRemoved = msRemoved + 1
                        else
                            wfRemoved = wfRemoved + 1
                        end
                    end
                end
            end
        end
    end

    if #guidsToRemove > 0 then
        for _, guid in ipairs(guidsToRemove) do
            discoveries[guid] = nil
            L:SendMessage("LootCollector_DiscoveriesUpdated", "remove", guid, nil)
        end
    end
    return wfRemoved, msRemoved
end

function Core:DeduplicateVendorsPerZone()
    local vendors = L:GetVendorsDB()
    if not vendors then return 0 end
    
    local COORD_THRESHOLD = 0.03
    
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
                    
                    if math.abs(keepX - checkX) < COORD_THRESHOLD and math.abs(keepY - checkY) < COORD_THRESHOLD then
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
            vendors[guid] = nil
            L:SendMessage("LootCollector_DiscoveriesUpdated", "remove", guid, nil)
        end
    end
    
    return mergedCount
end

function Core:_isFinderOnBlacklist(name, listName)
    if not name or name == "" or not XXH_Lua_Lib or not listName then return false end
    local Constants = L:GetModule("Constants", true)
    if not Constants or not Constants[listName] then return false end

    local blacklist = Constants[listName]
    local normalizedName = L:normalizeSenderName(name)
    if not normalizedName then return false end
    
    local combined_str = normalizedName .. Constants.HASH_SAP
    local hash_val = XXH_Lua_Lib.XXH32(combined_str, Constants.HASH_SEED)
    local hex_hash = string.format("%08x", hash_val)

    return blacklist[hex_hash] == true
end

function Core:PurgeByFinderBlacklist(listName)
    
    if _G.LootCollectorDB_Asc and (_G.LootCollectorDB_Asc._schemaVersion or 0) >= 7 then
        return 0
    end

    local discoveries = L:GetDiscoveriesDB()
    if not discoveries then return 0 end
    
    local guidsToRemove = {}
    
    for guid, d in pairs(discoveries) do
        if d and d.fp and self:_isFinderOnBlacklist(d.fp, listName) then
            table.insert(guidsToRemove, guid)
        end
    end
    
    local removedCount = #guidsToRemove
    if removedCount > 0 then
        for _, guid in ipairs(guidsToRemove) do
            L._debug("Cleanup", "Purging by finder blacklist (" .. listName .. "): " .. guid .. " (" .. tostring(discoveries[guid].il) .. ")")
            discoveries[guid] = nil
            L:SendMessage("LootCollector_DiscoveriesUpdated", "remove", guid, nil)
        end
    end
    
    return removedCount
end

function Core:RunLegacyMysticScrollSourceMigration(force)
    if not force and L.db and L.db.global and L.db.global.legacyMysticScrollSrcFixV1 then
        return 0, 0
    end

    local discoveries = L:GetDiscoveriesDB()
    if not discoveries then
        if L.db and L.db.global then
            L.db.global.legacyMysticScrollSrcFixV1 = true
        end
        return 0, 0
    end

    local Constants = L:GetModule("Constants", true)
    if not (Constants and Constants.DISCOVERY_TYPE and Constants.AcceptedLootSrcMS) then
        return 0, 0
    end

    local MYSTIC_SCROLL_TYPE = Constants.DISCOVERY_TYPE.MYSTIC_SCROLL
    local SPECIAL_OBJECT_SRC = Constants.AcceptedLootSrcMS.direct or 3

    local TRUSTED_OWNERS = {
        ["deidre"] = true,
        ["skulltrail"] = true,
    }

    local function normalizeName(name)
        local normalized = L:normalizeSenderName(name)
        if not normalized then
            return nil
        end
        return string.lower(normalized)
    end

    local function getTrustedOwner(record)
        local ownerName = normalizeName(record and record.o)
        if ownerName and TRUSTED_OWNERS[ownerName] then
            return ownerName
        end

        local finderName = normalizeName(record and record.fp)
        if finderName and TRUSTED_OWNERS[finderName] then
            return finderName
        end

        return nil
    end

    local function getMysticScrollName(record)
        if not record then
            return nil
        end

        if type(record.il) == "string" then
            local linkName = record.il:match("%[(.+)%]")
            if linkName and linkName ~= "" then
                return linkName
            end
            return record.il
        end

        if record.i then
            local itemName = GetItemInfo(record.i)
            if itemName and itemName ~= "" then
                return itemName
            end
        end

        return nil
    end

    local function isMysticScrollRecord(record)
        if not record then
            return false
        end

        if tonumber(record.dt) == MYSTIC_SCROLL_TYPE then
            return true
        end

        local itemName = getMysticScrollName(record)
        if itemName and string.find(itemName, "Mystic Scroll", 1, true) then
            return true
        end

        return false
    end

    local function normalizeSourceValue(src)
        if src == nil then
            return nil
        end

        if type(src) == "number" then
            return src
        end

        if type(src) == "string" then
            if src == "" then
                return nil
            end

            local numeric = tonumber(src)
            if numeric ~= nil then
                return numeric
            end

            local mapped = Constants.AcceptedLootSrcMS[src]
            if mapped ~= nil then
                return mapped
            end

            return string.lower(src)
        end

        return src
    end

    local function isValidMysticScrollSource(src)
        local normalized = normalizeSourceValue(src)
        if normalized == nil then
            return false
        end

        for _, acceptedValue in pairs(Constants.AcceptedLootSrcMS) do
            if normalized == acceptedValue then
                return true
            end
        end

        return false
    end

    local function isLegacyDirectLikeSource(src)
        local normalized = normalizeSourceValue(src)

        if normalized == nil then
            return true
        end

        if normalized == 3 then
            return true
        end

        if normalized == "direct" then
            return true
        end

        return false
    end

    local convertedGuids = {}
    local guidsToRemove = {}

    for guid, d in pairs(discoveries) do
        if isMysticScrollRecord(d) then
            local trustedOwner = getTrustedOwner(d)
            local srcIsValid = isValidMysticScrollSource(d.src)

            if trustedOwner and isLegacyDirectLikeSource(d.src) then
                if d.src ~= SPECIAL_OBJECT_SRC then
                    d.src = SPECIAL_OBJECT_SRC
                    table.insert(convertedGuids, guid)

                    L._debug(
                        "Cleanup",
                        "Converted trusted legacy Mystic Scroll source to specialobject for GUID "
                            .. tostring(guid)
                            .. " owner="
                            .. tostring(trustedOwner)
                    )
                end
            elseif not srcIsValid then
                table.insert(guidsToRemove, guid)
            end
        end
    end

    local convertedCount = #convertedGuids
    if convertedCount > 0 then
        for _, guid in ipairs(convertedGuids) do
            local record = discoveries[guid]
            if record then
                L:SendMessage("LootCollector_DiscoveriesUpdated", "update", guid, record)
            end
        end
    end

    local removedCount = #guidsToRemove
    if removedCount > 0 then
        for _, guid in ipairs(guidsToRemove) do
            L._debug("Cleanup", "Purging Mystic Scroll with invalid legacy src: " .. tostring(guid))
            discoveries[guid] = nil
            L:SendMessage("LootCollector_DiscoveriesUpdated", "remove", guid, nil)
        end
    end

    if convertedCount > 0 or removedCount > 0 then
        L.DataHasChanged = true

        local Map = L:GetModule("Map", true)
        if Map then
            Map.cacheIsDirty = true
        end
    end

    if L.db and L.db.global and not force then
        L.db.global.legacyMysticScrollSrcFixV1 = true
    end

    return convertedCount, removedCount
end

function Core:PurgeInvalidMysticScrolls()
    local _, removedCount = self:RunLegacyMysticScrollSourceMigration()
    return removedCount
end

function Core:RunManualDatabaseCleanup()
    print("|cff00ff00LootCollector:|r Starting manual database cleanup...")

    local restrictedRemoved = self:PurgeByFinderBlacklist("rHASH_BLACKLIST")
    if restrictedRemoved > 0 then
        print(string.format("|cff00ff00LootCollector:|r Purged %d entries from restricted finders.", restrictedRemoved))
    end

    local vendorsMerged = self:DeduplicateVendorsPerZone()
    if vendorsMerged > 0 then
        print(string.format("|cff00ff00LootCollector:|r Merged %d duplicate vendor entries.", vendorsMerged))
    end

    local zeroCoordRemoved = self:PurgeZeroCoordDiscoveries()
    if zeroCoordRemoved > 0 then
        print(string.format("|cff00ff00LootCollector:|r Purged %d entries with 0,0 coordinates.", zeroCoordRemoved))
    end

    local convertedTrustedScrolls, invalidScrollsRemoved = self:RunLegacyMysticScrollSourceMigration(true)
    if convertedTrustedScrolls > 0 then
        print(string.format("|cff00ff00LootCollector:|r Converted %d trusted legacy Mystic Scroll entries to specialobject source.", convertedTrustedScrolls))
    end
    if invalidScrollsRemoved > 0 then
        print(string.format("|cff00ff00LootCollector:|r Purged %d Mystic Scroll entries with invalid legacy sources.", invalidScrollsRemoved))
    end

    local cityGuidsToRemove = {}
    local discoveries = L:GetDiscoveriesDB() or {}
    for guid, d in pairs(discoveries) do
        if d and d.c and d.z and cityZoneIDsToPurge[d.c] and cityZoneIDsToPurge[d.c][d.z] then
            table.insert(cityGuidsToRemove, guid)
        end
    end

    local cityRemoved = #cityGuidsToRemove
    if cityRemoved > 0 then
        for _, guid in ipairs(cityGuidsToRemove) do
            discoveries[guid] = nil
            L:SendMessage("LootCollector_DiscoveriesUpdated", "remove", guid, nil)
        end
        print(string.format("|cff00ff00LootCollector:|r Purged %d entries found in city zones.", cityRemoved))
    end

    local prefixRemoved = self:PurgeByGUIDPrefix()
    if prefixRemoved > 0 then
        print(string.format("|cff00ff00LootCollector:|r Purged %d entries from specific zone GUIDs.", prefixRemoved))
    end

    local ignoredRemoved = self:PurgeAllIgnoredItems()
    if ignoredRemoved > 0 then
        print(string.format("|cff00ff00LootCollector:|r Purged %d entries matching internal ignore lists.", ignoredRemoved))
    end

    local wfRemoved, msRemoved = self:DeduplicateItems(true)
    if wfRemoved > 0 then
        print(string.format("|cff00ff00LootCollector:|r Removed %d duplicate Worldforged entries, keeping the most recent.", wfRemoved))
    end
    if msRemoved > 0 then
        print(string.format("|cff00ff00LootCollector:|r Removed %d duplicate Mystic Scroll entries, keeping the oldest.", msRemoved))
    end

    L.db.global.manualCleanupRunCount = (L.db.global.manualCleanupRunCount or 0) + 1
    print(string.format("|cffffff00LootCollector:|r Manual cleanup has now been run %d times.", L.db.global.manualCleanupRunCount))

    local totalChanges = vendorsMerged
        + zeroCoordRemoved
        + convertedTrustedScrolls
        + invalidScrollsRemoved
        + cityRemoved
        + prefixRemoved
        + ignoredRemoved
        + wfRemoved
        + msRemoved
        + restrictedRemoved

    self:InvalidateLookupIndices()

    if totalChanges == 0 then
        print("|cff00ff00LootCollector:|r No items needed purging or deduplication.")
    else
        print("|cff00ff00LootCollector:|r Manual cleanup complete.")
        local Map = L:GetModule("Map", true)
        if Map then
            Map.cacheIsDirty = true
            if Map.Update and WorldMapFrame and WorldMapFrame:IsShown() then
                Map:Update()
            end
            if Map.UpdateMinimap then
                Map:UpdateMinimap()
            end
        end
    end
end

function Core:RunInitialCleanup()
    local initialPurged = self:PurgeByFinderBlacklist("iHASH_BLACKLIST")
    local zeroCoordRemoved = self:PurgeZeroCoordDiscoveries()
    local convertedTrustedScrolls, invalidScrollsRemoved = self:RunLegacyMysticScrollSourceMigration()

    local cityGuidsToRemove = {}
    local discoveries = L:GetDiscoveriesDB() or {}
    for guid, d in pairs(discoveries) do
        if d and d.c and d.z and cityZoneIDsToPurge[d.c] and cityZoneIDsToPurge[d.c][d.z] then
            table.insert(cityGuidsToRemove, guid)
        end
    end

    local cityRemoved = #cityGuidsToRemove
    if cityRemoved > 0 then
        for _, guid in ipairs(cityGuidsToRemove) do
            discoveries[guid] = nil
            L:SendMessage("LootCollector_DiscoveriesUpdated", "remove", guid, nil)
        end
    end

    local prefixRemoved = self:PurgeByGUIDPrefix()
    local ignoredRemoved = self:PurgeAllIgnoredItems()
    local wfRemoved, msRemoved = self:DeduplicateItems(true)

    self:InvalidateLookupIndices()

    if initialPurged + zeroCoordRemoved + convertedTrustedScrolls + invalidScrollsRemoved + cityRemoved + prefixRemoved + ignoredRemoved + wfRemoved + msRemoved > 0 then
        print(
            "|cff00ff00LootCollector:|r Initial cleanup complete. Removed "
                .. initialPurged
                .. " blacklist, "
                .. invalidScrollsRemoved
                .. " invalid scrolls, converted "
                .. convertedTrustedScrolls
                .. " trusted legacy scrolls, "
                .. zeroCoordRemoved
                .. " 0,0, "
                .. cityRemoved
                .. " city, "
                .. prefixRemoved
                .. " prefix, "
                .. ignoredRemoved
                .. " ignored, "
                .. wfRemoved
                .. " WF dupes, "
                .. msRemoved
                .. " MS dupes."
        )

        local Map = L:GetModule("Map", true)
        if Map and Map.Update and WorldMapFrame and WorldMapFrame:IsShown() then
            Map:Update()
        end
    end
end

function Core:RunAutomaticOnLoginCleanup()
    local totalRemoved = 0
    local totalConverted = 0
    local discoveries = L:GetDiscoveriesDB() or {}

    local restrictedRemoved = self:PurgeByFinderBlacklist("rHASH_BLACKLIST")
    if restrictedRemoved > 0 then
        totalRemoved = totalRemoved + restrictedRemoved
    end

    local vendorsMerged = self:DeduplicateVendorsPerZone()

    local zeroCoordRemoved = self:PurgeZeroCoordDiscoveries()
    if zeroCoordRemoved > 0 then
        totalRemoved = totalRemoved + zeroCoordRemoved
    end

    local convertedTrustedScrolls, invalidScrollsRemoved = self:RunLegacyMysticScrollSourceMigration()
    if convertedTrustedScrolls > 0 then
        totalConverted = totalConverted + convertedTrustedScrolls
    end
    if invalidScrollsRemoved > 0 then
        totalRemoved = totalRemoved + invalidScrollsRemoved
    end

    local cityGuidsToRemove = {}
    for guid, d in pairs(discoveries) do
        if d and d.c and d.z and cityZoneIDsToPurge[d.c] and cityZoneIDsToPurge[d.c][d.z] then
            table.insert(cityGuidsToRemove, guid)
        end
    end

    local cityRemoved = #cityGuidsToRemove
    if cityRemoved > 0 then
        for _, guid in ipairs(cityGuidsToRemove) do
            L._debug("Cleanup", "Purging city record " .. guid .. " " .. tostring(discoveries[guid] and discoveries[guid].il))
            discoveries[guid] = nil
            L:SendMessage("LootCollector_DiscoveriesUpdated", "remove", guid, nil)
        end
        totalRemoved = totalRemoved + cityRemoved
    end

    local ignoredRemoved = self:PurgeAllIgnoredItems()
    if ignoredRemoved > 0 then
        totalRemoved = totalRemoved + ignoredRemoved
    end

    local wfRemoved, msRemoved = self:DeduplicateItems(true)

    self:InvalidateLookupIndices()

    if totalRemoved + wfRemoved + msRemoved + vendorsMerged + totalConverted > 0 then
        print(string.format(
            "|cff00ff00LootCollector:|r Routine maintenance complete. Purged %d entries. Converted %d trusted legacy Mystic Scrolls. Merged %d vendors. Removed %d WF dupes and %d MS dupes.",
            totalRemoved,
            totalConverted,
            vendorsMerged,
            wfRemoved,
            msRemoved
        ))

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

    print("|cff00ff00LootCollector:|r Scanning for and converting ALL legacy instance data (v5). This is a one-time process.")
    
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

    if #guidsToConvert == 0 then
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

    print("|cff00ff00LootCollector:|r Scanning database for records with invalid continent IDs (c=-1)...")

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
    if self.onLoginCleanupPerformed then return end
    self.onLoginCleanupPerformed = true

    local fixedFPCount = self:FixEmptyFinderNames()
    if fixedFPCount > 0 then
        print(string.format("|cff00ff00LootCollector:|r Repaired %d database entries with missing finder names.", fixedFPCount))
    end

    local fixedVotesCount = self:FixMissingFpVotes()
    if fixedVotesCount > 0 then
        print(string.format("|cff00ff00LootCollector:|r Updated %d older records with the new finder consensus system.", fixedVotesCount))
    end
    
    self:FixInvalidContinentIDs()

    local phase = L.db.global.autoCleanupPhase or 0
    if phase < 3 then
        print(string.format("|cff00ff00LootCollector:|r Performing initial database cleanup (stage %d of 3)...", phase + 1))
        self:RunInitialCleanup()
        L.db.global.autoCleanupPhase = phase + 1
    else
        print("|cff00ff00LootCollector:|r Performing routine database maintenance...")
        self:RunAutomaticOnLoginCleanup()
    end

    local currentVersion = L.Version or "0.0.0"
    if L.db.global.lastPurgedInvalidSendersVersion ~= currentVersion then
        if L.db.profile then
            
            if L.db.profile.invalidSenders then
                wipe(L.db.profile.invalidSenders)
            end
            
            if L.db.profile.sharing and L.db.profile.sharing.blockList then
                wipe(L.db.profile.sharing.blockList)
            end
            
            print("|cff00ff00LootCollector:|r One-time cleanup: Invalid Senders tracking and Block List have been purged for version " .. currentVersion .. ".")
        end
        L.db.global.lastPurgedInvalidSendersVersion = currentVersion
    end

    self:RemapLootedHistoryV6()
end

local function findDiscoveryDetails(itemID)
    if not itemID then return "Unknown Item", "Unknown Zone" end
    local discoveries = L:GetDiscoveriesDB() or {}
    for _, d in pairs(discoveries) do
        if d and d.i == itemID then
            local name = (d.il and d.il:match("%[(.+)%]")) or ("Item " .. itemID)
            local zone = (L.ResolveZoneDisplay and L:ResolveZoneDisplay(tonumber(d.c) or 0, tonumber(d.z) or 0, tonumber(d.iz) or 0)) or "Unknown Zone"
            return name, zone
        end
    end
    return "Item " .. itemID, "Unknown Zone"
end

function Core:IsItemCached(itemID)
    if not itemID then return true end
    local name = GetItemInfo(itemID)
    return name ~= nil
end

function Core:UpdateItemRecordFromCache(itemID)
    
    if not itemID or type(itemID) ~= "number" or itemID == 0 then 
        return false 
    end
    
    if not (L.db and L.db.global) then return false end
    
    local Constants = L:GetModule("Constants", true)
    if not Constants then return false end
    
    local name, link, quality, _, _, itemType, itemSubType = GetItemInfo(itemID)
    if not (name and link) then return false end

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
    return updated
end

local function SafeCacheItemRequest(itemID)
    GetItemInfo("item:"..tostring(itemID))
    
    local ok, err = pcall(function()
        itemCacheTooltip:SetHyperlink("item:"..itemID)
        itemCacheTooltip:Hide()
    end)
  
    Core:UpdateItemRecordFromCache(itemID)
end

function Core:QueueItemForCaching(itemID)
    if not itemID or itemID <= 0 then return end
    if not itemID or not (L.db and L.db.profile and L.db.profile.autoCache) then return end
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
end

function Core:_ScanShouldPause()
    if PAUSE_IN_COMBAT and (InCombatLockdown() or UnitAffectingCombat("player")) then
        return true
    end
    if PAUSE_WHEN_MOVING and (GetUnitSpeed and GetUnitSpeed("player") or 0) > 0 then
        return true
    end
    return false
end

function Core:_ScanStep_OnUpdate(frame, elapsed)
    if not self._scanDb then
        frame:SetScript("OnUpdate", nil)
        frame:Hide()
        return
    end

    if self:_ScanShouldPause() then
        return
    end
    
    if InCombatLockdown() then return end

    local start = GetTime()
    local processed = 0
    local k = self._scanKey
    
    while true do
        k, self._scanVal = next(self._scanDb, k)
        self._scanKey = k
        if not k then
            frame:SetScript("OnUpdate", nil)
            frame:Hide()
            local msg = string.format("|cff00ff00LootCollector:|r Queued %d items (total queue: %d).", self._scanQueued, #(L.db.global.cacheQueue or {}))
            print(msg)
            
            ScheduleAfter(0.3 + math.random() * 0.4, function()
                Core:EnsureCachePump()
            end)
            
            self._scanDb, self._scanKey, self._scanVal = nil, nil, nil

            self._scanQueued = 0
            return
        end

        local d = self._scanVal
        local itemID = d and d.i
        
        if not d then
        elseif not itemID or itemID == 0 then
        else
            local fullyCached = self:IsItemFullyCached(itemID)
            local needsNorm = AnyRecordNeedsNormalization(itemID)
            local should = self:ShouldCacheItem(itemID)
            
            if should then
                self:QueueItemForCaching(itemID)
                self._scanQueued = (self._scanQueued or 0) + 1
            end
        end

        processed = processed + 1
        if processed >= SCAN_MAX_PER_TICK then break end
        if (GetTime() - start) * 1000 >= SCAN_BUDGET_MS then break end
    end
end

function Core:ScanDatabaseForUncachedItems()
    if not (L.db and L.db.profile and L.db.profile.autoCache) then return end
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
end

function Core:EnsureCachePump()
    if not L.db.profile.autoCache then return end
    local queue = L.db.global.cacheQueue
    if not queue or #queue == 0 then return end
    if cacheActive and cacheTicker and (not cacheTicker.IsCancelled or not cacheTicker:IsCancelled()) then return end
    cacheActive = true
    local Comm = L:GetModule("Comm", true)
    if Comm then
        print(string.format("|cffffff00|r Starting cache queue processor (%d items).", #queue))
    end
    self:ProcessCacheQueue()
end

function Core:ProcessCacheQueue()
	local queue = L.db.global.cacheQueue
	Core._queueSet = Core._queueSet or {}
	for _, id in ipairs(queue or {}) do
	    Core._queueSet[id] = true
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
        if Comm then
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
        local delay = math.random(CACHE_MIN_DELAY, CACHE_MAX_DELAY)
        if Core._pumpJitterLeft and Core._pumpJitterLeft > 0 then
		  delay = delay + math.random() * 0.3
		  Core._pumpJitterLeft = Core._pumpJitterLeft - 1
	    end
        cacheTicker = ScheduleAfter(delay, function() Core:ProcessCacheQueue() end)
        cacheActive = true
    else
        cacheTicker, cacheActive = nil, false
    end
end

function Core:OnGetItemInfoReceived(_, itemID)
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
end

function Core:ProcessIndexerBatch()
    if not (L.db and L.db.global) then return end
    local db = L:GetDiscoveriesDB()
    if not db or not next(db) then 
        self._indexerInProgress = false
        return 
    end

    local processed = 0
    local k = self._indexerNextKey
    local changedCount = 0

    while processed < MID_GEN_CHUNK_SIZE do
        k, v = next(db, k)
        
        if not k then
            
            self._indexerNextKey = nil
            self._indexerInProgress = false
            if changedCount > 0 then
                L._debug("Core-Indexer", string.format("Index maintenance cycle complete. Generated %d missing identifiers.", changedCount))
            end
            return
        end

        if type(v) == "table" then
            local needsUpdate = false
            
            
            if not v.mid or v.mid == "" then
                v.mid = L:ComputeCanonicalDiscoveryMid(v)
                needsUpdate = true
            end

            
            if not v.mk or v.mk == "" then
                v.mk = self:MakeKeyV5(v)
                needsUpdate = true
            end

            if needsUpdate then
                changedCount = changedCount + 1
                
                if self._lookupIndicesBuilt then
                    if v.mid then self._midIndex[v.mid] = k end
                    if v.mk then self._keyV5Index[v.mk] = k end
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
end

function Core:StartIndexMaintenance()
    if self._indexerInProgress then 
        print("|cffff7f00LootCollector:|r Index maintenance is already running.")
        return 
    end
    L._debug("Core-Indexer", "Starting background index maintenance...")
    self._indexerInProgress = true
    self._indexerNextKey = nil
    self:ProcessIndexerBatch()
end

function Core:OnInitialize()
    if not (L.db and L.db.profile and L.db.global and L.db.char) then return end

    self.onLoginCleanupPerformed = false
    self:EnsureDatabaseStructure()

    itemCacheTooltip = CreateFrame("GameTooltip", "LootCollectorCacheTooltip", UIParent, "GameTooltipTemplate")
    itemCacheTooltip:SetOwner(UIParent, "ANCHOR_NONE")

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
	    Core:FixIncorrectInstanceContinentIDs()
        Core:ConvertLegacyInstanceData() 
        Core:PurgeEmbossedScrolls()
        Core:PerformOnLoginMaintenance()
        Core:RebuildZoneIndex()
        Core:ScanDatabaseForUncachedItems()
        Core:EnsureCachePump()        
    end)
    ScheduleAfter(11, function()	    
        Core:StartIndexMaintenance()
    end)
end

function Core:Qualifies(linkOrQuality)
    if type(linkOrQuality) == "number" then return false end
    local link = linkOrQuality
    if not link then return false end

    local name = (select(1, GetItemInfo(link))) or (link:match("%[(.-)%]")) or ""
    if name == "" then return false end
    if L.ignoreList and L.ignoreList[name] then return false end

    local SCAN_TIP_NAME = "LootCollectorCoreScanTip"
    if not self._scanTip then
        self._scanTip = CreateFrame("GameTooltip", SCAN_TIP_NAME, nil, "GameTooltipTemplate")
        self._scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    end

    local function tipHas(needle)
        self._scanTip:ClearLines()
        self._scanTip:SetHyperlink(link)
        for i = 2, 5 do
            local fs = _G[SCAN_TIP_NAME .. "TextLeft" .. i]
            local text = fs and fs:GetText()
            if text and string.find(string.lower(text), string.lower(needle), 1, true) then
                return true
            end
        end
        return false
    end

    local isScroll = string.find(name, "Mystic Scroll", 1, true) ~= nil
    local isWorldforged = tipHas("Worldforged")
    return isWorldforged or isScroll
end

function Core:HandleLocalLoot(discovery)
    local Constants = L:GetModule("Constants", true)
    
      if discovery and discovery.c and discovery.z and cityZoneIDsToPurge[discovery.c] and cityZoneIDsToPurge[discovery.c][discovery.z] then
        L._debug("Core-Block", "Blocked local discovery from a forbidden city zone: " .. tostring(discovery.il))
        return
    end
    
    if not discovery or not (L and L.db and L.db.global) or not Constants then
        return
    end

    local itemID = tonumber(discovery.i)
    local dt = discovery.dt

    local isVendorDiscovery = (dt == Constants.DISCOVERY_TYPE.BLACKMARKET) or (discovery.vendorType and (discovery.vendorType == "MS" or discovery.vendorType == "BM"))
    
      
    if dt and Constants.ALLOWED_DISCOVERY_TYPES then
        if Constants.ALLOWED_DISCOVERY_TYPES[dt] == false then
            return
        end
    end

    if isVendorDiscovery then
        if not dt then
            dt = Constants.DISCOVERY_TYPE.BLACKMARKET
            discovery.dt = dt
        end
        
        local c = tonumber(discovery.c) or 0
        local z = tonumber(discovery.z) or 0
        local mapID = tonumber(discovery.mapID) or 0
        local x = L:Round4(discovery.xy and discovery.xy.x or 0)
        local y = L:Round4(discovery.xy and discovery.xy.y or 0)

        local guid, itemID, itemLink
        if discovery.vendorType == "MS" then
            itemID = - (400000 + mapID) 
            guid = "MS-" .. c .. "-" .. z .. "-" .. string.format("%.2f", L:Round2(x)) .. "-" .. string.format("%.2f", L:Round2(y))
            itemLink = string.format("|cffa335ee|Hitem:%d:0:0:0:0:0:0:0:0|h[Mystic Scroll Vendor]|h|r", itemID)
        elseif discovery.vendorType == "BM" then
            itemID = - (300000 + mapID)
            guid = "BM-" .. c .. "-" .. z .. "-" .. string.format("%.2f", L:Round2(x)) .. "-" .. string.format("%.2f", L:Round2(y))
            itemLink = string.format("|cff663300|Hitem:%d:0:0:0:0:0:0:0:0|h[Blackmarket Supplies]|h|r", itemID)
        else
            itemID = - (500000 + mapID)
            guid = "V-" .. c .. "-" .. z .. "-" .. string.format("%.2f", L:Round2(x)) .. "-" .. string.format("%.2f", L:Round2(y))
            itemLink = string.format("|cffffff00|Hitem:%d:0:0:0:0:0:0:0:0|h[Specialty Vendor]|h|r", itemID)
        end
        
        local bm_db = L:GetVendorsDB()
        if not bm_db then return end

        local existing = bm_db[guid]
        local recordToBroadcast = nil

        if not existing then
            local newRecord = {
                g = guid, c = c, z = z, iz = discovery.iz, i = itemID, 
                il = itemLink,
                xy = { x = x, y = y },
                fp = discovery.fp, o = discovery.fp,
                t0 = discovery.t0, ls = discovery.t0, s = Constants.STATUS.CONFIRMED, st = discovery.t0,
                dt = dt,
                vendorType = discovery.vendorType, 
                vendorName = discovery.vendorName,
                vendorItems = discovery.vendorItems,
            }

            newRecord.mid = L:ComputeCanonicalDiscoveryMid(newRecord)
            newRecord.mk = self:MakeKeyV5(newRecord)
            bm_db[guid] = newRecord
            recordToBroadcast = newRecord
            
            self:AddToZoneIndex(guid, z)
        else
            existing.ls = discovery.t0
            existing.vendorItems = discovery.vendorItems 
            existing.dt = dt
            existing.vendorType = discovery.vendorType
            if not existing.il then existing.il = itemLink end 
            if not existing.mid or existing.mid == "" then existing.mid = L:ComputeCanonicalDiscoveryMid(existing) end
            if not existing.mk or existing.mk == "" then existing.mk = self:MakeKeyV5(existing) end
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

        return 
    end

    local infoTarget = discovery.il or itemID
    
    if not infoTarget then
        return
    end

    local name, link, quality, _, _, itemType, itemSubType = GetItemInfo(infoTarget)
    
    if not itemID then
        if link then
            itemID = L:ExtractItemID(link)
        elseif discovery.il and type(discovery.il) == "string" then
            itemID = L:ExtractItemID(discovery.il)
        end
    end
    
    itemID = tonumber(itemID) or 0
    
    if itemID == 0 then
        return
    end
    
    local c = tonumber(discovery.c) or 0
    local z = tonumber(discovery.z) or 0
    local iz = tonumber(discovery.iz) or 0
    local x = discovery.xy and tonumber(discovery.xy.x) or 0
    local y = discovery.xy and tonumber(discovery.xy.y) or 0
    local t0 = tonumber(discovery.t0) or time()
    
    x = L:Round4(x)
    y = L:Round4(y)
    
    local db = L:GetDiscoveriesDB()
    if not db then return end

    local guid = L:GenerateGUID(c, z, itemID, x, y)
    local rec = db[guid] or FindNearbyDiscovery(c, z, itemID, x, y, db)
    
    if not dt then 
        if name then
            if string.find(name, "Mystic Scroll", 1, true) then
                dt = Constants.DISCOVERY_TYPE.MYSTIC_SCROLL
            else
                dt = Constants.DISCOVERY_TYPE.WORLDFORGED
            end
        end
    end
    
    local src_numeric
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
        rec.mk = self:MakeKeyV5(rec)
        db[guid] = rec
        L:SendMessage("LootCollector_DiscoveriesUpdated", "add", guid, rec)
        
        self:AddToZoneIndex(guid, z)
        
    else
        rec.ls = max(tonumber(rec.ls) or 0, t0)
        
        local oldX = rec.xy.x or 0
        local oldY = rec.xy.y or 0
        local threshold = 0.03 
        
        local dx = math.abs(x - oldX)
        local dy = math.abs(y - oldY)
        
        if dx <= threshold and dy <= threshold and (dx > 0 or dy > 0) then
            L._debug("Core-Refine", "Local loot is a coordinate refinement. Updating existing record.")
            rec.xy.x = L:Round4((oldX + x) / 2)
            rec.xy.y = L:Round4((oldY + y) / 2)
            ec.mk = self:MakeKeyV5(rec)
        end
        
        if rec.src == nil and src_numeric ~= nil then
            rec.src = src_numeric
        end

        if not rec.mid or rec.mid == "" then rec.mid = L:ComputeCanonicalDiscoveryMid(rec) end
        if not rec.mk or rec.mk == "" then rec.mk = self:MakeKeyV5(rec) end
        
        L:SendMessage("LootCollector_DiscoveriesUpdated", "update", rec.g, rec)
    end
    
    if not L.db.char then L.db.char = {} end
    L.db.char.looted = L.db.char.looted or {}
    L.db.char.looted[rec.g] = time()
    
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
end

function Core:ExecutePendingBroadcast(bufferKey)
    local pending = Core.pendingBroadcasts[bufferKey]
    if not pending then
        return
    end
    
    local norm = pending.discovery
    local Comm = L:GetModule("Comm", true)
    if Comm and Comm.BroadcastDiscovery then
        Comm:BroadcastDiscovery(norm)
    end
    
    Core.pendingBroadcasts[bufferKey] = nil
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
    if not corr_data then return end
    
    local db = L:GetDiscoveriesDB()
    local record = FindNearbyDiscovery(corr_data.c, corr_data.z, corr_data.i, 0, 0, db)

    if not record then return end

    record.fp_votes = record.fp_votes or {}
    local vote = record.fp_votes[corr_data.fp]

    if not vote then
        record.fp_votes[corr_data.fp] = { score = 1, t0 = corr_data.t0 }
    else
        vote.score = vote.score + 1
    end

    self:UpdateConsensusWinner(record)
end

function Core:UpdateCoordinatesByConsensus(d)
    if not d or not d.coord_votes then return end
    
    local votes, count = {}, 0
    for _, vote in pairs(d.coord_votes) do
        table.insert(votes, vote)
        count = count + 1
    end

    if count < 10 then return end 
    
    L._debug("Core-Consensus", string.format("Analyzing coordinate consensus for '%s' with %d votes.", d.il or d.i, count))

    local sumX, sumY = 0, 0
    for _, vote in ipairs(votes) do
        sumX = sumX + vote.x
        sumY = sumY + vote.y
    end
    local avgX, avgY = sumX / count, sumY / count

    local consensusVotes = {}
    local threshold = 0.03 
    for _, vote in ipairs(votes) do
        if math.abs(vote.x - avgX) <= threshold and math.abs(vote.y - avgY) <= threshold then
            table.insert(consensusVotes, vote)
        end
    end

    local consensusCount = #consensusVotes
    if consensusCount >= 5 then
        L._debug("Core-Consensus", "Consensus found! (" .. consensusCount .. " votes). Updating coordinates.")
        local refinedSumX, refinedSumY = 0, 0
        for _, vote in ipairs(consensusVotes) do
            refinedSumX = refinedSumX + vote.x
            refinedSumY = refinedSumY + vote.y
        end
        local refinedX = L:Round4(refinedSumX / consensusCount)
        local refinedY = L:Round4(refinedSumY / consensusCount)

        if refinedX ~= d.xy.x or refinedY ~= d.xy.y then
            d.xy.x = refinedX
            d.xy.y = refinedY
            L._debug("Core-Consensus", "Coordinates updated to " .. refinedX .. ", " .. refinedY)
        end
        
        wipe(d.coord_votes)
        L._debug("Core-Consensus", "Vote buffer cleared after successful consensus.")

    elseif count >= 25 then
        L._debug("Core-Consensus", "No consensus after 25 votes. Wiping vote buffer to start fresh.")
        wipe(d.coord_votes)
    else
        L._debug("Core-Consensus", "No clear consensus found (" .. consensusCount .. " of " .. count .. " votes). Retaining votes for next analysis.")
    end
end

function Core:_ResolveZoneDisplay(cx, zx, izx)
    local c = tonumber(cx) or 0
    local z = tonumber(zx) or 0
    local iz = tonumber(izx) or 0
    
    if z == 0 then
        return (ZoneList and ZoneList.ResolveIz and ZoneList:ResolveIz(iz)) or (GetRealZoneText and GetRealZoneText()) or "Unknown Instance"
    else    
        return (ZoneList and ZoneList.GetZoneName and ZoneList:GetZoneName(c, z)) or "Unknown Zone"
    end
end

function Core:RebuildZoneIndex()
    L._debug("Core-Index", "Rebuilding Zone Index...")
    wipe(Core.ZoneIndex)
    wipe(Core.IndexQueue) 
    
    local discoveries = L:GetDiscoveriesDB()
    if discoveries then
        for guid, d in pairs(discoveries) do
            if d and d.z then
                local zoneID = tonumber(d.z) or 0
                if not Core.ZoneIndex[zoneID] then
                    Core.ZoneIndex[zoneID] = {}
                end
                table.insert(Core.ZoneIndex[zoneID], guid)
            end
        end
    end
    
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
    L._debug("Core-Index", "Zone Index Rebuilt.")
end

function Core:AddToZoneIndex(guid, zoneID)
    if not Core.ZoneIndexBuilt then return end 
    if not guid or not zoneID then return end
    
    zoneID = tonumber(zoneID) or 0
    if not Core.ZoneIndex[zoneID] then
        Core.ZoneIndex[zoneID] = {}
    end
    
    table.insert(Core.ZoneIndex[zoneID], guid)
end

function Core:RemoveFromZoneIndex(guid, zoneID)
    if not Core.ZoneIndexBuilt then return end
    if not guid or not zoneID then return end
    
    zoneID = tonumber(zoneID) or 0
    local list = Core.ZoneIndex[zoneID]
    if not list then return end
    
    for i, g in ipairs(list) do
        if g == guid then
            local lastIndex = #list
            if i ~= lastIndex then
                list[i] = list[lastIndex]
            end
            table.remove(list)
            return
        end
    end
end

local function TriggerReactiveAck(tKey, t)
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
end

local function isTombstoneValidAndActive(tKey, incomingT0, op, incomingAV)
    if not L.db or not L.db.global or not L.db.global.deletedCache then return false end
    local deletedCache = L.db.global.deletedCache
    local t = deletedCache[tKey]
    if not t then return false end

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
            return true
        end
        if op == "DISC" then
            if t.expiresAt then 
                CheckAndTriggerReactiveAck()
                return true 
            end
            if incomingT0 > (tonumber(t.t0) or 0) then
                deletedCache[tKey] = nil
                return false
            else
                CheckAndTriggerReactiveAck()
                return true
            end
        end
    else
        deletedCache[tKey] = nil
        return false
    end
    return true
end

function Core:AddDiscovery(discoveryData, options)
    options = options or {}
    local op = tostring(options.op or (options.isNetwork and "DISC" or "LOCAL"))

    if discoveryData then
        local c = tonumber(discoveryData.c) or 0
        local z = tonumber(discoveryData.z) or 0
        if cityZoneIDsToPurge and cityZoneIDsToPurge[c] and cityZoneIDsToPurge[c][z] then
            L._debug("Core-Block", "Blocked incoming discovery from a forbidden city zone: " .. tostring(discoveryData.il))
            return 
        end
    end

    if options.isNetwork then
        if not (discoveryData and discoveryData.xy and discoveryData.c and discoveryData.z and (discoveryData.il or discoveryData.i)) then
            return 
        end
        local z = tonumber(discoveryData.z) or 0
        local ZoneList = L:GetModule("ZoneList", true)
        if not (ZoneList and ZoneList.MapDataByID and ZoneList.MapDataByID[z]) then           
            return
        end
    end

    if L:IsZoneIgnored() and options.isNetwork then
        return
    end

    if not (L.db and L.db.global) then
        return
    end

    if type(discoveryData) ~= "table" then
        return
    end

    local infoTarget = discoveryData.il or discoveryData.i
    if not infoTarget then
        return
    end

    local name, link, quality, itemType, itemSubType

    local itemID = discoveryData.i
    if not itemID then
        if not link then
            _, link = GetItemInfo(infoTarget)
        end
        if link then
            itemID = L:ExtractItemID(link)
        elseif type(discoveryData.il) == "string" then
            itemID = L:ExtractItemID(discoveryData.il)
        end
    end

    itemID = tonumber(itemID) or 0
    if itemID == 0 then return end

    discoveryData.i = itemID

    local Constants = L:GetModule("Constants", true)
    local STATUS_CONFIRMED = (Constants and Constants.STATUS and Constants.STATUS.CONFIRMED) or "CONFIRMED"
    local STATUS_UNCONFIRMED = (Constants and Constants.STATUS and Constants.STATUS.UNCONFIRMED) or "UNCONFIRMED"
    local STATUS_FADING = (Constants and Constants.STATUS and Constants.STATUS.FADING) or "FADING"
    local STATUS_STALE = (Constants and Constants.STATUS and Constants.STATUS.STALE) or "STALE"

    local dt = discoveryData.dt
    if not dt and itemID > 0 and Constants and Constants.DISCOVERY_TYPE then
        local cachedName = name
        if not cachedName then
            cachedName = select(1, GetItemInfo(itemID))
        end
        if cachedName then
            if string.find(cachedName, "Mystic Scroll", 1, true) then
                dt = Constants.DISCOVERY_TYPE.MYSTIC_SCROLL
            else
                dt = Constants.DISCOVERY_TYPE.WORLDFORGED
            end
        end
    end
    discoveryData.dt = dt

    local isBlackmarket = Constants and Constants.DISCOVERY_TYPE and dt == Constants.DISCOVERY_TYPE.BLACKMARKET

    if options.isNetwork then
        if isBlackmarket then
        elseif self:IsItemFullyCached(itemID) then
        else
            local firstDelay = math.random(5, 25)
            self:QueueItemForCaching(itemID)

            L:ScheduleAfter(firstDelay, function()
                if self:IsItemFullyCached(itemID) then
                    self:AddDiscovery(discoveryData, options)
                else
                    SafeCacheItemRequest(itemID)
                    L:ScheduleAfter(5, function()
                        if self:IsItemFullyCached(itemID) then
                            self:AddDiscovery(discoveryData, options)
                        end
                    end)
                end
            end)
            return
        end
    end

    if self:ShouldCacheItem(itemID) and not isBlackmarket then
        self:QueueItemForCaching(itemID)
        self:EnsureCachePump()
    end

    local x = L:Round4((discoveryData.xy and discoveryData.xy.x) or discoveryData.x or 0)
    local y = L:Round4((discoveryData.xy and discoveryData.xy.y) or discoveryData.y or 0)
    local c = tonumber(discoveryData.c) or 0
    local z = tonumber(discoveryData.z) or 0
    local iz = tonumber(discoveryData.iz) or 0
    local t0 = tonumber(discoveryData.t0) or tonumber(discoveryData.t) or time()

    discoveryData.xy = discoveryData.xy or {}
    discoveryData.xy.x = x
    discoveryData.xy.y = y
    discoveryData.c = c
    discoveryData.z = z
    discoveryData.iz = iz
    discoveryData.t0 = t0

    if isBlackmarket then
        local guid
        local vendorType = discoveryData.vendorType

        if not vendorType then
            if itemID >= -399999 and itemID <= -300000 then vendorType = "BM"
            elseif itemID >= -499999 and itemID <= -400000 then vendorType = "MS" end
        end

        if vendorType == "MS" then
            guid = "MS-" .. c .. "-" .. z .. "-" .. string.format("%.2f", L:Round2(x)) .. "-" .. string.format("%.2f", L:Round2(y))
        else
            guid = "BM-" .. c .. "-" .. z .. "-" .. string.format("%.2f", L:Round2(x)) .. "-" .. string.format("%.2f", L:Round2(y))
        end

        discoveryData.g = guid

        local vendorItems = {}
        if discoveryData.vendorItemIDs and type(discoveryData.vendorItemIDs) == "table" then
            for _, receivedItemID in ipairs(discoveryData.vendorItemIDs) do
                local vName, vLink = GetItemInfo(receivedItemID)
                if vName and vLink then
                    table.insert(vendorItems, { itemID = receivedItemID, name = vName, link = vLink, })
                end
            end
        end

        local bm_db = L:GetVendorsDB()
        if not bm_db then return end

        local existing = bm_db[guid]
        local recordToBroadcast

        if not existing then
            local newRecord = {
                g = guid, c = c, z = z, iz = iz, i = itemID,
                il = discoveryData.il, xy = { x = x, y = y },
                fp = discoveryData.fp, o = discoveryData.sender or discoveryData.o,
                t0 = t0, ls = t0, s = STATUS_CONFIRMED, st = t0,
                dt = dt, vendorType = vendorType,
                vendorName = discoveryData.vendorName or discoveryData.fp,
                vendorItems = vendorItems,
            }

            bm_db[guid] = newRecord
            recordToBroadcast = newRecord

            L:SendMessage("LootCollector_DiscoveriesUpdated", "add", guid, newRecord)
            self:AddToZoneIndex(guid, z)

            if options.isNetwork and not options.suppressToast then
                local Toast = L:GetModule("Toast", true)
                if Toast and Toast.Show then
                    Toast:Show(newRecord, false, { op = op })
                end
            end
        else
            existing.ls = math.max(tonumber(existing.ls) or 0, t0 or 0)
            existing.vendorName = discoveryData.vendorName or existing.vendorName
            if #vendorItems > 0 then
                existing.vendorItems = vendorItems
            end
            recordToBroadcast = existing

            L:SendMessage("LootCollector_DiscoveriesUpdated", "update", guid, existing)
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
        return
    end

    local db = L:GetDiscoveriesDB()
    if not db then return end

    local guid = discoveryData.g or L:GenerateGUID(c, z, itemID, x, y)
    discoveryData.g = guid

    local incomingMid = nil
    if type(discoveryData.mid) == "string" and discoveryData.mid ~= "" then
        incomingMid = discoveryData.mid
    end

    local keyV5 = self:MakeKeyV5({
        c = c, z = z, iz = iz, i = itemID, xy = { x = x, y = y },
    })

    L.db.global.deletedCache = L.db.global.deletedCache or {}

    if incomingMid and isTombstoneValidAndActive(incomingMid, t0, op, discoveryData.av) then return end
    if isTombstoneValidAndActive("k:" .. keyV5, t0, op, discoveryData.av) then return end

    local canonicalMid = nil
    local existing, existingGuid = self:FindExistingDiscovery(guid, incomingMid, keyV5)
    
    if not existing and not options.isNetwork and FindNearbyDiscovery then
        local nearby = FindNearbyDiscovery(c, z, itemID, x, y, db)
        if nearby then
            existing = nearby
            existingGuid = nearby.g
            guid = nearby.g
        end
    end
    
    local function ensureCanonicalMid()
        if canonicalMid == nil then
            canonicalMid = L:ComputeCanonicalDiscoveryMid({
                c = c, z = z, iz = iz, i = itemID, xy = { x = x, y = y }, t0 = t0,
            })
        end
        return canonicalMid
    end

    if not existing and not incomingMid then
        local probeCanonicalMid = ensureCanonicalMid()
        if isTombstoneValidAndActive(probeCanonicalMid, t0, op, discoveryData.av) then return end
        existing, existingGuid = self:FindByMid(probeCanonicalMid)
    end

    name, link, quality, _, _, itemType, itemSubType = GetItemInfo(infoTarget)

    local finalLink = discoveryData.il or link
    if link and quality and EnsureColoredLink then
        finalLink = EnsureColoredLink(link, quality)
    end

    local src_numeric = discoveryData.src
    if type(src_numeric) == "string" then
        local mapped = nil
        if dt == Constants.DISCOVERY_TYPE.MYSTIC_SCROLL and Constants.AcceptedLootSrcMS then
            mapped = Constants.AcceptedLootSrcMS[src_numeric]
        elseif dt == Constants.DISCOVERY_TYPE.WORLDFORGED and Constants.AcceptedLootSrcWF then
            mapped = Constants.AcceptedLootSrcWF[src_numeric]
        end
        if mapped ~= nil then
            src_numeric = mapped
        end
    end

    local itemTypeID = discoveryData.it
    if not itemTypeID and Constants and Constants.ITEM_TYPE_TO_ID then
        itemTypeID = Constants.ITEM_TYPE_TO_ID[itemType] or 0
    end

    local itemSubTypeID = discoveryData.ist
    if not itemSubTypeID and Constants and Constants.ITEM_SUBTYPE_TO_ID then
        itemSubTypeID = Constants.ITEM_SUBTYPE_TO_ID[itemSubType] or 0
    end

    local classAbbr = discoveryData.cl
    if (not classAbbr or classAbbr == "") and GetItemClassAbbr then
        classAbbr = GetItemClassAbbr(finalLink or itemID) or "cl"
    end
    if not classAbbr or classAbbr == "" then
        classAbbr = "cl"
    end

    local normalizedStatus = discoveryData.s
    if normalizedStatus ~= STATUS_CONFIRMED
        and normalizedStatus ~= STATUS_UNCONFIRMED
        and normalizedStatus ~= STATUS_FADING
        and normalizedStatus ~= STATUS_STALE then
        if options.isNetwork then
            normalizedStatus = (op == "CONF") and STATUS_CONFIRMED or STATUS_UNCONFIRMED
        else
            normalizedStatus = STATUS_CONFIRMED
        end
    end

    local finderName = discoveryData.fp or UnitName("player") or "Unknown"
    local s_flag = (finderName == "An Unnamed Collector") and 1 or 0

    local changed = false
    local isNew = false
    local rec

    if not existing then
        local storedMid = incomingMid
        if not storedMid or storedMid == "" then
            storedMid = ensureCanonicalMid()
        end
    
        rec = {
            g = guid,
            c = c, z = z, iz = iz, i = itemID, il = finalLink,
            q = tonumber(discoveryData.q) or tonumber(quality) or 0,
            xy = { x = x, y = y },
            fp = finderName,
            o = discoveryData.sender or discoveryData.o or finderName,
            t0 = t0, ls = t0,
            st = tonumber(discoveryData.st) or t0,
            s = normalizedStatus,
            mc = tonumber(discoveryData.mc) or 1,
            dt = dt,
            src = src_numeric,
            cl = classAbbr,
            it = tonumber(itemTypeID) or 0,
            ist = tonumber(itemSubTypeID) or 0,
            mid = storedMid,
            mk = keyV5,
            adc = tonumber(discoveryData.adc) or 0,
            fp_votes = { [finderName] = { score = 1, t0 = t0 } },
            s_flag = s_flag,
        }

        db[guid] = rec
        self:AddToZoneIndex(guid, z)
        
        if self._lookupIndicesBuilt then
            if rec.mid then self._midIndex[rec.mid] = guid end
            if rec.mk then self._keyV5Index[rec.mk] = guid end
        end

        isNew = true
        changed = true

        L:SendMessage("LootCollector_DiscoveriesUpdated", "add", guid, rec)
        
        if options.isNetwork and not options.suppressToast then
            local Toast = L:GetModule("Toast", true)
            if Toast and Toast.Show then
                Toast:Show(rec, false, { op = op })
            end
        end

    else
        rec = existing
        guid = existingGuid

        local oldX = rec.xy and rec.xy.x or 0
        local oldY = rec.xy and rec.xy.y or 0
        local threshold = 0.03 
        local dx = math.abs(x - oldX)
        local dy = math.abs(y - oldY)
        
        if dx <= threshold and dy <= threshold and (dx > 0 or dy > 0) then
            L._debug("Core-Refine", "Local loot is a coordinate refinement. Updating existing record.")
            rec.xy.x = L:Round4((oldX + x) / 2)
            rec.xy.y = L:Round4((oldY + y) / 2)
            changed = true
        end

        if not rec.st or t0 > (rec.st or 0) then
            if op == "CONF" and normalizedStatus == STATUS_CONFIRMED and rec.s ~= STATUS_CONFIRMED then
                rec.s = STATUS_CONFIRMED
                rec.st = t0
                changed = true
            elseif normalizedStatus == STATUS_FADING or normalizedStatus == STATUS_STALE then
                rec.s = normalizedStatus
                rec.st = t0
                changed = true
            end
        end

        local newLs = tonumber(discoveryData.ls) or t0
        if newLs > (rec.ls or 0) then
            rec.ls = newLs
            changed = true
        end

        local incMc = tonumber(discoveryData.mc) or 1
        if incMc > 1 then
            rec.mc = math.max(rec.mc or 1, incMc)
            changed = true
        end
        
        if discoveryData.adc and discoveryData.adc > (rec.adc or 0) then
            rec.adc = discoveryData.adc
            changed = true
        end

        if not rec.il and finalLink then
            rec.il = finalLink
            changed = true
        end
        
        if not rec.dt and dt then
            rec.dt = dt
            changed = true
        end
        if rec.src == nil and src_numeric ~= nil then
            rec.src = src_numeric
            changed = true
        end

        if changed then
            L:SendMessage("LootCollector_DiscoveriesUpdated", "update", guid, rec)
        end
    end

    if changed then
        L.DataHasChanged = true
        local Map = L:GetModule("Map", true)
        if Map then
            Map.cacheIsDirty = true
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
    end
end

function Core:PurgeZeroCoordDiscoveries()
    local discoveries = L:GetDiscoveriesDB()
    if not discoveries then return 0 end
    
    local guidsToRemove = {}
    
    for guid, d in pairs(discoveries) do
        if d and d.xy and d.xy.x == 0 and d.xy.y == 0 then
            table.insert(guidsToRemove, guid)
        end
    end
    
    local removedCount = #guidsToRemove
    if removedCount > 0 then
        for _, guid in ipairs(guidsToRemove) do
            L._debug("Cleanup", "Purging zero-coord record: " .. guid .. " (" .. tostring(discoveries[guid].il) .. ")")
            discoveries[guid] = nil
            L:SendMessage("LootCollector_DiscoveriesUpdated", "remove", guid, nil)
        end
    end
    
    return removedCount
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

function Core:ReportDiscoveryAsGone(guid)
    if not guid then return end
    local db = L:GetDiscoveriesDB()
    if not db then return end

    local rec = db[guid]
    if not rec then return end

    rec.mk = rec.mk or self:MakeKeyV5(rec)

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
        Comm:BroadcastAckFor(discoveryPayload, rec.mid, "DET")
    else
        L._debug("Core-Report", "Failed to broadcast ACK. Missing Comm, BroadcastAckFor, or mid.")
    end

    L.db.global.deletedCache = L.db.global.deletedCache or {}
    StoreDiscoveryTombstone(L.db.global.deletedCache, rec, nil)

    if rec.mk and rec.t0 then
        L.db.global.deletedCache["k:" .. rec.mk] = {
            t0 = rec.t0,
            deletedAt = time(),
        }
    end

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
            if rec.mk then self._keyV5Index[rec.mk] = nil end
        end
        
        discoveries[guid] = nil
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
            if rec.mk then self._keyV5Index[rec.mk] = nil end
        end
        
        discoveries[guid] = nil
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

function Core:MakeKeyV5(norm)
    local c  = tonumber(norm.c) or 0
    local z  = tonumber(norm.z) or 0
    local iz = tonumber(norm.iz) or 0
    local i  = tonumber(norm.i) or 0
    local x  = L:Round4(norm.xy and norm.xy.x or 0)
    local y  = L:Round4(norm.xy and norm.xy.y or 0)
    if z == 0 then
        return string.format("%d:%d:%d:%d:%.4f:%.4f", c, z, iz, i, x, y)
    else
        return string.format("%d:%d:%d:%d:%.4f:%.4f", c, z, 0, i, x, y)
    end
end

function Core:BuildLookupIndices()
    if self._lookupIndicesBuilt then return end
    self._keyV5Index = {}
    self._midIndex = {}
    
    local db = L:GetDiscoveriesDB()
    if not db then return end
    
    for g, r in pairs(db) do
        if type(r) == "table" then
            if r.mid then 
                self._midIndex[r.mid] = g 
            end
            if self.MakeKeyV5 then
                local mk = r.mk or self:MakeKeyV5(r)
                self._keyV5Index[mk] = g
                r.mk = mk
            end
        end
    end
    self._lookupIndicesBuilt = true
end

function Core:FindByMid(mid)
    if not mid or mid == "" then return nil, nil end
    local db = L:GetDiscoveriesDB()
    if not db then return nil, nil end

    self:BuildLookupIndices()
    
    local idx = self._midIndex[mid]
    if idx and db[idx] then
        return db[idx], idx
    end

    return nil, nil
end

function Core:FindExistingDiscovery(guid, incomingMid, keyV5)
    local db = L:GetDiscoveriesDB()
    if not db then return nil, nil end

    if guid and db[guid] then
        return db[guid], guid
    end

    self:BuildLookupIndices()

    if incomingMid and incomingMid ~= "" then
        local midGuid = self._midIndex[incomingMid]
        if midGuid and db[midGuid] then
            return db[midGuid], midGuid
        end
    end

    if keyV5 and keyV5 ~= "" then
        local keyGuid = self._keyV5Index[keyV5]
        if keyGuid and db[keyGuid] then
            return db[keyGuid], keyGuid
        end
    end

    return nil, nil
end

function Core:ProcessAckVote(mid, sender)
    L._debug("Core-Ack", "ProcessAckVote invoked for mid: " .. tostring(mid) .. " from " .. tostring(sender))
    if not mid or mid == "" or not sender or sender == "" then return end
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
        return
    end

    
    guid = guid or rec.g
    L._debug("Core-Ack", "Match found! GUID: " .. tostring(guid) .. " | Current ADC: " .. tostring(rec.adc or 0))
    
    rec.ack_votes = rec.ack_votes or {}
    if rec.ack_votes[sender] then 
        L._debug("Core-Ack", "Sender has already voted on this record. Aborting.")
        return 
    end
    
    rec.ack_votes[sender] = true
    local voteCount = 0
    for _ in pairs(rec.ack_votes) do voteCount = voteCount + 1 end
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
    
    local days = tonumber(fixData.dur) or 90 
    local expiryTime = time() + (days * 86400)
    local tolerance = tonumber(fixData.tol) or 0.05
    
    if fixData.type == 1 then 
        for guid, d in pairs(discoveries) do
            if d.i == fixData.i and d.c == fixData.c and d.z == fixData.z then
                local dx = (d.xy and d.xy.x or 0) - fixData.nx
                local dy = (d.xy and d.xy.y or 0) - fixData.ny
                if (dx*dx + dy*dy) <= (fixData.prox * fixData.prox) then
                    table.insert(recordsToUpdate, guid)
                end
            end
        end
    elseif fixData.type == 2 then 
        for guid, d in pairs(discoveries) do
            if d.i == fixData.i and d.c == fixData.c and d.z == fixData.z then
                local dx = math.abs((d.xy and d.xy.x or 0) - fixData.ox)
                local dy = math.abs((d.xy and d.xy.y or 0) - fixData.oy)
                if dx <= tolerance and dy <= tolerance then
                    table.insert(recordsToUpdate, guid)
                end
            end
        end
    elseif fixData.type == 3 then
        for guid, d in pairs(discoveries) do
            if d.i == fixData.i and d.c == fixData.c and d.z == fixData.z then
                local dx = math.abs((d.xy and d.xy.x or 0) - fixData.ox)
                local dy = math.abs((d.xy and d.xy.y or 0) - fixData.oy)
                if dx <= tolerance and dy <= tolerance then
                    table.insert(recordsToDelete, guid)
                end
            end
        end
    elseif fixData.type == 4 then
        for guid, d in pairs(discoveries) do
            if d.i == fixData.i and d.c == fixData.c and d.z == fixData.z then
                local dx = math.abs((d.xy and d.xy.x or 0) - fixData.ox)
                local dy = math.abs((d.xy and d.xy.y or 0) - fixData.oy)
                if dx <= tolerance and dy <= tolerance then
                    table.insert(recordsToRemoteKill, guid)
                end
            end
        end
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
			local newGuid = L:GenerateGUID(newRecord.c, newRecord.z, newRecord.i, newRecord.xy.x, newRecord.xy.y)
			newRecord.g = newGuid
			newRecord.mid = L:ComputeCanonicalDiscoveryMid(newRecord)
			newRecord.mk = self:MakeKeyV5(newRecord)
			discoveries[newGuid] = newRecord
			updatedCount = updatedCount + 1
		  end
	    end
	end
    
    if recordsToRemoteKill and #recordsToRemoteKill > 0 then
        for _, killGuid in ipairs(recordsToRemoteKill) do            
            local staggeredDelay = math.random(30, 200)
            L._debug("Core-GFIX", string.format("GFIX staggered: Remote Kill for %s scheduled in %d seconds.", killGuid, staggeredDelay))
            
            ScheduleAfter(staggeredDelay, function()                
                if discoveries[killGuid] then
                    self:ReportDiscoveryAsGone(killGuid)
                end
            end)
            remoteKilledCount = remoteKilledCount + 1
        end
    end

    if recordsToRemoteKill and #recordsToRemoteKill > 0 then
        for _, killGuid in ipairs(recordsToRemoteKill) do            
            self:ReportDiscoveryAsGone(killGuid)
            remoteKilledCount = remoteKilledCount + 1
        end
    end

    if updatedCount > 0 or deletedCount > 0 or remoteKilledCount > 0 then
        self:InvalidateLookupIndices()
        local Map = L:GetModule("Map", true)
        if Map and Map.Update then Map:Update() end
        if remoteKilledCount > 0 then
            L._debug("Core-GFIX", string.format("GFIX-Type4: Successfully triggered Remote Kill for %d local records.", remoteKilledCount))
        end
    end
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
