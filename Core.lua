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
end

function Core:OnInitialize()
    if not (L.db and L.db.profile and L.db.global and L.db.char) then return end

    -- Ensure required containers exist
    L.db.global.discoveries = L.db.global.discoveries or {}
    L.db.char.looted = L.db.char.looted or {}
    L.db.char.hidden = L.db.char.hidden or {}

    -- Run migrations (includes promotion to global/overlays)
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
    local guid = buildGuid2(discovery.zoneID, itemID, x, y)
    local nowTs = time()

    local db = L.db.global.discoveries
    local existing = db[guid]

    if not existing then
        -- New canonical discovery
        discovery.guid = guid
        discovery.itemID = itemID
        discovery.timestamp = discovery.timestamp or nowTs
        discovery.lastSeen = nowTs
        discovery.status = STATUS_UNCONFIRMED
        discovery.statusTs = nowTs
        discovery.lootedByMe = nil
        self:EnsureVerificationFields(discovery)
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

    -- Update existing canonical record on local loot
    self:EnsureVerificationFields(existing)
    existing.lastSeen = nowTs
    -- Ensure the original finder is preserved, unless it was Unknown
    if not existing.foundBy_player or existing.foundBy_player == "Unknown" then
        existing.foundBy_player = UnitName("player")
    end

    -- Mark per-character completion
    L.db.char.looted[guid] = nowTs

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
            coords = { x = existing.coords and existing.coords.x or x, y = existing.coords and existing.coords.y or y },
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

    -- Normalize coords to 2 decimals before computing guid
    local x = (discoveryData.coords and discoveryData.coords.x) or 0
    local y = (discoveryData.coords and discoveryData.coords.y) or 0
    x = round2(x)
    y = round2(y)
    discoveryData.coords = discoveryData.coords or {}
    discoveryData.coords.x = x
    discoveryData.coords.y = y

    local guid = buildGuid2(discoveryData.zoneID, itemID, x, y)

    local db = L.db.global.discoveries
    if not db[guid] then
        discoveryData.guid = guid
        discoveryData.itemID = itemID
        discoveryData.lootedByMe = nil
        self:EnsureVerificationFields(discoveryData)
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
    local existing = db[guid]
    self:EnsureVerificationFields(existing)

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