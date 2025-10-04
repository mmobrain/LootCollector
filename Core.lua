local L = LootCollector
local Core = L:NewModule("Core")

-- Upvalues
local floor    = math.floor
local time     = time
local tonumber = tonumber
local tostring = tostring
local pairs    = pairs
local select   = select
local type     = type
local max      = math.max

-- Status constants
local STATUS_UNCONFIRMED = "UNCONFIRMED"
local STATUS_CONFIRMED   = "CONFIRMED"
local STATUS_FADING      = "FADING"
local STATUS_STALE       = "STALE"

-- Merge distance constants
local DISCOVERY_MERGE_DISTANCE = 0.03
local DISCOVERY_MERGE_DISTANCE_SQ = DISCOVERY_MERGE_DISTANCE * DISCOVERY_MERGE_DISTANCE

local itemCacheTooltip 
local cacheTicker 
local CACHE_MIN_DELAY, CACHE_MAX_DELAY = 30, 60

local function debugPrint(message)
    local Comm = L:GetModule("Comm", true)
    if Comm and Comm.verbose then
        print(string.format("|cffffff00[Core DEBUG]|r %s", tostring(message)))
    end
end

-- Round normalized map coordinates to 2 decimals for storage and GUIDs
local function round2(v)
    v = tonumber(v) or 0
    return floor(v * 100 + 0.5) / 100
end

-- Build canonical guid string: "zoneID-itemID-x2-y2"
local function buildGuid2(zoneID, itemID, x, y)
    local x2 = round2(x or 0); local y2 = round2(y or 0); return tostring(zoneID or 0) .. "-" .. tostring(itemID or 0) .. "-" .. tostring(x2) .. "-" .. tostring(y2)
end

-- Find an existing discovery for the same item within a mergeable distance
local function FindNearbyDiscovery(zoneID, itemID, x, y, db)
    if not db then return nil end; for guid, d in pairs(db) do if d.zoneID == zoneID and d.itemID == itemID then if d.coords then local dx = (d.coords.x or 0) - x; local dy = (d.coords.y or 0) - y; if (dx*dx + dy*dy) < DISCOVERY_MERGE_DISTANCE_SQ then return d end end end end; return nil
end

-- Extract numeric itemID from an itemLink
local function extractItemID(itemLink)
    if type(itemLink) ~= "string" then return nil end; local id = itemLink:match("item:(%d+)"); return id and tonumber(id) or nil
end

-- Ensure verification fields exist on a discovery record
function Core:EnsureVerificationFields(d)
    if not d then return end; if not d.itemID then d.itemID = extractItemID(d.itemLink) end; d.status = d.status or d.verificationStatus or STATUS_UNCONFIRMED; d.statusTs = tonumber(d.statusTs) or tonumber(d.lastConfirmed) or tonumber(d.lastSeen) or tonumber(d.timestamp) or time(); d.lastSeen = tonumber(d.lastSeen) or tonumber(d.timestamp) or time(); d.verificationStatus = nil; d.lastConfirmed = nil; d.coords = d.coords or { x = 0, y = 0 }; d.coords.x = round2(d.coords.x or 0); d.coords.y = round2(d.coords.y or 0); d.mergeCount = d.mergeCount or 1; d.lootedByMe = nil
end

-- Merge b into a, favoring newer timestamps; returns merged a
local function mergeRecords(a, b)
    if not a.itemLink and b.itemLink then a.itemLink = b.itemLink end; a.lastSeen  = max(tonumber(a.lastSeen) or 0, tonumber(b.lastSeen) or 0); local aTs = tonumber(a.statusTs) or 0; local bTs = tonumber(b.statusTs) or 0; if bTs > aTs and b.status then a.status = b.status; a.statusTs = bTs end; return a
end

-- One-time migrations
function Core:MigrateDiscoveries()
    if not (L.db and L.db.profile and L.db.global and L.db.char) then return end; local profile = L.db.profile; local global  = L.db.global; local char = L.db.char; profile._schemaVersion = profile._schemaVersion or 0; global._schemaVersion  = global._schemaVersion or 0; profile.discoveries = profile.discoveries or {}; global.discoveries  = global.discoveries or {}; char.looted = char.looted or {}; char.hidden = char.hidden or {}; if profile._schemaVersion < 1 then for _, d in pairs(profile.discoveries) do if type(d) == "table" then if not d.itemID then d.itemID = extractItemID(d.itemLink) end; self:EnsureVerificationFields(d) end end; profile._schemaVersion = 1 end; if profile._schemaVersion < 2 then local newMap = {}; for _, d in pairs(profile.discoveries) do if type(d) == "table" then self:EnsureVerificationFields(d); local z = d.zoneID or 0; local i = d.itemID or extractItemID(d.itemLink) or 0; local x = d.coords and d.coords.x or 0; local y = d.coords and d.coords.y or 0; local guid2 = buildGuid2(z, i, x, y); d.guid = guid2; if newMap[guid2] then newMap[guid2] = mergeRecords(newMap[guid2], d) else newMap[guid2] = d end end end; profile.discoveries = newMap; profile._schemaVersion = 2 end; if global._schemaVersion < 1 then local moved = 0; if profile.discoveries and next(profile.discoveries) then for guid, d in pairs(profile.discoveries) do if type(d) == "table" then self:EnsureVerificationFields(d); if d.lootedByMe then char.looted[guid] = tonumber(d.statusTs) or tonumber(d.timestamp) or time() end; d.lootedByMe = nil; global.discoveries[guid] = d; moved = moved + 1 end end; profile.discoveries = {} end; global._schemaVersion = 1; if moved > 0 then print(string.format("|cff00ff00LootCollector:|r Promoted %d discoveries to account scope.", moved)) end end; if global._schemaVersion < 2 then local byItemZone = {}; for guid, d in pairs(global.discoveries) do if d and d.zoneID and d.itemID then local key = tostring(d.zoneID) .. ":" .. tostring(d.itemID); if not byItemZone[key] then byItemZone[key] = {} end; table.insert(byItemZone[key], d) end end; local newDb = {}; local numMerged = 0; for key, group in pairs(byItemZone) do while #group > 0 do local cluster = { table.remove(group, 1) }; local i = #group; while i >= 1 do local d2 = group[i]; local isNear = false; for _, d1 in ipairs(cluster) do local dx = ((d1.coords and d1.coords.x) or 0) - ((d2.coords and d2.coords.x) or 0); local dy = ((d1.coords and d1.coords.y) or 0) - ((d2.coords and d2.coords.y) or 0); if (dx*dx + dy*dy) < DISCOVERY_MERGE_DISTANCE_SQ then isNear = true; break end end; if isNear then table.insert(cluster, table.remove(group, i)) end; i = i - 1 end; if #cluster == 1 then local d = cluster[1]; self:EnsureVerificationFields(d); newDb[d.guid] = d; else numMerged = numMerged + #cluster; local sum_x, sum_y = 0, 0; local merged_d = {}; for k,v in pairs(cluster[1]) do merged_d[k] = v end; for _, d_in_cluster in ipairs(cluster) do sum_x = sum_x + ((d_in_cluster.coords and d_in_cluster.coords.x) or 0); sum_y = sum_y + ((d_in_cluster.coords and d_in_cluster.coords.y) or 0); if (d_in_cluster.lastSeen or 0) > (merged_d.lastSeen or 0) then mergeRecords(merged_d, d_in_cluster) end end; merged_d.coords.x = round2(sum_x / #cluster); merged_d.coords.y = round2(sum_y / #cluster); merged_d.mergeCount = #cluster; local newGuid = buildGuid2(merged_d.zoneID, merged_d.itemID, merged_d.coords.x, merged_d.coords.y); merged_d.guid = newGuid; newDb[newGuid] = merged_d end; end end; if numMerged > 0 then print(string.format("|cff00ff00LootCollector:|r Merged %d nearby discoveries into %d more accurate locations.", numMerged, #newDb)) end; global.discoveries = newDb; global._schemaVersion = 2 end
end

local PURGE_VERSION = "EmbossedScroll_v1"
function Core:PurgeEmbossedScrolls()
    if L.db.global.purgeEmbossedState == 2 then debugPrint("Skipping PurgeEmbossedScrolls: Verification complete."); return end; local purgeState = L.db.global.purgeEmbossedState or 0; debugPrint("Starting PurgeEmbossedScrolls scan (State: " .. purgeState .. ")"); local discoveries = L.db.global.discoveries or {}; local guidsToProcess = {}; local processedCount = 0; for guid, d in pairs(discoveries) do if d then local name; local itemID = d.itemID or extractItemID(d.itemLink); debugPrint(string.format("Checking GUID: %s, ItemID: %s", tostring(guid), tostring(itemID))); if d.itemLink then name = d.itemLink:match("%[(.+)%]") ; debugPrint(string.format("... Name from itemLink: '%s'", tostring(name))) end; if not name and itemID then name = GetItemInfo(itemID); debugPrint(string.format("... Name from GetItemInfo(%s): '%s'", tostring(itemID), tostring(name))) end; if name and string.find(name, "Embossed Mystic Scroll", 1, true) then debugPrint(string.format("|cff00ff00MATCH FOUND! Queuing for removal.|r")); table.insert(guidsToProcess, guid) end end end; processedCount = #guidsToProcess; if purgeState == 0 then debugPrint("Running Cleanup stage. Found " .. processedCount .. " items to remove."); for _, guid in ipairs(guidsToProcess) do discoveries[guid] = nil end; if processedCount > 0 then print(string.format("|cff00ff00LootCollector:|r Removed %d 'Embossed Mystic Scroll' entries from the database.", processedCount)) end; L.db.global.purgeEmbossedState = 1 elseif purgeState == 1 then debugPrint("Running Verification stage. Found " .. processedCount .. " items."); if processedCount == 0 then debugPrint("|cff00ff00Verification successful. No Embossed scrolls found.|r"); L.db.global.purgeEmbossedState = 2 else print("|cffff7f00LootCollector:|r Verification failed! Found " .. processedCount .. " 'Embossed Mystic Scroll' entries that should have been deleted. The cleanup will run again on next login.") end end; debugPrint("Finished PurgeEmbossedScrolls scan.")
end

local function findDiscoveryDetails(itemID) if not itemID then return "Unknown Item", "Unknown Zone" end; local discoveries = L.db.global.discoveries or {}; for guid, d in pairs(discoveries) do if d and d.itemID == itemID then local name = (d.itemLink and d.itemLink:match("%[(.+)%]")) or ("Item " .. itemID); return name, d.zone or "Unknown Zone" end end; return "Item " .. itemID, "Unknown Zone" end;
function Core:IsItemCached(itemID) if not itemID then return true end; local name = GetItemInfo(itemID); return name ~= nil end;
function Core:QueueItemForCaching(itemID) if not itemID or not L.db.profile.autoCache then return end; L.db.global.cacheQueue = L.db.global.cacheQueue or {}; local queueMap = {}; for _, id in ipairs(L.db.global.cacheQueue) do queueMap[id] = true end; if not queueMap[itemID] then table.insert(L.db.global.cacheQueue, itemID) end end;
function Core:ScanDatabaseForUncachedItems() if not L.db.profile.autoCache then return end; local discoveries = L.db.global.discoveries or {}; local queuedCount = 0; for guid, d in pairs(discoveries) do if d and d.itemID and not self:IsItemCached(d.itemID) then self:QueueItemForCaching(d.itemID); queuedCount = queuedCount + 1 end end; if queuedCount > 0 then print(string.format("|cff00ff00LootCollector:|r Found and queued %d uncached items for background processing.", queuedCount)); debugPrint(string.format("Total items in cache queue: %d", #(L.db.global.cacheQueue or {}))) end end;
function Core:ProcessCacheQueue() if not L.db.profile.autoCache then if cacheTicker then cacheTicker:Cancel(); cacheTicker = nil end; return end; local queue = L.db.global.cacheQueue; if not queue or #queue == 0 then if cacheTicker then cacheTicker:Cancel(); cacheTicker = nil end; debugPrint("Item cache queue is now empty."); return end; local itemID = table.remove(queue, 1); if itemID then if not self:IsItemCached(itemID) then local itemName, itemZone = findDiscoveryDetails(itemID); debugPrint(string.format("Processing cache for item %d (%s in %s). Queue remaining: %d", itemID, itemName, itemZone, #queue)); itemCacheTooltip:SetHyperlink("item:" .. itemID); itemCacheTooltip:Hide() else debugPrint(string.format("Item %d was already cached, skipping. Queue remaining: %d", itemID, #queue)) end end; if cacheTicker then cacheTicker:Cancel() end; if #queue > 0 then local delay = math.random(CACHE_MIN_DELAY, CACHE_MAX_DELAY); debugPrint(string.format("Next cache check in %d seconds.", delay)); cacheTicker = Timer.After(delay, function() self:ProcessCacheQueue() end) end end;
function Core:OnGetItemInfoReceived(event, itemID) local name, itemLink, _, _, _, _, _, _, _, texture = GetItemInfo(itemID); if name and texture then debugPrint(string.format("|cff00ff00Successfully cached item %d (%s).|r", itemID, name)); if itemLink then local discoveries = L.db.global.discoveries or {}; for guid, d in pairs(discoveries) do if d and d.itemID == itemID and not d.itemLink then d.itemLink = itemLink end end end end; local Map = L:GetModule("Map", true); if Map and Map.Update and WorldMapFrame and WorldMapFrame:IsShown() then Map:Update() end end;

function Core:OnInitialize()
    if not (L.db and L.db.profile and L.db.global and L.db.char) then return end; if L.db.profile.autoCache == nil then L.db.profile.autoCache = true end; L.db.global.cacheQueue = L.db.global.cacheQueue or {}; L.db.global.discoveries = L.db.global.discoveries or {}; L.db.char.looted = L.db.char.looted or {}; L.db.char.hidden = L.db.char.hidden or {}; self:MigrateDiscoveries();
    itemCacheTooltip = CreateFrame("GameTooltip", "LootCollectorCacheTooltip", UIParent, "GameTooltipTemplate"); itemCacheTooltip:SetOwner(UIParent, "ANCHOR_NONE"); L:RegisterEvent("GET_ITEM_INFO_RECEIVED", self.OnGetItemInfoReceived);
    Timer.After(10, function() self:PurgeEmbossedScrolls(); self:ScanDatabaseForUncachedItems(); if #L.db.global.cacheQueue > 0 and (not cacheTicker or cacheTicker:IsCancelled()) then self:ProcessCacheQueue() end end)
end

function Core:Qualifies(linkOrQuality) if type(linkOrQuality)=="number" then return false end; local link=linkOrQuality; if not link then return false end; local SCAN_TIP_NAME="LootCollectorCoreScanTip"; if not self._scanTip then self._scanTip=CreateFrame("GameTooltip",SCAN_TIP_NAME,nil,"GameTooltipTemplate"); self._scanTip:SetOwner(UIParent,"ANCHOR_NONE") end; local function tipHas(needle) self._scanTip:ClearLines(); self._scanTip:SetHyperlink(link); for i=2,5 do local fs=_G[SCAN_TIP_NAME.."TextLeft"..i]; local text=fs and fs:GetText(); if text and string.find(string.lower(text),string.lower(needle),1,true) then return true end end; return false end;
    local name=(select(1,GetItemInfo(link)))or(link:match("%[(.-)%]"))or""; if name=="" then return false end; if string.find(name,"Embossed Mystic Scroll",1,true) then return false end; local isScroll=string.find(name,"Mystic Scroll",1,true)~=nil; local isWorldforged=tipHas("Worldforged"); return isWorldforged or isScroll
end

function Core:HandleLocalLoot(discovery)
    if L:IsZoneIgnored() then return end; if not(L.db and L.db.profile and L.db.global and L.db.char)then return end; local itemID=extractItemID(discovery.itemLink); if not itemID then return end; discovery.foundBy_player=UnitName("player"); discovery.coords=discovery.coords or{x=0,y=0}; discovery.coords.x=round2(discovery.coords.x or 0); discovery.coords.y=round2(discovery.coords.y or 0); local x=discovery.coords.x; local y=discovery.coords.y; local nowTs=time(); local db=L.db.global.discoveries; local existing=FindNearbyDiscovery(discovery.zoneID,itemID,x,y,db); if not existing then local guid=buildGuid2(discovery.zoneID,itemID,x,y); discovery.guid=guid; discovery.itemID=itemID; discovery.timestamp=discovery.timestamp or nowTs; discovery.lastSeen=nowTs; discovery.status=STATUS_UNCONFIRMED; discovery.statusTs=nowTs; discovery.lootedByMe=nil; self:EnsureVerificationFields(discovery); db[guid]=discovery; L.db.char.looted[guid]=nowTs; print(string.format("|cff00ff00[%s]:|r New discovery! %s in %s.",L.name,discovery.itemLink or"an item",discovery.zone or"Unknown")); local Map=L:GetModule("Map",true); if Map and Map.Update and WorldMapFrame and WorldMapFrame:IsShown()then Map:Update()end; local Comm=L:GetModule("Comm",true); if Comm and Comm.BroadcastDiscovery then Comm:BroadcastDiscovery(discovery)end; return end; self:EnsureVerificationFields(existing); local n=existing.mergeCount or 1; existing.coords.x=(existing.coords.x*n+x)/(n+1); existing.coords.y=(existing.coords.y*n+y)/(n+1); existing.coords.x=round2(existing.coords.x); existing.coords.y=round2(existing.coords.y); existing.mergeCount=n+1; existing.lastSeen=nowTs; if not existing.foundBy_player or existing.foundBy_player=="Unknown"then existing.foundBy_player=UnitName("player")end; L.db.char.looted[existing.guid]=nowTs; local shouldShareConfirmation=(existing.status==STATUS_FADING); if shouldShareConfirmation then if existing.status~=STATUS_UNCONFIRMED then existing.status=STATUS_UNCONFIRMED; existing.statusTs=nowTs else existing.statusTs=nowTs end; local confirmPayload={guid=existing.guid,itemLink=existing.itemLink,itemID=existing.itemID or extractItemID(discovery.itemLink),zone=existing.zone,subZone=existing.subZone,zoneID=existing.zoneID,coords={x=existing.coords.x,y=existing.coords.y},foundBy_player=UnitName("player"),foundBy_class=select(2,UnitClass("player")),timestamp=nowTs,lootedByMe=true,}; local Comm=L:GetModule("Comm",true); if Comm and Comm.BroadcastConfirmation then Comm:BroadcastConfirmation(confirmPayload)end end; local Map=L:GetModule("Map",true); if Map and Map.Update and WorldMapFrame and WorldMapFrame:IsShown()then Map:Update()end
end

function Core:OnLootOpened()
    if L:IsZoneIgnored() then return end
    if not (L.db and L.db.profile and L.db.profile.enabled) then return end

    local numItems = GetNumLootItems() or 0
    if L.db.profile.checkOnlySingleItemLoot and numItems > 1 then
        return
    end

    for i = 1, numItems do
        local link = GetLootSlotLink(i)
        if link and self:Qualifies(link) then           
            local px, py = GetPlayerMapPosition("player")
            px, py = px or 0, py or 0
            
            local discovery = {
                itemLink = link,
                zone     = GetRealZoneText(),
                subZone  = GetSubZoneText(),
                zoneID   = GetCurrentMapZone() or 0,
                coords   = { x = px, y = py },
                foundBy_player = UnitName("player"),
                foundBy_class  = select(2, UnitClass("player")),
                timestamp = time(),
                source    = "world_loot",
            }
            self:HandleLocalLoot(discovery)
        end
    end
end
function Core:AddDiscovery(discoveryData,isNetworkDiscovery) if L:IsZoneIgnored()and isNetworkDiscovery then return end; if not(L.db and L.db.global)then return end; if type(discoveryData)~="table"then return end; local itemID=discoveryData.itemID or extractItemID(discoveryData.itemLink); if not itemID then return end; if not self:IsItemCached(itemID)then self:QueueItemForCaching(itemID); if not cacheTicker or cacheTicker:IsCancelled()then self:ProcessCacheQueue()end end; local x=(discoveryData.coords and discoveryData.coords.x)or 0; local y=(discoveryData.coords and discoveryData.coords.y)or 0; x=round2(x); y=round2(y); discoveryData.coords=discoveryData.coords or{}; discoveryData.coords.x=x; discoveryData.coords.y=y; local db=L.db.global.discoveries; local existing=FindNearbyDiscovery(discoveryData.zoneID,itemID,x,y,db); if not existing then local guid=buildGuid2(discoveryData.zoneID,itemID,x,y); discoveryData.guid=guid; discoveryData.itemID=itemID; discoveryData.lootedByMe=nil; self:EnsureVerificationFields(discoveryData); db[guid]=discoveryData; if isNetworkDiscovery then local toast=L:GetModule("Toast",true); if toast and toast.Show then toast:Show(discoveryData)end end; if not isNetworkDiscovery then print(string.format("|cff00ff00[%s]:|r New discovery! %s in %s.",L.name,discoveryData.itemLink or"an item",discoveryData.zone or"Unknown"))end; if WorldMapFrame and WorldMapFrame:IsShown()then local Map=L:GetModule("Map",true); if Map and Map.Update then Map:Update()end end; return end; self:EnsureVerificationFields(existing); local n=existing.mergeCount or 1; existing.coords.x=(existing.coords.x*n+x)/(n+1); existing.coords.y=(existing.coords.y*n+y)/(n+1); existing.coords.x=round2(existing.coords.x); existing.coords.y=round2(existing.coords.y); existing.mergeCount=n+1; local incomingTs=tonumber(discoveryData.statusTs)or tonumber(discoveryData.lastSeen)or tonumber(discoveryData.timestamp)or time(); if incomingTs>(existing.statusTs or 0)and discoveryData.status then existing.status=discoveryData.status; existing.statusTs=incomingTs end; local incomingLastSeen=tonumber(discoveryData.lastSeen)or tonumber(discoveryData.timestamp)or time(); if incomingLastSeen>(existing.lastSeen or 0)then existing.lastSeen=incomingLastSeen end; if not existing.itemLink and discoveryData.itemLink then existing.itemLink=discoveryData.itemLink; existing.itemID=existing.itemID or itemID end;
    local Map=L:GetModule("Map",true); if Map and Map.Update and WorldMapFrame and WorldMapFrame:IsShown()then Map:Update()end
end

function Core:ClearDiscoveries()
    if not (L.db and L.db.global) then return end
    L.db.global.discoveries = {}
    print(string.format("[%s] Cleared all discoveries.", L.name))
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
        local Map = L:GetModule("Map", true)
        if Map and Map.Update then
            Map:Update()
        end
        return true
    end
    return false
end

return Core