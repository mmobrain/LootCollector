-- Modules/Core.lua
-- UNK.B64.UTF-8



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

local SCAN_BUDGET_MS   = 4       
local SCAN_MAX_PER_TICK = 300    
local PAUSE_IN_COMBAT   = true
local PAUSE_WHEN_MOVING = false

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

-- DEPRECATED: This name-based list is incorrect for localization. It is replaced by cityZoneIDsToPurge. Keeping commented for now.
--[[
local cityZonesToPurge = {
    ["Stormwind City"] = true,
    ["Ironforge"] = true,
    ["Darnassus"] = true,
    ["Orgrimmar"] = true,
    ["Thunder Bluff"] = true,
    ["Undercity"] = true,
    ["Shattrath City"] = true,
    ["Dalaran"] = true,
}
--]]

-- NEW: ID-based lookup for purging city zones. This is language-independent.
local cityZoneIDsToPurge = {
    [1] = { -- Kalimdor
        [10] = true, -- Darnassus
        [22] = true, -- Orgrimmar
        [41] = true, -- Thunder Bluff
    },
    [2] = { -- Eastern Kingdoms
        [23] = true, -- Ironforge
        [37] = true, -- Stormwind City
        [46] = true, -- Undercity
    },
    [3] = { -- Outland
        [6] = true, -- Shattrath City
    },
    [4] = { -- Northrend
        [3] = true, -- Dalaran
    }
}

local guidPrefixesToPurge = {
    ["1-22-"] = true,
    ["2-37-"] = true,
    ["2-23-"] = true,
    ["2-46-"] = true,
    ["1-10-"] = true,
    ["3-6-"]  = true,
    ["3-3-"]  = true,
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
    local forlater = "357fn9+K36bfiiDfo9+M36sg35vfjN+y35jfn9+MID0g34I="
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

local function extractItemID(itemLink)
    if type(itemLink) ~= "string" then return nil end
    local id = itemLink:match("item:(%d+)")
    return id and tonumber(id) or nil
end

function Core:EnsureVerificationFields(d)
    if not d then return end
    if not d.i then d.i = extractItemID(d.il) end
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
    local db = L.db and L.db.global and L.db.global.discoveries or {}
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
    if not (L.db and L.db.profile and L.db.global and L.db.char) then return end

    
    L.db.global.discoveries = L.db.global.discoveries or {}
    L.db.global.blackmarketVendors = L.db.global.blackmarketVendors or {}
    L.db.global.cacheQueue = L.db.global.cacheQueue or {}
    L.db.global.manualCleanupRunCount = L.db.global.manualCleanupRunCount or 0
    L.db.global.autoCleanupPhase = L.db.global.autoCleanupPhase or 0
    if L.db.global.purgeEmbossedState == nil then L.db.global.purgeEmbossedState = 0 end

    
    L.db.char.looted = L.db.char.looted or {}
    L.db.char.hidden = L.db.char.hidden or {}

    
    if L.db.profile.autoCache == nil then L.db.profile.autoCache = true end
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

function Core:PurgeDiscoveriesFromBlockedPlayers()
    if not (L.db and L.db.profile and L.db.profile.sharing and L.db.profile.sharing.blockList and L.db.global and L.db.global.discoveries) then
        print("|cffff7f00LootCollector:|r Block list is empty or database is not ready.")
        return 0
    end

    local blockList = L.db.profile.sharing.blockList
    if not next(blockList) then
        print("|cffff7f00LootCollector:|r Block list is empty. Nothing to purge.")
        return 0
    end

    local discoveries = L.db.global.discoveries
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
            -- Notifies the UI that a discovery was removed
            L:SendMessage("LootCollector_DiscoveriesUpdated", "remove", guid, nil)
        end
        print(string.format("|cff00ff00LootCollector:|r Purged %d discoveries from blocked players.", removedCount))
        -- Refresh map if it's open
        local Map = L:GetModule("Map", true)
        if Map and Map.Update and WorldMapFrame and WorldMapFrame:IsShown() then
            Map:Update()
        end
    else
        print("|cff00ff00LootCollector:|r No discoveries found from players on your block list.")
    end

    return removedCount
end

local PURGE_VERSION = "EmbossedScroll_v1"
function Core:PurgeEmbossedScrolls()
    if L.db.global.purgeEmbossedState == 2 then
        
        return
    end

    local purgeState = L.db.global.purgeEmbossedState or 0
    

    local discoveries = L.db.global.discoveries or {}
    local guidsToProcess = {}
    local processedCount = 0

    for guid, d in pairs(discoveries) do
        if d then
            local name
            local itemID = d.i or extractItemID(d.il)
            

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
    if not (L.db and L.db.global and L.db.global.discoveries) then return 0 end
    local discoveries = L.db.global.discoveries
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
            discoveries[guid] = nil
            -- Notifies Viewer of removed discovery
            L:SendMessage("LootCollector_DiscoveriesUpdated", "remove", guid, nil)
        end
    end
    return removedCount
end

function Core:PurgeByGUIDPrefix()
    if not (L.db and L.db.global and L.db.global.discoveries) then return 0 end
    local prefixes = {
        ["1-22-"] = true, ["2-37-"] = true, ["2-23-"] = true,
        ["2-46-"] = true, ["1-10-"] = true, ["3-6-"] = true, ["3-3-"] = true,
    }
    local discoveries = L.db.global.discoveries
    local toDel = {}
    for guid in pairs(discoveries) do
        for pfx in pairs(prefixes) do
            if guid:sub(1, #pfx) == pfx then
                table.insert(toDel, guid)
                break
            end
        end
    end
    for _, g in ipairs(toDel) do 
        discoveries[g] = nil
        -- Notifies Viewer of removed discovery
        L:SendMessage("LootCollector_DiscoveriesUpdated", "remove", g, nil)
    end
    return #toDel
end



function Core:RemapLootedHistoryV6()
  
    if not (L.db and L.db.char and not L.db.char.looted_remapped_v6) then
        return
    end

  
    if not (L.db.global and next(L.db.global.discoveries) and next(L.db.char.looted)) then
        L.db.char.looted_remapped_v6 = true
        return
    end

  
    
   
    local wfLookup = {}
    local Constants = L:GetModule("Constants", true)
    if Constants and Constants.DISCOVERY_TYPE then
        for guid, d in pairs(L.db.global.discoveries) do
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
    if not (L.db and L.db.global and L.db.global.discoveries) then return 0, 0 end

    local groups = {}
    for guid, d in pairs(L.db.global.discoveries) do
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
            local firstDiscovery = L.db.global.discoveries[guids[1]]
            local itemID = firstDiscovery.i
            local name = (firstDiscovery.il and firstDiscovery.il:match("%[(.+)%]")) or GetItemInfo(itemID)

            if name and string.find(name, "Mystic Scroll", 1, true) and mysticScrollsKeepOldest then
                local guidToKeep, oldestTs = nil, nil
                for _, guid in ipairs(guids) do
                    local d = L.db.global.discoveries[guid]
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
                    local d = L.db.global.discoveries[guid]
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
            L.db.global.discoveries[guid] = nil
            -- Notifies Viewer of removed discovery
            L:SendMessage("LootCollector_DiscoveriesUpdated", "remove", guid, nil)
        end
    end
    return wfRemoved, msRemoved
end

-- Deduplicate vendors within the same zone by merging nearby vendors with same name
function Core:DeduplicateVendorsPerZone()
    if not (L.db and L.db.global and L.db.global.discoveries) then return 0 end
    
    local discoveries = L.db.global.discoveries
    local COORD_THRESHOLD = 0.03
    
    -- Group vendors by zone and vendor name
    local vendorGroups = {}
    for guid, d in pairs(discoveries) do
        if d and d.vendorName and d.vendorType then
            local key = string.format("%d:%d:%s:%s", d.c or 0, d.z or 0, d.vendorName, d.vendorType)
            vendorGroups[key] = vendorGroups[key] or {}
            table.insert(vendorGroups[key], guid)
        end
    end
    
    local guidsToRemove = {}
    local mergedCount = 0
    
    -- Process each vendor group
    for _, guids in pairs(vendorGroups) do
        if #guids > 1 then
            -- Sort by most recent timestamp (ls) descending
            table.sort(guids, function(a, b)
                local aTime = tonumber(discoveries[a].ls) or 0
                local bTime = tonumber(discoveries[b].ls) or 0
                return aTime > bTime
            end)
            
            local i = 1
            while i <= #guids do
                local keepGuid = guids[i]
                local keepVendor = discoveries[keepGuid]
                local keepX = keepVendor.xy and L:Round4(keepVendor.xy.x) or 0
                local keepY = keepVendor.xy and L:Round4(keepVendor.xy.y) or 0
                
                local j = i + 1
                while j <= #guids do
                    local checkGuid = guids[j]
                    local checkVendor = discoveries[checkGuid]
                    local checkX = checkVendor.xy and L:Round4(checkVendor.xy.x) or 0
                    local checkY = checkVendor.xy and L:Round4(checkVendor.xy.y) or 0
                    
                    -- Check if coordinates are close enough to be the same vendor
                    if math.abs(keepX - checkX) < COORD_THRESHOLD and math.abs(keepY - checkY) < COORD_THRESHOLD then
                        -- Merge vendorItems from checkVendor into keepVendor
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
                        
                        -- Update merge count
                        keepVendor.mc = (tonumber(keepVendor.mc) or 1) + 1
                        
                        -- Mark for removal
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
    
    -- Remove duplicate vendors
    if #guidsToRemove > 0 then
        for _, guid in ipairs(guidsToRemove) do
            discoveries[guid] = nil
            L:SendMessage("LootCollector_DiscoveriesUpdated", "remove", guid, nil)
        end
    end
    
    return mergedCount
end

-- Remove all discoveries with invalid zone data (z=0 and iz=0)
function Core:PurgeInvalidZoneDiscoveries()
    if not (L.db and L.db.global and L.db.global.discoveries) then return 0 end
    
    local discoveries = L.db.global.discoveries
    local guidsToRemove = {}
    
    for guid, d in pairs(discoveries) do
        if d then
            local z = tonumber(d.z) or 0
            local iz = tonumber(d.iz) or 0
            
            
            if z == 0 and iz == 0 then
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
    end
    
    return removedCount
end


function Core:_isFinderRestricted(name)
    if not name or name == "" or not XXH_Lua_Lib then return false end
    local Constants = L:GetModule("Constants", true)
    if not Constants or not Constants.rHASH_BLACKLIST then return false end

    local normalizedName = L:normalizeSenderName(name)
    if not normalizedName then return false end
    
    local combined_str = normalizedName .. Constants.HASH_SAP
    local hash_val = XXH_Lua_Lib.XXH32(combined_str, Constants.HASH_SEED)
    local hex_hash = string.format("%08x", hash_val)

    return Constants.rHASH_BLACKLIST[hex_hash] == true
end


function Core:PurgeByRestrictedFinders()
    if not (L.db and L.db.global and L.db.global.discoveries) then return 0 end
    
    local discoveries = L.db.global.discoveries
    local guidsToRemove = {}
    
    for guid, d in pairs(discoveries) do
        -- Check if the discovery has a finder and if that finder is on the restricted list
        if d and d.fp and self:_isFinderRestricted(d.fp) then
            table.insert(guidsToRemove, guid)
        end
    end
    
    local removedCount = #guidsToRemove
    if removedCount > 0 then
        for _, guid in ipairs(guidsToRemove) do
            discoveries[guid] = nil
            -- Notifies the UI that a discovery was removed
            L:SendMessage("LootCollector_DiscoveriesUpdated", "remove", guid, nil)
        end
    end
    
    return removedCount
end

-- MODIFIED: Replaced name-based city purge with ID-based logic.
function Core:RunManualDatabaseCleanup()
    print("|cff00ff00LootCollector:|r Starting manual database cleanup...")

    -- NEW: Purge discoveries from restricted finders first.
    local restrictedRemoved = self:PurgeByRestrictedFinders()
    if restrictedRemoved > 0 then
        print(string.format("|cff00ff00LootCollector:|r Purged %d entries from restricted finders.", restrictedRemoved))
    end

    -- Remove discoveries with invalid zone data (z=0 and iz=0)
    local invalidZoneRemoved = self:PurgeInvalidZoneDiscoveries()
    if invalidZoneRemoved > 0 then
        print(string.format("|cff00ff00LootCollector:|r Purged %d entries with invalid zone data.", invalidZoneRemoved))
    end

    -- Deduplicate vendors per zone
    local vendorsMerged = self:DeduplicateVendorsPerZone()
    if vendorsMerged > 0 then
        print(string.format("|cff00ff00LootCollector:|r Merged %d duplicate vendor entries.", vendorsMerged))
    end

    local zeroCoordRemoved = self:PurgeZeroCoordDiscoveries()
    if zeroCoordRemoved > 0 then
        print(string.format("|cff00ff00LootCollector:|r Purged %d entries with (0,0) coordinates.", zeroCoordRemoved))
    end

    local cityGuidsToRemove = {}
    for guid, d in pairs(L.db.global.discoveries or {}) do
        -- Use numerical IDs directly instead of resolving to a localized name
        if d and d.c and d.z and cityZoneIDsToPurge[d.c] and cityZoneIDsToPurge[d.c][d.z] then
            table.insert(cityGuidsToRemove, guid)
        end
    end
    local cityRemoved = #cityGuidsToRemove
    if cityRemoved > 0 then
        for _, guid in ipairs(cityGuidsToRemove) do
            L.db.global.discoveries[guid] = nil
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
    print(string.format("|cffffff00LootCollector:|r Manual cleanup has now been run %d time(s).", L.db.global.manualCleanupRunCount))

    -- MODIFIED: Added restrictedRemoved to the check.
    if (invalidZoneRemoved + vendorsMerged + zeroCoordRemoved + cityRemoved + prefixRemoved + ignoredRemoved + wfRemoved + msRemoved + restrictedRemoved) == 0 then
        print("|cff00ff00LootCollector:|r No items needed purging or deduplication.")
    else
        print("|cff00ff00LootCollector:|r Manual cleanup complete.")
        local Map = L:GetModule("Map", true)
        if Map and Map.Update and WorldMapFrame and WorldMapFrame:IsShown() then
            Map:Update()
        end
    end
end

-- MODIFIED: Replaced name-based city purge with ID-based logic.
function Core:RunInitialCleanup()
    local zeroCoordRemoved = self:PurgeZeroCoordDiscoveries()

    local cityGuidsToRemove = {}
    for guid, d in pairs(L.db.global.discoveries or {}) do
        -- Use numerical IDs directly instead of resolving to a localized name
        if d and d.c and d.z and cityZoneIDsToPurge[d.c] and cityZoneIDsToPurge[d.c][d.z] then
            table.insert(cityGuidsToRemove, guid)
        end
    end
    local cityRemoved = #cityGuidsToRemove
    if cityRemoved > 0 then
        for _, guid in ipairs(cityGuidsToRemove) do
            L.db.global.discoveries[guid] = nil
            -- Notifies Viewer of removed discovery
            L:SendMessage("LootCollector_DiscoveriesUpdated", "remove", guid, nil)
        end
    end

    local prefixRemoved = self:PurgeByGUIDPrefix()
    local ignoredRemoved = self:PurgeAllIgnoredItems()
    local wfRemoved, msRemoved = self:DeduplicateItems(true)

    if (zeroCoordRemoved + cityRemoved + prefixRemoved + ignoredRemoved + wfRemoved + msRemoved) > 0 then
        print("|cff00ff00LootCollector:|r Initial cleanup complete. Removed: " .. zeroCoordRemoved .. " (0,0) coords, " .. cityRemoved .. " city, " .. prefixRemoved .. " prefix, " .. ignoredRemoved .. " ignored, " .. wfRemoved .. " WF dupes, " .. msRemoved .. " MS dupes.")
        local Map = L:GetModule("Map", true)
        if Map and Map.Update and WorldMapFrame and WorldMapFrame:IsShown() then
            Map:Update()
        end
    end
end

-- MODIFIED: Replaced name-based city purge with ID-based logic.
function Core:RunAutomaticOnLoginCleanup()
    local totalRemoved = 0
    
    -- NEW: Purge discoveries from restricted finders on login.
    local restrictedRemoved = self:PurgeByRestrictedFinders()
    if restrictedRemoved > 0 then
        totalRemoved = totalRemoved + restrictedRemoved
    end

    -- Purge discoveries with invalid zone data (z=0 and iz=0)
    local invalidZoneRemoved = self:PurgeInvalidZoneDiscoveries()
    if invalidZoneRemoved > 0 then
        totalRemoved = totalRemoved + invalidZoneRemoved
    end

    -- Deduplicate vendors per zone
    local vendorsMerged = self:DeduplicateVendorsPerZone()
   

    -- Purge discoveries with (0,0) coordinates
    local zeroCoordRemoved = self:PurgeZeroCoordDiscoveries()
    if zeroCoordRemoved > 0 then
        totalRemoved = totalRemoved + zeroCoordRemoved
    end

    -- Purge discoveries from city zones
    local cityGuidsToRemove = {}
    for guid, d in pairs(L.db.global.discoveries or {}) do
        -- Use numerical IDs directly instead of resolving to a localized name
        if d and d.c and d.z and cityZoneIDsToPurge[d.c] and cityZoneIDsToPurge[d.c][d.z] then
            table.insert(cityGuidsToRemove, guid)
        end
    end
    local cityRemoved = #cityGuidsToRemove
    if cityRemoved > 0 then
        for _, guid in ipairs(cityGuidsToRemove) do
            L.db.global.discoveries[guid] = nil
            -- Notifies Viewer of removed discovery
            L:SendMessage("LootCollector_DiscoveriesUpdated", "remove", guid, nil)
        end
        totalRemoved = totalRemoved + cityRemoved
    end

    -- Purge by GUID prefix
    local prefixRemoved = self:PurgeByGUIDPrefix()
    if prefixRemoved > 0 then
        totalRemoved = totalRemoved + prefixRemoved
    end
    
    -- Purge ignored items
    local ignoredRemoved = self:PurgeAllIgnoredItems()
    if ignoredRemoved > 0 then
        totalRemoved = totalRemoved + ignoredRemoved
    end

    
    local wfRemoved, msRemoved = self:DeduplicateItems(true)

  
    if (totalRemoved + wfRemoved + msRemoved + vendorsMerged) > 0 then
        print(string.format("|cff00ff00LootCollector:|r Routine maintenance complete. Purged %d entries. Merged %d vendors. Removed %d WF dupes and %d MS dupes.", totalRemoved, vendorsMerged, wfRemoved, msRemoved))
        local Map = L:GetModule("Map", true)
        if Map and Map.Update and WorldMapFrame and WorldMapFrame:IsShown() then
            Map:Update()
        end
    end
end

function Core:FixEmptyFinderNames()
    if not (L.db and L.db.global and L.db.global.discoveries) then return 0 end
    
    local discoveries = L.db.global.discoveries
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
    if not (L.db and L.db.global and L.db.global.discoveries) then return 0 end
    
    local discoveries = L.db.global.discoveries
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

function Core:PerformOnLoginMaintenance()
    if self.onLoginCleanupPerformed then return end
    self.onLoginCleanupPerformed = true

    -- *** Run the fix for empty finder names ***
    local fixedFPCount = self:FixEmptyFinderNames()
    if fixedFPCount > 0 then
        print(string.format("|cff00ff00LootCollector:|r Repaired %d database entries with missing finder names.", fixedFPCount))
    end

    -- *** Retroactively add fp_votes to older records ***
    local fixedVotesCount = self:FixMissingFpVotes()
    if fixedVotesCount > 0 then
        print(string.format("|cff00ff00LootCollector:|r Updated %d older records with the new finder consensus system.", fixedVotesCount))
    end

    local phase = L.db.global.autoCleanupPhase or 0
    if phase < 3 then
        print(string.format("|cff00ff00LootCollector:|r Performing initial database cleanup (stage %d of 2)...", phase + 1))
        self:RunInitialCleanup()
        L.db.global.autoCleanupPhase = phase + 1
    else
        print("|cff00ff00LootCollector:|r Performing routine database maintenance...")
        self:RunAutomaticOnLoginCleanup()
    end

    
    self:RemapLootedHistoryV6()
end

local function findDiscoveryDetails(itemID)
    if not itemID then return "Unknown Item", "Unknown Zone" end
    local discoveries = L.db.global.discoveries or {}
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
    if not (L.db and L.db.global and itemID) then return false end
    local Constants = L:GetModule("Constants", true)
    if not Constants then return false end
    
    local name, link, quality, _, _, itemType, itemSubType = GetItemInfo(itemID)
    if not (name and link) then return false end

    local colored = EnsureColoredLink(link, quality)
    local updated = false
    local discoveries = L.db.global.discoveries or {}
    
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
        if Map and Map.Update and WorldMapFrame and WorldMapFrame:IsShown() then Map:Update() end
        
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
            else
        
            end
        end
        

        processed = processed + 1
        if processed >= SCAN_MAX_PER_TICK then break end
        if (GetTime() - start) * 1000 >= SCAN_BUDGET_MS then break end
    end
end

function Core:ScanDatabaseForUncachedItems()
    if not (L.db and L.db.profile and L.db.profile.autoCache) then return end
    local db = (L.db.global and L.db.global.discoveries) or {}
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
        else
            
        end
    end

    if cacheTicker and cacheTicker.Cancel then cacheTicker:Cancel() end
    if #queue > 0 then
        local delay = math.random(CACHE_MIN_DELAY, CACHE_MAX_DELAY)
        if Core._pumpJitterLeft and Core._pumpJitterLeft > 0 then
		  delay = delay + math.random() * 0.3
		  Core._pumpJitterLeft = Core._pumpJitterLeft - 1
	    end
        local Comm = L:GetModule("Comm", true)
        if Comm then
            
        end
        cacheTicker = ScheduleAfter(delay, function() Core:ProcessCacheQueue() end)
        cacheActive = true
    else
        cacheTicker, cacheActive = nil, false
        local Comm = L:GetModule("Comm", true)
        if Comm then
            
        end
    end
end

function Core:OnGetItemInfoReceived(_, itemID)
    if itemID then
        self:UpdateItemRecordFromCache(itemID)
    end
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

    ScheduleAfter(10, function()
        Core:PurgeEmbossedScrolls()
        Core:PerformOnLoginMaintenance()
        Core:ScanDatabaseForUncachedItems()
        Core:EnsureCachePump()
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

function Core:OnLootOpened()
    -- dbg
end

function Core:HandleLocalLoot(discovery)
    local Constants = L:GetModule("Constants", true)
    
    if not discovery or not (L and L.db and L.db.global) or not Constants then
        return
    end

    local itemID = tonumber(discovery.i)
    local dt = discovery.dt

    
    local isVendorDiscovery = (dt == Constants.DISCOVERY_TYPE.BLACKMARKET) or (discovery.vendorType and (discovery.vendorType == "MS" or discovery.vendorType == "BM"))

    if isVendorDiscovery then
        -- Ensure dt is set correctly if it was missing
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
        
        local bm_db = L.db.global.blackmarketVendors
        local existing = bm_db[guid]

        if not existing then
            bm_db[guid] = {
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
        else
            existing.ls = discovery.t0
            existing.vendorItems = discovery.vendorItems 
            
            existing.dt = dt
            existing.vendorType = discovery.vendorType
            if not existing.il then existing.il = itemLink end 
        end
        
        local Map = L:GetModule("Map", true)
        if Map and Map.Update and WorldMapFrame and WorldMapFrame:IsShown() then Map:Update() end
        return 
    end

    
    local name, link, quality, _, _, itemType, itemSubType = GetItemInfo(discovery.il)
    itemID = itemID or (discovery.il and tonumber((discovery.il:match("item:(%d+)")))) or 0
    
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
    
    local db = L.db.global.discoveries
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
            src = discovery.src,
            fp_votes = { [finderName] = { score = 1, t0 = t0 } },
            s_flag = s_flag,
        }
        db[guid] = rec
        
        -- Notifies Viewer of new discovery
        L:SendMessage("LootCollector_DiscoveriesUpdated", "add", guid, rec)
    else
        
        rec.ls = max(tonumber(rec.ls) or 0, t0)
        if not rec.src and discovery.src then
            rec.src = discovery.src
        end
        
        -- Notifies Viewer of updated discovery
        L:SendMessage("LootCollector_DiscoveriesUpdated", "update", guid, rec)
    end
    
    
    if not L.db.char then L.db.char = {} end
    L.db.char.looted = L.db.char.looted or {}
    L.db.char.looted[rec.g] = time()
    
    if not self:IsItemCached(itemID) then
        if self.QueueItemForCaching then
            self:QueueItemForCaching(itemID)
        end
    end
    
    local Map = L:GetModule("Map", true)
    if Map and Map.Update and WorldMapFrame and WorldMapFrame:IsShown() then Map:Update() end
    
    local norm = {
        i = itemID, il = colored or discovery.il, q = quality or 1,
        c = c, z = z, iz = iz, xy = { x = x, y = y }, t0 = t0,
        dt = dt, it = it, ist = ist, cl = cl,
        src = discovery.src,
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
    
    if not self:IsItemFullyCached(norm.i) then
        
    end
    
    local Comm = L:GetModule("Comm", true)
    if Comm and Comm.BroadcastDiscovery then
        
        Comm:BroadcastDiscovery(norm)
    else
        
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
    
    local record
    
    record = FindNearbyDiscovery(corr_data.c, corr_data.z, corr_data.i, 0, 0, L.db.global.discoveries)

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
    

    
    local sumX, sumY = 0, 0
    for _, vote in ipairs(votes) do
        sumX = sumX + vote.x
        sumY = sumY + vote.y
    end
    local avgX, avgY = sumX / count, sumY / count

    
    local consensusVotes = {}
    local threshold = 0.02
    for _, vote in ipairs(votes) do
        if math.abs(vote.x - avgX) <= threshold and math.abs(vote.y - avgY) <= threshold then
            table.insert(consensusVotes, vote)
        end
    end

    
    local consensusCount = #consensusVotes
    if consensusCount >= 5 then 
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
        end
    end

    
    wipe(d.coord_votes)
end

local function FindWorldforgedInZone(continent, zoneID, itemID, db)
    if not db then return nil end
    local Constants = L:GetModule("Constants", true)
    if not Constants then return nil end

    for _, d in pairs(db) do
        if d and d.c == continent and d.z == zoneID and d.i == itemID and d.dt == Constants.DISCOVERY_TYPE.WORLDFORGED then
            return d
        end
    end
    
    return nil
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

function Core:AddDiscovery(discoveryData, options)
    options = options or {}
    local op = options.op or "DISC"
    
      if discoveryData then
        local c = tonumber(discoveryData.c) or 0
        local z = tonumber(discoveryData.z) or 0
        -- MODIFIED: Check against the ID-based city list
        if cityZoneIDsToPurge[c] and cityZoneIDsToPurge[c][z] then
            return 
        end
      end
	  
	if options.isNetwork then

        if not (discoveryData and discoveryData.xy and discoveryData.c and discoveryData.z and (discoveryData.il or discoveryData.i)) then
            return -- Silently drop malformed packet
        end
	  
	  
       
           
        -- Reject if zone information is invalid (z and iz are both 0)
        local z = tonumber(discoveryData.z) or 0
        local iz = tonumber(discoveryData.iz) or 0
        if z == 0 and iz == 0 then
            return -- Silently drop packet with invalid zone data
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
    
    local itemID = discoveryData.i or extractItemID(discoveryData.il)
    if not itemID then
        return
    end
    
    local Constants = L:GetModule("Constants", true)
    local dt = discoveryData.dt
    if not dt and itemID > 0 then
        local name = select(1, GetItemInfo(itemID))
        if name then
            if string.find(name, "Mystic Scroll", 1, true) then
                dt = Constants.DISCOVERY_TYPE.MYSTIC_SCROLL
            else
                dt = Constants.DISCOVERY_TYPE.WORLDFORGED
            end
        end
    end
    discoveryData.dt = dt -- Ensure it's set for later use

    local isBlackmarket = Constants and dt == Constants.DISCOVERY_TYPE.BLACKMARKET
    
    if options.isNetwork then
        if isBlackmarket then
            -- Process vendors immediately*
        elseif self:IsItemFullyCached(itemID) then
            -- Process cached items immediately*
        else
            -- Defer processing for uncached items
            local firstDelay = math.random(5, 25)
            self:QueueItemForCaching(itemID)

            ScheduleAfter(firstDelay, function()
                if self:IsItemFullyCached(itemID) then
                    self:AddDiscovery(discoveryData, options)
                else
                    SafeCacheItemRequest(itemID)
                    ScheduleAfter(5, function()
                        if self:IsItemFullyCached(itemID) then
                            self:AddDiscovery(discoveryData, options)
                        else
                            -- Drop packet if still not cached
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
    
    local x = (discoveryData.xy and discoveryData.xy.x) or 0
    local y = (discoveryData.xy and discoveryData.xy.y) or 0
    x = L:Round4(x)
    y = L:Round4(y)
    
    local c = discoveryData.c or 0
    local z = discoveryData.z or 0
    local iz = discoveryData.iz or 0
    
    if options.isNetwork and z == 0 and iz == 0 then
        local legacyZoneName = discoveryData.zn or discoveryData.zone
        if legacyZoneName then
            local ZoneList = L:GetModule("ZoneList", true)
            if ZoneList and ZoneList.ResolveInstanceIz then
                local resolved_iz = ZoneList:ResolveInstanceIz(legacyZoneName)
                if resolved_iz > 0 then
                    iz = resolved_iz
                    discoveryData.iz = iz
                end
            end
        end
    end

    if isBlackmarket then
        local guid, vendorType
        vendorType = discoveryData.vendorType
        if not vendorType then
            if itemID >= -399999 and itemID <= -300000 then vendorType = "BM"
            elseif itemID >= -499999 and itemID <= -400000 then vendorType = "MS"
            end
        end

        if vendorType == "MS" then
            guid = "MS-" .. c .. "-" .. z .. "-" .. string.format("%.2f", L:Round2(x)) .. "-" .. string.format("%.2f", L:Round2(y))
        else
            guid = "BM-" .. c .. "-" .. z .. "-" .. string.format("%.2f", L:Round2(x)) .. "-" .. string.format("%.2f", L:Round2(y))
        end
        
        local vendorItems = {}
        if discoveryData.vendorItemIDs and type(discoveryData.vendorItemIDs) == "table" then
            for _, receivedItemID in ipairs(discoveryData.vendorItemIDs) do
                local name, link = GetItemInfo(receivedItemID)
                if name and link then
                    table.insert(vendorItems, { itemID = receivedItemID, name = name, link = link })
                end
            end
        end

        local bm_db = L.db.global.blackmarketVendors
        local existing = bm_db[guid]

        if not existing then
            bm_db[guid] = {
                g = guid, c = c, z = z, iz = iz, i = itemID, 
                il = discoveryData.il,
                xy = { x = x, y = y },
                fp = discoveryData.fp, o = discoveryData.sender,
                t0 = discoveryData.t0, ls = discoveryData.t0, s = Constants.STATUS.CONFIRMED, st = discoveryData.t0,
                dt = discoveryData.dt,
                vendorType = vendorType,
                vendorName = discoveryData.vendorName or discoveryData.fp,
                vendorItems = vendorItems,
            }
        else
            existing.ls = max(existing.ls or 0, discoveryData.t0 or 0)
            existing.vendorName = discoveryData.vendorName or existing.vendorName
            if #vendorItems > 0 then
                existing.vendorItems = vendorItems
            end
        end
        
        local Map = L:GetModule("Map", true)
        if Map and Map.Update and WorldMapFrame and WorldMapFrame:IsShown() then Map:Update() end
        return
    end
    
    local db = L.db.global.discoveries
    local existing
    
    if (op == "CONF" or op == "SHOW") and dt == Constants.DISCOVERY_TYPE.WORLDFORGED then
        existing = FindWorldforgedInZone(c, z, itemID, db)
    end

    if not existing then
        local guid = L:GenerateGUID(c, z, itemID, x, y)
        existing = db[guid] or FindNearbyDiscovery(c, z, itemID, x, y, db)
    end
    
    if op == "DISC" then
        local incoming_fp = discoveryData.fp
        if discoveryData.sflag == 1 then incoming_fp = "An Unnamed Collector" end

        if not existing then
            local newRecord = {
                g = L:GenerateGUID(c, z, itemID, x, y), c = c, z = z, iz = iz, i = itemID, xy = {x=x, y=y},
                il = discoveryData.il, q = discoveryData.q, t0 = discoveryData.t0,
                ls = discoveryData.ls, st = discoveryData.ls, s = Constants.STATUS.UNCONFIRMED,
                mc = 1, fp = incoming_fp, o = discoveryData.sender,
                fp_votes = { [incoming_fp] = { score = 1, t0 = discoveryData.t0 } },
                dt = discoveryData.dt, it = discoveryData.it, ist = discoveryData.ist, cl = discoveryData.cl,
                src = discoveryData.src,
                s_flag = discoveryData.sflag,
                mid = discoveryData.mid,
                adc = 0, ack_votes = {},
            }
            db[newRecord.g] = newRecord
            
            L:SendMessage("LootCollector_DiscoveriesUpdated", "add", newRecord.g, newRecord)
			if not options.suppressToast then
				local toast = L:GetModule("Toast", true)
				if toast and toast.Show then 
					toast:Show(newRecord, false, options) 
				end
			end
                        
            if toast and toast.Show then toast:Show(newRecord, false, options) end
        else
            if incoming_fp ~= existing.fp then
                -- Defensively create the fp_votes table if it doesn't exist on an old record.
                if not existing.fp_votes then
                    existing.fp_votes = {}
                    if existing.fp and existing.t0 then
                        existing.fp_votes[existing.fp] = { score = 1, t0 = existing.t0 }
                    end
                end

                if not existing.corr_sent_ts or (time() - existing.corr_sent_ts > 900) then
                    local Comm = L:GetModule("Comm", true)
                    if Comm and Comm.BroadcastCorrection then
                        self:UpdateConsensusWinner(existing)
                        local winner_data = existing.fp_votes[existing.fp]
                        
                        Comm:BroadcastCorrection({
                            i = existing.i, c = existing.c, z = existing.z,
                            fp = existing.fp,
                            t0 = winner_data and winner_data.t0 or existing.t0,
                        })
                        existing.corr_sent_ts = time()
                    end
                end
            end
            
            if options.isNetwork then
                existing.coord_votes = existing.coord_votes or {}
                existing.coord_votes[discoveryData.sender] = { x = x, y = y }
                
                local voteCount = 0
                for _ in pairs(existing.coord_votes) do voteCount = voteCount + 1 end
                
                if voteCount >= 10 then
                    self:UpdateCoordinatesByConsensus(existing)
                end
            end
            
            L:SendMessage("LootCollector_DiscoveriesUpdated", "update", existing.g, existing)
        end

    elseif op == "CONF" or op == "SHOW" then
        if existing then
            existing.ls = max(existing.ls or 0, discoveryData.ls or discoveryData.t0)
            if op == "CONF" then
                existing.mc = (existing.mc or 1) + 1
                L:SendMessage("LOOTCOLLECTOR_CONFIRMATION_RECEIVED", discoveryData)
            end
        else
            if x ~= 0 and y ~= 0 then
                -- Sanitize finder name for new records from CONF/SHOW
                local finder = discoveryData.fp
                if not finder or finder == "" then
                    finder = "An Unnamed Collector"
                end
                
                local newRecord = {
                    g = L:GenerateGUID(c, z, itemID, x, y), c = c, z = z, iz = iz, i = itemID, xy = {x=x, y=y},
                    il = discoveryData.il, q = discoveryData.q, t0 = discoveryData.t0,
                    ls = (discoveryData.ls or discoveryData.t0), st = (discoveryData.ls or discoveryData.t0), s = Constants.STATUS.UNCONFIRMED,
                    mc = 1, fp = finder, o = discoveryData.sender,
                    fp_votes = { [finder] = { score = 1, t0 = discoveryData.t0 } },
                    dt = discoveryData.dt, it = discoveryData.it, ist = discoveryData.ist, cl = discoveryData.cl,
                    src = discoveryData.src,
                    mid = discoveryData.mid,
                    adc = 0, ack_votes = {},
                }
                db[newRecord.g] = newRecord
                
                L:SendMessage("LootCollector_DiscoveriesUpdated", "add", newRecord.g, newRecord)
                
                local toast = L:GetModule("Toast", true)
                if toast and toast.Show then toast:Show(newRecord, false, options) end
            end
        end
    end
    
    
    if existing then
        local wasUpdated = false
        if not existing.il then 
            existing.il = discoveryData.il 
            wasUpdated = true
        end
        if not existing.mid and discoveryData.mid then 
            existing.mid = discoveryData.mid 
            wasUpdated = true
        end
        if (existing.q or 0) == 0 and discoveryData.q then 
            existing.q = discoveryData.q 
            wasUpdated = true
        end
        
        if wasUpdated then
            L:SendMessage("LootCollector_DiscoveriesUpdated", "update", existing.g, existing)
        end
    end

    local Map = L:GetModule("Map", true)
    if Map and Map.Update and WorldMapFrame and WorldMapFrame:IsShown() then Map:Update() end
end

function Core:PurgeZeroCoordDiscoveries()
    if not (L.db and L.db.global and L.db.global.discoveries) then return 0 end
    
    local discoveries = L.db.global.discoveries
    local guidsToRemove = {}
    
    for guid, d in pairs(discoveries) do
        if d and d.xy and d.xy.x == 0 and d.xy.y == 0 then
            table.insert(guidsToRemove, guid)
        end
    end
    
    local removedCount = #guidsToRemove
    if removedCount > 0 then
        for _, guid in ipairs(guidsToRemove) do
            discoveries[guid] = nil
            L:SendMessage("LootCollector_DiscoveriesUpdated", "remove", guid, nil)
        end
    end
    
    return removedCount
end

function Core:ReportDiscoveryAsGone(guid)
    if not guid then return end
    local db = L.db.global.discoveries
    local rec = db[guid]
    if not rec then return end

    local Comm = L:GetModule("Comm", true)
    if not (Comm and Comm.BroadcastAckFor) then
        
        return
    end

    
    
    
    if rec.mid and rec.mid ~= "" then
        local discoveryPayload = {
            i = rec.i, il = rec.il, c = rec.c, z = rec.z,
            iz = rec.iz or 0, xy = rec.xy, t0 = rec.t0,
        }
        Comm:BroadcastAckFor(discoveryPayload, rec.mid, "DET")
    end

    
    self:RemoveDiscoveryByGuid(guid, string.format("Discovery %s reported as gone and removed.", rec.il or guid))
end

function Core:RemoveDiscoveryByGuid(guid, reason)
    if not guid or not (L.db and L.db.global and L.db.global.discoveries) then return end
    if L.db.global.discoveries[guid] then
        local rec = L.db.global.discoveries[guid]
        L.db.global.discoveries[guid] = nil
        print(string.format("|cff00ff00LootCollector:|r %s", reason or ("Discovery " .. guid .. " removed.")))
        
        -- Notifies Viewer of removed discovery
        L:SendMessage("LootCollector_DiscoveriesUpdated", "remove", guid, nil)
        
        local Map = L:GetModule("Map", true)
        if Map and Map.Update then
            Map:Update()
        end
        
        
        L:SendMessage("LOOTCOLLECTOR_DISCOVERY_LIST_UPDATED")
        return true
    end
    return false
end

function Core:RemoveBlackmarketVendorByGuid(guid)
    if not guid or not (L.db and L.db.global and L.db.global.blackmarketVendors) then return end
    if L.db.global.blackmarketVendors[guid] then
        L.db.global.blackmarketVendors[guid] = nil
        print("|cff00ff00LootCollector:|r Specialty Vendor pin removed from local database.")
        
        local Map = L:GetModule("Map", true)
        if Map and Map.Update then
            Map:Update()
        end
        return true
    end
    return false
end

function Core:ClearDiscoveries()
    if not (L.db and L.db.global) then return end
    L.db.global.discoveries = {}
    L.db.global.blackmarketVendors = {}
    print(string.format("[%s] Cleared all discovery and vendor data.", L.name))
    
    -- Notifies Viewer that all discoveries were cleared
    L:SendMessage("LootCollector_DiscoveriesUpdated", "clear", nil, nil)
    
    local Map = L:GetModule("Map", true)
    if Map and Map.Update and WorldMapFrame and WorldMapFrame:IsShown() then
        Map:Update()
    end
end

function Core:RemoveDiscovery(guid)
    if not guid or not (L.db and L.db.global and L.db.global.discoveries) then return end
    if L.db.global.discoveries[guid] then
        L.db.global.discoveries[guid] = nil
        print(string.format("|cff00ff00LootCollector:|r Discovery %s removed.", guid))
        
        -- Notifies Viewer of removed discovery
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
    if not (L.db and L.db.global and L.db.global.discoveries) then return 0 end
    local changed = 0
    for _, d in pairs(L.db.global.discoveries) do
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

local Core = L:GetModule("Core", true)
if not Core then
    
    return
end

local PROTO_V            = 5
local OP_DISC            = "DISC"
local OP_CONF            = "CONF"
local OP_ACK             = "ACK"

local DELETION_THRESHOLD_FADING = 7
local DELETION_THRESHOLD_STALE = 14
local DELETION_THRESHOLD_REMOVE = 21

local function roundTo(v, places)
    v = tonumber(v) or 0
    local mul = 10 ^ (places or 0)
    return math.floor(v * mul + 0.5) / mul
end

function Core:_MakeKeyV5(norm)
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

function Core:_FindByMid(mid)
    if not (L and L.db and L.db.global and L.db.global.discoveries) then
        return nil
    end
    local db = L.db.global.discoveries
    for _, rec in pairs(db) do
        if type(rec) == "table" and rec.mid == mid then
            return rec
        end
    end
    return nil
end

function Core:ProcessAckVote(mid, sender)
    if not mid or mid == "" or not sender or sender == "" then return end
    
    local rec = self:_FindByMid(mid)
    if not rec then return end
    
    
    rec.ack_votes = rec.ack_votes or {}
    
    
    if rec.ack_votes[sender] then return end
    
    
    rec.ack_votes[sender] = true
    local voteCount = 0
    for _ in pairs(rec.ack_votes) do voteCount = voteCount + 1 end
    rec.adc = voteCount
    
    

    
    if voteCount >= DELETION_THRESHOLD_REMOVE then
        self:RemoveDiscoveryByGuid(rec.g, string.format("Discovery %s removed by consensus (%d votes).", rec.il or "item", voteCount))
    elseif rec.s == "CONFIRMED" and voteCount >= DELETION_THRESHOLD_STALE then
        rec.s = "STALE"
        rec.st = time()
    elseif rec.s == "CONFIRMED" and voteCount >= DELETION_THRESHOLD_FADING then
        rec.s = "FADING"
        rec.st = time()
    end
    
    
    L:SendMessage("LOOTCOLLECTOR_DISCOVERY_LIST_UPDATED")
    local Map = L:GetModule("Map", true)
    if Map and Map.Update and WorldMapFrame and WorldMapFrame:IsShown() then
        Map:Update()
    end
end

function Core:HandleGuidedFix(fixData)
    if not fixData or not (L.db and L.db.global and L.db.global.discoveries) then return end

    local db = L.db.global.discoveries
    local updatedCount = 0
    local recordsToUpdate = {}

    
    if fixData.type == 1 then 
        for guid, d in pairs(db) do
            if d.i == fixData.i and d.c == fixData.c and d.z == fixData.z then
                local dx = (d.xy.x or 0) - fixData.nx
                local dy = (d.xy.y or 0) - fixData.ny
                if (dx*dx + dy*dy) <= (fixData.prox * fixData.prox) then
                    table.insert(recordsToUpdate, guid)
                end
            end
        end
    elseif fixData.type == 2 then 
        for guid, d in pairs(db) do
            if d.i == fixData.i and d.c == fixData.c and d.z == fixData.z then
                local dx = math.abs((d.xy.x or 0) - fixData.ox)
                local dy = math.abs((d.xy.y or 0) - fixData.oy)
                if dx <= fixData.tol and dy <= fixData.tol then
                    table.insert(recordsToUpdate, guid)
                end
            end
        end
    end

    
    if #recordsToUpdate > 0 then
        for _, oldGuid in ipairs(recordsToUpdate) do
            local oldRecord = db[oldGuid]
            if oldRecord then
                
                db[oldGuid] = nil
                
                
                local newRecord = {}
                for k, v in pairs(oldRecord) do newRecord[k] = v end
                
                newRecord.xy.x = fixData.nx
                newRecord.xy.y = fixData.ny
                
                
                local newGuid = L:GenerateGUID(newRecord.c, newRecord.z, newRecord.i, newRecord.xy.x, newRecord.xy.y)
                newRecord.g = newGuid
                
                
                db[newGuid] = newRecord
                updatedCount = updatedCount + 1
            end
        end
    end

    if updatedCount > 0 then
        
        local Map = L:GetModule("Map", true)
        if Map and Map.Update then
            Map:Update()
        end

    end
end
-- QSBBIEEgQSBBIEEgQSBBIEEgQQrwn5KlIPCfkqUg8J+SpSDwn5KlIPCfkqUg8J+SpSDwn5KlIPCfkqUg8J+SpSDwn5Kl