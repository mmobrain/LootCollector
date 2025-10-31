local AceAddon     = LibStub("AceAddon-3.0")
local AceEvent     = LibStub("AceEvent-3.0")
local AceComm      = LibStub("AceComm-3.0")
local AceDB        = LibStub("AceDB-3.0")

local LootCollector = AceAddon:NewAddon("LootCollector", "AceEvent-3.0", "AceComm-3.0")
_G.LootCollector = LootCollector

BINDING_HEADER_LOOTCOLLECTOR = "LootCollector"

LootCollector.addonPrefix = "BBLC25AM"
LootCollector.chatChannel = "BBLC25C"

LootCollector.LEGACY_MODE_ACTIVE = false 

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
	["The \"Kodo Egg\""] = true,	
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
      
      local Core = LootCollector:GetModule("Core", true)
      if Core and Core.AddDiscovery then
        -- Add discovery with suppressToast flag to prevent toast from delaying map update
        Core:AddDiscovery(data, { isNetwork = true, op = "SHOW", suppressToast = true })
      end
  
      -- Immediately focus on the discovery
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

StaticPopupDialogs["LOOTCOLLECTOR_MIGRATE_DB"] = {
  text = "|cffff0000LootCollector: Action Required|r\n\nYour database is out of date and the addon is running in a limited |cffff7f00Legacy Mode|r.\n\nTo unlock all features, you must migrate your data. Your per-character looted history will be preserved. All other data is discarded! ME data is limited in this release!",
  button1 = "Migrate Now",
  button2 = "Ask Me Later",
  OnAccept = function()
    local Migration = LootCollector:GetModule("Migration_v5", true)
    if Migration and Migration.PreserveAndReset then
        Migration:PreserveAndReset()
    else
        print("|cffff0000LootCollector Error:|r Migration module is not available. Please type |cffffff00/lcpreserve|r to manually start the migration.")
    end
  end,
  OnCancel = function()
    print("|cffff7f00LootCollector:|r Migration postponed. Addon will remain in Legacy Mode for this session.")
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
}

local dbDefaults = {
    profile = {
        enabled = true,
        paused = false,
        offeredOptionalDB = nil, -- Flag for one-time offer
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
            pinSize = 17, 
            minimapPinSize = 14, 
            showZoneSummaries = false,
            showMapFilter = true,
            showMinimap = true,
            autoTrackNearest = false,
            maxMinimapDistance = 0,
            showMysticScrolls = true,
            showWorldforged = true,
            minRarity = 0,
            usableByClasses = {},
            allowedEquipLoc = {},
        },
        toasts = { 
            enabled = true,
            hidePlayerNames = false,
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
        discoveries = {},
    },
    char = { looted = {}, hidden = {}, looted_remapped_v6 = false },
    global = { 
        discoveries = {},
        blackmarketVendors = {},
        cacheQueue = {},
        autoCleanupPhase = 0,
        manualCleanupRunCount = 0,
        purgeEmbossedState = 0,
    },
}

function LootCollector._debug(module, message) return end
    
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

function LootCollector:GenerateGUID(c, z, i, x, y)
    
    local x2 = self:Round2(x or 0)
    local y2 = self:Round2(y or 0)
    return tostring(c or 0) .. "-" .. tostring(z or 0) .. "-" .. tostring(i or 0) .. "-" .. string.format("%.2f", x2) .. "-" .. string.format("%.2f", y2)
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


function LootCollector.ResolveZoneDisplay(continent, zoneID, iz)
    local ZoneList = LootCollector:GetModule("ZoneList", true)
    local c = tonumber(continent) or 0
    local z = tonumber(zoneID) or 0
    local inst = tonumber(iz) or 0

    if z == 0 then
        return (ZoneList and ZoneList.ResolveIz and ZoneList:ResolveIz(inst)) or (GetRealZoneText and GetRealZoneText()) or "Unknown Instance"
    else
        return (ZoneList and ZoneList.GetZoneName and ZoneList:GetZoneName(c, z)) or "Unknown Zone"
    end

    return "Unknown Zone"
end

function LootCollector.GetZoneAbbrevWithIz(continent, zoneID, iz)
    local ZoneList = LootCollector:GetModule("ZoneList", true)
    local display = LootCollector.ResolveZoneDisplay(continent, zoneID, iz)
    if ZoneList and ZoneList.ZONE_ABBREVIATIONS then
        return ZoneList.ZONE_ABBREVIATIONS[display] or display
    end
    return display
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
    if f.minRarity == nil then f.minRarity = 0 end
    if f.allowedEquipLoc == nil then f.allowedEquipLoc = {} end
    if f.usableByClasses == nil then f.usableByClasses = {} end
    if f.showMinimap == nil then f.showMinimap = true end
    if f.showMysticScrolls == nil then f.showMysticScrolls = true end
    if f.showWorldforged == nil then f.showWorldforged = true end
    if f.maxMinimapDistance == nil then f.maxMinimapDistance = 0 end
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

function LootCollector:OnInitialize()
    -- *** FINAL, ROBUST MIGRATION PRE-CHECK on RAW DB ***
    local needsMigration = false
    local dbVersion = 0
    if _G.LootCollectorDB_Asc and type(_G.LootCollectorDB_Asc) == "table" then
        local rawDB = _G.LootCollectorDB_Asc
        
        -- Check for the schema version: first at the root (new), then fallback to global (old).
        if rawDB._schemaVersion then
            dbVersion = rawDB._schemaVersion
        elseif rawDB.global and rawDB.global._schemaVersion then
            dbVersion = rawDB.global._schemaVersion
        end

        -- A database needs migration ONLY if its version is old AND it actually contains old discovery data.
        if dbVersion < 6 and rawDB.global and rawDB.global.discoveries and next(rawDB.global.discoveries) then
            needsMigration = true
        end
    end


    if needsMigration then
        self.LEGACY_MODE_ACTIVE = true
        StaticPopup_Show("LOOTCOLLECTOR_MIGRATE_DB")
        return 
    end
    
    self.db = LibStub("AceDB-3.0"):New("LootCollectorDB_Asc", dbDefaults, true)
    
    if _G.LootCollectorDB_Asc then
        _G.LootCollectorDB_Asc._schemaVersion = 6
    end

    self.channelReady = false 
    
    self.name = "LootCollector"
    self.Version = "alpha-0.5.8"
    
    -- *** PER-CHARACTER MIGRATION FINALIZER & VERIFIER ***
    if self.db.profile and self.db.profile.preservedLootedData_v6 then
        local currentCharKey = UnitName("player") .. " - " .. GetRealmName()
        if self.db.profile.preservedLootedData_v6[currentCharKey] then
            print("|cff00ff00LootCollector:|r Restoring preserved looted history for " .. UnitName("player") .. "...")
            self:_debug("Migration-Finalize", "Found preserved data for current character: " .. currentCharKey)
            
            self.db.char.looted = self.db.profile.preservedLootedData_v6[currentCharKey].looted or {}
            
            print("|cff00ff00LootCollector:|r Looted history for this character has been successfully restored.")
        end

        local isFinalized = false
        if self.db.char and self.db.char.looted then
            local firstKey = next(self.db.char.looted)
            if not firstKey then
                isFinalized = true
            elseif type(firstKey) == "string" and firstKey:match("^(%d+)-(%d+)-(%d+)-([%-%d%.]+)-([%-%d%.]+)$") then
                isFinalized = true
            end
        else
            isFinalized = true
        end

        if isFinalized then
            if self.db.profile.preservedLootedData_v6[currentCharKey] then
                self:_debug("Migration-Finalize", "Verified current character's looted data is in new format. Removing from preservation table.")
                self.db.profile.preservedLootedData_v6[currentCharKey] = nil
            
                if not next(self.db.profile.preservedLootedData_v6) then
                    self.db.profile.preservedLootedData_v6 = nil
                    print("|cff00ff00LootCollector:|r All preserved looted data has now been restored.")
                end
            end
        else
             self:_debug("Migration-Finalize", "Verification failed. Preserved data will be kept for next login.")
        end
    end
    -- *** END MIGRATION FINALIZER ***

    -- This code now only runs if the database is version 6 or higher.
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
    
    self.pauseQueue = { incoming = {}, outgoing = {} }
    self.notifiedNewVersion = nil

    self.db.global.discoveries = self.db.global.discoveries or {}
    
    -- *** FIX: Ensure the 'char' table exists before accessing its children ***
    self.db.char = self.db.char or {}
    self.db.char.looted = self.db.char.looted or {}
    self.db.char.hidden = self.db.char.hidden or {}

    -- MODIFIED: New logic for versioned optional DB
    if _G.LootCollector_OptionalDB_Data and type(_G.LootCollector_OptionalDB_Data) == "table" then
        local dbData = _G.LootCollector_OptionalDB_Data
        if dbData.version and dbData.data and self.db.profile.offeredOptionalDB ~= dbData.version then
            -- Auto-merge if database is empty, otherwise show prompt
            if not self.db.global.discoveries or not next(self.db.global.discoveries) then
                print("|cff00ff00LootCollector:|r New installation detected. Automatically merging starter database...")
                local ImportExport = self:GetModule("ImportExport", true)
                if ImportExport and ImportExport.ApplyImportString then
                    ImportExport:ApplyImportString(dbData.data, "MERGE", false, true, true)
                end
                if self.db and self.db.profile then
                    self.db.profile.offeredOptionalDB = dbData.version
                end
            else
                C_Timer.After(5, function()
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

    -- Refresh map and minimap
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
    print(string.format("|cffffd100LootCollector Debug:|r DelayedChannelInit started. Timer will fire in %d seconds.", DELAY_SECONDS))

    
    self:ScheduleAfter(DELAY_SECONDS, function()
        print("|cffffd100LootCollector Debug:|r Timer finished. Setting channelReady to true.")
        LootCollector.channelReady = true

        if LootCollector.db and LootCollector.db.profile.sharing.enabled and not LootCollector:IsZoneIgnored() then
            print("|cffffd100LootCollector Debug:|r Sharing is enabled, attempting to join channel.")
            if Comm.EnsureChannelJoined then
                Comm:EnsureChannelJoined()
            else
                print("|cffff0000LootCollector Error:|r Comm.EnsureChannelJoined is missing!")
            end
        else
            print("|cffffd100LootCollector Debug:|r Sharing is disabled, skipping channel join.")
        end
    end)

    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
end

function LootCollector:OnEnable()   
    local Map = self:GetModule("Map", true); if Map then self:RegisterEvent("WORLD_MAP_UPDATE", function() if WorldMapFrame and WorldMapFrame:IsShown() then Map:Update() end end) end
    if self.LEGACY_MODE_ACTIVE then return end 
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "DelayedChannelInit")
end

function LootCollector:OnDisable()
    self:UnregisterAllEvents()
end

SLASH_LCHISTORY1 = "/lchistory"
SlashCmdList["LCHISTORY"] = function()
    local HT = LootCollector:GetModule("HistoryTab", true)
    if HT and HT.Toggle then
        HT:Toggle()
    else
        print("|cffff7f00LootCollector:|r HistoryTab module not available.")
    end
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

-- QSBBIEEgQSBBIEEgQSBBIEEgQQrwn5KlIPCfkqUg8J+SpSDwn5KlIPCfkqUg8J+SpSDwn5KlIPCfkqUg8J+SpSDwn5Kl