local AceAddon     = LibStub("AceAddon-3.0")
local AceEvent     = LibStub("AceEvent-3.0")
local AceComm      = LibStub("AceComm-3.0")
local AceDB        = LibStub("AceDB-3.0")

local LootCollector = AceAddon:NewAddon("LootCollector", "AceEvent-3.0", "AceComm-3.0")
_G.LootCollector = LootCollector

BINDING_HEADER_LOOTCOLLECTOR = GetAddOnMetadata(..., "Title")
LootCollector.LEGACY_MODE_ACTIVE = true
LootCollector.addonPrefix = "BBLC25AM"
LootCollector.chatChannel = "BBLC25C"
LootCollector.DEBUG_MODE = false

LootCollector._profilerEnabled = true
LootCollector._profilerStats = {}
LootCollector._normalizedNameCache = {}

if type(C_Timer) == "table" and type(C_Timer.NewTicker) == "function" then
    C_Timer.NewTicker(86400, function()
        if LootCollector._profilerStats then
            wipe(LootCollector._profilerStats)
        end
    end)
end

function LootCollector:ProfileStart()
    if not self._profilerEnabled then return nil end
    return debugprofilestop()
end

function LootCollector:ProfileStop(funcName, startTime)
    if not startTime then return end
    local elapsed = debugprofilestop() - startTime
    
    local stats = self._profilerStats[funcName]
    if not stats then
        stats = { 
            calls = 0, total = 0, max = 0, min = 999999, 
            
            b3 = 0, b5 = 0, b10 = 0, b20 = 0, b50 = 0 
        }
        self._profilerStats[funcName] = stats
    end
    
    stats.calls = stats.calls + 1
    stats.total = stats.total + elapsed
    
    if elapsed > stats.max then stats.max = elapsed end
    if elapsed < stats.min then stats.min = elapsed end
    
    
    if elapsed >= 50.0 then
        stats.b50 = stats.b50 + 1
    elseif elapsed >= 20.0 then
        stats.b20 = stats.b20 + 1
    elseif elapsed >= 10.0 then
        stats.b10 = stats.b10 + 1
    elseif elapsed >= 5.0 then
        stats.b5 = stats.b5 + 1
    elseif elapsed >= 3.0 then
        stats.b3 = stats.b3 + 1
    end
end

LootCollector.ignoreList = {
    ["Embossed Mystic Scroll"] = true,
    ["Unimbued Mystic Scroll"] = true,
    ["Untapped Mystic Scroll"] = true,
    ["Felforged Mystic Scroll: Unlock Uncommon"] = true,
    ["Felforged Mystic Scroll: Unlock Rare"] = true,
    ["Felforged Mystic Scroll: Unlock Legendary"] = true,
    ["Felforged Mystic Scroll: Unlock Epic"] = true,
    ["Enigmatic Mystic Scroll"] = true,
    ["Friendly Sludgemonster"] = true,
    ["Worldforged Key Fragment"] = true,
    ["Worldforged Key"] = true,	
}

LootCollector.sourceSpecificIgnoreList = {
    ["Mystic Scroll: White Walker"] = true,
    ["Mystic Scroll: Powder Mage"] = true,
    ["Mystic Scroll: Midnight Flames"] = true,
    ["Mystic Scroll: Lucifur"] = true,
    ["Mystic Scroll: Knight of the Eclipse"] = true,
    ["Mystic Scroll: Hoplite"] = true,
    ["Mystic Scroll: Fire Watch"] = true,
    ["Mystic Scroll: Eskimo"] = true,
    ["Mystic Scroll: Dark Surgeon"] = true,
    ["Mystic Scroll: Cauterizing Fire"] = true,
    ["Mystic Scroll: Blood Venom"] = true,
    ["Mystic Scroll: Ancestral Ninja"] = true,
}

StaticPopupDialogs["LOOTCOLLECTOR_SHOW_DISCOVERY_REQUEST"] = {
    text = "|cffffff00%s|r wants to show you a discovery on the map for:\n%s",
    button1 = "Allow",
    button2 = "Ignore Session",
    button3 = "Block Permanently",
    OnAccept = function(self, data)
      if not data then return end
      
      local Core = LootCollector:GetModule("Core", true)
      local finalGuid = nil
      if Core and Core.AddDiscovery then
        finalGuid = Core:AddDiscovery(data, { isNetwork = false, op = "SHOW", suppressToast = true })
      end
      
      if finalGuid then
          local Map = LootCollector:GetModule("Map", true)
          if Map and Map.FocusOnDiscovery then
              Map:FocusOnDiscovery(finalGuid)
          end
      end
    end,
    OnCancel = function(self, data, reason)
        if reason == "clicked" and data and data.sender then
            LootCollector.sessionIgnoredShowRequests = LootCollector.sessionIgnoredShowRequests or {}
            LootCollector.sessionIgnoredShowRequests[data.sender] = true
            print(string.format("|cffff7f00LootCollector:|r Ignoring map show requests from %s for this session.", data.sender))
        end
    end,
    OnAlt = function(self, data)
      if not (data and data.sender) then return end
      local sender = data.sender
      if LootCollector.db and LootCollector.db.profile and LootCollector.db.profile.sharing then
        LootCollector.db.profile.sharing.blockList = LootCollector.db.profile.sharing.blockList or {}
        LootCollector.db.profile.sharing.blockList[sender] = true
        LootCollector.sessionIgnoredShowRequests = LootCollector.sessionIgnoredShowRequests or {}
        LootCollector.sessionIgnoredShowRequests[sender] = true
        print(string.format("|cffff0000LootCollector:|r Player |cffffff00%s|r has been added to your block list.", sender))
      end
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
  }

StaticPopupDialogs["LOOTCOLLECTOR_OPTIONAL_DB_UPDATE"] = {
  text = "LootCollector has detected a starter database (version %s).\n\n%s\n\nWould you like to merge it with your existing data?",
  button1 = "Yes, Merge",
  button2 = "No, Thanks",
  OnAccept = function(self, data)
    local dbData = _G.LootCollector_OptionalDB_Data
    if not (dbData and dbData.data) then return end
    local ImportExport = LootCollector:GetModule("ImportExport", true)
    if ImportExport and ImportExport.ApplyImportString then
        ImportExport:ApplyImportString(dbData.data, "MERGE", false)
    end
    if LootCollector.db and LootCollector.db.profile and data then
        LootCollector.db.profile.offeredOptionalDB = data
    end
  end,
  OnCancel = function(self, data, reason)
    if LootCollector.db and LootCollector.db.profile and data then
        LootCollector.db.profile.offeredOptionalDB = data
    end
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
}

local meCollectedCache = {}
local meCollectedCacheTime = {}
local ME_COLLECTED_CACHE_DURATION = 240

local dbDefaults = {
    profile = {
        enabled = true,
        paused = false,
        offeredOptionalDB = nil,
        minQuality = 2,
        favorites = {},
	    checkOnlySingleItemLoot = true,
	    enhancedWFTooltip = true,
        mapFilters = { 
            hideAll = false, 
            hideFaded = false, 
            hideStale = false, 
            hideLooted = false,
            hideUncached = false,
            hideUnconfirmed = false,
            hideLearnedTransmog = false,
            hideCollectedME = false,
		    hideBags = false,
	        hidePlayerNames = false,
            disableFadeEffect = false,
            pinSize = 17, 
            minimapPinSize = 14, 
            showZoneSummaries = false,
            showMapFilter = true,
            showMinimap = true,
            autoTrackNearest = false,
            maxMinimapDistance = 800,
            showMysticScrolls = true,
            showWorldforged = true,
            showVendors = true,
            minRarity = 0,
            usableByClasses = {},
            allowedEquipLoc = {},
			enableChatLinkIntegration = true,
        },
        toasts = { 
            enabled = true,            
            displayTime = 5.0,
            tickerEnabled = true,
            tickerSpeed = 90,
            tickerFontDelta = 3,
            tickerOutline = false,
            whiteFrame = true,
        },
        sharing = { 
            enabled = true, 
            anonymous = false, 
            delayed = false, 
            delaySeconds = 30, 
            pauseInHighRisk = false,
            allowShowRequests = true,
            rejectPartySync = false,
            rejectGuildSync = false,
            rejectWhisperSync = false,
            ackOnChannel = true,
            blockList = {},
            whiteList = {},
        },
	  viewer = {
        rowFont = "Fonts\\ARIALN.TTF",
        rowFontSize = 14,
        rowHeight = 28,
        uiFont = "Fonts\\ARIALN.TTF",
        uiFontSize = 13,
        useWCAGColoring = true,
        inlineVendorView = false,
        splitRatio = 0.64,
        asyncLoading = true,
        
        width = 1150,
        height = 674,
        point = "CENTER",
        x = 0,
        y = 0,
        scale = 1.0,
        },
        lastVersionToastAt = 0,
        ignoreZones = {},
        decay = { fadeAfterDays  = 30, staleAfterDays = 90, },
	    debugMode = false,
	    mdebugMode = false,
	    idebugMode = false,
	    cdebugMode = false,
	    vdebugMode = false,
        discoveries = {},
    },
    char = { looted = {}, hidden = {} },
    global = { 
        realms = {}, 
        cacheQueue = {},
        autoCleanupPhase = 0,
        manualCleanupRunCount = 0,
        purgeEmbossedState = 0,
    },
}

LootCollector.shadingModeActive = false

function LootCollector._debug(module, message)
    local debugMode = false
    if LootCollector.db and LootCollector.db.profile then
        debugMode = LootCollector.db.profile.debugMode
    elseif _G.LootCollectorDB_Asc and _G.LootCollectorDB_Asc.profiles and _G.LootCollectorDB_Asc.profiles.Default then
        debugMode = _G.LootCollectorDB_Asc.profiles.Default.debugMode
    end

    if debugMode then
        print(string.format("|cffffff00[LC-Debug|cffff8c00][%s]|r %s", tostring(module), tostring(message)))
    end
end

function LootCollector._mdebug(module, message)
    if LootCollector.db and LootCollector.db.profile and LootCollector.db.profile.mdebugMode then
        print(string.format("|cffffff00[LC-MapDebug|cffff8c00][%s]|r %s", tostring(module), tostring(message)))
    end
end

function LootCollector._idebug(module, message)
    if LootCollector.db and LootCollector.db.profile and LootCollector.db.profile.idebugMode then
        print(string.format("|cffffff00[LC-Debug|cffff8c00][%s]|r %s", tostring(module), tostring(message)))
    end
end

function LootCollector._ddebug(module, message)
    if LootCollector.DEBUG_MODE then
        print(string.format("|cffffff00[LC-DetectDebug|cffff8c00][%s]|r %s", tostring(module), tostring(message)))
    end
end

function LootCollector._cdebug(module, message)
    if LootCollector.db and LootCollector.db.profile and LootCollector.db.profile.cdebugMode then
        print(string.format("|cffffff00[LC-ChatDebug|cffff8c00][%s]|r %s", tostring(module), tostring(message)))
    end
end
    
LootCollector._normalizedNameCache = {}
function LootCollector:normalizeSenderName(sender)
    if type(sender) ~= "string" then return nil end
    
    local cached = self._normalizedNameCache[sender]
    if cached ~= nil then 
        return cached == false and nil or cached 
    end
    
    local name = sender:match("([^%-]+)") or sender
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    
    if name == "" then
        self._normalizedNameCache[sender] = false
        return nil
    end
    
    self._normalizedNameCache[sender] = name
    return name
end

function LootCollector:Round2(v)
    v = tonumber(v) or 0
    return math.floor(v * 100 + 0.5) / 100
end

function LootCollector:Round4(v)
    v = tonumber(v) or 0
    return math.floor(v * 10000 + 0.5) / 10000
end

function LootCollector:GenerateGUID(c, z, iz, i, x, y)
    local x4 = self:Round4(x or 0)
    local y4 = self:Round4(y or 0)
    return tostring(c or 0) .. "-" .. tostring(z or 0) .. "-" .. tostring(iz or 0) .. "-" .. tostring(i or 0) .. "-" .. string.format("%.4f", x4) .. "-" .. string.format("%.4f", y4)
end

function LootCollector:GenerateVendorGUID(vendorType, c, z, iz, x, y)
    local x4 = self:Round4(x or 0)
    local y4 = self:Round4(y or 0)
    return tostring(vendorType or "V") .. "-" .. tostring(c or 0) .. "-" .. tostring(z or 0) .. "-" .. tostring(iz or 0) .. "-" .. string.format("%.4f", x4) .. "-" .. string.format("%.4f", y4)
end

function LootCollector:ComputeDistance(c1, z1, x1, y1, c2, z2, x2, y2)
    local pTime = self.ProfileStart and self:ProfileStart() 

    c1 = tonumber(c1) or 0
    z1 = tonumber(z1) or 0
    x1 = tonumber(x1) or 0
    y1 = tonumber(y1) or 0
    
    c2 = tonumber(c2) or 0
    z2 = tonumber(z2) or 0
    x2 = tonumber(x2) or 0
    y2 = tonumber(y2) or 0
    
    if c1 ~= c2 then 
        if pTime then self:ProfileStop("LootCollector:ComputeDistance", pTime) end
        return nil 
    end 

    if z1 == z2 then
        local Map = self:GetModule("Map", true)
        local zoneData = Map and Map.WorldMapSize and Map.WorldMapSize[c1] and Map.WorldMapSize[c1][z1]
        if zoneData then
            local xDelta = (x2 - x1) * zoneData.width
            local yDelta = (y2 - y1) * zoneData.height
            local dist = math.sqrt(xDelta*xDelta + yDelta*yDelta)
            if pTime then self:ProfileStop("LootCollector:ComputeDistance", pTime) end
            return dist, xDelta, yDelta
        end
    end

    if C_WorldMap and type(C_WorldMap.GetWorldPosition) == "function" then
        local wx1, wy1 = C_WorldMap.GetWorldPosition(z1, x1, y1)
        local wx2, wy2 = C_WorldMap.GetWorldPosition(z2, x2, y2)
        if wx1 and wy1 and wx2 and wy2 then
            local xDelta = wx2 - wx1
            local yDelta = wy2 - wy1
            local dist = math.sqrt(xDelta*xDelta + yDelta*yDelta)
            if pTime then self:ProfileStop("LootCollector:ComputeDistance", pTime) end
            return dist, xDelta, yDelta
        end
    end
    
    local Map = self:GetModule("Map", true)
    if not (Map and Map.WorldMapSize) then 
        if pTime then self:ProfileStop("LootCollector:ComputeDistance", pTime) end
        return nil 
    end
    
    local function getContPosition(c, z, x, y)
        local zData = Map.WorldMapSize[c] and Map.WorldMapSize[c][z]
        if not zData then return nil, nil end
        return x * zData.width + zData.xOffset, y * zData.height + zData.yOffset
    end
    
    local cx1, cy1 = getContPosition(c1, z1, x1, y1)
    local cx2, cy2 = getContPosition(c2, z2, x2, y2)
    if not cx1 or not cx2 then 
        if pTime then self:ProfileStop("LootCollector:ComputeDistance", pTime) end
        return nil 
    end
    
    local xDelta = cx2 - cx1
    local yDelta = cy2 - cy1
    local dist = math.sqrt(xDelta*xDelta + yDelta*yDelta)
    
    if pTime then self:ProfileStop("LootCollector:ComputeDistance", pTime) end
    return dist, xDelta, yDelta
end

function LootCollector:GetActiveRealmKey()
    if self.realmNameCached then return self.realmNameCached end
    local realmName = nil
    if GetRealmName then
        realmName = GetRealmName()
    end
    if type(realmName) ~= "string" or realmName == "" then
        realmName = "Unknown Realm"
    end
    self.realmNameCached = realmName
    return realmName
end

function LootCollector:ActivateRealmBucket()
    if not (self.db and self.db.global) then return end

    local g = self.db.global
    local realmKey = self:GetActiveRealmKey()

    g.realms = g.realms or {}
    g.realms[realmKey] = g.realms[realmKey] or {}
    local bucket = g.realms[realmKey]

    bucket.discoveries = bucket.discoveries or {}
    bucket.blackmarketVendors = bucket.blackmarketVendors or {}

    if g.discoveries and type(g.discoveries) == "table" then
        if g.discoveries ~= bucket.discoveries then
            local count = 0
            for k, v in pairs(g.discoveries) do
                if not bucket.discoveries[k] then
                    bucket.discoveries[k] = v
                    count = count + 1
                end
            end
            if count > 0 then
                print(string.format("|cff00ff00LootCollector:|r Migrated %d legacy global discoveries to realm bucket: %s", count, realmKey))
            end
        end
        g.discoveries = nil
    end

    if g.blackmarketVendors and type(g.blackmarketVendors) == "table" then
        if g.blackmarketVendors ~= bucket.blackmarketVendors then
             local count = 0
            for k, v in pairs(g.blackmarketVendors) do
                if not bucket.blackmarketVendors[k] then
                    bucket.blackmarketVendors[k] = v
                    count = count + 1
                end
            end
            if count > 0 then
                print(string.format("|cff00ff00LootCollector:|r Migrated %d legacy global vendors to realm bucket: %s", count, realmKey))
            end
        end
        g.blackmarketVendors = nil
    end

    self.activeRealmKey = realmKey
end

function LootCollector:GetDiscoveriesDB()
    if not self.db or not self.db.global then return nil end
    if not self.activeRealmKey then self:ActivateRealmBucket() end
    if self.db.global.realms and self.db.global.realms[self.activeRealmKey] then
        return self.db.global.realms[self.activeRealmKey].discoveries
    end
    return nil
end

function LootCollector:GetVendorsDB()
    if not self.db or not self.db.global then return nil end
    if not self.activeRealmKey then self:ActivateRealmBucket() end
    if self.db.global.realms and self.db.global.realms[self.activeRealmKey] then
        return self.db.global.realms[self.activeRealmKey].blackmarketVendors
    end
    return nil
end

function LootCollector:ScheduleAfter(seconds, func)
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
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

function LootCollector:BuildAreaIDToZoneIndex()
  if self.AIDToIndex then return end
  self._debug("Map", "Building AreaID-to-ZoneIndex translation table...")
  self.AIDToIndex = {}
local Map = self:GetModule("Map", true)
  if not Map then return end
  for c, continentData in pairs(Map.WorldMapSize) do
    if type(c) == "number" and c > 0 then
      self.AIDToIndex[c] = {}
      local zonesOnContinent = { GetMapZones(c) } 
      local nameToIndex = {}
      for i, name in ipairs(zonesOnContinent) do
        nameToIndex[name] = i
      end
      
      for areaID, zoneInfo in pairs(continentData) do
        local zoneName = zoneInfo.name
        local zoneIndex = nameToIndex[zoneName]
        if zoneIndex then
          self.AIDToIndex[c][areaID] = zoneIndex
          self._debug("Map", string.format("  -> Mapped [c=%d, areaID=%d, name=%s] to zoneIndex %d", c, areaID, zoneName, zoneIndex))
        end
      end
    end
  end
end

function LootCollector:AreaIDToZoneIndex(continent, areaID)
  self._debug("Map:AreaIDToZoneIndex - processing", string.format("[c=%d, areaID=%d]", tonumber(continent), tonumber(areaID)))
  if not continent or not areaID then return areaID end
  if not self.AIDToIndex then self:BuildAreaIDToZoneIndex() end
  
  continent = tonumber(continent)
  areaID = tonumber(areaID)
  
  local byCont = self.AIDToIndex and self.AIDToIndex[continent]
  local zoneIndex = byCont and byCont[areaID]
  
  if zoneIndex then
    self._debug("Map", string.format("Translated [c=%d, areaID=%d] -> zoneIndex %d", continent, areaID, zoneIndex))
    return zoneIndex
  end

  self._debug("Map", string.format("Translation FAILED for [c=%d, areaID=%d]. Falling back to areaID.", continent, areaID))
  return areaID
end

function LootCollector.ResolveZoneDisplay(continent, zoneID, iz)
    local ZoneList = LootCollector:GetModule("ZoneList", true)
    local mapID = tonumber(zoneID) or 0 
    if ZoneList and ZoneList.MapDataByID and ZoneList.MapDataByID[mapID] then
        return ZoneList.MapDataByID[mapID].name
    end
    return (GetRealZoneText and GetRealZoneText()) or "Unknown Zone"
end

local STATUS_FADING = "FADING"
local STATUS_STALE = "STALE"
local STATUS_UNCONFIRMED = "UNCONFIRMED"

function LootCollector:GetFilters()
    local c = self.db and self.db.char
    local p = self.db and self.db.profile
    local f = (c and c.mapFilters) or {}
    local ui = (p and p.mapFilters) or {}
    
    
    local combined = {}
    
    
    combined.hideAll = f.hideAll or false
    combined.hideFaded = f.hideFaded or false
    combined.hideStale = f.hideStale or false
    combined.hideLooted = f.hideLooted or false
    combined.hideUnconfirmed = f.hideUnconfirmed or false
    combined.hideUncached = f.hideUncached or false
    combined.hideLearnedTransmog = f.hideLearnedTransmog or false
    combined.hideCollectedME = f.hideCollectedME or false
    combined.hideBags = f.hideBags or false
    combined.minRarity = f.minRarity or 0
    combined.allowedEquipLoc = f.allowedEquipLoc or {}
    combined.usableByClasses = f.usableByClasses or {}
    combined.showMysticScrolls = f.showMysticScrolls ~= false
    combined.showWorldforged = f.showWorldforged ~= false
    combined.showVendors = f.showVendors ~= false
    combined.autoTrackNearest = f.autoTrackNearest or false

    
    combined.showMinimap = ui.showMinimap ~= false
    combined.maxMinimapDistance = ui.maxMinimapDistance or 800
    combined.pinSize = ui.pinSize or 16
    combined.minimapPinSize = ui.minimapPinSize or 10
    combined.disableFadeEffect = ui.disableFadeEffect or false
    combined.showZoneSummaries = ui.showZoneSummaries or false
    combined.hideSearchBar = ui.hideSearchBar or false
    combined.disableProximityList = ui.disableProximityList or false
	combined.enableChatLinkIntegration = ui.enableChatLinkIntegration ~= false
    
    return combined
end

function LootCollector:GetDiscoveryStatus(d)
    local s = (d and d.s) or STATUS_UNCONFIRMED
    if s == STATUS_FADING or s == STATUS_STALE or s == "CONFIRMED" or s == STATUS_UNCONFIRMED then
        return s
    end
    return STATUS_UNCONFIRMED
end

function LootCollector:IsLootedByChar(guid)
    if not (self.db and self.db.char and self.db.char.looted) then return false end
    return self.db.char.looted[guid] and true or false
end

local appearanceCache = {}
local appearanceCacheTime = {}
local APPEARANCE_CACHE_DURATION = 300

function LootCollector:IsMysticEnchantCollected(itemID)
    if not itemID or itemID == 0 then return false end

    
    local nowTime = GetTime()
    if meCollectedCacheTime[itemID] and (nowTime - meCollectedCacheTime[itemID]) < ME_COLLECTED_CACHE_DURATION then
        return meCollectedCache[itemID]
    end

    local isCollected = false
    if C_MysticEnchant and C_MysticEnchant.IsCollected then
        local ok, result = pcall(C_MysticEnchant.IsCollected, itemID)
        if ok and result then
            isCollected = true
        end
    end

    if not isCollected then
        local Scanner = self:GetModule("Scanner", true)
        if Scanner then
            local itemData = Scanner:GetItemData(itemID)
            if itemData and itemData.isCollected then
                isCollected = true
            end
        end
    end

    meCollectedCache[itemID] = isCollected
    meCollectedCacheTime[itemID] = nowTime

    return isCollected
end

function LootCollector:IsAppearanceCollected(itemID)
    if not itemID or itemID == 0 then return false end
    if not C_Appearance or not C_AppearanceCollection then return false end
    
    local now = GetTime()
    if appearanceCacheTime[itemID] and (now - appearanceCacheTime[itemID]) < APPEARANCE_CACHE_DURATION then
        return appearanceCache[itemID]
    end
    
    local isCollected = false
    local appearanceID = C_Appearance.GetItemAppearanceID(itemID)
    if appearanceID then
        isCollected = C_AppearanceCollection.IsAppearanceCollected(appearanceID) or false
    end
    
    appearanceCache[itemID] = isCollected
    appearanceCacheTime[itemID] = now
    
    return isCollected
end

function LootCollector:DiscoveryPassesFilters(d)
    local Constants = self:GetModule("Constants", true)
    local f = self:GetFilters()
    if not d or f.hideAll then return false end

    local s = self:GetDiscoveryStatus(d)
    if (s == STATUS_UNCONFIRMED and f.hideUnconfirmed) or
       (s == STATUS_FADING and f.hideFaded) or
       (s == STATUS_STALE and f.hideStale) or
       (f.hideLooted and d.g and self:IsLootedByChar(d.g)) then
        return false
    end

    if f.hideLearnedTransmog and d.i and d.i > 0 and self:IsAppearanceCollected(d.i) then
        return false
    end

    if f.hideCollectedME and Constants and d.dt == Constants.DISCOVERY_TYPE.MYSTIC_SCROLL and d.i and d.i > 0 and self:IsMysticEnchantCollected(d.i) then
        return false
    end
	
	if f.hideBags and d.it == 2 then
        return false
    end

    local quality = d.q or 0
    if quality < (f.minRarity or 0) then return false end

    if not Constants then return true end

    local dt = d.dt or Constants.DISCOVERY_TYPE.UNKNOWN
    if dt == Constants.DISCOVERY_TYPE.MYSTIC_SCROLL and not f.showMysticScrolls then return false end
    if dt == Constants.DISCOVERY_TYPE.WORLDFORGED  and not f.showWorldforged  then return false end

    if next(f.usableByClasses) then
        local canBeUsed = false
        local isMysticScroll = (d.dt == Constants.DISCOVERY_TYPE.MYSTIC_SCROLL)
        if isMysticScroll then
            local itemClassToken = (d.cl and d.cl ~= "cl") and Constants.CLASS_ABBREVIATIONS_REVERSE and Constants.CLASS_ABBREVIATIONS_REVERSE[d.cl]
            if itemClassToken and f.usableByClasses[itemClassToken] then
                canBeUsed = true
            end
        else 
            local itemType = d.it
            local itemSubType = d.ist
            local isProficiencyArmor = Constants.PROFICIENCY_ARMOR_ISTS and Constants.PROFICIENCY_ARMOR_ISTS[itemSubType]
            local isWeapon = (itemType == Constants.ITEM_TYPE_TO_ID["Weapon"])
            
            if isProficiencyArmor or isWeapon then
                if not Constants.CLASS_PROFICIENCIES then return true end
                for classToken, _ in pairs(f.usableByClasses) do
                    local proficiencies = Constants.CLASS_PROFICIENCIES[classToken]
                    if proficiencies then
                        local listToSearch = isProficiencyArmor and proficiencies.armor or proficiencies.weapons
                        if listToSearch then
                            for _, allowed_ist in ipairs(listToSearch) do
                                if itemSubType == allowed_ist then
                                    canBeUsed = true
                                    break
                                end
                            end
                        end
                    end
                    if canBeUsed then break end
                end
            else
                canBeUsed = true
            end
        end
        if not canBeUsed then return false end
    end

    if next(f.allowedEquipLoc) then
        local equipLoc = nil
        local _, _, _, _, _, _, _, _, cachedEquipLoc = GetItemInfo(d.il or d.i or 0)
        if cachedEquipLoc and cachedEquipLoc ~= "" then
            equipLoc = cachedEquipLoc
        else
            if d.ist and d.ist > 0 and Constants.IST_TO_EQUIPLOC and Constants.IST_TO_EQUIPLOC[d.ist] then
                equipLoc = Constants.IST_TO_EQUIPLOC[d.ist]
            end
        end
        
        if equipLoc and not f.allowedEquipLoc[equipLoc] then
            return false
        elseif not equipLoc then
            return false
        end
    end

    return true
end

StaticPopupDialogs["LOOTCOLLECTOR_MIGRATION_RELOAD"] = {
  text = "LootCollector has successfully upgraded your database.\n\nA UI reload is required to save these changes.\n\nThis is a one-time process.",
  button1 = "Reload Now",
  OnAccept = function()
    ReloadUI()
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 0, 
  exclusive = 1,
  showAlert = true,
}

function LootCollector:PreInitializeMigration()
    if not (_G.LootCollectorDB_Asc and type(_G.LootCollectorDB_Asc) == "table") then
        self.LEGACY_MODE_ACTIVE = false 
        return
    end

    local rawDB = _G.LootCollectorDB_Asc
    local currentSchema = rawDB._schemaVersion or 0

    if currentSchema >= 8 then
        self.LEGACY_MODE_ACTIVE = false 
        return
    end
    
    self.MIGRATION_JUST_HAPPENED = true

    local cityZoneIDsToPurge = {[1]={[382]=true,[322]=true,[363]=true,[1204]=true},[2]={[342]=true,[302]=true,[383]=true},[3]={[482]=true},[4]={[505]=true}}
    local Constants = self:GetModule("Constants", true)
    local HASH_SAP = (Constants and Constants.HASH_SAP) or "LC@Asc.BB25"
    local HASH_SEED = (Constants and Constants.HASH_SEED) or 2025
    local cHASH_BLACKLIST = (Constants and Constants.cHASH_BLACKLIST) or {}
    local AcceptedLootSrcMS = Constants and Constants.AcceptedLootSrcMS

    local function _isFinderOnBlacklist(name)
        if not name or name == "" or not _G.XXH_Lua_Lib then return false end
        local normalizedName = (string.match(name, "([^%-]+)") or name):gsub("^%s+", ""):gsub("%s+$", "")
        if not normalizedName or normalizedName == "" then return false end
        local combined_str = normalizedName .. HASH_SAP
        local hash_val = _G.XXH_Lua_Lib.XXH32(combined_str, HASH_SEED)
        local hex_hash = string.format("%08x", hash_val)
        return cHASH_BLACKLIST[hex_hash] == true
    end

    local function PurgeByFinderBlacklist(discoveries)
        if not discoveries then return 0 end
        local guidsToRemove = {}
        for guid, d in pairs(discoveries) do
            if d and d.fp and _isFinderOnBlacklist(d.fp) then table.insert(guidsToRemove, guid) end
        end
        for _, guid in ipairs(guidsToRemove) do discoveries[guid] = nil end
        return #guidsToRemove
    end
    
    local function PurgeByCityZones(discoveries)
        if not discoveries then return 0 end
        local guidsToRemove = {}
        for guid, d in pairs(discoveries) do
            if d and d.c and d.z and cityZoneIDsToPurge[tonumber(d.c)] and cityZoneIDsToPurge[tonumber(d.c)][tonumber(d.z)] then
                table.insert(guidsToRemove, guid)
            end
        end
        for _, guid in ipairs(guidsToRemove) do discoveries[guid] = nil end
        return #guidsToRemove
    end

    local function PurgeZeroCoordDiscoveries(discoveries)
        if not discoveries then return 0 end
        local guidsToRemove = {}
        for guid, d in pairs(discoveries) do
            if d and d.xy and tonumber(d.xy.x) == 0 and tonumber(d.xy.y) == 0 then
                table.insert(guidsToRemove, guid)
            end
        end
        for _, guid in ipairs(guidsToRemove) do discoveries[guid] = nil end
        return #guidsToRemove
    end

    local function GenerateLegacyGUID(c, mapID, i, x, y)
        local x2 = math.floor((tonumber(x) or 0) * 100 + 0.5) / 100
        local y2 = math.floor((tonumber(y) or 0) * 100 + 0.5) / 100
        return tostring(c or 0) .. "-" .. tostring(mapID or 0) .. "-" .. tostring(i or 0) .. "-" .. string.format("%.2f", x2) .. "-" .. string.format("%.2f", y2)
    end

    
    
    
    if currentSchema < 7 then
        local LegacyZoneData = {[1]={[1]="Ammen Vale",[2]="Ashenvale",[3]="Azshara",[4]="Azuremyst Isle",[5]="Ban'ethil Barrow Den",[6]="Bloodmyst Isle",[7]="Burning Blade Coven",[8]="Caverns of Time",[9]="Darkshore",[10]="Darnassus",[11]="Desolace",[12]="Durotar",[13]="Dustwallow Marsh",[14]="Dustwind Cave",[15]="Fel Rock",[16]="Felwood",[17]="Feralas",[18]="Maraudon",[19]="Moonglade",[20]="Moonlit Ossuary",[21]="Mulgore",[22]="Orgrimmar",[23]="Palemane Rock",[24]="Camp Narache",[25]="Shadowglen",[26]="Shadowthread Cave",[27]="Silithus",[28]="Sinister Lair",[29]="Skull Rock",[30]="Stillpine Hold",[31]="Stonetalon Mountains",[32]="Tanaris",[33]="Teldrassil",[34]="The Barrens",[35]="The Exodar",[36]="The Gaping Chasm",[37]="The Noxious Lair",[38]="The Slithering Scar",[39]="The Venture Co. Mine",[40]="Thousand Needles",[41]="Thunder Bluff",[42]="Tides' Hollow",[43]="Twilight's Run",[44]="Un'Goro Crater",[45]="Valley of Trials",[46]="Wailing Caverns",[47]="Winterspring"},[2]={[1]="Alterac Mountains",[2]="Amani Catacombs",[3]="Arathi Highlands",[4]="Badlands",[5]="Blackrock Mountain",[6]="Blasted Lands",[7]="Burning Steppes",[8]="Coldridge Pass",[9]="Coldridge Valley",[10]="Deadwind Pass",[11]="Deathknell",[12]="Dun Morogh",[13]="Duskwood",[14]="Eastern Plaguelands",[15]="Echo Ridge Mine",[16]="Elwynn Forest",[17]="Eversong Woods",[18]="Fargodeep Mine",[19]="Ghostlands",[20]="Gol'Bolar Quarry",[21]="Gold Coast Quarry",[22]="Hillsbrad Foothills",[23]="Ironforge",[24]="Isle of Quel'Danas",[25]="Jangolode Mine",[26]="Jasperlode Mine",[27]="Loch Modan",[28]="Night Web's Hollow",[29]="Northshire Valley",[30]="Redridge Mountains",[31]="Scarlet Monastery",[32]="Searing Gorge",[33]="Secret Inquisitorial Dungeon",[34]="Shadewell Spring",[35]="Silvermoon City",[36]="Silverpine Forest",[37]="Stormwind City",[38]="Stranglethorn Vale",[39]="Sunstrider Isle",[40]="Swamp of Sorrows",[41]="The Deadmines",[42]="The Grizzled Den",[43]="The Hinterlands",[44]="Tirisfal Glades",[45]="Uldaman",[46]="Undercity",[47]="Western Plaguelands",[48]="Westfall",[49]="Wetlands"}}
        local LegacyInstanceData = {[1]="Ragefire Chasm",[2]="Wailing Caverns",[3]="The Deadmines",[4]="Shadowfang Keep",[5]="The Stockade",[6]="Blackfathom Deeps",[7]="Gnomeregan",[8]="Razorfen Kraul",[9]="Scarlet Monastery",[10]="Razorfen Downs",[11]="Uldaman",[12]="Zul'Farrak",[13]="Maraudon",[14]="The Temple of Atal'hakkar",[15]="Blackrock Depths",[16]="Dire Maul",[17]="Lower Blackrock Spire",[18]="Upper Blackrock Spire",[19]="Scholomance",[20]="Stratholme",[21]="Molten Core",[22]="Onyxia's Lair",[23]="Blackwing Lair",[24]="Zul'Gurub",[25]="Ruins of Ahn'Qiraj",[26]="Temple of Ahn'Qiraj"}
        local NewMapDataByID = {[5]={name="Durotar"},[10]={name="Mulgore"},[12]={name="The Barrens"},[16]={name="Alterac Mountains"},[17]={name="Arathi Highlands"},[18]={name="Badlands"},[20]={name="Blasted Lands"},[21]={name="Tirisfal Glades"},[22]={name="Silverpine Forest"},[23]={name="Western Plaguelands"},[24]={name="Eastern Plaguelands"},[25]={name="Hillsbrad Foothills"},[27]={name="The Hinterlands"},[28]={name="Dun Morogh"},[29]={name="Searing Gorge"},[30]={name="Burning Steppes"},[31]={name="Elwynn Forest"},[33]={name="Deadwind Pass"},[35]={name="Duskwood"},[36]={name="Loch Modan"},[37]={name="Redridge Mountains"},[38]={name="Stranglethorn Vale"},[39]={name="Swamp of Sorrows"},[40]={name="Westfall"},[41]={name="Wetlands"},[42]={name="Teldrassil"},[43]={name="Darkshore"},[44]={name="Ashenvale"},[62]={name="Thousand Needles"},[82]={name="Stonetalon Mountains"},[102]={name="Desolace"},[122]={name="Feralas"},[142]={name="Dustwallow Marsh"},[162]={name="Tanaris"},[182]={name="Azshara"},[183]={name="Felwood"},[202]={name="Un'Goro Crater"},[242]={name="Moonglade"},[262]={name="Silithus"},[282]={name="Winterspring"},[302]={name="Stormwind City"},[322]={name="Orgrimmar"},[342]={name="Ironforge"},[363]={name="Thunder Bluff"},[382]={name="Darnassus"},[383]={name="Undercity"},[463]={name="Eversong Woods"},[464]={name="Ghostlands"},[465]={name="Azuremyst Isle"},[472]={name="The Exodar"},[477]={name="Bloodmyst Isle"},[481]={name="Silvermoon City"},[681]={name="Ragefire Chasm"},[687]={name="Zul'Farrak"},[689]={name="Blackfathom Deeps"},[691]={name="The Stockade"},[692]={name="Gnomeregan"},[693]={name="Uldaman"},[697]={name="Molten Core"},[698]={name="Zul'Gurub"},[700]={name="Dire Maul"},[705]={name="Blackrock Depths"},[718]={name="Ruins of Ahn'Qiraj"},[719]={name="Onyxia's Lair"},[722]={name="Blackrock Spire",altName="Lower Blackrock Spire",altName2="Upper Blackrock Spire"},[750]={name="Wailing Caverns"},[751]={name="Maraudon"},[756]={name="Blackwing Lair"},[757]={name="The Deadmines"},[761]={name="Razorfen Downs"},[762]={name="Razorfen Kraul"},[763]={name="Scarlet Monastery"},[764]={name="Scholomance"},[765]={name="Shadowfang Keep"},[766]={name="Stratholme"},[767]={name="Temple of Ahn'Qiraj"},[2022]={name="The Temple of Atal'hakkar"},[1244]={name="Valley of Trials"},[1238]={name="Northshire Valley"},[1243]={name="Shadowglen"},[1239]={name="Coldridge Valley"},[1245]={name="Camp Narache"},[1242]={name="Ammen Vale"},[1241]={name="Sunstrider Isle"},[1240]={name="Deathknell"},[1204]={name="Caverns of Time"},[1205]={name="Blackrock Mountain"},[1211]={name="Stillpine Hold"},[1212]={name="Tides' Hollow"},[1213]={name="Night Web's Hollow"},[1214]={name="Gol'Bolar Quarry"},[1215]={name="Coldridge Pass"},[1216]={name="The Grizzled Den"},[1217]={name="Burning Blade Coven"},[1218]={name="Dustwind Cave"},[1219]={name="Skull Rock"},[1220]={name="Fargodeep Mine"},[1222]={name="Jasperlode Mine"},[1223]={name="Amani Catacombs"},[1224]={name="Palemane Rock"},[1225]={name="The Venture Co. Mine"},[1226]={name="Echo Ridge Mine"},[1227]={name="Twilight's Run"},[1228]={name="The Noxious Lair"},[1229]={name="The Gaping Chasm"},[1230]={name="Ban'ethil Barrow Den"},[1232]={name="Fel Rock"},[1233]={name="Shadowthread Cave"},[1234]={name="The Slithering Scar"},[1236]={name="Gold Coast Quarry"},[1237]={name="Jangolode Mine"},[2028]={name="Shadewell Spring"},[2029]={name="Secret Inquisitorial Dungeon"},[2030]={name="Sinister Lair"},[2031]={name="Moonlit Ossuary"}}

        local nameToNewMapID = {}
        for mapID, data in pairs(NewMapDataByID) do
            if data and data.name then nameToNewMapID[data.name] = mapID end
            if data and data.altName then nameToNewMapID[data.altName] = mapID end
            if data and data.altName2 then nameToNewMapID[data.altName2] = mapID end
        end
        
        local OldToNewZoneMap = {
            ["1:2"]={c=1,z=44}, ["1:3"]={c=1,z=182}, ["1:4"]={c=1,z=465}, ["1:6"]={c=1,z=477}, ["1:9"]={c=1,z=43}, ["1:11"]={c=1,z=102}, ["1:12"]={c=1,z=5}, ["1:13"]={c=1,z=142}, ["1:16"]={c=1,z=183}, ["1:17"]={c=1,z=122}, ["1:19"]={c=1,z=242}, ["1:21"]={c=1,z=10}, ["1:27"]={c=1,z=262}, ["1:31"]={c=1,z=82}, ["1:32"]={c=1,z=162}, ["1:33"]={c=1,z=42}, ["1:34"]={c=1,z=12}, ["1:40"]={c=1,z=62}, ["1:44"]={c=1,z=202}, ["1:47"]={c=1,z=282},
            ["1:1"]={c=1,z=1242}, ["1:10"]={c=1,z=382}, ["1:22"]={c=1,z=322}, ["1:24"]={c=1,z=1245}, ["1:25"]={c=1,z=1243}, ["1:35"]={c=1,z=472}, ["1:41"]={c=1,z=363}, ["1:45"]={c=1,z=1244},
            ["1:8"]={c=1,z=1204}, ["1:18"]={c=1,z=751}, ["1:46"]={c=1,z=750}, 
            ["2:1"]={c=2,z=16}, ["2:3"]={c=2,z=17}, ["2:4"]={c=2,z=18}, ["2:5"]={c=2,z=1205}, ["2:6"]={c=2,z=20}, ["2:7"]={c=2,z=30}, ["2:10"]={c=2,z=33}, ["2:12"]={c=2,z=28}, ["2:13"]={c=2,z=35}, ["2:14"]={c=2,z=24}, ["2:16"]={c=2,z=31}, ["2:17"]={c=2,z=463}, ["2:19"]={c=2,z=464}, ["2:22"]={c=2,z=25}, ["2:27"]={c=2,z=36}, ["2:30"]={c=2,z=37}, ["2:32"]={c=2,z=29}, ["2:36"]={c=2,z=22}, ["2:38"]={c=2,z=38}, ["2:40"]={c=2,z=39}, ["2:43"]={c=2,z=27}, ["2:44"]={c=2,z=21}, ["2:47"]={c=2,z=23}, ["2:48"]={c=2,z=40}, ["2:49"]={c=2,z=41},
            ["2:9"]={c=2,z=1239}, ["2:11"]={c=2,z=1240}, ["2:23"]={c=2,z=342}, ["2:29"]={c=2,z=1238}, ["2:35"]={c=2,z=481}, ["2:37"]={c=2,z=302}, ["2:39"]={c=2,z=1241}, ["2:46"]={c=2,z=383},
            ["2:24"]={c=2,z=799}, ["2:31"]={c=2,z=763}, ["2:41"]={c=2,z=757}, ["2:45"]={c=2,z=693}, 
            ["3:1"]={c=3,z=476}, ["3:2"]={c=3,z=466}, ["3:3"]={c=3,z=478}, ["3:4"]={c=3,z=480}, ["3:5"]={c=3,z=474}, ["3:6"]={c=3,z=482}, ["3:7"]={c=3,z=479}, ["3:8"]={c=3,z=468},
            ["4:1"]={c=4,z=487}, ["4:2"]={c=4,z=511}, ["4:3"]={c=4,z=505}, ["4:4"]={c=4,z=489}, ["4:5"]={c=4,z=491}, ["4:6"]={c=4,z=492}, ["4:7"]={c=4,z=542}, ["4:8"]={c=4,z=493}, ["4:9"]={c=4,z=494}, ["4:10"]={c=4,z=496}, ["4:11"]={c=4,z=502}, ["4:12"]={c=4,z=497},
        }

        local discoveries = rawDB.global and rawDB.global.discoveries
        if discoveries then
            print("|cff00ff00LootCollector:|r Performing pre-migration database cleanup...")
            local restrictedRemoved = PurgeByFinderBlacklist(discoveries)
            local cityRemoved = PurgeByCityZones(discoveries)
            local zeroRemoved = PurgeZeroCoordDiscoveries(discoveries)
            print(string.format("|cff00ff00LootCollector:|r Cleanup removed %d blacklisted data, %d city, and %d zero-coord entries.", restrictedRemoved, cityRemoved, zeroRemoved))
        end

        print("|cff00ff00LootCollector:|r Database version " .. tostring(currentSchema) .. " detected. Beginning automatic upgrade to v7...")
        local discoveriesConverted, vendorsConverted, lootedConverted = 0, 0, 0
        local locale = GetLocale()
        local isEnglishClient = (locale == "enUS" or locale == "enGB")
        local playerName = self:normalizeSenderName(UnitName("player"))

        if isEnglishClient then       
            rawDB.global = rawDB.global or {}
            local finalDiscoveries = {}
            local finalVendors = {}
            local discardedCount = 0

            for oldGuid, d in pairs(rawDB.global.discoveries or {}) do            
                 if self:normalizeSenderName(d.fp) == playerName then
                    local c, z, i, x, y = oldGuid:match("^(%d+)%-(%d+)%-(%d+)%-([%-%d%.]+)%-([%-%d%.]+)$")
                    local oldC, oldZ = tonumber(d.c or c), tonumber(d.z or z)
                    
                    local newMapInfo = nil
                    if oldC and oldZ then
                         local key = oldC .. ":" .. oldZ
                         newMapInfo = OldToNewZoneMap[key]
                    end

                    if newMapInfo then
                         local newGuid = GenerateLegacyGUID(newMapInfo.c, newMapInfo.z, i, x, y)
                         d.g, d.c, d.z, d.iz = newGuid, newMapInfo.c, newMapInfo.z, 0 
                         finalDiscoveries[newGuid] = d
                         discoveriesConverted = discoveriesConverted + 1                     
                    else
                        local zoneName = (oldC and oldZ and LegacyZoneData[oldC] and LegacyZoneData[oldC][oldZ])
                        local instanceName = (d.iz and tonumber(d.iz) > 0) and LegacyInstanceData[tonumber(d.iz)]
                        local finalName = zoneName or instanceName
                        local isInstance = not zoneName and instanceName
                        
                        if finalName then
                            local isMysticScroll = (d.il and string.find(d.il, "Mystic Scroll"))
                            local passesSrcCheck = true
                            if isMysticScroll then
                                if not AcceptedLootSrcMS or not d.src or not AcceptedLootSrcMS[d.src] then
                                    passesSrcCheck = false
                                end
                            end

                            if passesSrcCheck then
                                local newMapID = nameToNewMapID[finalName]
                                if newMapID then
                                    local newGuid = GenerateLegacyGUID(oldC, newMapID, i, x, y)
                                    d.g, d.c, d.z, d.iz = newGuid, oldC, newMapID, isInstance and newMapID or 0
                                    finalDiscoveries[newGuid] = d
                                    discoveriesConverted = discoveriesConverted + 1
                                else
                                    discardedCount = discardedCount + 1
                                end
                            else
                                discardedCount = discardedCount + 1
                            end
                        else
                            discardedCount = discardedCount + 1
                        end
                    end
                 end
            end

            for oldGuid, d in pairs(rawDB.global.blackmarketVendors or {}) do            
                 if self:normalizeSenderName(d.fp) == playerName then
                    local prefix, c, z, x, y = oldGuid:match("^(%a+)%-(%d+)%-(%d+)%-([%-%d%.]+)%-([%-%d%.]+)$")
                    if prefix then
                        local oldC, oldZ = tonumber(c), tonumber(d.z or z)
                        
                        local newMapInfo = nil
                        if oldC and oldZ then
                            local key = oldC .. ":" .. oldZ
                            newMapInfo = OldToNewZoneMap[key]
                        end

                        if newMapInfo then
                            local newGuid = prefix .. "-" .. newMapInfo.c .. "-" .. newMapInfo.z .. "-" .. x .. "-" .. y
                            d.g, d.c, d.z = newGuid, newMapInfo.c, newMapInfo.z
                            finalVendors[newGuid] = d
                            vendorsConverted = vendorsConverted + 1
                        else
                            local zoneName = (oldC and oldZ and LegacyZoneData[oldC] and LegacyZoneData[oldC][oldZ])
                            if zoneName then
                                local newMapID = nameToNewMapID[zoneName]
                                if newMapID then
                                    local newGuid = prefix .. "-" .. oldC .. "-" .. newMapID .. "-" .. x .. "-" .. y
                                    d.g, d.c, d.z = newGuid, oldC, newMapID
                                    finalVendors[newGuid] = d
                                    vendorsConverted = vendorsConverted + 1
                                else
                                   discardedCount = discardedCount + 1
                                end
                            else
                                discardedCount = discardedCount + 1
                            end
                        end
                    end
                 end
            end
            
            rawDB.global.discoveries = finalDiscoveries
            rawDB.global.blackmarketVendors = finalVendors
            if discardedCount > 0 then
                print(string.format("|cffff7f00LootCollector:|r Discarded %d of your own unmappable old records during migration.", discardedCount))
            end

        else       
            rawDB.global = rawDB.global or {}
            rawDB.global.discoveries = {}
            rawDB.global.blackmarketVendors = {}
        end

        if _G.LootCollector_OptionalDB_Data and _G.LootCollector_OptionalDB_Data.data then
            local dataStr = _G.LootCollector_OptionalDB_Data.data
            local success, deserialized = pcall(function()
                return LibStub("AceSerializer-3.0"):Deserialize(LibStub("LibDeflate"):DecompressDeflate(LibStub("LibDeflate"):DecodeForPrint(dataStr:match("^!LC1!(.+)$"))))
            end)

            if success and type(deserialized) == "table" then
                local starterDiscoveries = deserialized.discoveries or {}
                local starterVendors = deserialized.blackmarketVendors or {}
                local mergedDiscoveries = 0
                local mergedVendors = 0

                for guid, d in pairs(starterDiscoveries) do
                    local c, z, i, x, y = guid:match("^(%d+)%-(%d+)%-(%d+)%-([%-%d%.]+)%-([%-%d%.]+)$")
                    local oldC, oldZ = tonumber(d.c or c), tonumber(d.z or z)
                    
                    local newMapInfo = nil
                    if oldC and oldZ then
                         local key = oldC .. ":" .. oldZ
                         newMapInfo = OldToNewZoneMap[key]
                    end
                    
                    if newMapInfo then
                         local newGuid = GenerateLegacyGUID(newMapInfo.c, newMapInfo.z, i, x, y)
                         d.g, d.c, d.z, d.iz = newGuid, newMapInfo.c, newMapInfo.z, 0
                         guid = newGuid 
                    end

                    if not rawDB.global.discoveries[guid] then
                        rawDB.global.discoveries[guid] = d 
                        mergedDiscoveries = mergedDiscoveries + 1
                    end
                end
                for guid, d in pairs(starterVendors) do
                    if not rawDB.global.blackmarketVendors[guid] then
                        rawDB.global.blackmarketVendors[guid] = { g=d.guid, c=d.continent, z=d.zoneID, iz=d.instanceID or 0, i=d.itemID, xy=d.coords, il=d.itemLink, q=d.itemQuality or 0, t0=d.timestamp, ls=d.lastSeen, st=d.statusTs, s=d.status, mc=d.mergeCount, fp=d.foundBy_player, o=d.originator, src=d.source, cl=d.class, it=d.itemType or 0, ist=d.itemSubType or 0, dt=d.discoveryType or 0, vendorType=d.vendorType, vendorName=d.vendorName, vendorItems=d.vendorItems }
                        mergedVendors = mergedVendors + 1
                    end
                end
                print(string.format("|cff00ff00LootCollector:|r Starter database has been merged (%d discoveries, %d vendors).", mergedDiscoveries, mergedVendors))
            end
        end

        if rawDB.char then
            for charName, charData in pairs(rawDB.char) do
                if charData and charData.looted then
                    local finalLooted = {}
                    for oldGuid, timestamp in pairs(charData.looted) do
                        local c, z, i, x, y = oldGuid:match("^(%d+)%-(%d+)%-(%d+)%-([%-%d%.]+)%-([%-%d%.]+)$")
                        if c and z and i and x and y then
                            local oldC, oldZ = tonumber(c), tonumber(z)
                            
                            local newMapInfo = nil
                            if oldC and oldZ then
                                local key = oldC .. ":" .. oldZ
                                newMapInfo = OldToNewZoneMap[key]
                            end
                            
                            if newMapInfo then
                                local newGuid = GenerateLegacyGUID(newMapInfo.c, newMapInfo.z, i, x, y)
                                finalLooted[newGuid] = timestamp
                                lootedConverted = lootedConverted + 1
                            else
                                local zoneName = (oldC and oldZ and LegacyZoneData[oldC] and LegacyZoneData[oldC][oldZ])
                                if zoneName then
                                    local newMapID = nameToNewMapID[zoneName]
                                    if newMapID then
                                        local newGuid = GenerateLegacyGUID(oldC, newMapID, i, x, y)
                                        finalLooted[newGuid] = timestamp
                                        lootedConverted = lootedConverted + 1
                                    end
                                end
                            end
                        end
                    end
                    charData.looted = finalLooted
                end
            end
        end
        
        rawDB._schemaVersion = 7
        currentSchema = 7
        print(string.format("|cff00ff00LootCollector:|r V7 Upgrade complete! Personal: %d discoveries, %d vendors. Looted: %d records.", discoveriesConverted, vendorsConverted, lootedConverted))
        StaticPopup_Show("LOOTCOLLECTOR_MIGRATION_RELOAD")
    end

    
    
    
    if currentSchema == 7 then
        print("|cff00ff00LootCollector:|r Upgrading database to v8 (High-Precision Coordinates & Unified Instance Tracking)...")
        
        
        local function _lcHex32(u)
            local n = tonumber(u) or 0
            local hi = math.floor(n / 65536)
            local lo = n % 65536
            return string.format("%04x%04x", hi, lo)
        end

        local function _lcFNV1a32(s)
            local hash = 2166136261
            for i = 1, #s do
                hash = bit.bxor(hash, string.byte(s, i))
                hash = (hash * 16777619) % 4294967296
            end
            return hash
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

        local guidMap = {}
        local discoveriesConverted = 0
        local vendorsConverted = 0
        local lootedConverted = 0
        local amnestyGranted = 0
        
        rawDB.global = rawDB.global or {}
        rawDB.global.deletedCache = {} 
        
        local tnow = time()
        
        if rawDB.global.realms then
            for realmKey, realmData in pairs(rawDB.global.realms) do
                
                if realmData.discoveries then
                    local newDiscoveries = {}
                    for oldGuid, d in pairs(realmData.discoveries) do
                        
                        
                        local age = tnow - (tonumber(d.ls) or 0)
                        
                        if age >= (120 * 86400) then
                            
                            d.ls = tnow - (113 * 86400)
                            d.s = "STALE"
                            d.st = tnow
                            amnestyGranted = amnestyGranted + 1
                        elseif d.s == "STALE" or age >= (90 * 86400) then
                            
                            d.ls = tnow - (83 * 86400)
                            d.s = "FADING"
                            d.st = tnow
                            amnestyGranted = amnestyGranted + 1
                        elseif d.s == "FADING" or age >= (30 * 86400) then
                            
                            d.ls = (tonumber(d.ls) or tnow) + (7 * 86400)
                            
                            if (tnow - d.ls) < (30 * 86400) then
                                d.ls = tnow - (30 * 86400) 
                            end
                            amnestyGranted = amnestyGranted + 1
                        end
                        
                        local iz = tonumber(d.iz) or 0
                        local x = d.xy and d.xy.x or 0
                        local y = d.xy and d.xy.y or 0
                        
                        local newGuid = self:GenerateGUID(d.c, d.z, iz, d.i, x, y)
                        d.g = newGuid
                        d.mk = nil 
                        
                        local payload = {
                            v = 5, op = "DISC", c = d.c, z = d.z, iz = iz, i = d.i,
                            x = self:Round4(x), y = self:Round4(y)
                        }
                        d.mid = _lcHex32(_lcFNV1a32(_lcIdentityString(payload)))
                        
                        newDiscoveries[newGuid] = d
                        guidMap[oldGuid] = newGuid
                        discoveriesConverted = discoveriesConverted + 1
                    end
                    realmData.discoveries = newDiscoveries
                end
                
                
                if realmData.blackmarketVendors then
                    local newVendors = {}
                    for oldGuid, d in pairs(realmData.blackmarketVendors) do
                        local iz = tonumber(d.iz) or 0
                        local x = d.xy and d.xy.x or 0
                        local y = d.xy and d.xy.y or 0
                        
                        local vType = d.vendorType
                        if not vType then
                            local i = tonumber(d.i) or 0
                            vType = (i >= -499999 and i <= -400000) and "MS" or "BM"
                        end
                        
                        local newGuid = self:GenerateVendorGUID(vType, d.c, d.z, iz, x, y)
                        d.g = newGuid
                        d.mk = nil
                        
                        local payload = {
                            v = 5, op = "DISC", c = d.c, z = d.z, iz = iz, i = d.i,
                            x = self:Round4(x), y = self:Round4(y)
                        }
                        d.mid = _lcHex32(_lcFNV1a32(_lcIdentityString(payload)))
                        
                        newVendors[newGuid] = d
                        guidMap[oldGuid] = newGuid
                        vendorsConverted = vendorsConverted + 1
                    end
                    realmData.blackmarketVendors = newVendors
                end
            end
        end
        
        
        if rawDB.char then
            for charName, charData in pairs(rawDB.char) do
                if charData and charData.looted then
                    local newLooted = {}
                    for oldGuid, timestamp in pairs(charData.looted) do
                        local newGuid = guidMap[oldGuid]
                        if newGuid then
                            newLooted[newGuid] = timestamp
                            lootedConverted = lootedConverted + 1
                        else
                            newLooted[oldGuid] = timestamp 
                        end
                    end
                    charData.looted = newLooted
                end
            end
        end
        
        rawDB._schemaVersion = 8
        currentSchema = 8
        print(string.format("|cff00ff00LootCollector:|r V8 Upgrade complete! %d Discoveries, %d Vendors, %d Looted records migrated.", discoveriesConverted, vendorsConverted, lootedConverted))
        if amnestyGranted > 0 then
            print(string.format("|cff00ff00LootCollector:|r Applied V8 Amnesty to %d legacy records, extending their decay timers by 7 days.", amnestyGranted))
        end
        StaticPopup_Show("LOOTCOLLECTOR_MIGRATION_RELOAD")
    end
end

local function ApplyAscensionHooks()
    
    if _G.ClassInfoUtil and type(_G.ClassInfoUtil.GetSpecName) == "function" and not _G.ClassInfoUtil._LCHooked then
        _G.ClassInfoUtil.GetSpecName = function(class, spec)
            if not class or not spec then return "" end
            local ok, info = pcall(_G.C_ClassInfo.GetSpecInfo, class, spec)
            if ok and info and info.Name then
                return info.Name
            end
            return ""
        end
        _G.ClassInfoUtil._LCHooked = true
    end

    
    if type(_G.GameTooltip_GetEnchantRequirements) == "function" and not _G._LCEnchantReqHooked then
        local origReq = _G.GameTooltip_GetEnchantRequirements
        _G.GameTooltip_GetEnchantRequirements = function(...)
            local ok, res = pcall(origReq, ...)
            if ok then return res end
            return nil
        end
        _G._LCEnchantReqHooked = true
    end
end

ApplyAscensionHooks()

function LootCollector:OnInitialize()
    
    self:PreInitializeMigration()

    if self.LEGACY_MODE_ACTIVE then
        print("|cffff0000LootCollector is in Legacy Mode!|r")
        print("|cffffff00Your database is from an older version and needs to be updated.|r")
        print(" - Please |cffff7f00/reload|r your UI to trigger the automatic update.")
        return 
    end

    self.db = LibStub("AceDB-3.0"):New("LootCollectorDB_Asc", dbDefaults, true)

    if _G.LootCollectorDB_Asc then
        _G.LootCollectorDB_Asc.schemaVersion = _G.LootCollectorDB_Asc.schemaVersion or 8
        if _G.LootCollectorDB_Asc.schemaVersion < 8 then
            _G.LootCollectorDB_Asc.schemaVersion = 8
        end
    end

    self:ActivateRealmBucket()

    self.channelReady = false
    self.name         = "LootCollector"
    self.Version      = "beta-0.8.3"

    local Constants = self:GetModule("Constants", true)
    if Constants and Constants.GetDefaultChannel then
        self.chatChannel = Constants:GetDefaultChannel()
        self.addonPrefix = Constants:GetDefaultPrefix()
    else
        self.chatChannel = "BBLC25C"
        self.addonPrefix = "BBLC25AM"
    end

    local Comm = self:GetModule("Comm", true)
    if Comm then
        Comm.addonPrefix = self.addonPrefix
        Comm.channelName = self.chatChannel
    end

    
    self.notifiedNewVersion = nil

    self.db.char        = self.db.char or {}
    self.db.char.looted = self.db.char.looted or {}
    self.db.char.hidden = self.db.char.hidden or {}

    
    local discoveries = self:GetDiscoveriesDB()
    local isNewDatabase = (not discoveries) or (not next(discoveries))
    
    if isNewDatabase then
        
        local loaded, reason = LoadAddOn("LootCollector_StarterDB")
        if loaded and _G.LootCollector_OptionalDB_Data and type(_G.LootCollector_OptionalDB_Data) == "table" then
            local dbData = _G.LootCollector_OptionalDB_Data
            if dbData.version and dbData.data and self.db.profile and self.db.profile.offeredOptionalDB ~= dbData.version then
                print("|cff00ff00LootCollector:|r New installation detected. Automatically merging starter database...")
                local ImportExport = self:GetModule("ImportExport", true)
                if ImportExport and ImportExport.ApplyImportString then
                    ImportExport:ApplyImportString(dbData.data, "MERGE", false, true, true)
                end
                if self.db and self.db.profile then
                    self.db.profile.offeredOptionalDB = dbData.version
                end
            end
        end
    else
        
        local name, title, notes, loadable, reason, security, newVersion = GetAddOnInfo("LootCollector_StarterDB")
        if name and loadable then
            local starterVersion = GetAddOnMetadata("LootCollector_StarterDB", "Version")
            
            if starterVersion and self.db.profile and self.db.profile.offeredOptionalDB ~= starterVersion then
                
                local loaded = LoadAddOn("LootCollector_StarterDB")
                if loaded and _G.LootCollector_OptionalDB_Data then
                    local dbData = _G.LootCollector_OptionalDB_Data
                    self:ScheduleAfter(5, function()
                        
                        StaticPopup_Show("LOOTCOLLECTOR_OPTIONAL_DB_UPDATE", starterVersion, dbData.changelog or "No changes listed.", starterVersion)
                    end)
                end
            end
        end
    end
    
    SLASH_LootCollectorARROW1 = "/lcarrow"
    SlashCmdList["LootCollectorARROW"] = function(msg)
        local Arrow = self:GetModule("Arrow", true)
        if Arrow and Arrow.SlashCommandHandler then
            Arrow:SlashCommandHandler(msg)
        else
            print("|cffff7f00LootCollector:|r Arrow module not available.")
        end
    end

    SLASH_LOOTCOLLECTORTOGGLE1 = "/lctoggle"
    SlashCmdList["LOOTCOLLECTORTOGGLE"] = function()
        LootCollector:ToggleAllDiscoveries()
    end
    
    
    SLASH_LOOTCOLLECTORPAUSE1 = "/lcpause"
    SlashCmdList["LOOTCOLLECTORPAUSE"] = function()
        LootCollector:TogglePause()
    end
    
    SLASH_LOOTCOLLECTORCCQ1 = "/lcccq"
    SlashCmdList["LOOTCOLLECTORCCQ"] = function()
        if LootCollector.db and LootCollector.db.global then
            local queueSize = (LootCollector.db.global.cacheQueue and #LootCollector.db.global.cacheQueue) or 0
            LootCollector.db.global.cacheQueue = {}
            local Core = LootCollector:GetModule("Core", true)
            if Core and Core._queueSet then
                 wipe(Core._queueSet)
            end
            print(string.format("|cff00ff00LootCollector:|r Cleared %d items from the background cache queue.", queueSize))
        else
            print("|cffff7f00LootCollector:|r Database not ready.")
        end
    end
	
	SLASH_LOOTCOLLECTORCZFIX1 = "/lcczfix"
    SlashCmdList["LOOTCOLLECTORCZFIX"] = function()
        local Core = LootCollector:GetModule("Core", true)
        if Core and Core.FixLegacyZoneIDs then
            LootCollector.db.global.legacyZoneFixV2 = false
            Core:FixLegacyZoneIDs()
        else
             print("|cffff7f00LootCollector:|r Core module not available.")
        end
    end

end

LootCollector.isHibernating = false

function LootCollector:IsPaused()
    return self.isHibernating
end

function LootCollector:EvaluateAutoPause()
    if not (self.db and self.db.char) then return end
    
    local c = self.db.char
    local shouldHibernate = c.paused 

    if not shouldHibernate and c.autoPauseInRaidGroup then
        if GetNumRaidMembers() > 0 then
            shouldHibernate = true
        end
    end

    if not shouldHibernate then
        local inInstance, instanceType = IsInInstance()
        if inInstance then
            if c.autoPauseInBG and (instanceType == "pvp" or instanceType == "arena") then
                shouldHibernate = true
            elseif c.autoPauseInRaidInstance and instanceType == "raid" then
                shouldHibernate = true
            end
        end
    end

    if shouldHibernate and not self.isHibernating then
        self:EnterHibernation()
    elseif not shouldHibernate and self.isHibernating then
        self:ExitHibernation()
    end
end

function LootCollector:EnterHibernation()
    self.isHibernating = true
    print("|cffff7f00LootCollector:|r Hibernation Mode |cffff0000ON|r. All processing, map icons, and local detection are stopped.")
    
    
    local Comm = self:GetModule("Comm", true)
    if Comm then
        if Comm._rateLimitQueue then wipe(Comm._rateLimitQueue) end
        if Comm._delayQueue then wipe(Comm._delayQueue) end
        if Comm._incomingMessageQueue then wipe(Comm._incomingMessageQueue) end
    end
    
    
    local Core = self:GetModule("Core", true)
    if Core then
        if Core.pendingBroadcasts then wipe(Core.pendingBroadcasts) end
        if Core.StopCaching then Core:StopCaching() end
    end
    
    
    local Arrow = self:GetModule("Arrow", true)
    if Arrow and Arrow.Hide then Arrow:Hide() end

    
    local Map = self:GetModule("Map", true)
    if Map then
        Map.cacheIsDirty = true
        if Map.Update and WorldMapFrame and WorldMapFrame:IsShown() then Map:Update() end
        if Map.UpdateMinimap then Map:UpdateMinimap() end
    end
end

function LootCollector:ExitHibernation()
    self.isHibernating = false
    print("|cff00ff00LootCollector:|r Hibernation Mode |cff00ff00OFF|r. Normal functionality resumed.")
    
    
    local Core = self:GetModule("Core", true)
    if Core and Core.EnsureCachePump then Core:EnsureCachePump() end
    
    
    local Arrow = self:GetModule("Arrow", true)
    if Arrow and Arrow.Show and self.db.profile.mapFilters and self.db.profile.mapFilters.autoTrackNearest then 
        Arrow:Show() 
    end

    
    local Map = self:GetModule("Map", true)
    if Map then
        Map.cacheIsDirty = true
        if Map.Update and WorldMapFrame and WorldMapFrame:IsShown() then Map:Update() end
        if Map.UpdateMinimap then Map:UpdateMinimap() end
    end
end

function LootCollector:TogglePause()
    if not (self.db and self.db.char) then return end
    self.db.char.paused = not self.db.char.paused
    self:EvaluateAutoPause()
end

function LootCollector:ToggleAllDiscoveries()
    if not (self.db and self.db.char and self.db.char.mapFilters) then return end
    self.db.char.mapFilters.hideAll = not self.db.char.mapFilters.hideAll
    
    if self.db.char.mapFilters.hideAll then
        print("|cffff7f00LootCollector:|r All discoveries are now |cffff0000HIDDEN|r on the Map and Minimap.")
    else
        print("|cff00ff00LootCollector:|r All discoveries are now |cff00ff00SHOWN|r on the Map and Minimap.")
    end
    
    local Map = self:GetModule("Map", true)
    if Map then
        if Map.Update and WorldMapFrame and WorldMapFrame:IsShown() then
            Map:Update()
        end
        if Map.UpdateMinimap then
            Map:UpdateMinimap()
        end
    end
end

function LootCollector:IsZoneIgnored()
    if not (self.db and self.db.profile and self.db.profile.ignoreZones) then return false end
    local zoneName = GetRealZoneText()
    return zoneName and self.db.profile.ignoreZones[zoneName]
end

function LootCollector:DelayedChannelInit()
    pcall(LeaveChannelByName, "BBLCC25")
    local Comm = self:GetModule("Comm", true)
    if not Comm then return end
    local DELAY_SECONDS = 12.0
    self:ScheduleAfter(DELAY_SECONDS, function()
        LootCollector.channelReady = true
        if LootCollector.db and LootCollector.db.profile.sharing.enabled and not LootCollector:IsZoneIgnored() then
            if Comm.EnsureChannelJoined then
                Comm:EnsureChannelJoined()
            end
        end
    end)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
end

function LootCollector:OnEnable()   
    local Map = self:GetModule("Map", true)
    if Map then 
        self:RegisterEvent("WORLD_MAP_UPDATE", function() 
            if WorldMapFrame and WorldMapFrame:IsShown() then Map:Update() end 
        end) 
    end
    
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function(event, ...)
        self:DelayedChannelInit()
        
        self:EvaluateAutoPause() 
    end)
    
    
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "EvaluateAutoPause")
    self:RegisterEvent("RAID_ROSTER_UPDATE", "EvaluateAutoPause")
    self:RegisterEvent("PARTY_MEMBERS_CHANGED", "EvaluateAutoPause")
end

function LootCollector:OnDisable()
    self:UnregisterAllEvents()
end

SLASH_LCCLEANUP1 = "/lccdb"
SlashCmdList["LCCLEANUP"] = function()
    local Core = LootCollector:GetModule("Core", true)
    if Core and Core.RunManualDatabaseCleanup then
        Core:RunManualDatabaseCleanup()
    else
        print("|cffff7f00LootCollector:|r Core module not available.")
    end
end