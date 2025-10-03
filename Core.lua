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
local DISCOVERY_MERGE_DISTANCE = 0.03 -- 3% of map width
local DISCOVERY_MERGE_DISTANCE_SQ = DISCOVERY_MERGE_DISTANCE * DISCOVERY_MERGE_DISTANCE

-- Round normalized map coordinates to 2 decimals for storage and GUIDs
local function round2(v)
    v = tonumber(v) or 0
    return floor(v * 100 + 0.5) / 100
end

-- Build canonical guid string: "zoneID-itemID-x2-y2"
local function buildGuid2(zoneID, itemID, x, y)
    local x2 = round2(x or 0)
    local y2 = round2(y or 0)
    return tostring(zoneID or 0) .. "-" .. tostring(itemID or 0) .. "-" .. tostring(x2) .. "-" .. tostring(y2)
end

-- Find an existing discovery for the same item within a mergeable distance
local function FindNearbyDiscovery(zoneID, itemID, x, y, db)
    if not db then return nil end
    for guid, d in pairs(db) do
        if d.zoneID == zoneID and d.itemID == itemID then
            if d.coords then
                local dx = (d.coords.x or 0) - x
                local dy = (d.coords.y or 0) - y
                if (dx*dx + dy*dy) < DISCOVERY_MERGE_DISTANCE_SQ then
                    return d
                end
            end
        end
    end
    return nil
end

-- Extract numeric itemID from an itemLink
local function extractItemID(itemLink)
    if type(itemLink) ~= "string" then return nil end
    local id = itemLink:match("item:(%d+)")
    return id and tonumber(id) or nil
end

-- Ensure verification fields exist on a discovery record
function Core:EnsureVerificationFields(d)
    if not d then return end
    -- Normalize itemID cache for later use
    if not d.itemID then
        d.itemID = extractItemID(d.itemLink)
    end
    -- Initialize verification/status fields if missing
    d.status   = d.status or d.verificationStatus or STATUS_UNCONFIRMED
    d.statusTs = tonumber(d.statusTs) or tonumber(d.lastConfirmed) or tonumber(d.lastSeen) or tonumber(d.timestamp) or time()
    d.lastSeen = tonumber(d.lastSeen) or tonumber(d.timestamp) or time()
    -- Backward-compat cleanup
    d.verificationStatus = nil
    d.lastConfirmed = nil
    -- Normalize coords to 2 decimals for storage
    d.coords = d.coords or { x = 0, y = 0 }
    d.coords.x = round2(d.coords.x or 0)
    d.coords.y = round2(d.coords.y or 0)
    -- Initialize merge count for coordinate averaging
    d.mergeCount = d.mergeCount or 1
    -- Strip any per-character flags from canonical records
    d.lootedByMe = nil
end

-- Merge b into a, favoring newer timestamps; returns merged a
local function mergeRecords(a, b)
    if not a.itemLink and b.itemLink then a.itemLink = b.itemLink end
    a.lastSeen  = max(tonumber(a.lastSeen) or 0, tonumber(b.lastSeen) or 0)
    local aTs   = tonumber(a.statusTs) or 0
    local bTs   = tonumber(b.statusTs) or 0
    if bTs > aTs and b.status then
        a.status   = b.status
        a.statusTs = bTs
    end
    -- coords already 2-decimal normalized by EnsureVerificationFields
    return a
end

-- One-time migrations:
-- v1: add status/statusTs/lastSeen to legacy profile store
-- v2: re-key to 2-decimal GUIDs and merge duplicates in legacy profile store
-- v3: promote discoveries from profile -> global; convert lootedByMe -> char.looted[guid]
-- v4 (global): merge nearby duplicate discoveries
function Core:MigrateDiscoveries()
    if not (L.db and L.db.profile and L.db.global and L.db.char) then return end

    local profile = L.db.profile
    local global  = L.db.global
    local char    = L.db.char

    profile._schemaVersion = profile._schemaVersion or 0
    global._schemaVersion  = global._schemaVersion or 0

    profile.discoveries = profile.discoveries or {}
    global.discoveries  = global.discoveries or {}
    char.looted = char.looted or {}
    char.hidden = char.hidden or {}

    -- v1 on legacy profile store
    if profile._schemaVersion < 1 then
        for _, d in pairs(profile.discoveries) do
            if d and type(d) == "table" then
                if not d.itemID then d.itemID = extractItemID(d.itemLink) end
                self:EnsureVerificationFields(d)
            end
        end
        profile._schemaVersion = 1
    end

    -- v2 on legacy profile store
    if profile._schemaVersion < 2 then
        local newMap = {}
        for _, d in pairs(profile.discoveries) do
            if d and type(d) == "table" then
                self:EnsureVerificationFields(d)
                local z = d.zoneID or 0
                local i = d.itemID or extractItemID(d.itemLink) or 0
                local x = d.coords and d.coords.x or 0
                local y = d.coords and d.coords.y or 0
                local guid2 = buildGuid2(z, i, x, y)
                d.guid = guid2
                if newMap[guid2] then
                    newMap[guid2] = mergeRecords(newMap[guid2], d)
                else
                    newMap[guid2] = d
                end
            end
        end
        profile.discoveries = newMap
        profile._schemaVersion = 2
    end

    -- v3: promote to global and convert per-character looted flags
    if global._schemaVersion < 1 then
        -- Only migrate if legacy profile store is non-empty and global is (mostly) empty
        local moved = 0
        if profile.discoveries and next(profile.discoveries) then
            for guid, d in pairs(profile.discoveries) do
                if d and type(d) == "table" then
                    self:EnsureVerificationFields(d)
                    -- Convert any per-character 'lootedByMe' into char overlay
                    if d.lootedByMe then
                        char.looted[guid] = tonumber(d.statusTs) or tonumber(d.timestamp) or time()
                    end
                    d.lootedByMe = nil
                    global.discoveries[guid] = d
                    moved = moved + 1
                end
            end
            -- Clear legacy store after promotion
            profile.discoveries = {}
        end
        global._schemaVersion = 1
        if moved > 0 then
            print(string.format("|cff00ff00LootCollector:|r Promoted %d discoveries to account scope.", moved))
        end
    end

    -- v4 (global): merge nearby duplicate discoveries
    if global._schemaVersion < 2 then
        local byItemZone = {}
        for guid, d in pairs(global.discoveries) do
            if d and d.zoneID and d.itemID then
                local key = tostring(d.zoneID) .. ":" .. tostring(d.itemID)
                if not byItemZone[key] then byItemZone[key] = {} end
                table.insert(byItemZone[key], d)
            end
        end

        local newDb = {}
        local numMerged = 0
        local numTotalBefore = 0
        local numTotalAfter = 0

        for key, group in pairs(byItemZone) do
            numTotalBefore = numTotalBefore + #group
            while #group > 0 do
                local cluster = { table.remove(group, 1) }
                local i = #group
                while i >= 1 do
                    local d2 = group[i]
                    local isNear = false
                    for _, d1 in ipairs(cluster) do
                        local dx = ((d1.coords and d1.coords.x) or 0) - ((d2.coords and d2.coords.x) or 0)
                        local dy = ((d1.coords and d1.coords.y) or 0) - ((d2.coords and d2.coords.y) or 0)
                        if (dx*dx + dy*dy) < DISCOVERY_MERGE_DISTANCE_SQ then
                            isNear = true
                            break
                        end
                    end
                    if isNear then
                        table.insert(cluster, table.remove(group, i))
                    end
                    i = i - 1
                end

                if #cluster == 1 then
                    local d = cluster[1]
                    self:EnsureVerificationFields(d)
                    newDb[d.guid] = d
                else
                    numMerged = numMerged + #cluster
                    local sum_x, sum_y = 0, 0
                    local merged_d = {}
                    for k,v in pairs(cluster[1]) do merged_d[k] = v end

                    for _, d_in_cluster in ipairs(cluster) do
                        sum_x = sum_x + ((d_in_cluster.coords and d_in_cluster.coords.x) or 0)
                        sum_y = sum_y + ((d_in_cluster.coords and d_in_cluster.coords.y) or 0)
                        if (d_in_cluster.lastSeen or 0) > (merged_d.lastSeen or 0) then
                            mergeRecords(merged_d, d_in_cluster)
                        end
                    end

                    merged_d.coords.x = round2(sum_x / #cluster)
                    merged_d.coords.y = round2(sum_y / #cluster)
                    merged_d.mergeCount = #cluster
                    local newGuid = buildGuid2(merged_d.zoneID, merged_d.itemID, merged_d.coords.x, merged_d.coords.y)
                    merged_d.guid = newGuid
                    newDb[newGuid] = merged_d
                end
                numTotalAfter = numTotalAfter + 1
            end
        end
        
        if numMerged > 0 then
            print(string.format("|cff00ff00LootCollector:|r Merged %d nearby discoveries into %d more accurate locations.", numTotalBefore, numTotalAfter))
        end
        
        global.discoveries = newDb
        global._schemaVersion = 2
    end
end

function Core:OnInitialize()
    if not (L.db and L.db.profile and L.db.global and L.db.char) then return end

    -- Ensure required containers exist
    L.db.global.discoveries = L.db.global.discoveries or {}
    L.db.char.looted = L.db.char.looted or {}
    L.db.char.hidden = L.db.char.hidden or {}

    -- Run migrations (includes promotion to global/overlays and merging)
    self:MigrateDiscoveries()
end

-- Quality filter
function Core:Qualifies(linkOrQuality)
  -- Back-compat: if given a number, always require explicit link checks elsewhere
  if type(linkOrQuality) == "number" then
    return false
  end
  local link = linkOrQuality
  if not link then return false end

  -- Lazy-create a shared scanner used by Detect too if present
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

  local name = (select(1, GetItemInfo(link))) or (link:match("%[(.-)%]")) or ""
  local isScroll = name and string.find(name, "Mystic Scroll", 1, true) ~= nil
  local isWorldforged = tipHas("Worldforged")

  return isWorldforged or isScroll
end

-- Internal: handle a qualified local loot event (player looted something)
function Core:HandleLocalLoot(discovery)
    if L:IsZoneIgnored() then return end
    if not (L.db and L.db.profile and L.db.global and L.db.char) then return end

    local itemID = extractItemID(discovery.itemLink)
    if not itemID then return end

    -- *** ROBUSTNESS FIX ***
    -- Ensure the current player is always credited for local loot events.
    discovery.foundBy_player = UnitName("player")

    -- Normalize coords
    discovery.coords = discovery.coords or { x = 0, y = 0 }
    discovery.coords.x = round2(discovery.coords.x or 0)
    discovery.coords.y = round2(discovery.coords.y or 0)

    local x = discovery.coords.x
    local y = discovery.coords.y
    local nowTs = time()

    local db = L.db.global.discoveries
    local existing = FindNearbyDiscovery(discovery.zoneID, itemID, x, y, db)

    if not existing then
        -- New canonical discovery, not near any others
        local guid = buildGuid2(discovery.zoneID, itemID, x, y)
        discovery.guid = guid
        discovery.itemID = itemID
        discovery.timestamp = discovery.timestamp or nowTs
        discovery.lastSeen = nowTs
        discovery.status = STATUS_UNCONFIRMED
        discovery.statusTs = nowTs
        discovery.lootedByMe = nil
        self:EnsureVerificationFields(discovery) -- This will set mergeCount = 1
        db[guid] = discovery

        -- Mark per-character completion
        L.db.char.looted[guid] = nowTs

        -- No toast for your own discoveries, just chat feedback.
        print(string.format("|cff00ff00[%s]:|r New discovery! %s in %s.", L.name, discovery.itemLink or "an item", discovery.zone or "Unknown"))

        -- Update map if open
        local Map = L:GetModule("Map", true)
        if Map and Map.Update and WorldMapFrame and WorldMapFrame:IsShown() then
            Map:Update()
        end

        -- Broadcast the new discovery via Comm (DISC goes AceComm + Channel)
        local Comm = L:GetModule("Comm", true)
        if Comm and Comm.BroadcastDiscovery then
            Comm:BroadcastDiscovery(discovery)
        end
        return
    end

    -- Merge into existing canonical record on local loot
    self:EnsureVerificationFields(existing)
    
    -- Weighted average of coordinates
    local n = existing.mergeCount or 1
    existing.coords.x = (existing.coords.x * n + x) / (n + 1)
    existing.coords.y = (existing.coords.y * n + y) / (n + 1)
    existing.coords.x = round2(existing.coords.x)
    existing.coords.y = round2(existing.coords.y)
    existing.mergeCount = n + 1

    existing.lastSeen = nowTs
    -- Ensure the original finder is preserved, unless it was Unknown
    if not existing.foundBy_player or existing.foundBy_player == "Unknown" then
        existing.foundBy_player = UnitName("player")
    end

    -- Mark per-character completion for the merged discovery's GUID
    L.db.char.looted[existing.guid] = nowTs

    -- Hardcoded confirmation rule: Always share a confirmation if the discovery is FADING,
    -- as this helps refresh its status on the network.
    local shouldShareConfirmation = (existing.status == STATUS_FADING)

    if shouldShareConfirmation then
        if existing.status ~= STATUS_UNCONFIRMED then
            existing.status = STATUS_UNCONFIRMED
            existing.statusTs = nowTs
        else
            existing.statusTs = nowTs
        end

        local confirmPayload = {
            guid = existing.guid,
            itemLink = existing.itemLink,
            itemID = existing.itemID or extractItemID(existing.itemLink),
            zone = existing.zone,
            subZone = existing.subZone,
            zoneID = existing.zoneID,
            coords = { x = existing.coords.x, y = existing.coords.y },
            foundBy_player = UnitName("player"),
            foundBy_class = select(2, UnitClass("player")),
            timestamp = nowTs,
            lootedByMe = true,
        }

        local Comm = L:GetModule("Comm", true)
        if Comm and Comm.BroadcastConfirmation then
            Comm:BroadcastConfirmation(confirmPayload)
        end
    end

    local Map = L:GetModule("Map", true)
    if Map and Map.Update and WorldMapFrame and WorldMapFrame:IsShown() then
        Map:Update()
    end
end

-- LOOT_OPENED -> HandleLocalLoot
function Core:OnLootOpened()
  if L:IsZoneIgnored() then return end
  if not (L.db and L.db.profile and L.db.profile.enabled) then return end

  local numItems = GetNumLootItems() or 0
  if L.db.profile.checkOnlySingleItemLoot and numItems > 1 then
    -- Optional: keep this guard as-is to minimize false positives from multi-loot bodies
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
        -- *** TYPO FIX IS HERE ***
        foundBy_player = UnitName("player"),
        foundBy_class  = select(2, UnitClass("player")),
        timestamp = time(),
        source    = "world_loot", -- mark explicit world loot
      }
      self:HandleLocalLoot(discovery)
    end
  end
end

-- Public: add a discovery (used by Comm/DBSync/network)
function Core:AddDiscovery(discoveryData, isNetworkDiscovery)
    if L:IsZoneIgnored() and isNetworkDiscovery then return end
    if not (L.db and L.db.global) then return end
    if type(discoveryData) ~= "table" then return end

    local itemID = discoveryData.itemID or extractItemID(discoveryData.itemLink)
    if not itemID then return end

    -- Normalize coords to 2 decimals before any processing
    local x = (discoveryData.coords and discoveryData.coords.x) or 0
    local y = (discoveryData.coords and discoveryData.coords.y) or 0
    x = round2(x)
    y = round2(y)
    discoveryData.coords = discoveryData.coords or {}
    discoveryData.coords.x = x
    discoveryData.coords.y = y

    local db = L.db.global.discoveries
    local existing = FindNearbyDiscovery(discoveryData.zoneID, itemID, x, y, db)

    if not existing then
        -- New discovery, not near any others
        local guid = buildGuid2(discoveryData.zoneID, itemID, x, y)
        discoveryData.guid = guid
        discoveryData.itemID = itemID
        discoveryData.lootedByMe = nil
        self:EnsureVerificationFields(discoveryData) -- sets mergeCount = 1
        db[guid] = discoveryData

        -- Only show a toast for new discoveries from the network.
        if isNetworkDiscovery then
            local toast = L:GetModule("Toast", true)
            if toast and toast.Show then
                toast:Show(discoveryData)
            end
        end

        -- Feedback only for local additions (avoid spam on network adds)
        if not isNetworkDiscovery then
            print(string.format("|cff00ff00[%s]:|r New discovery! %s in %s.", L.name, discoveryData.itemLink or "an item", discoveryData.zone or "Unknown"))
        end

        if WorldMapFrame and WorldMapFrame:IsShown() then
            local Map = L:GetModule("Map", true)
            if Map and Map.Update then
                Map:Update()
            end
        end
        return
    end

    -- Merge into existing
    self:EnsureVerificationFields(existing)

    -- Weighted average of coordinates for network updates
    local n = existing.mergeCount or 1
    existing.coords.x = (existing.coords.x * n + x) / (n + 1)
    existing.coords.y = (existing.coords.y * n + y) / (n + 1)
    existing.coords.x = round2(existing.coords.x)
    existing.coords.y = round2(existing.coords.y)
    existing.mergeCount = n + 1

    -- Merge timestamps and status
    local incomingTs = tonumber(discoveryData.statusTs) or tonumber(discoveryData.lastSeen) or tonumber(discoveryData.timestamp) or time()
    if incomingTs > (existing.statusTs or 0) and discoveryData.status then
        existing.status = discoveryData.status
        existing.statusTs = incomingTs
    end

    local incomingLastSeen = tonumber(discoveryData.lastSeen) or tonumber(discoveryData.timestamp) or time()
    if incomingLastSeen > (existing.lastSeen or 0) then
        existing.lastSeen = incomingLastSeen
    end

    if not existing.itemLink and discoveryData.itemLink then
        existing.itemLink = discoveryData.itemLink
        existing.itemID = existing.itemID or itemID
    end

    if WorldMapFrame and WorldMapFrame:IsShown() then
        local Map = L:GetModule("Map", true)
        if Map and Map.Update then
            Map:Update()
        end
    end
end

function Core:ClearDiscoveries()
    if not (L.db and L.db.global) then return end
    L.db.global.discoveries = {}
    print(string.format("[%s] Cleared all discoveries.", L.name))
    if WorldMapFrame and WorldMapFrame:IsShown() then
        local Map = L:GetModule("Map", true)
        if Map and Map.Update then
            Map:Update()
        end
    end
end

return Core
