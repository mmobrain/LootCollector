
local AceAddon     = LibStub("AceAddon-3.0")
local AceEvent     = LibStub("AceEvent-3.0")
local AceComm      = LibStub("AceComm-3.0")
local AceDB        = LibStub("AceDB-3.0")

local LootCollector = AceAddon:NewAddon("LootCollector", "AceEvent-3.0", "AceComm-3.0")
_G.LootCollector = LootCollector

BINDING_HEADER_LOOTCOLLECTOR = "LootCollector"
LootCollector.LEGACY_MODE_ACTIVE = true
LootCollector.addonPrefix = "BBLC25AM"
LootCollector.chatChannel = "BBLC25C"

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
    button2 = "Deny",
    button3 = "Block Sender",
    OnAccept = function(self, data)
      if not data then return end
      
      
      if not data.g and LootCollector.GenerateGUID then
          data.g = LootCollector:GenerateGUID(data.c, data.z, data.i, data.xy.x, data.xy.y)
      end

      local Core = LootCollector:GetModule("Core", true)
      if Core and Core.AddDiscovery then
        
        
        Core:AddDiscovery(data, { isNetwork = false, op = "SHOW", suppressToast = true })
      end
      
      local Map = LootCollector:GetModule("Map", true)
      if Map and Map.FocusOnDiscovery then
        Map:FocusOnDiscovery(data)
      end
    end,
    OnButton3Click = function(self, data)
      if not (data and data.sender) then return end
      local sender = data.sender
      if LootCollector.db and LootCollector.db.profile and LootCollector.db.profile.sharing then
        LootCollector.db.profile.sharing.blockList = LootCollector.db.profile.sharing.blockList or {}
        LootCollector.db.profile.sharing.blockList[sender] = true
        print(string.format("|cffff7f00LootCollector:|r Player |cffffff00%s|r has been added to your block list.", sender))
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
    if not (dbData and dbData.data and dbData.version) then return end
    local ImportExport = LootCollector:GetModule("ImportExport", true)
    if ImportExport and ImportExport.ApplyImportString then
        ImportExport:ApplyImportString(dbData.data, "MERGE", false)
    end
    if LootCollector.db and LootCollector.db.profile then
        LootCollector.db.profile.offeredOptionalDB = dbData.version
    end
  end,
  OnCancel = function()
    local dbData = _G.LootCollector_OptionalDB_Data
    if not (dbData and dbData.version) then return end
    if LootCollector.db and LootCollector.db.profile then
        LootCollector.db.profile.offeredOptionalDB = dbData.version
    end
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
}

local dbDefaults = {
    profile = {
        enabled = true,
        paused = false,
        offeredOptionalDB = nil,
        minQuality = 2,
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
		    hidePlayerNames = false,
            pinSize = 17, 
            minimapPinSize = 14, 
            showZoneSummaries = false,
            showMapFilter = true,
            showMinimap = true,
            autoTrackNearest = false,
            maxMinimapDistance = 1400,
            showMysticScrolls = true,
            showWorldforged = true,
            minRarity = 0,
            usableByClasses = {},
            allowedEquipLoc = {},
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
            blockList = {},
            whiteList = {},
        },      
        lastVersionToastAt = 0,
        ignoreZones = {},
        decay = { fadeAfterDays  = 30, staleAfterDays = 90, },
	    debugMode = false,
	    mdebugMode = false,	  
	    idebugMode = false,
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
        print(string.format("|cffffff00[LC-Debug|cffff8c00][%s]|r %s", tostring(module), tostring(message)))
    end
end

function LootCollector._idebug(module, message)
    if LootCollector.db and LootCollector.db.profile and LootCollector.db.profile.idebugMode then
        print(string.format("|cffffff00[LC-Debug|cffff8c00][%s]|r %s", tostring(module), tostring(message)))
    end
end
    
function LootCollector:normalizeSenderName(sender)
    if type(sender) ~= "string" then return nil end
    local name = sender:match("([^%-]+)") or sender
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    return name ~= "" and name or nil
end

function LootCollector:Round2(v)
    v = tonumber(v) or 0
    return math.floor(v * 100 + 0.5) / 100
end

function LootCollector:Round4(v)
    v = tonumber(v) or 0
    return math.floor(v * 10000 + 0.5) / 10000
end

function LootCollector:GenerateGUID(c, mapID, i, x, y)
    local x2 = self:Round2(x or 0)
    local y2 = self:Round2(y or 0)
    return tostring(c or 0) .. "-" .. tostring(mapID or 0) .. "-" .. tostring(i or 0) .. "-" .. string.format("%.2f", x2) .. "-" .. string.format("%.2f", y2)
end

function LootCollector:GetActiveRealmKey()
    
    
    local realmName = nil

    if GetRealmName then
        realmName = GetRealmName()
    end

    if type(realmName) ~= "string" or realmName == "" then
        
        realmName = "Unknown Realm"
    end

    return realmName
end

function LootCollector:ActivateRealmBucket()
    
    
    if not (self.db and self.db.global) then
        return
    end

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
    local p = self.db and self.db.profile
    local f = (p and p.mapFilters) or {}
    if f.hideAll == nil then f.hideAll = false end
    if f.hideFaded == nil then f.hideFaded = false end
    if f.hideStale == nil then f.hideStale = false end
    if f.hideLooted == nil then f.hideLooted = false end
    if f.hideUnconfirmed == nil then f.hideUnconfirmed = false end
    if f.hideUncached == nil then f.hideUncached = false end
    if f.hideLearnedTransmog == nil then f.hideLearnedTransmog = false end
    if f.minRarity == nil then f.minRarity = 0 end
    if f.allowedEquipLoc == nil then f.allowedEquipLoc = {} end
    if f.usableByClasses == nil then f.usableByClasses = {} end
    if f.showMinimap == nil then f.showMinimap = true end
    if f.showMysticScrolls == nil then f.showMysticScrolls = true end
    if f.showWorldforged == nil then f.showWorldforged = true end
    if f.maxMinimapDistance == nil then f.maxMinimapDistance = 1400 end
    if f.pinSize == nil then f.pinSize = 16 end
    return f
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
    if (rawDB._schemaVersion or 0) >= 7 then
        self.LEGACY_MODE_ACTIVE = false 
        return
    end
    
    
    self.MIGRATION_JUST_HAPPENED = true

    local cityZoneIDsToPurge = {[1]={[382]=true,[322]=true,[363]=true},[2]={[342]=true,[302]=true,[383]=true},[3]={[482]=true},[4]={[505]=true}}
        
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
        for _, guid in ipairs(guidsToRemove) do
            
            
            discoveries[guid] = nil
        end
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
        for _, guid in ipairs(guidsToRemove) do
            discoveries[guid] = nil
        end
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
        for _, guid in ipairs(guidsToRemove) do
            discoveries[guid] = nil
        end
        return #guidsToRemove
    end

    local function DeduplicateItems(discoveries)
        if not discoveries then return 0 end
        local groups = {}
        for guid, d in pairs(discoveries) do
            if d and d.i and d.z and d.c then
                local key = d.c .. ":" .. d.z .. ":" .. d.i
                groups[key] = groups[key] or {}
                table.insert(groups[key], guid)
            end
        end
        local guidsToRemove = {}
        for _, guids in pairs(groups) do
            if #guids > 1 then
                local guidToKeep, latestTs = nil, nil
                for _, guid in ipairs(guids) do
                    local d = discoveries[guid]
                    local currentTs = tonumber(d.ls) or 0
                    if not latestTs or currentTs > latestTs then latestTs = currentTs; guidToKeep = guid end
                end
                for _, guid in ipairs(guids) do if guid ~= guidToKeep then table.insert(guidsToRemove, guid) end end
            end
        end
        for _, guid in ipairs(guidsToRemove) do
            discoveries[guid] = nil
        end
        return #guidsToRemove
    end
    
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
        
        ["1:2"] = { c=1, z=44 },   
        ["1:3"] = { c=1, z=182 },  
        ["1:4"] = { c=1, z=465 },  
        ["1:6"] = { c=1, z=477 },  
        ["1:9"] = { c=1, z=43 },   
        ["1:11"] = { c=1, z=102 }, 
        ["1:12"] = { c=1, z=5 },   
        ["1:13"] = { c=1, z=142 }, 
        ["1:16"] = { c=1, z=183 }, 
        ["1:17"] = { c=1, z=122 }, 
        ["1:19"] = { c=1, z=242 }, 
        ["1:21"] = { c=1, z=10 },  
        ["1:27"] = { c=1, z=262 }, 
        ["1:31"] = { c=1, z=82 },  
        ["1:32"] = { c=1, z=162 }, 
        ["1:33"] = { c=1, z=42 },  
        ["1:34"] = { c=1, z=12 },  
        ["1:40"] = { c=1, z=62 },  
        ["1:44"] = { c=1, z=202 }, 
        ["1:47"] = { c=1, z=282 }, 
        
        ["1:1"] = { c=1, z=1242 }, 
        ["1:10"] = { c=1, z=382 }, 
        ["1:22"] = { c=1, z=322 }, 
        ["1:24"] = { c=1, z=1245 },
        ["1:25"] = { c=1, z=1243 },
        ["1:35"] = { c=1, z=472 }, 
        ["1:41"] = { c=1, z=363 }, 
        ["1:45"] = { c=1, z=1244 },
        
        ["1:8"] = { c=1, z=1204 }, 
        ["1:18"] = { c=1, z=751 }, 
        ["1:46"] = { c=1, z=750 }, 

        
        ["2:1"] = { c=2, z=16 },   
        ["2:3"] = { c=2, z=17 },   
        ["2:4"] = { c=2, z=18 },   
        ["2:5"] = { c=2, z=1205 }, 
        ["2:6"] = { c=2, z=20 },   
        ["2:7"] = { c=2, z=30 },   
        ["2:10"] = { c=2, z=33 },  
        ["2:12"] = { c=2, z=28 },  
        ["2:13"] = { c=2, z=35 },  
        ["2:14"] = { c=2, z=24 },  
        ["2:16"] = { c=2, z=31 },  
        ["2:17"] = { c=2, z=463 }, 
        ["2:19"] = { c=2, z=464 }, 
        ["2:22"] = { c=2, z=25 },  
        ["2:27"] = { c=2, z=36 },  
        ["2:30"] = { c=2, z=37 },  
        ["2:32"] = { c=2, z=29 },  
        ["2:36"] = { c=2, z=22 },  
        ["2:38"] = { c=2, z=38 },  
        ["2:40"] = { c=2, z=39 },  
        ["2:43"] = { c=2, z=27 },  
        ["2:44"] = { c=2, z=21 },  
        ["2:47"] = { c=2, z=23 },  
        ["2:48"] = { c=2, z=40 },  
        ["2:49"] = { c=2, z=41 },  
        
        ["2:9"] = { c=2, z=1239 }, 
        ["2:11"] = { c=2, z=1240 },
        ["2:23"] = { c=2, z=342 }, 
        ["2:29"] = { c=2, z=1238 },
        ["2:35"] = { c=2, z=481 }, 
        ["2:37"] = { c=2, z=302 }, 
        ["2:39"] = { c=2, z=1241 },
        ["2:46"] = { c=2, z=383 }, 
        
        ["2:24"] = { c=2, z=799 }, 
        ["2:31"] = { c=2, z=763 }, 
        ["2:41"] = { c=2, z=757 }, 
        ["2:45"] = { c=2, z=693 }, 

        
        ["3:1"] = { c=3, z=476 },  
        ["3:2"] = { c=3, z=466 },  
        ["3:3"] = { c=3, z=478 },  
        ["3:4"] = { c=3, z=480 },  
        ["3:5"] = { c=3, z=474 },  
        ["3:6"] = { c=3, z=482 },  
        ["3:7"] = { c=3, z=479 },  
        ["3:8"] = { c=3, z=468 },  

        
        ["4:1"] = { c=4, z=487 },  
        ["4:2"] = { c=4, z=511 },  
        ["4:3"] = { c=4, z=505 },  
        ["4:4"] = { c=4, z=489 },  
        ["4:5"] = { c=4, z=491 },  
        ["4:6"] = { c=4, z=492 },  
        ["4:7"] = { c=4, z=542 },  
        ["4:8"] = { c=4, z=493 },  
        ["4:9"] = { c=4, z=494 },  
        ["4:10"] = { c=4, z=496 }, 
        ["4:11"] = { c=4, z=502 }, 
        ["4:12"] = { c=4, z=497 }, 
    }

    local discoveries = rawDB.global and rawDB.global.discoveries
    if discoveries then
        
        print("|cff00ff00LootCollector:|r Performing pre-migration database cleanup...")
        local restrictedRemoved = PurgeByFinderBlacklist(discoveries)
        local cityRemoved = PurgeByCityZones(discoveries)
        local zeroRemoved = PurgeZeroCoordDiscoveries(discoveries)
        local dupesRemoved = DeduplicateItems(discoveries)
        print(string.format("|cff00ff00LootCollector:|r Cleanup removed %d blacklisted data, %d city, %d zero-coord, and %d duplicate entries.", restrictedRemoved, cityRemoved, zeroRemoved, dupesRemoved))
    end

    print("|cff00ff00LootCollector:|r Database version " .. tostring(rawDB._schemaVersion or "pre-6") .. " detected. Beginning automatic upgrade to v7...")
    local discoveriesConverted, vendorsConverted, lootedConverted = 0, 0, 0
    local currentTime = time()

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
                     
                     local newGuid = self:GenerateGUID(newMapInfo.c, newMapInfo.z, i, x, y)
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
                                self._debug("Migration-Cleanup", "Discarding Mystic Scroll with invalid/missing source: " .. tostring(d.il))
                            end
                        end

                        if passesSrcCheck then
                            local newMapID = nameToNewMapID[finalName]
                            if newMapID then
                                local newGuid = self:GenerateGUID(oldC, newMapID, i, x, y)
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
                        print(string.format("Migration-Fix FIXED Legacy Vendor: %s -> %s", oldGuid, newGuid))
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
                     local newGuid = self:GenerateGUID(newMapInfo.c, newMapInfo.z, i, x, y)
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
        else
            print("|cffff0000LootCollector:|r ERROR: Could not parse the starter database. It may be corrupt. Skipping merge.")
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
                            local newGuid = self:GenerateGUID(newMapInfo.c, newMapInfo.z, i, x, y)
                            finalLooted[newGuid] = timestamp
                            lootedConverted = lootedConverted + 1
                        else
                            local zoneName = (oldC and oldZ and LegacyZoneData[oldC] and LegacyZoneData[oldC][oldZ])
                            if zoneName then
                                local newMapID = nameToNewMapID[zoneName]
                                if newMapID then
                                    local newGuid = self:GenerateGUID(oldC, newMapID, i, x, y)
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
    local report = string.format("|cff00ff00LootCollector:|r Upgrade complete! Personal: %d discoveries, %d vendors. Looted: %d records. Schema is now v7.", discoveriesConverted, vendorsConverted, lootedConverted)
    print(report)
    StaticPopup_Show("LOOTCOLLECTOR_MIGRATION_RELOAD")
end

function LootCollector:OnInitialize()
    
    self:PreInitializeMigration()

    
    
    
    if self.LEGACYMODEACTIVE then
        print("|cffff0000LootCollector is in Legacy Mode!|r")
        print("|cffffff00Your database is from an older version and needs to be updated.|r")
        print(" - Please |cffff7f00/reload|r your UI to trigger the automatic update.")
        return 
    end

    
    self.db = LibStub("AceDB-3.0"):New("LootCollectorDB_Asc", dbDefaults, true)

    
    if _G.LootCollectorDB_Asc then
        _G.LootCollectorDB_Asc.schemaVersion = _G.LootCollectorDB_Asc.schemaVersion or 7
        if _G.LootCollectorDB_Asc.schemaVersion < 7 then
            _G.LootCollectorDB_Asc.schemaVersion = 7
        end
    end

    
    self:ActivateRealmBucket()

    self.channelReady = false
    self.name         = "LootCollector"
    self.Version      = "alpha-0.7.45"

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

    self.pauseQueue         = { incoming = {}, outgoing = {} }
    self.notifiedNewVersion = nil

    self.db.char        = self.db.char or {}
    self.db.char.looted = self.db.char.looted or {}
    self.db.char.hidden = self.db.char.hidden or {}

    
    if _G.LootCollector_OptionalDB_Data and type(_G.LootCollector_OptionalDB_Data) == "table" then
        local dbData = _G.LootCollector_OptionalDB_Data
        if dbData.version and dbData.data and self.db.profile and self.db.profile.offeredOptionalDB ~= dbData.version then
            local discoveries = self:GetDiscoveriesDB()
            if (not discoveries) or (not next(discoveries)) then
                
                print("|cff00ff00LootCollector:|r New installation detected. Automatically merging starter database...")
                local ImportExport = self:GetModule("ImportExport", true)
                if ImportExport and ImportExport.ApplyImportString then
                    
                    ImportExport:ApplyImportString(dbData.data, "MERGE", false, true, true)
                end
                if self.db and self.db.profile then
                    self.db.profile.offeredOptionalDB = dbData.version
                end
            else
                
                self:ScheduleAfter(5, function()
                    StaticPopup_Show("LOOTCOLLECTOR_OPTIONAL_DB_UPDATE", dbData.version, dbData.changelog or "No changes listed.")
                end)
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

function LootCollector:IsPaused()
    return self.db and self.db.profile.paused
end

function LootCollector:ProcessPauseQueues()
    if self:IsPaused() then return end
    local Core = self:GetModule("Core", true); local Comm = self:GetModule("Comm", true); if not Core or not Comm then return end
    local incomingCount = #self.pauseQueue.incoming; for _, discoveryData in ipairs(self.pauseQueue.incoming) do Core:AddDiscovery(discoveryData, { isNetwork = true }) end; self.pauseQueue.incoming = {}
    local outgoingCount = #self.pauseQueue.outgoing; for _, discoveryData in ipairs(self.pauseQueue.outgoing) do Comm:_BroadcastNow(discoveryData) end; self.pauseQueue.outgoing = {}
    if (incomingCount + outgoingCount) > 0 then print(string.format("|cff00ff00LootCollector:|r Processed %d incoming and %d outgoing queued messages.", incomingCount, outgoingCount)); local Map = self:GetModule("Map", true); if Map and Map.Update then Map:Update() end end
end

function LootCollector:TogglePause()
    if not (self.db and self.db.profile) then return end
    self.db.profile.paused = not self.db.profile.paused
    if self.db.profile.paused then print("|cffff7f00LootCollector:|r Processing is now |cffff0000PAUSED|r. Messages will be queued.") else print("|cff00ff00LootCollector:|r Processing is now |cff00ff00RESUMED|r."); self:ProcessPauseQueues() end
end

function LootCollector:ToggleAllDiscoveries()
    if not (self.db and self.db.profile and self.db.profile.mapFilters) then return end
    local filters = self:GetFilters()
    filters.hideAll = not filters.hideAll
    if filters.hideAll then
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
    local Map = self:GetModule("Map", true); if Map then self:RegisterEvent("WORLD_MAP_UPDATE", function() if WorldMapFrame and WorldMapFrame:IsShown() then Map:Update() end end) end
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "DelayedChannelInit")
    
    
    
        
            
        
    
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
